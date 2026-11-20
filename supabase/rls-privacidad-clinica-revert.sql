-- Reversión exacta de supabase/rls-privacidad-clinica.sql: restaura las políticas leídas de pg_policies el 20 de noviembre de 2026.
BEGIN;
DROP POLICY IF EXISTS history_read ON public.medical_history;
CREATE POLICY history_read ON public.medical_history FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.medical_records m WHERE m.id = medical_history.record_id AND private.can_read_patient(m.patient_id)));
DROP POLICY IF EXISTS laborder_read ON public.lab_orders;
CREATE POLICY laborder_read ON public.lab_orders FOR SELECT TO authenticated USING (
  private.my_patient(private.encounter_patient(encounter_id)) OR private.treats_patient(private.encounter_patient(encounter_id))
  OR private.has_role('recepcionista'::hospital_role) OR private.has_role('admin'::hospital_role));
DROP POLICY IF EXISTS vitals_read ON public.vital_signs;
CREATE POLICY vitals_read ON public.vital_signs FOR SELECT TO authenticated USING (
  private.my_patient(private.encounter_patient(encounter_id)) OR private.treats_patient(private.encounter_patient(encounter_id))
  OR private.cares_for(private.encounter_patient(encounter_id)));
DROP POLICY IF EXISTS prescription_read ON public.prescriptions;
CREATE POLICY prescription_read ON public.prescriptions FOR SELECT TO authenticated USING (
  private.my_patient(private.encounter_patient(encounter_id)) OR private.treats_patient(private.encounter_patient(encounter_id))
  OR private.has_role('admin'::hospital_role));
DROP POLICY IF EXISTS labresult_read ON public.lab_results;
CREATE POLICY labresult_read ON public.lab_results FOR SELECT TO authenticated USING (
  private.lab_permission('any'::text) OR ((published_at IS NOT NULL) AND (validated_by IS NOT NULL) AND (validated_at IS NOT NULL) AND (EXISTS (
    SELECT 1 FROM public.lab_orders o WHERE ((o.id = lab_results.order_id) AND (private.treats_patient(private.encounter_patient(o.encounter_id))
      OR ((lab_results.published_to_patient_at IS NOT NULL) AND private.my_patient(private.encounter_patient(o.encounter_id)))))))));
COMMIT;
-- private.doctor_care_access se conserva (no se usa tras revertir); puede eliminarse con DROP FUNCTION si se desea.
