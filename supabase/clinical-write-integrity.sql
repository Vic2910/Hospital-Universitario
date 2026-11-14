-- DRAFT: not deployed. Apply only after explicit authorization, in one migration transaction.
-- No UPDATE/DELETE of clinical data; no change to public RPC signatures or SELECT policies.
DO $$
DECLARE x record; actual text; target text;
BEGIN
 -- Fail closed if the shared backend changed after dependency review.
 FOR x IN SELECT * FROM (VALUES
  ('private','cares_for','61f25717d965160a449f0d06b35c50b8'),
  ('private','native_doctor_id','ef60c68fc78a8495bef8fcbaca851acd'),
  ('private','native_doctor_encounter','17ab20f6dda889cd40618e225d9e446d'),
  ('public','doctor_native_start','b90903934b0bad4b68104d3068c9dfec'),
  ('public','doctor_native_save','13de85512583ac0ee20358c59909692f'),
  ('public','doctor_native_finish','8580825852e66a0e01278db68d65cfb1'),
  ('public','doctor_native_lab','14354b9ab7d6fd0086fa3e39b47b76cb'),
  ('public','doctor_native_labs','fb249bc10a8c6fe8e145e8ffe1ddb5fe'),
  ('public','doctor_native_prescribe','612a0ce6d474143034c09128e20a3b8c'),
  ('public','start_laboratory_order','7f5476e962c901a3ca7ec373d42fe528'),
  ('public','publish_lab_result','1c0e94043d3839ee02f8d85ce01ec34f'),
  ('public','correct_laboratory_result','5fe5ed6a642ef5b709e52ca1013b0b8d'),
  ('public','dispense_item','e4caac608fd2be3576f0c10d8784c701')
 ) v(schema_name,function_name,definition_hash) LOOP
  SELECT CASE WHEN count(*)=1 THEN min(md5(pg_get_functiondef(p.oid))) END INTO actual
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname=x.schema_name AND p.proname=x.function_name AND p.prokind='f'
    AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres';
  IF actual IS DISTINCT FROM x.definition_hash THEN
   RAISE EXCEPTION 'Dependencia %.% cambió: revisar antes de desplegar',x.schema_name,x.function_name;
  END IF;
 END LOOP;
 FOREACH target IN ARRAY ARRAY['clinical_encounters','diagnoses','vital_signs','lab_orders','prescriptions','prescription_items'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname=target AND c.relrowsecurity) THEN
   RAISE EXCEPTION 'Falta tabla con RLS: %',target;
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id
  LEFT JOIN public.appointments a ON a.id=e.appointment_id
  WHERE e.appointment_id IS NULL OR a.id IS NULL OR a.doctor_id IS DISTINCT FROM e.doctor_id OR a.patient_id IS DISTINCT FROM m.patient_id) THEN
  RAISE EXCEPTION 'Hay consultas heredadas sin cita o inconsistentes: revisar sin modificar datos';
 END IF;
END $$;

-- Existing medical/lab/dispensing RPCs execute as postgres and retain their privileges.
-- Keep nursing's existing INSERT on vital_signs, secured by the trigger below.
REVOKE INSERT,UPDATE,DELETE ON TABLE public.clinical_encounters,public.diagnoses,public.lab_orders,
 public.prescriptions,public.prescription_items FROM PUBLIC,anon,authenticated;
REVOKE UPDATE,DELETE ON TABLE public.vital_signs FROM PUBLIC,anon,authenticated;
DO $$
DECLARE target text; columns text;
BEGIN
 -- Also remove explicit column grants; revoking table grants alone is insufficient for them.
 FOREACH target IN ARRAY ARRAY['clinical_encounters','diagnoses','lab_orders','prescriptions','prescription_items','vital_signs'] LOOP
  SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO columns FROM pg_attribute
   WHERE attrelid=format('public.%I',target)::regclass AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE UPDATE (%s) ON TABLE public.%I FROM PUBLIC,anon,authenticated',columns,target);
  IF target<>'vital_signs' THEN
   EXECUTE format('REVOKE INSERT (%s) ON TABLE public.%I FROM PUBLIC,anon,authenticated',columns,target);
  END IF;
 END LOOP;
END $$;

CREATE FUNCTION private.clinical_encounter_identity_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.appointments; patient uuid;
BEGIN
 IF TG_OP='UPDATE' THEN
  IF NEW.record_id IS DISTINCT FROM OLD.record_id OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id
   OR NEW.appointment_id IS DISTINCT FROM OLD.appointment_id THEN
   RAISE EXCEPTION 'No se puede reasignar una consulta clínica existente' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
 END IF;
 IF NEW.appointment_id IS NULL THEN RAISE EXCEPTION 'La consulta requiere una cita válida' USING ERRCODE='23514'; END IF;
 -- Same order as native start: appointment before encounter; record lock serializes reassignment.
 SELECT * INTO a FROM public.appointments WHERE id=NEW.appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cita inexistente' USING ERRCODE='23503'; END IF;
 SELECT patient_id INTO patient FROM public.medical_records WHERE id=NEW.record_id FOR SHARE;
 IF patient IS NULL OR a.patient_id IS DISTINCT FROM patient OR a.doctor_id IS DISTINCT FROM NEW.doctor_id THEN
  RAISE EXCEPTION 'Cita, médico y expediente no corresponden a la misma consulta' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.clinical_encounter_identity_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER clinical_encounter_identity_guard BEFORE INSERT OR UPDATE OF record_id,doctor_id,appointment_id
 ON public.clinical_encounters FOR EACH ROW EXECUTE FUNCTION private.clinical_encounter_identity_guard();

CREATE FUNCTION private.clinical_parent_identity_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_TABLE_NAME='appointments' THEN
  IF (NEW.patient_id IS DISTINCT FROM OLD.patient_id OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id)
   AND EXISTS(SELECT 1 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id
    WHERE e.appointment_id=OLD.id AND (e.doctor_id IS DISTINCT FROM NEW.doctor_id OR m.patient_id IS DISTINCT FROM NEW.patient_id)) THEN
   RAISE EXCEPTION 'La reasignación rompe el vínculo de una consulta existente' USING ERRCODE='23514';
  END IF;
 ELSE
  IF NEW.patient_id IS DISTINCT FROM OLD.patient_id AND EXISTS(SELECT 1 FROM public.clinical_encounters WHERE record_id=OLD.id) THEN
   RAISE EXCEPTION 'Un expediente con consultas no puede trasladarse a otro paciente' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.clinical_parent_identity_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER clinical_appointment_identity_guard BEFORE UPDATE OF patient_id,doctor_id ON public.appointments
 FOR EACH ROW EXECUTE FUNCTION private.clinical_parent_identity_guard();
CREATE TRIGGER clinical_record_identity_guard BEFORE UPDATE OF patient_id ON public.medical_records
 FOR EACH ROW EXECUTE FUNCTION private.clinical_parent_identity_guard();

CREATE FUNCTION private.clinical_vitals_write_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters; a public.appointments; patient uuid; own_doctor boolean;
BEGIN
 IF auth.uid() IS NULL OR NEW.recorded_by IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'No autorizado para registrar signos vitales de esta consulta' USING ERRCODE='42501'; END IF;
 IF TG_OP='UPDATE' AND NEW.encounter_id IS DISTINCT FROM OLD.encounter_id THEN
  RAISE EXCEPTION 'No se pueden trasladar signos vitales a otra consulta' USING ERRCODE='23514';
 END IF;
 SELECT * INTO e FROM public.clinical_encounters WHERE id=NEW.encounter_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'No autorizado para registrar signos vitales de esta consulta' USING ERRCODE='42501'; END IF;
 SELECT patient_id INTO patient FROM public.medical_records WHERE id=e.record_id;
 own_doctor=private.has_role('doctor') AND EXISTS(SELECT 1 FROM public.staff s
  WHERE s.id=e.doctor_id AND s.profile_id=auth.uid() AND s.active AND s.category='doctor');
 IF NOT(own_doctor OR private.cares_for(patient)) THEN
  RAISE EXCEPTION 'No autorizado para registrar signos vitales de esta consulta' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=e.appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'La consulta no tiene una cita válida' USING ERRCODE='23514'; END IF;
 SELECT * INTO e FROM public.clinical_encounters WHERE id=NEW.encounter_id FOR UPDATE;
 SELECT patient_id INTO patient FROM public.medical_records WHERE id=e.record_id FOR SHARE;
 IF e.ended_at IS NOT NULL OR a.status<>'en_atencion' THEN
  RAISE EXCEPTION 'La consulta está cerrada o no admite registros clínicos' USING ERRCODE='22023'; END IF;
 IF a.doctor_id IS DISTINCT FROM e.doctor_id OR a.patient_id IS DISTINCT FROM patient THEN
  RAISE EXCEPTION 'Cita, consulta y expediente incoherentes' USING ERRCODE='23514'; END IF;
 -- Identical bounds to doctor_native_save; no new clinical reference ranges.
 IF NEW.weight_kg<=0 OR NEW.weight_kg>1000 OR NEW.height_cm<=0 OR NEW.height_cm>300
  OR NEW.temperature_c<25 OR NEW.temperature_c>50 OR NEW.systolic<20 OR NEW.systolic>350
  OR NEW.diastolic<10 OR NEW.diastolic>250 OR NEW.heart_rate<10 OR NEW.heart_rate>350
  OR (NEW.systolic IS NOT NULL AND NEW.diastolic IS NOT NULL AND NEW.systolic<=NEW.diastolic) THEN
  RAISE EXCEPTION 'Signos vitales fuera de los límites admitidos por la RPC médica' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.clinical_vitals_write_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER clinical_vitals_write_guard BEFORE INSERT OR UPDATE ON public.vital_signs
 FOR EACH ROW EXECUTE FUNCTION private.clinical_vitals_write_guard();

DO $$
DECLARE target text; role_name text;
BEGIN
 FOREACH target IN ARRAY ARRAY['clinical_encounters','diagnoses','lab_orders','prescriptions','prescription_items'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_any_column_privilege(role_name,format('public.%I',target),'INSERT')
    OR has_any_column_privilege(role_name,format('public.%I',target),'UPDATE')
    OR has_table_privilege(role_name,format('public.%I',target),'DELETE') THEN
    RAISE EXCEPTION 'Permiso de escritura residual en %.%: revisar herencia de roles',role_name,target;
   END IF;
  END LOOP;
 END LOOP;
 IF NOT has_table_privilege('authenticated','public.vital_signs','INSERT') THEN
  RAISE EXCEPTION 'No debe perderse el registro autorizado de signos vitales'; END IF;
END $$;
