-- Privacidad clínica: recepción sin antecedentes ni motivos de laboratorio; médicos según su atención — 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO. Probar primero en un entorno de pruebas. Reversión exacta: supabase/rls-privacidad-clinica-revert.sql.
--
-- Políticas desplegadas que se reemplazan (leídas con pg_policies):
--   medical_history.history_read   = can_read_patient(...)  → incluye recepcionista y admin y cualquier médico con treats_patient.
--   lab_orders.laborder_read       = my_patient OR treats_patient OR recepcionista OR admin.
--   vital_signs.vitals_read        = my_patient (aun con la consulta abierta) OR treats_patient OR cares_for.
--   prescriptions.prescription_read= my_patient OR treats_patient OR admin.
--   lab_results.labresult_read     = lab_permission OR (publicado y validado AND (treats_patient OR paciente con publicación)).
-- No se tocan patients ni medical_records: recepción los necesita para gestionar identidad, expediente y citas.
-- Las RPC doctor_native_*, my_consultation_history y laboratorio son SECURITY DEFINER y no dependen de estas políticas;
-- la app iOS y web-preview no cambian. Puede afectar al panel externo de Recepción si leía estas tablas directamente.
BEGIN;

-- Autorización asistencial del médico sobre un paciente (más estricta que treats_patient, que incluye cualquier cita futura):
--   * asignación vigente en care_team_assignments, o
--   * una consulta propia previa o en curso con el paciente (continuidad asistencial), o
--   * una cita propia en atención, o programada/confirmada que empiece en las próximas 24 h o haya empezado hace menos de 24 h.
CREATE OR REPLACE FUNCTION private.doctor_care_access(p_patient uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT private.has_role('doctor') AND private.my_staff_id() IS NOT NULL AND (
   EXISTS (SELECT 1 FROM public.care_team_assignments c WHERE c.patient_id = p_patient AND c.staff_id = private.my_staff_id()
           AND c.starts_at <= now() AND (c.ends_at IS NULL OR c.ends_at > now()))
   OR EXISTS (SELECT 1 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id = e.record_id
           WHERE m.patient_id = p_patient AND e.doctor_id = private.my_staff_id())
   OR EXISTS (SELECT 1 FROM public.appointments a WHERE a.patient_id = p_patient AND a.doctor_id = private.my_staff_id()
           AND (a.status = 'en_atencion' OR (a.status IN ('programada','confirmada') AND a.starts_at BETWEEN now() - interval '24 hours' AND now() + interval '24 hours'))))
$function$;
-- Las políticas se evalúan con el usuario que consulta: como las demás auxiliares (treats_patient, cares_for…), es ejecutable por
-- authenticated y nunca por anon. Solo devuelve un booleano sobre la propia sesión.
REVOKE ALL ON FUNCTION private.doctor_care_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.doctor_care_access(uuid) TO authenticated;

-- Antecedentes: paciente propietario, médico con atención autorizada, enfermería asignada y administración. Sin recepción.
DROP POLICY IF EXISTS history_read ON public.medical_history;
CREATE POLICY history_read ON public.medical_history FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.medical_records m WHERE m.id = medical_history.record_id AND (
    private.my_patient(m.patient_id) OR private.doctor_care_access(m.patient_id) OR private.cares_for(m.patient_id) OR private.has_role('admin'))));

-- Órdenes de laboratorio (incluyen el motivo clínico): paciente, médico autor o con atención autorizada y administración/laboratorio.
DROP POLICY IF EXISTS laborder_read ON public.lab_orders;
CREATE POLICY laborder_read ON public.lab_orders FOR SELECT TO authenticated USING (
  private.my_patient(private.encounter_patient(encounter_id)) OR private.encounter_doctor(encounter_id)
  OR private.doctor_care_access(private.encounter_patient(encounter_id)) OR private.has_role('admin'));

-- Signos vitales: el paciente solo tras el cierre de la consulta; médico autor o con atención; enfermería asignada.
DROP POLICY IF EXISTS vitals_read ON public.vital_signs;
CREATE POLICY vitals_read ON public.vital_signs FOR SELECT TO authenticated USING (
  (private.my_patient(private.encounter_patient(encounter_id))
     AND EXISTS (SELECT 1 FROM public.clinical_encounters e WHERE e.id = vital_signs.encounter_id AND e.ended_at IS NOT NULL))
  OR private.encounter_doctor(encounter_id) OR private.doctor_care_access(private.encounter_patient(encounter_id))
  OR private.cares_for(private.encounter_patient(encounter_id)));

-- Recetas: el paciente siempre (necesita su receta), médico autor o con atención, administración (farmacia).
DROP POLICY IF EXISTS prescription_read ON public.prescriptions;
CREATE POLICY prescription_read ON public.prescriptions FOR SELECT TO authenticated USING (
  private.my_patient(private.encounter_patient(encounter_id)) OR private.encounter_doctor(encounter_id)
  OR private.doctor_care_access(private.encounter_patient(encounter_id)) OR private.has_role('admin'));

-- Resultados: igual que antes, pero el médico con atención autorizada en lugar de treats_patient.
DROP POLICY IF EXISTS labresult_read ON public.lab_results;
CREATE POLICY labresult_read ON public.lab_results FOR SELECT TO authenticated USING (
  private.lab_permission('any') OR (published_at IS NOT NULL AND validated_by IS NOT NULL AND validated_at IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.lab_orders o WHERE o.id = lab_results.order_id AND (
      private.encounter_doctor(o.encounter_id) OR private.doctor_care_access(private.encounter_patient(o.encounter_id))
      OR (lab_results.published_to_patient_at IS NOT NULL AND private.my_patient(private.encounter_patient(o.encounter_id)))))));

COMMIT;

-- Comprobaciones (solo lectura) tras aplicar en pruebas:
--   SELECT tablename, policyname, qual FROM pg_policies WHERE tablename IN ('medical_history','lab_orders','vital_signs','prescriptions','lab_results') ORDER BY 1;
