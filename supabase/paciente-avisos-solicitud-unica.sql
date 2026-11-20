-- Paciente: avisos de su cuenta y una sola solicitud de atención activa — 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO. Requiere autorización expresa antes de ejecutarlo en Hospital Móviles (uvebpsbbwofthucghccc).
--
-- Situación desplegada (inspeccionada con el MCP en solo lectura):
--   * private.laboratory_notifications ya avisa al paciente cuando un resultado se publica para él. No se toca.
--   * No existe aviso al paciente cuando recepción le programa, reprograma o cancela una cita, cuando se entrega
--     su receta ni cuando se rechaza su solicitud de atención. doctor_appointment_notice solo avisa al médico.
--   * submit_my_attention_request no impide enviar otra solicitud con una pendiente o una cita programada.
-- Cambios:
--   1. Tres disparadores nuevos que solo insertan en public.notifications (destinatario = cuenta del paciente,
--      event_key único para no duplicar). No modifican citas, recetas ni solicitudes.
--   2. submit_my_attention_request: misma definición desplegada más dos comprobaciones (solicitud pendiente o en
--      revisión; cita programada, confirmada o en atención vigente). La idempotencia por p_key se conserva.
-- No crea tablas ni RPC, no cambia RLS ni GRANT (CREATE OR REPLACE conserva los privilegios).
BEGIN;

CREATE OR REPLACE FUNCTION private.patient_appointment_notice()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE recipient uuid; title text; body text; event text;
BEGIN
 SELECT p.profile_id INTO recipient FROM public.patients p WHERE p.id=NEW.patient_id;
 IF recipient IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=recipient AND r.role='paciente' AND r.active) THEN RETURN NEW; END IF;
 IF NEW.status IN ('programada','confirmada') AND (TG_OP='INSERT' OR NEW.starts_at IS DISTINCT FROM OLD.starts_at OR OLD.status NOT IN ('programada','confirmada')) THEN
  title=CASE WHEN TG_OP='UPDATE' AND NEW.starts_at IS DISTINCT FROM OLD.starts_at THEN 'Tu cita fue reprogramada' ELSE 'Tienes una cita programada' END;
  body='Tu cita es el '||to_char(NEW.starts_at AT TIME ZONE 'America/El_Salvador','DD/MM/YYYY')||' a las '||to_char(NEW.starts_at AT TIME ZONE 'America/El_Salvador','HH24:MI')||'. Revisa los detalles en Mis citas.';
  event='patient:appointment:'||NEW.id::text||':'||extract(epoch from NEW.starts_at)::text;
 ELSIF TG_OP='UPDATE' AND NEW.status='cancelada' AND OLD.status IS DISTINCT FROM NEW.status THEN
  title='Tu cita fue cancelada';
  body='La cita del '||to_char(NEW.starts_at AT TIME ZONE 'America/El_Salvador','DD/MM/YYYY HH24:MI')||' fue cancelada. Puedes enviar una nueva solicitud de atención.';
  event='patient:appointment:'||NEW.id::text||':cancelled';
 ELSE RETURN NEW; END IF;
 INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
 VALUES(recipient,title,body,'cita','appointments',NEW.id::text,event)
 ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION private.patient_prescription_notice()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE recipient uuid;
BEGIN
 IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status<>'entregada' THEN RETURN NEW; END IF;
 SELECT p.profile_id INTO recipient FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id
  JOIN public.patients p ON p.id=m.patient_id WHERE e.id=NEW.encounter_id;
 IF recipient IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=recipient AND r.role='paciente' AND r.active) THEN RETURN NEW; END IF;
 INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
 VALUES(recipient,'Tu receta fue entregada','La receta '||coalesce(NEW.prescription_code,'')||' fue entregada. Revisa las indicaciones en Mis recetas.','receta','prescriptions',NEW.id::text,'patient:prescription:'||NEW.id::text||':delivered')
 ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION private.patient_request_notice()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE recipient uuid;
BEGIN
 IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status<>'rechazada' THEN RETURN NEW; END IF;
 recipient=coalesce(NEW.requester_id,(SELECT profile_id FROM public.patients WHERE id=NEW.patient_id));
 IF recipient IS NULL THEN RETURN NEW; END IF;
 INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
 VALUES(recipient,'Tu solicitud de atención no fue aprobada',coalesce(nullif(trim(NEW.closure_reason),''),'Recepción revisó tu solicitud.')||' Puedes enviar una nueva solicitud.','atencion','appointment_requests',NEW.id::text,'patient:request:'||NEW.id::text||':rejected')
 ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS patient_appointment_notice ON public.appointments;
CREATE TRIGGER patient_appointment_notice AFTER INSERT OR UPDATE OF starts_at, status ON public.appointments
 FOR EACH ROW EXECUTE FUNCTION private.patient_appointment_notice();
DROP TRIGGER IF EXISTS patient_prescription_notice ON public.prescriptions;
CREATE TRIGGER patient_prescription_notice AFTER UPDATE OF status ON public.prescriptions
 FOR EACH ROW EXECUTE FUNCTION private.patient_prescription_notice();
DROP TRIGGER IF EXISTS patient_request_notice ON public.appointment_requests;
CREATE TRIGGER patient_request_notice AFTER UPDATE OF status ON public.appointment_requests
 FOR EACH ROW EXECUTE FUNCTION private.patient_request_notice();
REVOKE ALL ON FUNCTION private.patient_appointment_notice(),private.patient_prescription_notice(),private.patient_request_notice() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.submit_my_attention_request(p_key uuid, p_specialty bigint, p_period text, p_reason text, p_symptoms bigint[], p_other text DEFAULT NULL::text, p_missing jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid=auth.uid(); v_existing uuid; v_owner uuid; v_person jsonb; v_patient uuid; v_birth date;
BEGIN
 IF v_uid IS NULL OR NOT private.has_role('paciente') THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_key::text,0));
 SELECT id,requester_id INTO v_existing,v_owner FROM public.appointment_requests WHERE id=p_key;
 IF FOUND THEN
   IF v_owner IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'Identificador no disponible' USING ERRCODE='42501'; END IF;
   RETURN v_existing;
 END IF;
 -- Una sola solicitud activa por cuenta: recepción debe programarla o rechazarla antes de recibir otra.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('attention:'||v_uid::text,0));
 IF EXISTS(SELECT 1 FROM public.appointment_requests ar WHERE (ar.requester_id=v_uid OR private.my_patient(ar.patient_id))
   AND ar.status IN ('pendiente','en_revision')) THEN
   RAISE EXCEPTION 'Ya tienes una solicitud en revisión. Recepción debe atenderla antes de enviar otra.' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.appointments a JOIN public.patients p ON p.id=a.patient_id WHERE p.profile_id=v_uid
   AND a.status IN ('programada','confirmada','en_atencion') AND a.ends_at>now()) THEN
   RAISE EXCEPTION 'Ya tienes una cita programada. Comunícate con recepción si necesitas cambiarla.' USING ERRCODE='22023'; END IF;
 IF p_specialty IS NULL OR NOT EXISTS(SELECT 1 FROM public.specialties WHERE id=p_specialty AND active)
   OR NOT private.attention_specialty_available(p_specialty) THEN
   RAISE EXCEPTION 'Especialidad sin médico activo asignado' USING ERRCODE='22023'; END IF;
 IF p_period IS NULL OR p_period NOT IN ('manana','tarde','indiferente') OR nullif(trim(p_reason),'') IS NULL
   OR length(p_reason)>2000 OR coalesce(length(p_other),0)>1000 OR coalesce(cardinality(p_symptoms),0)>30 THEN
   RAISE EXCEPTION 'Revisa el motivo, los síntomas y la preferencia' USING ERRCODE='22023'; END IF;
 IF coalesce(cardinality(p_symptoms),0)=0 OR EXISTS(SELECT 1 FROM unnest(p_symptoms) id
   WHERE id IS NULL OR NOT EXISTS(SELECT 1 FROM public.symptom_catalog s WHERE s.id=id AND s.active)) THEN
   RAISE EXCEPTION 'Selecciona síntomas activos' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.symptom_catalog WHERE id=ANY(p_symptoms) AND name='Otro')
   AND nullif(trim(p_other),'') IS NULL THEN RAISE EXCEPTION 'Describe el otro síntoma' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_missing) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_missing) k
   WHERE k NOT IN ('first_name','last_name','birth_date','phone','dui')) THEN
   RAISE EXCEPTION 'Campos personales no permitidos' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_missing) e(k,v) WHERE jsonb_typeof(v)<>'string' OR length(v#>>'{}')>100) THEN
   RAISE EXCEPTION 'Datos personales inválidos' USING ERRCODE='22023'; END IF;
 SELECT public.my_attention_context()->'person' INTO v_person;
 -- Only missing account fields can be completed. Never changes a clinical patient.
 SELECT jsonb_object_agg(k,CASE WHEN nullif(trim(v_person->>k),'') IS NULL THEN v ELSE v_person->k END)
 INTO v_person FROM jsonb_each(v_person || p_missing) e(k,v);
 v_birth=(v_person->>'birth_date')::date;
 IF nullif(trim(v_person->>'first_name'),'') IS NULL OR length(v_person->>'first_name')>100
   OR nullif(trim(v_person->>'last_name'),'') IS NULL OR length(v_person->>'last_name')>100
   OR (v_person->>'dui') IS NULL OR (v_person->>'dui') !~ '^[0-9]{8}-[0-9]$'
   OR (v_person->>'phone') IS NULL OR (v_person->>'phone') !~ '^[0-9]{4}-[0-9]{4}$'
   OR nullif(v_person->>'email','') IS NULL OR v_birth IS NULL OR v_birth>current_date
   OR v_birth<current_date-interval '120 years' THEN
   RAISE EXCEPTION 'Completa los datos personales obligatorios' USING ERRCODE='22023'; END IF;
 UPDATE public.profiles SET first_name=v_person->>'first_name',last_name=v_person->>'last_name',
   birth_date=v_birth,phone=v_person->>'phone' WHERE id=v_uid;
 SELECT id INTO v_patient FROM public.patients WHERE profile_id=v_uid;
 INSERT INTO public.appointment_requests(id,requester_id,patient_id,specialty_id,preferred_period,reason,
   applicant_data,other_symptoms,status)
 VALUES(p_key,v_uid,v_patient,p_specialty,p_period,trim(p_reason),v_person,nullif(trim(p_other),''),'pendiente');
 INSERT INTO public.appointment_request_symptoms(request_id,symptom_id)
 SELECT p_key,id FROM (SELECT DISTINCT unnest(p_symptoms) id) x;
 RETURN p_key;
END $function$;

COMMIT;
