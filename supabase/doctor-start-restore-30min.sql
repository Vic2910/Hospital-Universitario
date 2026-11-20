-- Restaura la regla original de doctor_native_start: abrir desde 30 minutos antes de la cita.
-- Definición leída del servidor el 19 de noviembre de 2026 (pg_get_functiondef). Úsala al terminar las pruebas
-- y pon openingLeadMinutes = 30 en DoctorClinicalRules (Swift) y HospitalCore.doctorClinical (JS).
BEGIN;
CREATE OR REPLACE FUNCTION public.doctor_native_start(p_appointment uuid, p_key uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE d uuid=private.native_doctor_id(); a public.appointments; e public.clinical_encounters; r uuid;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=p_appointment AND doctor_id=d FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cita no asignada' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.clinical_encounters WHERE appointment_id=a.id;
 IF FOUND THEN
  IF e.doctor_id<>d THEN RAISE EXCEPTION 'Consulta no autorizada' USING ERRCODE='42501'; END IF;
  RETURN e.id;
 END IF;
 IF a.status NOT IN ('programada','confirmada','en_atencion') OR a.starts_at>now()+interval '30 minutes' THEN
  RAISE EXCEPTION 'La cita todavía no puede iniciarse o ya finalizó' USING ERRCODE='22023'; END IF;
 SELECT id INTO r FROM public.medical_records WHERE patient_id=a.patient_id;
 IF r IS NULL THEN RAISE EXCEPTION 'Recepción debe vincular el expediente' USING ERRCODE='22023'; END IF;
 INSERT INTO public.clinical_encounters(id,record_id,appointment_id,doctor_id) VALUES(p_key,r,a.id,d);
 IF a.status<>'en_atencion' THEN PERFORM public.update_appointment_status(a.id,'en_atencion'); END IF;
 RETURN p_key;
END $function$;
COMMIT;
