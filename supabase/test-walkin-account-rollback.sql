-- Real database triggers/RPC/RLS; temporary identities, entirely reverted. Not an HTTP signup test.
CREATE OR REPLACE FUNCTION pg_temp.verify_walkin_account() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE receptionist uuid=gen_random_uuid(); doctor_user uuid=gen_random_uuid(); doctor_staff uuid=gen_random_uuid();
 account_user uuid=gen_random_uuid(); other_user uuid=gen_random_uuid(); normal_user uuid=gen_random_uuid();
 patient uuid; record uuid; request uuid=gen_random_uuid(); other_request uuid=gen_random_uuid();
 specialty bigint; symptom bigint; result jsonb;
 document text=lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0';
BEGIN
 BEGIN
  SELECT id INTO specialty FROM public.specialties WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO symptom FROM public.symptom_catalog WHERE active AND name<>'Otro' ORDER BY id LIMIT 1;
  IF specialty IS NULL OR symptom IS NULL THEN RAISE EXCEPTION 'Falta catálogo requerido'; END IF;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (receptionist,receptionist::text||'@walkin-account.example.test','{}'),(doctor_user,doctor_user::text||'@walkin-account.example.test','{}');
  UPDATE public.user_roles SET active=false WHERE user_id IN(receptionist,doctor_user);
  INSERT INTO public.user_roles(user_id,role) VALUES(receptionist,'recepcionista'),(doctor_user,'doctor');
  INSERT INTO public.staff(id,profile_id,employee_code,category) VALUES(doctor_staff,doctor_user,'WALKIN-TEST-'||doctor_user::text,'doctor');
  INSERT INTO public.doctor_specialties(doctor_id,specialty_id) VALUES(doctor_staff,specialty);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',receptionist,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  patient=public.create_walkin_patient('Persona local','Presencial',document,'7999-0000','1990-01-01',NULL);
  SELECT id INTO record FROM public.medical_records WHERE patient_id=patient;
  RESET ROLE;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (account_user,account_user::text||'@walkin-account.example.test',jsonb_build_object('first_name','Persona local','last_name','Presencial','birth_date','1990-01-01','phone','7999-0000','dui',document));
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=account_user) OR NOT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=account_user AND role='paciente' AND active)
   OR EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=account_user AND role<>'paciente' AND active) THEN RAISE EXCEPTION 'Cuenta/perfil/rol incorrecto'; END IF;
  IF (SELECT count(*) FROM public.patients WHERE dui=document)<>1 OR (SELECT profile_id FROM public.patients WHERE id=patient) IS NOT NULL THEN RAISE EXCEPTION 'Duplicó o vinculó automáticamente'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',account_user,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.patients WHERE id=patient)<>0 OR (SELECT count(*) FROM public.medical_records WHERE id=record)<>0 THEN RAISE EXCEPTION 'Acceso clínico por coincidencia de DUI'; END IF;
  PERFORM public.submit_my_attention_request(request,specialty,'indiferente','Solicitud local reversible',ARRAY[symptom]);
  IF (SELECT patient_id FROM public.appointment_requests WHERE id=request) IS NOT NULL THEN RAISE EXCEPTION 'Solicitud vinculó por DUI'; END IF;
  BEGIN
   PERFORM public.link_attention_patient(request,patient,true);
   RAISE EXCEPTION 'Paciente se vinculó solo' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',receptionist,'role','authenticated')::text,true);
  BEGIN
   PERFORM public.link_attention_patient(request,patient,false);
   RAISE EXCEPTION 'Vinculó sin confirmar identidad' USING ERRCODE='Z0002';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.link_attention_patient(request,patient,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',account_user,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.patients WHERE id=patient AND profile_id=account_user)<>1
   OR (SELECT count(*) FROM public.medical_records WHERE id=record AND patient_id=patient)<>1 THEN RAISE EXCEPTION 'No conserva expediente al vincular'; END IF;
  RESET ROLE;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (other_user,other_user::text||'@walkin-account.example.test',jsonb_build_object('first_name','Otra cuenta local','last_name','Prueba','birth_date','1990-01-01','phone','7999-0000','dui',document)),
   (normal_user,normal_user::text||'@walkin-account.example.test','{"first_name":"Cuenta nueva local","last_name":"Prueba","birth_date":"1990-01-01"}');
  IF EXISTS(SELECT 1 FROM public.patients WHERE profile_id IN(other_user,normal_user)) THEN RAISE EXCEPTION 'Creó paciente en registro Auth'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.patients WHERE id=patient)<>0 OR (SELECT count(*) FROM public.medical_records WHERE id=record)<>0 THEN RAISE EXCEPTION 'Cuenta ajena obtuvo datos'; END IF;
  PERFORM public.submit_my_attention_request(other_request,specialty,'indiferente','Revisión local reversible',ARRAY[symptom]);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',receptionist,'role','authenticated')::text,true);
  BEGIN
   PERFORM public.link_attention_patient(other_request,patient,true);
   RAISE EXCEPTION 'Reasignó expediente de otra cuenta' USING ERRCODE='Z0002';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  RESET ROLE;
  IF (SELECT count(*) FROM public.patients WHERE dui=document)<>1 OR (SELECT profile_id FROM public.patients WHERE id=patient) IS DISTINCT FROM account_user
   OR (SELECT id FROM public.medical_records WHERE patient_id=patient) IS DISTINCT FROM record THEN RAISE EXCEPTION 'Alteró identidad o duplicó expediente'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  result=jsonb_build_object('result','PASS','flow','expediente presencial → cuenta/perfil sin duplicar → sin acceso automático → recepción verifica/vincula → mismo expediente accesible',
   'security','otra cuenta sin acceso ni reasignación; registro nuevo sin paciente/expediente','fixtures','revertidos');
  RAISE EXCEPTION 'Rollback walkin account fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN result;
 END;
END $$;
SELECT pg_temp.verify_walkin_account() verification;
