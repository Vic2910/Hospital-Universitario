CREATE OR REPLACE FUNCTION private.attention_request_owner() RETURNS trigger
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

CREATE OR REPLACE FUNCTION public.my_attention_context() RETURNS jsonb
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
