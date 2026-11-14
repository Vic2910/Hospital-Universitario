-- Hospital Móviles only. Additive account-owned requests; no clinical auto-enrollment.
ALTER TABLE public.appointment_requests ALTER COLUMN patient_id DROP NOT NULL;
ALTER TABLE public.appointment_requests
 ADD COLUMN requester_id uuid REFERENCES public.profiles(id),
 ADD COLUMN applicant_data jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN other_symptoms text;
UPDATE public.appointment_requests r SET requester_id=p.profile_id
 FROM public.patients p WHERE p.id=r.patient_id;
CREATE INDEX appointment_requests_requester_created_idx ON public.appointment_requests(requester_id,created_at DESC);
ALTER TABLE public.appointment_requests DROP CONSTRAINT appointment_requests_preferred_period_check;
ALTER TABLE public.appointment_requests ADD CONSTRAINT appointment_requests_preferred_period_check
 CHECK(preferred_period IN ('manana','tarde','indiferente'));
ALTER TABLE public.appointment_requests ADD CONSTRAINT attention_owner_required
 CHECK(patient_id IS NOT NULL OR requester_id IS NOT NULL);
ALTER TABLE public.appointment_requests ADD CONSTRAINT attention_other_length CHECK(length(other_symptoms)<=1000);

-- Existing catalogs remain authoritative; these are requested master symptom labels.
INSERT INTO public.symptom_catalog(name)
 VALUES('Gripe'),('Lesión o posible fractura'),('Otro')
 ON CONFLICT(name) DO NOTHING;

CREATE FUNCTION private.attention_request_owner() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NOT NULL AND NOT(private.has_role('recepcionista') OR private.has_role('admin')) THEN
   IF NOT private.has_role('paciente') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
   IF NEW.requester_id IS NOT NULL AND NEW.requester_id<>auth.uid() THEN
     RAISE EXCEPTION 'No puede enviar por otra cuenta' USING ERRCODE='42501';
   END IF;
   NEW.requester_id=auth.uid();
   IF NEW.patient_id IS NOT NULL AND NOT private.my_patient(NEW.patient_id) THEN
     RAISE EXCEPTION 'Paciente ajeno' USING ERRCODE='42501';
   END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.attention_request_owner() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER attention_request_owner BEFORE INSERT ON public.appointment_requests
 FOR EACH ROW EXECUTE FUNCTION private.attention_request_owner();
CREATE POLICY attention_account_read ON public.appointment_requests FOR SELECT TO authenticated
 USING(requester_id=(SELECT auth.uid()) AND private.has_role('paciente'));

CREATE FUNCTION private.attention_specialty_available(p_specialty bigint) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.doctor_specialties d JOIN public.staff s ON s.id=d.doctor_id
 JOIN public.user_roles r ON r.user_id=s.profile_id AND r.role='doctor' AND r.active
 WHERE d.specialty_id=p_specialty AND s.active AND s.category='doctor')
$$;
REVOKE ALL ON FUNCTION private.attention_specialty_available(bigint) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.my_attention_context() RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid=auth.uid(); v_person jsonb;
BEGIN
 IF v_uid IS NULL OR NOT private.has_role('paciente') THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('first_name',p.first_name,'last_name',p.last_name,
   'birth_date',p.birth_date,'phone',p.phone,'email',u.email,
   'dui',coalesce(nullif(pt.dui,''),nullif(u.raw_user_meta_data->>'dui',''),
     (SELECT ar.applicant_data->>'dui' FROM public.appointment_requests ar WHERE ar.requester_id=v_uid
      AND ar.applicant_data ? 'dui' ORDER BY ar.created_at DESC LIMIT 1)))
 INTO v_person FROM public.profiles p JOIN auth.users u ON u.id=p.id
 LEFT JOIN public.patients pt ON pt.profile_id=p.id WHERE p.id=v_uid;
 IF v_person IS NULL THEN RAISE EXCEPTION 'Perfil no disponible' USING ERRCODE='42501'; END IF;
 IF coalesce(v_person->>'dui','') !~ '^[0-9]{8}-[0-9]$' THEN
   v_person=jsonb_set(v_person,'{dui}','null'::jsonb); END IF;
 IF coalesce(v_person->>'phone','') !~ '^[0-9]{4}-[0-9]{4}$' THEN
   v_person=jsonb_set(v_person,'{phone}','null'::jsonb); END IF;
 IF (v_person->>'birth_date')::date>current_date OR (v_person->>'birth_date')::date<current_date-interval '120 years' THEN
   v_person=jsonb_set(v_person,'{birth_date}','null'::jsonb); END IF;
 IF length(v_person->>'first_name')>100 THEN v_person=jsonb_set(v_person,'{first_name}','null'::jsonb); END IF;
 IF length(v_person->>'last_name')>100 THEN v_person=jsonb_set(v_person,'{last_name}','null'::jsonb); END IF;
 RETURN jsonb_build_object('person',v_person,
 'specialties',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,
   'available',private.attention_specialty_available(s.id)) ORDER BY s.name),'[]'::jsonb)
   FROM public.specialties s WHERE s.active),
 'symptoms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) ORDER BY s.id),'[]'::jsonb)
   FROM public.symptom_catalog s WHERE s.active));
END $$;

CREATE FUNCTION public.submit_my_attention_request(p_key uuid,p_specialty bigint,p_period text,p_reason text,
 p_symptoms bigint[],p_other text DEFAULT NULL,p_missing jsonb DEFAULT '{}'::jsonb) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
END $$;

CREATE FUNCTION public.my_attention_requests() RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('paciente') THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC,r.id DESC) FROM (
   SELECT ar.id,ar.created_at,ar.status,ar.reason,ar.preferred_period,s.name specialty_name,
     ar.other_symptoms,(SELECT coalesce(jsonb_agg(c.name ORDER BY c.id),'[]'::jsonb)
     FROM public.appointment_request_symptoms rs JOIN public.symptom_catalog c ON c.id=rs.symptom_id
     WHERE rs.request_id=ar.id) symptoms,
     (SELECT a.id FROM public.appointments a WHERE a.request_id=ar.id) appointment_id
   FROM public.appointment_requests ar JOIN public.specialties s ON s.id=ar.specialty_id
   WHERE ar.requester_id=auth.uid() OR private.my_patient(ar.patient_id)
   ORDER BY ar.created_at DESC,ar.id DESC LIMIT 100) r),'[]'::jsonb);
END $$;

-- Backend handoff for the separate reception project. No second scheduling engine.
CREATE FUNCTION public.review_attention_request(p_request uuid,p_status public.request_state) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_status public.request_state;
BEGIN
 IF auth.uid() IS NULL OR NOT(private.has_role('recepcionista') OR private.has_role('admin')) THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT status INTO v_status FROM public.appointment_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente' USING ERRCODE='22023'; END IF;
 IF v_status=p_status THEN RETURN; END IF;
 IF v_status NOT IN ('pendiente','en_revision') OR p_status IS NULL OR p_status NOT IN ('en_revision','rechazada','cancelada') THEN
   RAISE EXCEPTION 'Transición no permitida' USING ERRCODE='22023'; END IF;
 UPDATE public.appointment_requests SET status=p_status,reviewed_by=auth.uid() WHERE id=p_request;
END $$;

CREATE FUNCTION public.link_attention_patient(p_request uuid,p_patient uuid,p_identity_confirmed boolean) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_r public.appointment_requests%ROWTYPE; v_p public.patients%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT(private.has_role('recepcionista') OR private.has_role('admin')) THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 IF p_identity_confirmed IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Recepción debe verificar la identidad' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_r FROM public.appointment_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_r.requester_id IS NULL OR v_r.status NOT IN ('pendiente','en_revision') THEN
   RAISE EXCEPTION 'Solicitud no vinculable' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public.profiles WHERE id=v_r.requester_id FOR UPDATE;
 SELECT * INTO v_p FROM public.patients WHERE id=p_patient FOR UPDATE;
 IF NOT FOUND OR (v_p.profile_id IS NOT NULL AND v_p.profile_id<>v_r.requester_id)
   OR (v_r.patient_id IS NOT NULL AND v_r.patient_id<>p_patient)
   OR EXISTS(SELECT 1 FROM public.patients WHERE profile_id=v_r.requester_id AND id<>p_patient)
   OR v_p.dui IS DISTINCT FROM v_r.applicant_data->>'dui'
   OR v_p.birth_date IS DISTINCT FROM (v_r.applicant_data->>'birth_date')::date THEN
   RAISE EXCEPTION 'Identidad incompatible o paciente ya vinculado' USING ERRCODE='22023'; END IF;
 UPDATE public.patients SET profile_id=v_r.requester_id WHERE id=p_patient;
 UPDATE public.appointment_requests SET patient_id=p_patient,status='en_revision',reviewed_by=auth.uid() WHERE id=p_request;
END $$;

REVOKE ALL ON FUNCTION public.my_attention_context() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.my_attention_requests() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.submit_my_attention_request(uuid,bigint,text,text,bigint[],text,jsonb) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.review_attention_request(uuid,public.request_state) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.link_attention_patient(uuid,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_attention_context(),public.my_attention_requests(),
 public.submit_my_attention_request(uuid,bigint,text,text,bigint[],text,jsonb),
 public.review_attention_request(uuid,public.request_state),public.link_attention_patient(uuid,uuid,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
