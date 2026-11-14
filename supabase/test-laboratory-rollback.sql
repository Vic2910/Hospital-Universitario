-- Native doctor API E2E. All fixtures revert in the inner exception subtransaction.
CREATE OR REPLACE FUNCTION pg_temp.verify_mobile_laboratory() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
 u uuid=gen_random_uuid(); rec uuid=gen_random_uuid(); doc uuid=gen_random_uuid(); other_doc uuid=gen_random_uuid();
 staff_id uuid=gen_random_uuid(); other_staff uuid=gen_random_uuid(); room uuid=gen_random_uuid(); req uuid=gen_random_uuid();
 patient uuid; appointment uuid; encounter uuid; lab uuid=gen_random_uuid(); rx uuid=gen_random_uuid(); save_key uuid=gen_random_uuid();
 specialty bigint; symptom bigint; test_id bigint; medication uuid; ver integer; result jsonb; w jsonb; chart jsonb;
 dui text=lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0';
 lab_user uuid=gen_random_uuid(); lab_staff uuid=gen_random_uuid(); second_test bigint; lab_order uuid; batch jsonb;
 starts timestamptz=date_trunc('minute',now())+interval '10 minutes'; work_day date;
BEGIN
 BEGIN
  work_day=(starts AT TIME ZONE 'America/Guatemala')::date;
  SELECT id INTO specialty FROM public.specialties WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO symptom FROM public.symptom_catalog WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO test_id FROM public.lab_test_types WHERE active ORDER BY id LIMIT 1;
  IF test_id IS NULL THEN RAISE EXCEPTION 'No hay catálogo de laboratorio activo para verificar'; END IF;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (u,u::text||'@laboratory-flow.example.test',jsonb_build_object('first_name','Paciente temporal','last_name','Prueba','birth_date','1990-01-01','dui',dui,'phone','7999-0000')),
   (rec,rec::text||'@laboratory-flow.example.test','{}'),
   (doc,doc::text||'@laboratory-flow.example.test','{"first_name":"Doctor temporal","last_name":"Prueba"}'),
   (other_doc,other_doc::text||'@laboratory-flow.example.test','{}');
  UPDATE public.user_roles SET active=false WHERE user_id IN(rec,doc,other_doc);
  INSERT INTO public.user_roles(user_id,role) VALUES(rec,'recepcionista'),(doc,'doctor'),(other_doc,'doctor');
  INSERT INTO public.staff(id,profile_id,employee_code,category) VALUES(staff_id,doc,'DOCTOR-TEST-'||doc::text,'doctor'),(other_staff,other_doc,'DOCTOR-TEST-'||other_doc::text,'doctor');
  INSERT INTO public.doctor_specialties(doctor_id,specialty_id) VALUES(staff_id,specialty);
  INSERT INTO public.consulting_rooms(id,code) VALUES(room,'DOCTOR-TEST-'||room::text);
  INSERT INTO public.staff_shifts(staff_id,starts_at,ends_at) VALUES(staff_id,work_day::timestamp AT TIME ZONE 'America/Guatemala',(work_day+2)::timestamp AT TIME ZONE 'America/Guatemala');
  INSERT INTO public.doctor_schedules(doctor_id,weekday,start_time,end_time,valid_from,valid_until)
   SELECT staff_id,extract(dow FROM d),time '00:00',time '24:00',d::date,d::date FROM generate_series(work_day::timestamp,(work_day+1)::timestamp,interval '1 day')d;
  INSERT INTO public.doctor_consulting_rooms(doctor_id,consulting_room_id,starts_at,ends_at,slot_minutes) VALUES(staff_id,room,starts,starts+interval '3 hours',30);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM public.submit_my_attention_request(req,specialty,'indiferente','Motivo original de prueba',ARRAY[symptom]);
  BEGIN
   PERFORM public.doctor_native_workspace(starts-interval '1 hour',starts+interval '1 hour');
   RAISE EXCEPTION 'Paciente obtuvo acceso médico';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',rec,'role','authenticated')::text,true);
  patient=public.create_walkin_patient('Paciente temporal','Prueba',dui,'7999-0000','1990-01-01',NULL);
  PERFORM public.link_attention_patient(req,patient,true);
  appointment=public.schedule_appointment(patient,staff_id,room,starts,starts+interval '30 minutes',req);
  RESET ROLE;
  INSERT INTO public.medical_history(record_id,history_type,description) SELECT id,'alergia','Antecedente reversible de prueba' FROM public.medical_records WHERE patient_id=patient;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_doc,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  w=public.doctor_native_workspace(starts-interval '1 hour',starts+interval '1 hour');
  IF jsonb_array_length(w->'appointments')<>0 THEN RAISE EXCEPTION 'Otro doctor recibió citas ajenas'; END IF;
  IF (public.doctor_native_patients()->>'total')::int<>0 THEN RAISE EXCEPTION 'Directorio expone pacientes ajenos'; END IF;
  BEGIN
   PERFORM public.doctor_native_patient_labs(patient);
   RAISE EXCEPTION 'Otro doctor leyó laboratorios ajenos';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   PERFORM public.doctor_native_chart(patient);
   RAISE EXCEPTION 'Otro doctor abrió expediente ajeno';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
   PERFORM public.doctor_native_start(appointment,gen_random_uuid());
   RAISE EXCEPTION 'Otro doctor inició consulta ajena';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  w=public.doctor_native_workspace(starts-interval '1 hour',starts+interval '1 hour');
  IF jsonb_array_length(w->'appointments')<>1 OR w->'appointments'->0->>'reason'<>'Motivo original de prueba'
   OR jsonb_array_length(w->'appointments'->0->'symptoms')<>1 THEN RAISE EXCEPTION 'Agenda sin vínculo a solicitud y síntomas'; END IF;
  chart=public.doctor_native_chart(patient);
  IF (public.doctor_native_patients('Paciente temporal')->>'total')::int<>1
   OR (public.doctor_native_patients(replace(dui,'-',''))->>'total')::int<>1
   OR (public.doctor_native_patients(u::text||'@laboratory-flow.example.test')->>'total')::int<>1 THEN
   RAISE EXCEPTION 'Búsqueda por nombre, DUI o correo incompleta'; END IF;
  IF chart->'patient'->>'identification' IS DISTINCT FROM dui
   OR chart->'patient'->>'email' IS DISTINCT FROM u::text||'@laboratory-flow.example.test' THEN
   RAISE EXCEPTION 'Identificación o correo del expediente incorrectos'; END IF;
  IF jsonb_array_length(chart->'allergies')<>1 THEN RAISE EXCEPTION 'No se recuperó antecedente autorizado'; END IF;
  encounter=public.doctor_native_start(appointment,gen_random_uuid());
  IF public.doctor_native_start(appointment,gen_random_uuid())<>encounter THEN RAISE EXCEPTION 'Doble inicio duplicó consulta'; END IF;
  BEGIN
   PERFORM public.update_appointment_status(appointment,'completada');
   RAISE EXCEPTION 'Cita finalizada sin consulta completa';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  RESET ROLE;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES(lab_user,lab_user::text||'@laboratory-flow.example.test','{"first_name":"Laboratorio reversible"}');
  UPDATE public.user_roles SET active=false WHERE user_id=lab_user;
  INSERT INTO public.user_roles(user_id,role) VALUES(lab_user,'enfermera');
  INSERT INTO public.staff(id,profile_id,employee_code,category) VALUES(lab_staff,lab_user,'LAB-TEST-'||lab_user::text,'enfermera');
  INSERT INTO public.laboratory_authorizations(staff_id,can_process,can_validate,can_publish,authorized_by) VALUES(lab_staff,true,true,true,lab_user);
  SELECT id INTO second_test FROM public.lab_test_types WHERE active AND id<>test_id ORDER BY id LIMIT 1;
  IF second_test IS NULL THEN RAISE EXCEPTION 'Se necesitan dos exámenes activos'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  batch=public.doctor_native_labs(encounter,ARRAY[test_id,second_test],'Motivo local reversible',lab);
  IF public.doctor_native_labs(encounter,ARRAY[second_test,test_id],'Motivo local reversible',lab)<>batch THEN RAISE EXCEPTION 'Reintento duplicó selección'; END IF;
  IF (public.doctor_native_lab_orders()->>'total')::int<>2 THEN RAISE EXCEPTION 'No aparecen las dos órdenes propias'; END IF;
  BEGIN
   PERFORM public.doctor_native_labs(encounter,ARRAY[test_id,-1::bigint],'No debe insertar',gen_random_uuid());
   RAISE EXCEPTION 'Catálogo inválido permitido' USING ERRCODE='Z0002';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF (public.doctor_native_lab_orders()->>'total')::int<>2 THEN RAISE EXCEPTION 'Envío inválido dejó orden parcial'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_doc,'role','authenticated')::text,true);
  BEGIN
   PERFORM public.doctor_native_labs(encounter,ARRAY[test_id],'No autorizado',gen_random_uuid());
   RAISE EXCEPTION 'Otro doctor creó orden ajena' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF (public.doctor_native_lab_orders()->>'total')::int<>0 THEN RAISE EXCEPTION 'Otro doctor ve órdenes ajenas'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lab_user,'role','authenticated')::text,true);
  w=public.laboratory_panel(p_doctor=>staff_id);
  IF (w->>'total')::int<>2 THEN RAISE EXCEPTION 'Panel de laboratorio no recibe el formato existente'; END IF;
  SELECT id INTO lab_order FROM public.lab_orders WHERE encounter_id=encounter AND test_type_id=test_id;
  PERFORM public.configure_laboratory_test(test_id,'[{"key":"observacion_local","label":"Observación de prueba local","type":"text","required":true}]',
    (SELECT xmin::text FROM public.lab_test_types WHERE id=test_id));
  PERFORM public.start_laboratory_order(lab_order);
  PERFORM public.save_laboratory_draft(lab_order,0,'Informe descriptivo local reversible','{"observacion_local":{"value":"Valor local reversible","observation":"Observación local reversible"}}');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order)<>0 OR (SELECT count(*) FROM public.lab_result_drafts WHERE order_id=lab_order)<>0 THEN RAISE EXCEPTION 'Doctor lee borradores'; END IF;
  w=public.doctor_native_patient_labs(patient);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(w->'items') x WHERE x->>'result_summary' IS NOT NULL OR jsonb_array_length(x->'parameters')<>0) THEN RAISE EXCEPTION 'RPC expone borrador'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order)<>0 THEN RAISE EXCEPTION 'Paciente lee borrador'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lab_user,'role','authenticated')::text,true);
  PERFORM public.submit_laboratory_validation(lab_order,1);
  PERFORM public.validate_laboratory_result(lab_order,2);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order)<>0 THEN RAISE EXCEPTION 'Validado sin publicar visible'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lab_user,'role','authenticated')::text,true);
  PERFORM public.publish_laboratory_order(lab_order,3,false);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  w=public.doctor_native_patient_labs(patient);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(w->'items') x WHERE x->>'id'=lab_order::text AND x->>'status'='completado'
    AND x->>'result_summary' LIKE '%Informe descriptivo local reversible%' AND x->'parameters'->0->>'value'='Valor local reversible') THEN RAISE EXCEPTION 'Doctor no ve informe publicado y parámetros'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order)<>0 THEN RAISE EXCEPTION 'Paciente ve resultado sin publicación propia'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lab_user,'role','authenticated')::text,true);
  PERFORM public.reception_release_lab(lab_order);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order AND published_to_patient_at IS NOT NULL AND result_values->'observacion_local'->>'value'='Valor local reversible')<>1 THEN RAISE EXCEPTION 'Paciente no recupera resultado propio publicado'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_doc,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.lab_results WHERE order_id=lab_order)<>0 THEN RAISE EXCEPTION 'Doctor ajeno ve informe'; END IF;
  RESET ROLE;
  IF (SELECT count(*) FROM public.lab_orders WHERE encounter_id=encounter)<>2 THEN RAISE EXCEPTION 'Órdenes duplicadas'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  result=jsonb_build_object('result','PASS','flow','selección múltiple → dos órdenes del formato actual → panel Laboratorios → borrador → validación → publicación doctor → publicación paciente',
   'security','sin borradores para doctor/paciente; sin resultados ajenos; sin órdenes parciales; reintento sin duplicar','fixtures','revertidos');
  RAISE EXCEPTION 'Rollback laboratory fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN result;
 END;
END $$;
SELECT pg_temp.verify_mobile_laboratory() verification;
