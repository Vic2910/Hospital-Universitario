-- Hospitalizaciones visibles para paciente y médico. APLICADA en Hospital Móviles el 20 de noviembre de 2026 (migración hospitalizaciones_paciente).
-- Reutiliza la estructura hospitalaria existente: hospital_admissions (episodio), bed_assignments (habitación/cama y
-- traslados), beds, rooms (kind: vip | semiprivada) y hospital_floors. No crea tablas ni duplica datos.
-- Ingreso, asignación, alta y liberación siguen en el panel administrativo: assign_bed, medical_discharge, release_bed.
-- Validaciones ya existentes en producción y reutilizadas: one_active_admission_per_patient, one_active_patient_bed,
-- one_active_bed_patient, bed_assignments_check (released_at >= assigned_at), medical_discharge solo desde 'hospitalizado'.
-- Reversión al final del archivo.

-- Filas de episodio con sus asignaciones de cama ordenadas (incluye traslados). Solo para uso interno de las RPC.
CREATE OR REPLACE FUNCTION private.hospitalization_rows(p_patient uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'ordered_at') DESC), '[]'::jsonb) FROM (
  SELECT jsonb_build_object(
   'id', a.id, 'status', a.status::text, 'requested_kind', a.requested_kind::text,
   'reason', a.medical_reason, 'instructions', a.clinical_instructions, 'priority', a.priority,
   'ordered_at', a.ordered_at, 'discharged_at', a.medically_discharged_at, 'discharge_notes', a.discharge_notes,
   'closed_at', a.closed_at,
   'hospital_name', (SELECT s.name FROM public.hospital_settings s LIMIT 1),
   'doctor_name', (SELECT concat_ws(' ', p.first_name, p.last_name) FROM public.staff st JOIN public.profiles p ON p.id = st.profile_id WHERE st.id = a.ordered_by),
   'discharged_by_name', (SELECT concat_ws(' ', p.first_name, p.last_name) FROM public.profiles p WHERE p.id = a.medically_discharged_by),
   'assignments', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'room', r.code, 'room_kind', r.kind::text, 'bed', b.code, 'floor', f.name,
      'assigned_at', ba.assigned_at, 'released_at', ba.released_at) ORDER BY ba.assigned_at)
     FROM public.bed_assignments ba JOIN public.beds b ON b.id = ba.bed_id JOIN public.rooms r ON r.id = b.room_id
     LEFT JOIN public.hospital_floors f ON f.id = r.floor_id WHERE ba.admission_id = a.id), '[]'::jsonb)) AS x
  FROM public.hospital_admissions a
  WHERE a.patient_id = p_patient AND a.status IN ('asignado','hospitalizado','alta_medica','cerrado')
 ) q;
$$;
REVOKE ALL ON FUNCTION private.hospitalization_rows(uuid) FROM PUBLIC, anon, authenticated;

-- Paciente: solo su propio expediente (identidad del servidor, sin patient_id del cliente).
CREATE OR REPLACE FUNCTION public.my_hospitalizations()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('paciente') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT id INTO v FROM public.patients WHERE profile_id = auth.uid();
 IF v IS NULL THEN RETURN '[]'::jsonb; END IF;
 RETURN private.hospitalization_rows(v);
END $$;
REVOKE ALL ON FUNCTION public.my_hospitalizations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_hospitalizations() TO authenticated;

-- Médico: exige vínculo doctor activo (native_doctor_id) y relación asistencial (treats_patient).
CREATE OR REPLACE FUNCTION public.doctor_native_patient_hospitalizations(p_patient uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM private.native_doctor_id();
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Expediente no autorizado' USING ERRCODE='42501'; END IF;
 RETURN private.hospitalization_rows(p_patient);
END $$;
REVOKE ALL ON FUNCTION public.doctor_native_patient_hospitalizations(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_patient_hospitalizations(uuid) TO authenticated;

-- Traslado de habitación (no existe hoy: assign_bed rechaza otra cama si el ingreso está hospitalizado).
-- Cierra la asignación actual y abre otra en el mismo episodio: la trazabilidad queda en bed_assignments.
CREATE OR REPLACE FUNCTION public.transfer_bed(p_admission uuid, p_bed uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a public.hospital_admissions; old uuid; k public.room_kind; b public.beds; v uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT(private.has_role('admin') OR private.has_role('recepcionista')) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM public.hospital_admissions WHERE id = p_admission FOR UPDATE;
 IF NOT FOUND OR a.status <> 'hospitalizado' THEN RAISE EXCEPTION 'Solo se traslada una hospitalización activa'; END IF;
 SELECT bed_id INTO old FROM public.bed_assignments WHERE admission_id = a.id AND released_at IS NULL FOR UPDATE;
 IF old IS NULL THEN RAISE EXCEPTION 'No hay una cama activa para este ingreso'; END IF;
 IF old = p_bed THEN RETURN (SELECT id FROM public.bed_assignments WHERE admission_id = a.id AND released_at IS NULL); END IF;
 SELECT r.kind INTO k FROM public.rooms r JOIN public.beds x ON x.room_id = r.id WHERE x.id = p_bed AND r.active FOR UPDATE OF r;
 IF k IS NULL THEN RAISE EXCEPTION 'La habitación no está activa'; END IF;
 SELECT * INTO b FROM public.beds WHERE id = p_bed FOR UPDATE;
 IF NOT b.active OR b.state <> 'disponible' OR EXISTS(SELECT 1 FROM public.bed_assignments WHERE bed_id = p_bed AND released_at IS NULL) THEN
  RAISE EXCEPTION 'La cama ya no está disponible. Actualiza la consulta.'; END IF;
 PERFORM 1 FROM public.beds WHERE id = old FOR UPDATE;
 UPDATE public.bed_assignments SET released_at = now() WHERE admission_id = a.id AND released_at IS NULL;
 UPDATE public.beds SET state = 'limpieza' WHERE id = old;
 INSERT INTO public.bed_status_history(bed_id, old_state, new_state, actor_id) VALUES (old, 'ocupada', 'limpieza', auth.uid());
 INSERT INTO public.bed_assignments(admission_id, patient_id, bed_id, assigned_by) VALUES (a.id, a.patient_id, p_bed, auth.uid()) RETURNING id INTO v;
 UPDATE public.beds SET state = 'ocupada' WHERE id = p_bed;
 INSERT INTO public.bed_status_history(bed_id, old_state, new_state, actor_id) VALUES (p_bed, 'disponible', 'ocupada', auth.uid());
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.transfer_bed(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_bed(uuid, uuid) TO authenticated;

-- Reversión:
-- DROP FUNCTION IF EXISTS public.transfer_bed(uuid, uuid);
-- DROP FUNCTION IF EXISTS public.doctor_native_patient_hospitalizations(uuid);
-- DROP FUNCTION IF EXISTS public.my_hospitalizations();
-- DROP FUNCTION IF EXISTS private.hospitalization_rows(uuid);
