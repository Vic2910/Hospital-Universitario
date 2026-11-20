-- Hospital Moviles only. Additive alerts, own completed history and restricted consultation notes.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION private.doctor_appointment_notice()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE recipient uuid; event text;
BEGIN
 IF TG_OP='UPDATE' AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
 AND NEW.starts_at IS NOT DISTINCT FROM OLD.starts_at AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
 IF NEW.status NOT IN ('programada','confirmada') THEN RETURN NEW; END IF;
 SELECT s.profile_id INTO recipient FROM public.staff s WHERE s.id=NEW.doctor_id AND s.active AND s.category='doctor'
 AND EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=s.profile_id AND r.role='doctor' AND r.active);
 IF recipient IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id AND NEW.starts_at IS NOT DISTINCT FROM OLD.starts_at THEN RETURN NEW; END IF;
 event='appointment:'||NEW.id::text||':'||extract(epoch from NEW.starts_at)::text;
 INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
 VALUES(recipient,'Cita asignada','Tienes una cita el '||to_char(NEW.starts_at AT TIME ZONE 'America/Guatemala','DD/MM/YYYY HH24:MI')||'. Revisa tu agenda.','cita','appointments',NEW.id::text,event)
 ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.doctor_appointment_notice() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER doctor_appointment_notice AFTER INSERT OR UPDATE OF doctor_id,starts_at,status ON public.appointments
FOR EACH ROW EXECUTE FUNCTION private.doctor_appointment_notice();

CREATE OR REPLACE FUNCTION public.doctor_native_alerts(p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); items jsonb;
BEGIN
 IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
 SELECT auth.uid(),'Tu próxima consulta está por comenzar',
 'Tienes una cita a las '||to_char(a.starts_at AT TIME ZONE 'America/Guatemala','HH24:MI')||'. Revisa los detalles en tu agenda.',
 'recordatorio_cita','appointments',a.id::text,'reminder:'||a.id::text||':'||extract(epoch from a.starts_at)::text
 FROM public.appointments a WHERE a.doctor_id=d AND a.status IN ('programada','confirmada')
 AND a.starts_at>now() AND a.starts_at<=now()+interval '15 minutes'
 ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]') INTO items FROM
 (SELECT n.id,n.title,n.body,n.created_at,n.read_at,0 row_version,n.entity_type,n.entity_id
 FROM public.notifications n WHERE n.recipient_id=auth.uid() ORDER BY n.created_at DESC,n.id DESC LIMIT 30 OFFSET p_offset)x;
 RETURN jsonb_build_object('items',items,'unread',(SELECT count(*) FROM public.notifications WHERE recipient_id=auth.uid() AND read_at IS NULL),
 'has_more',(SELECT count(*)>p_offset+30 FROM public.notifications WHERE recipient_id=auth.uid()),
 'upcoming',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'starts_at',a.starts_at) ORDER BY a.starts_at),'[]') FROM
 (SELECT id,starts_at FROM public.appointments WHERE doctor_id=d AND status IN ('programada','confirmada')
 AND starts_at>now() AND starts_at<now()+interval '7 days' ORDER BY starts_at LIMIT 50)a));
END $$;
REVOKE ALL ON FUNCTION public.doctor_native_alerts(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_alerts(integer) TO authenticated;

-- This helper does not throw for other roles; it is safe inside RLS and does not recurse through RLS.
CREATE OR REPLACE FUNCTION private.owns_clinical_note(p_encounter uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT private.has_role('doctor') AND EXISTS(
 SELECT 1 FROM public.clinical_encounters e JOIN public.staff s ON s.id=e.doctor_id
 WHERE e.id=p_encounter AND s.profile_id=auth.uid() AND s.active AND s.category='doctor')
$$;
REVOKE ALL ON FUNCTION private.owns_clinical_note(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.owns_clinical_note(uuid) TO authenticated;
ALTER POLICY encounters_read ON public.clinical_encounters USING (
 private.owns_clinical_note(id) OR (ended_at IS NOT NULL AND private.my_patient(private.encounter_patient(id))));
ALTER POLICY diagnoses_read ON public.diagnoses USING (
 private.owns_clinical_note(encounter_id) OR (private.my_patient(private.encounter_patient(encounter_id))
 AND EXISTS(SELECT 1 FROM public.clinical_encounters e WHERE e.id=encounter_id AND e.ended_at IS NOT NULL)));
COMMIT;
