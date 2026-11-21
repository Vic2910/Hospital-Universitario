-- Hospital Móviles: solicitud de ambulancia del paciente y módulo «Habitaciones» del médico (iOS y Android).
-- Requiere: hospital_universitario_supabase.sql, panel_ambulance_operations.sql, hospitalization_reception.sql,
--           doctor-ios.sql (private.native_doctor_id) y doctor-admissions.sql.
-- Concurrencia: todas las escrituras críticas se serializan con pg_advisory_xact_lock + SELECT … FOR UPDATE.
-- Los conflictos se devuelven con SQLSTATE 40001 para que la app muestre «otro usuario se adelantó».

BEGIN;

-- ─────────────────────────────── AMBULANCIA DEL PACIENTE ───────────────────────────────
-- Lock global compartido por TODAS las solicitudes de pacientes: dos pacientes que pulsan «Solicitar» en el mismo
-- instante se procesan uno detrás de otro; el segundo ve la solicitud del primero y recibe su posición en cola.
CREATE OR REPLACE FUNCTION public.patient_request_ambulance(p_contact text,p_phone text,p_origin text,p_destination text,
 p_reason text,p_priority text,p_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid; r public.ambulance_requests; v uuid; free_units int; ahead int;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('paciente') THEN RAISE EXCEPTION 'Solo un paciente puede solicitar su ambulancia' USING ERRCODE='42501'; END IF;
 SELECT id INTO pid FROM public.patients WHERE profile_id=auth.uid();
 IF pid IS NULL THEN RAISE EXCEPTION 'Tu cuenta no tiene un expediente de paciente vinculado' USING ERRCODE='42501'; END IF;
 IF p_key IS NULL OR nullif(trim(p_contact),'') IS NULL OR nullif(trim(p_phone),'') IS NULL OR nullif(trim(p_origin),'') IS NULL
  OR nullif(trim(p_reason),'') IS NULL OR p_priority IS NULL OR p_priority NOT IN ('normal','urgente')
  OR length(p_contact)>200 OR length(p_phone)>50 OR length(p_origin)>1000 OR length(coalesce(p_destination,''))>1000 OR length(p_reason)>4000 THEN
  RAISE EXCEPTION 'Completa contacto, teléfono, ubicación de recogida, motivo y prioridad' USING ERRCODE='22023'; END IF;
 IF trim(p_phone) !~ '^[0-9+ ()-]{8,20}$' THEN RAISE EXCEPTION 'Ingresa un teléfono válido' USING ERRCODE='22023'; END IF;

 PERFORM pg_advisory_xact_lock(901407022::bigint);   -- serializa solicitudes simultáneas de pacientes

 -- Reintento idempotente (misma clave): devuelve la misma solicitud.
 SELECT * INTO r FROM public.ambulance_requests WHERE requester_id=auth.uid() AND request_key=p_key;
 IF FOUND THEN
  RETURN jsonb_build_object('id',r.id,'status',r.status,'duplicate',true,
   'queue_position',(SELECT count(*) FROM public.ambulance_requests q WHERE q.status IN ('pendiente','autorizada') AND (q.requested_at,q.id)<=(r.requested_at,r.id)));
 END IF;
 -- Un paciente solo puede tener una solicitud activa.
 IF EXISTS(SELECT 1 FROM public.ambulance_requests WHERE patient_id=pid AND status IN ('pendiente','autorizada','despachada')) THEN
  RAISE EXCEPTION 'Ya tienes una solicitud de ambulancia activa. Espera a que finalice o sea cancelada.' USING ERRCODE='22023'; END IF;

 SELECT count(*) INTO free_units FROM public.ambulances a WHERE a.active AND a.status='disponible'
  AND NOT EXISTS(SELECT 1 FROM public.ambulance_dispatches d WHERE d.ambulance_id=a.id AND d.completed_at IS NULL);
 SELECT count(*) INTO ahead FROM public.ambulance_requests WHERE status IN ('pendiente','autorizada');

 INSERT INTO public.ambulance_requests(patient_id,requester_id,contact_name,contact_phone,pickup_location,destination,reason,priority,request_key)
 VALUES(pid,auth.uid(),trim(p_contact),trim(p_phone),trim(p_origin),coalesce(nullif(trim(p_destination),''),'Hospital Universitario'),
  trim(p_reason),p_priority,p_key) RETURNING id INTO v;

 RETURN jsonb_build_object('id',v,'status','pendiente','duplicate',false,'queue_position',ahead+1,
  'units_available',greatest(free_units-ahead,0),
  'waiting',ahead>=free_units);  -- true: otra solicitud ocupó la unidad libre; la tuya queda en cola
END $$;

-- Lectura de las solicitudes propias + posición en cola (la app la refresca).
CREATE OR REPLACE FUNCTION public.patient_ambulance_requests() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid;
BEGIN
 SELECT id INTO pid FROM public.patients WHERE profile_id=auth.uid();
 IF auth.uid() IS NULL OR pid IS NULL THEN RAISE EXCEPTION 'Tu cuenta no tiene un expediente de paciente vinculado' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'requests',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'status',r.status,'priority',r.priority,'pickup_location',r.pickup_location,
    'destination',r.destination,'reason',r.reason,'requested_at',r.requested_at,'decision_reason',r.decision_reason,
    'unit',(SELECT a.code FROM public.ambulance_dispatches d JOIN public.ambulances a ON a.id=d.ambulance_id WHERE d.request_id=r.id ORDER BY d.dispatched_at DESC LIMIT 1),
    'queue_position',CASE WHEN r.status IN ('pendiente','autorizada') THEN (SELECT count(*) FROM public.ambulance_requests q
      WHERE q.status IN ('pendiente','autorizada') AND (q.requested_at,q.id)<=(r.requested_at,r.id)) END)
   ORDER BY r.requested_at DESC) FROM (SELECT * FROM public.ambulance_requests WHERE patient_id=pid ORDER BY requested_at DESC LIMIT 20) r),'[]'),
  'units_available',(SELECT count(*) FROM public.ambulances a WHERE a.active AND a.status='disponible'
   AND NOT EXISTS(SELECT 1 FROM public.ambulance_dispatches d WHERE d.ambulance_id=a.id AND d.completed_at IS NULL)));
END $$;

-- Cancelar la solicitud propia mientras no haya sido despachada.
CREATE OR REPLACE FUNCTION public.patient_cancel_ambulance(p_request uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.ambulance_requests;
BEGIN
 PERFORM pg_advisory_xact_lock(901407021::bigint);   -- mismo lock que review/assign del panel
 SELECT * INTO r FROM public.ambulance_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR r.patient_id IS NULL OR NOT private.my_patient(r.patient_id) THEN RAISE EXCEPTION 'Solicitud no encontrada' USING ERRCODE='42501'; END IF;
 IF r.status='cancelada' THEN RETURN; END IF;
 IF r.status NOT IN ('pendiente','autorizada') THEN RAISE EXCEPTION 'La ambulancia ya fue despachada; comunícate con el hospital' USING ERRCODE='40001'; END IF;
 UPDATE public.ambulance_requests SET status='cancelada',decision_reason='Cancelada por el paciente' WHERE id=r.id;
END $$;

-- ─────────────────────────────── HABITACIONES DEL MÉDICO ───────────────────────────────
-- Mapa de habitaciones y camas. El ocupante solo se identifica si la hospitalización la ordenó este médico.
CREATE OR REPLACE FUNCTION public.doctor_native_rooms() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id();
BEGIN
 RETURN jsonb_build_object(
  'rooms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'kind',r.kind::text,'floor',f.name,'active',r.active,
    'beds',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'code',b.code,
      'state',CASE WHEN ba.id IS NOT NULL THEN 'ocupada' WHEN NOT b.active THEN 'mantenimiento' ELSE b.state::text END,
      'available',r.active AND b.active AND b.state='disponible' AND ba.id IS NULL,
      'mine',ha.ordered_by=d,
      'occupant',CASE WHEN ha.ordered_by=d THEN jsonb_build_object('admission_id',ha.id,'patient_id',ha.patient_id,
        'patient_name',concat_ws(' ',p.first_name,p.last_name),'record_number',m.record_code,'status',ha.status::text,
        'reason',ha.medical_reason,'since',ba.assigned_at) END) ORDER BY b.code)
     FROM public.beds b
     LEFT JOIN public.bed_assignments ba ON ba.bed_id=b.id AND ba.released_at IS NULL
     LEFT JOIN public.hospital_admissions ha ON ha.id=ba.admission_id
     LEFT JOIN public.patients p ON p.id=ha.patient_id
     LEFT JOIN public.medical_records m ON m.patient_id=p.id
     WHERE b.room_id=r.id),'[]')) ORDER BY f.id,r.code)
   FROM public.rooms r JOIN public.hospital_floors f ON f.id=r.floor_id),'[]'),
  'hospitalized',coalesce((SELECT jsonb_agg(jsonb_build_object('admission_id',a.id,'patient_id',a.patient_id,
    'patient_name',concat_ws(' ',p.first_name,p.last_name),'record_number',m.record_code,'status',a.status::text,
    'category',a.requested_kind::text,'reason',a.medical_reason,'observations',a.clinical_instructions,'priority',a.priority,
    'ordered_at',a.ordered_at,'discharged_at',a.medically_discharged_at,'discharge_notes',a.discharge_notes,
    'room',r.code,'bed',b.code,'floor',f.name,'assigned_at',ba.assigned_at) ORDER BY a.ordered_at DESC)
   FROM public.hospital_admissions a JOIN public.patients p ON p.id=a.patient_id
   LEFT JOIN public.medical_records m ON m.patient_id=p.id
   LEFT JOIN LATERAL (SELECT * FROM public.bed_assignments x WHERE x.admission_id=a.id ORDER BY x.assigned_at DESC LIMIT 1) ba ON true
   LEFT JOIN public.beds b ON b.id=ba.bed_id LEFT JOIN public.rooms r ON r.id=b.room_id LEFT JOIN public.hospital_floors f ON f.id=r.floor_id
   WHERE a.ordered_by=d AND a.status IN ('solicitado','asignado','hospitalizado','alta_medica')),'[]'),
  'checked_at',now());
END $$;

-- Pacientes que YA pasaron consulta con este médico (atención finalizada o cita completada).
CREATE OR REPLACE FUNCTION public.doctor_native_room_candidates(p_query text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); q text=lower(trim(coalesce(p_query,'')));
BEGIN
 IF length(q)>120 THEN RAISE EXCEPTION 'Búsqueda inválida' USING ERRCODE='22023'; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY lower(x.full_name)) FROM (
  SELECT p.id,concat_ws(' ',p.first_name,p.last_name) full_name,m.record_code record_number,p.dui,
   (SELECT max(coalesce(e.ended_at,e.started_at)) FROM public.clinical_encounters e WHERE e.record_id=m.id AND e.doctor_id=d) last_consultation,
   (SELECT a.status::text FROM public.hospital_admissions a WHERE a.patient_id=p.id AND a.status IN ('solicitado','asignado','hospitalizado','alta_medica') LIMIT 1) active_admission
  FROM public.patients p JOIN public.medical_records m ON m.patient_id=p.id
  WHERE (EXISTS(SELECT 1 FROM public.clinical_encounters e WHERE e.record_id=m.id AND e.doctor_id=d AND e.ended_at IS NOT NULL)
     OR EXISTS(SELECT 1 FROM public.appointments ap WHERE ap.patient_id=p.id AND ap.doctor_id=d AND ap.status='completada'))
   AND (q='' OR strpos(lower(concat_ws(' ',p.first_name,p.last_name)),q)>0 OR strpos(lower(coalesce(m.record_code,'')),q)>0
     OR strpos(coalesce(p.dui,''),q)>0)
  ORDER BY lower(concat_ws(' ',p.first_name,p.last_name)) LIMIT 50) x),'[]');
END $$;

-- Validación común de cama libre (bloquea la fila: dos médicos no pueden tomar la misma cama).
CREATE OR REPLACE FUNCTION private.doctor_take_bed(p_admission uuid,p_bed uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.hospital_admissions; b public.beds; k public.room_kind; ra boolean; v uuid;
BEGIN
 SELECT * INTO a FROM public.hospital_admissions WHERE id=p_admission FOR UPDATE;
 SELECT * INTO b FROM public.beds WHERE id=p_bed FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cama inexistente' USING ERRCODE='22023'; END IF;
 SELECT kind,active INTO k,ra FROM public.rooms WHERE id=b.room_id;
 IF NOT ra OR NOT b.active OR b.state<>'disponible' OR EXISTS(SELECT 1 FROM public.bed_assignments WHERE bed_id=b.id AND released_at IS NULL) THEN
  RAISE EXCEPTION 'La habitación/cama % ya está ocupada o no disponible. Actualiza y elige otra.',b.code USING ERRCODE='40001'; END IF;
 IF k IS DISTINCT FROM a.requested_kind THEN RAISE EXCEPTION 'La cama no corresponde a la categoría solicitada (%)',a.requested_kind USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.bed_assignments WHERE patient_id=a.patient_id AND released_at IS NULL) THEN
  RAISE EXCEPTION 'El paciente ya tiene una cama asignada' USING ERRCODE='40001'; END IF;
 INSERT INTO public.bed_assignments(admission_id,patient_id,bed_id,assigned_by) VALUES(a.id,a.patient_id,b.id,auth.uid()) RETURNING id INTO v;
 UPDATE public.beds SET state='ocupada' WHERE id=b.id;
 UPDATE public.hospital_admissions SET status='hospitalizado' WHERE id=a.id;
 INSERT INTO public.bed_status_history(bed_id,old_state,new_state,actor_id) VALUES(b.id,b.state,'ocupada',auth.uid());
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION private.doctor_take_bed(uuid,uuid) FROM PUBLIC,anon,authenticated;

-- Asignar cama a una solicitud de ingreso pendiente que ordenó este médico.
CREATE OR REPLACE FUNCTION public.doctor_native_assign_bed(p_admission uuid,p_bed uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); a public.hospital_admissions;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('bed:'||coalesce(p_bed::text,''),0));
 SELECT * INTO a FROM public.hospital_admissions WHERE id=p_admission FOR UPDATE;
 IF NOT FOUND OR a.ordered_by<>d THEN RAISE EXCEPTION 'Solo puedes asignar cama a ingresos que tú solicitaste' USING ERRCODE='42501'; END IF;
 IF a.status='hospitalizado' AND EXISTS(SELECT 1 FROM public.bed_assignments WHERE admission_id=a.id AND bed_id=p_bed AND released_at IS NULL) THEN
  RETURN (SELECT id FROM public.bed_assignments WHERE admission_id=a.id AND released_at IS NULL); END IF;
 IF a.status<>'solicitado' THEN RAISE EXCEPTION 'El ingreso ya no está pendiente de cama' USING ERRCODE='40001'; END IF;
 RETURN private.doctor_take_bed(a.id,p_bed);
END $$;

-- Hospitalizar directamente desde Habitaciones: paciente ya atendido por el médico + cama libre.
CREATE OR REPLACE FUNCTION public.doctor_native_hospitalize(p_patient uuid,p_bed uuid,p_reason text,p_instructions text,p_priority text,p_key uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); k public.room_kind; v uuid; existing public.hospital_admissions;
BEGIN
 IF p_key IS NULL OR p_priority IS NULL OR p_priority NOT IN ('normal','urgente') OR nullif(trim(p_reason),'') IS NULL OR length(p_reason)>10000 OR length(coalesce(p_instructions,''))>10000 THEN
  RAISE EXCEPTION 'Completa motivo clínico y prioridad' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id WHERE m.patient_id=p_patient AND e.doctor_id=d AND e.ended_at IS NOT NULL)
  AND NOT EXISTS(SELECT 1 FROM public.appointments ap WHERE ap.patient_id=p_patient AND ap.doctor_id=d AND ap.status='completada') THEN
  RAISE EXCEPTION 'Solo puedes hospitalizar pacientes que ya pasaron consulta contigo' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('bed:'||coalesce(p_bed::text,''),0));
 PERFORM pg_advisory_xact_lock(hashtextextended('patient-admission:'||p_patient::text,0));
 SELECT * INTO existing FROM public.hospital_admissions WHERE ordered_by=d AND request_key=p_key;
 IF FOUND THEN RETURN existing.id; END IF;   -- reintento idempotente
 IF EXISTS(SELECT 1 FROM public.hospital_admissions WHERE patient_id=p_patient AND status IN ('solicitado','asignado','hospitalizado','alta_medica')) THEN
  RAISE EXCEPTION 'El paciente ya tiene una hospitalización o solicitud activa' USING ERRCODE='40001'; END IF;
 SELECT r.kind INTO k FROM public.beds b JOIN public.rooms r ON r.id=b.room_id WHERE b.id=p_bed;
 IF k IS NULL THEN RAISE EXCEPTION 'Cama inexistente' USING ERRCODE='22023'; END IF;
 INSERT INTO public.hospital_admissions(patient_id,ordered_by,requested_kind,medical_reason,clinical_instructions,priority,request_key)
 VALUES(p_patient,d,k,trim(p_reason),nullif(trim(p_instructions),''),p_priority,p_key) RETURNING id INTO v;
 PERFORM private.doctor_take_bed(v,p_bed);   -- si la cama se ocupó, toda la transacción se revierte
 RETURN v;
END $$;

-- Alta médica: solo de hospitalizaciones que ordenó este médico. Recepción luego libera la cama (release_bed).
CREATE OR REPLACE FUNCTION public.doctor_native_discharge(p_admission uuid,p_notes text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); a public.hospital_admissions;
BEGIN
 SELECT * INTO a FROM public.hospital_admissions WHERE id=p_admission FOR UPDATE;
 IF NOT FOUND OR a.ordered_by<>d THEN RAISE EXCEPTION 'Solo puedes dar de alta a pacientes que tú hospitalizaste' USING ERRCODE='42501'; END IF;
 IF a.status='alta_medica' THEN RETURN; END IF;
 IF a.status<>'hospitalizado' THEN RAISE EXCEPTION 'El paciente no está hospitalizado actualmente' USING ERRCODE='40001'; END IF;
 IF nullif(trim(p_notes),'') IS NULL OR length(p_notes)>10000 THEN RAISE EXCEPTION 'Escribe las indicaciones de alta' USING ERRCODE='22023'; END IF;
 PERFORM public.medical_discharge(a.id,p_notes);
END $$;

REVOKE ALL ON FUNCTION public.patient_request_ambulance(text,text,text,text,text,text,uuid),public.patient_ambulance_requests(),
 public.patient_cancel_ambulance(uuid),public.doctor_native_rooms(),public.doctor_native_room_candidates(text),
 public.doctor_native_assign_bed(uuid,uuid),public.doctor_native_hospitalize(uuid,uuid,text,text,text,uuid),
 public.doctor_native_discharge(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.patient_request_ambulance(text,text,text,text,text,text,uuid),public.patient_ambulance_requests(),
 public.patient_cancel_ambulance(uuid),public.doctor_native_rooms(),public.doctor_native_room_candidates(text),
 public.doctor_native_assign_bed(uuid,uuid),public.doctor_native_hospitalize(uuid,uuid,text,text,text,uuid),
 public.doctor_native_discharge(uuid,text) TO authenticated;

COMMIT;
