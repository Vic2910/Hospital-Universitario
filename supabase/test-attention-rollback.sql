-- Controlled, transactional verification. Every fixture is rolled back by the inner exception.
-- The only function created is session-local in pg_temp, never in an application schema.
CREATE OR REPLACE FUNCTION pg_temp.verify_attention_flow() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
 v_user uuid=gen_random_uuid(); v_other uuid=gen_random_uuid(); v_reception uuid=gen_random_uuid();
 v_doctor_profile uuid=gen_random_uuid(); v_doctor uuid=gen_random_uuid(); v_room uuid=gen_random_uuid();
 v_request uuid=gen_random_uuid(); v_patient uuid; v_appointment uuid; v_specialty bigint; v_symptom bigint;
 v_dui text=lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0';
 v_day date=(now() AT TIME ZONE 'America/Guatemala')::date+2;
 v_start timestamptz; v_context jsonb; v_rows jsonb; v_result jsonb; v_unavailable bigint;
BEGIN
 BEGIN
  SELECT id INTO v_specialty FROM public.specialties WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO v_symptom FROM public.symptom_catalog WHERE active ORDER BY id LIMIT 1;
  IF v_specialty IS NULL OR v_symptom IS NULL THEN RAISE EXCEPTION 'Falta catálogo real para prueba'; END IF;
  v_start=(v_day+time '09:00') AT TIME ZONE 'America/Guatemala';
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (v_user,v_user::text||'@attention.example.test',jsonb_build_object('first_name','Prueba transaccional','last_name','Solicitante','birth_date','1990-01-01','phone','7999-0000','dui',v_dui)),
   (v_other,v_other::text||'@attention.example.test','{}'),
   (v_reception,v_reception::text||'@attention.example.test','{}'),
   (v_doctor_profile,v_doctor_profile::text||'@attention.example.test','{}');
  UPDATE public.user_roles SET active=false WHERE user_id IN(v_reception,v_doctor_profile);
  INSERT INTO public.user_roles(user_id,role) VALUES(v_reception,'recepcionista'),(v_doctor_profile,'doctor');
  INSERT INTO public.staff(id,profile_id,employee_code,category) VALUES(v_doctor,v_doctor_profile,'TEST-'||v_doctor::text,'doctor');
  INSERT INTO public.doctor_specialties(doctor_id,specialty_id) VALUES(v_doctor,v_specialty);
  INSERT INTO public.consulting_rooms(id,code) VALUES(v_room,'TEST-'||v_room::text);
  INSERT INTO public.staff_shifts(staff_id,starts_at,ends_at) VALUES(v_doctor,v_start-interval '1 hour',v_start+interval '8 hours');
  INSERT INTO public.doctor_schedules(doctor_id,weekday,start_time,end_time,valid_from,valid_until)
   VALUES(v_doctor,extract(dow FROM v_day),time '08:00',time '17:00',v_day,v_day);
  INSERT INTO public.doctor_consulting_rooms(doctor_id,consulting_room_id,starts_at,ends_at,slot_minutes)
   VALUES(v_doctor,v_room,v_start,v_start+interval '3 hours',30);

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  v_context=public.my_attention_context();
  IF v_context->'person'->>'dui'<>v_dui THEN RAISE EXCEPTION 'No precarga DUI de la cuenta'; END IF;
  IF public.submit_my_attention_request(v_request,v_specialty,'indiferente','Prueba con reversión',ARRAY[v_symptom])<>v_request THEN
    RAISE EXCEPTION 'No devuelve solicitud'; END IF;
  PERFORM public.submit_my_attention_request(v_request,v_specialty,'indiferente','Prueba con reversión',ARRAY[v_symptom]);
  IF (SELECT count(*) FROM public.appointment_requests WHERE id=v_request)<>1 THEN RAISE EXCEPTION 'Idempotencia fallida'; END IF;
  IF EXISTS(SELECT 1 FROM public.patients WHERE profile_id=v_user) THEN RAISE EXCEPTION 'Creó paciente durante solicitud'; END IF;
  IF (SELECT patient_id FROM public.appointment_requests WHERE id=v_request) IS NOT NULL THEN RAISE EXCEPTION 'No admite cuenta sin expediente'; END IF;
  BEGIN
   PERFORM public.review_attention_request(v_request,'en_revision');
   RAISE EXCEPTION 'Paciente pudo revisar';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   PERFORM public.submit_my_attention_request(gen_random_uuid(),v_specialty,'manana','Suplantación',ARRAY[v_symptom],NULL,jsonb_build_object('user_id',v_other));
   RAISE EXCEPTION 'Aceptó identidad enviada';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
   UPDATE public.user_roles SET role='admin' WHERE user_id=v_user;
   RAISE EXCEPTION 'Paciente pudo cambiar rol';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_other,'role','authenticated')::text,true);
  IF EXISTS(SELECT 1 FROM public.appointment_requests WHERE id=v_request) THEN RAISE EXCEPTION 'RLS filtra otra cuenta incorrectamente'; END IF;
  IF jsonb_array_length(public.my_attention_requests())<>0 THEN RAISE EXCEPTION 'RPC expone otra solicitud'; END IF;
  BEGIN
   PERFORM public.submit_my_attention_request(v_request,v_specialty,'manana','Otra cuenta',ARRAY[v_symptom]);
   RAISE EXCEPTION 'Otra cuenta reutilizó clave';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   INSERT INTO public.appointment_requests(requester_id,specialty_id,preferred_period,reason)
    VALUES(v_user,v_specialty,'manana','Suplantación por REST');
   RAISE EXCEPTION 'Aceptó otra cuenta por inserción directa';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  SELECT (x->>'id')::bigint INTO v_unavailable FROM jsonb_array_elements(public.my_attention_context()->'specialties') x
   WHERE (x->>'available')::boolean=false LIMIT 1;
  IF v_unavailable IS NOT NULL THEN
   BEGIN
    PERFORM public.submit_my_attention_request(gen_random_uuid(),v_unavailable,'manana','Sin médico',ARRAY[v_symptom]);
    RAISE EXCEPTION 'Aceptó especialidad sin médico';
   EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END IF;
  PERFORM public.submit_my_attention_request(gen_random_uuid(),v_specialty,'tarde','Datos completados',ARRAY[v_symptom],NULL,
   jsonb_build_object('first_name','Prueba','last_name','Cuenta incompleta','birth_date','1995-01-01','phone','7999-0001','dui',
   lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-1'));
  IF public.my_attention_context()->'person'->>'phone'<>'7999-0001' THEN
   RAISE EXCEPTION 'No completa de forma segura el perfil'; END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_reception,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.appointment_requests WHERE id=v_request)<>1 THEN RAISE EXCEPTION 'Recepción no ve la solicitud'; END IF;
  PERFORM public.review_attention_request(v_request,'en_revision');
  v_patient=public.create_walkin_patient('Prueba transaccional','Solicitante',v_dui,'7999-0000','1990-01-01',NULL);
  BEGIN
   PERFORM public.link_attention_patient(v_request,v_patient,false);
   RAISE EXCEPTION 'Vinculación sin verificar identidad';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.link_attention_patient(v_request,v_patient,true);
  v_appointment=public.schedule_appointment(v_patient,v_doctor,v_room,v_start,v_start+interval '30 minutes',v_request);
  BEGIN
   PERFORM public.schedule_appointment(v_patient,v_doctor,v_room,v_start+interval '30 minutes',v_start+interval '60 minutes',v_request);
   RAISE EXCEPTION 'Recepción pudo duplicar la cita';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='Recepción pudo duplicar la cita' THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  v_rows=public.my_attention_requests();
  IF v_rows->0->>'status'<>'agendada' OR (v_rows->0->>'appointment_id')::uuid<>v_appointment THEN
   RAISE EXCEPTION 'Seguimiento no refleja cita'; END IF;
  IF (SELECT count(*) FROM public.appointments WHERE id=v_appointment AND patient_id=v_patient)<>1 THEN
   RAISE EXCEPTION 'Paciente no ve su cita por RLS'; END IF;
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE;
  v_result=jsonb_build_object('result','PASS','flow','cuenta sin expediente → pendiente → recepción → vínculo → cita → lectura propia',
    'security','RLS entre cuentas, rol protegido, RPC staff denegada a paciente, sin suplantación',
    'idempotency','una solicitud y una cita','fixtures','revertidos por subtransacción');
  RAISE EXCEPTION 'Rollback fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN
  RETURN v_result;
 END;
END $$;
SELECT pg_temp.verify_attention_flow() verification;
