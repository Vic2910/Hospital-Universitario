-- Modo de pruebas pedido el 20 de noviembre de 2026: el médico puede abrir su consulta a cualquier hora.
-- PREPARADO, NO APLICADO. Para volver a la regla original de 30 minutos: supabase/doctor-start-restore-30min.sql.
--
-- Único cambio respecto a la versión desplegada: se retira `a.starts_at>now()+interval '30 minutes'`.
-- Se mantiene todo lo demás:
--   - solo el médico asignado (native_doctor_id) puede abrir su cita;
--   - la RPC es idempotente y no duplica consultas;
--   - las citas canceladas, completadas o no asistidas siguen sin poder abrirse;
--   - Recepción debe haber vinculado el expediente;
--   - la cita pasa a en_atencion.
-- No cambia tablas, RLS, GRANT ni datos (CREATE OR REPLACE conserva los privilegios).
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
 IF a.status NOT IN ('programada','confirmada','en_atencion') THEN
  RAISE EXCEPTION 'La cita ya finalizó o fue cancelada' USING ERRCODE='22023'; END IF;
 SELECT id INTO r FROM public.medical_records WHERE patient_id=a.patient_id;
 IF r IS NULL THEN RAISE EXCEPTION 'Recepción debe vincular el expediente' USING ERRCODE='22023'; END IF;
 INSERT INTO public.clinical_encounters(id,record_id,appointment_id,doctor_id) VALUES(p_key,r,a.id,d);
 IF a.status<>'en_atencion' THEN PERFORM public.update_appointment_status(a.id,'en_atencion'); END IF;
 RETURN p_key;
END $function$;
COMMIT;
