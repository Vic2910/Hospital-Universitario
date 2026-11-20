-- Native doctor API E2E. All fixtures revert in the inner exception subtransaction.
BEGIN;
DO $$
DECLARE
 u uuid=gen_random_uuid(); rec uuid=gen_random_uuid(); doc uuid=gen_random_uuid(); other_doc uuid=gen_random_uuid();
 staff_id uuid=gen_random_uuid(); other_staff uuid=gen_random_uuid(); room uuid=gen_random_uuid(); req uuid=gen_random_uuid();
 patient uuid; appointment uuid; encounter uuid; lab uuid=gen_random_uuid(); rx uuid=gen_random_uuid(); save_key uuid=gen_random_uuid();
 specialty bigint; symptom bigint; test_id bigint; medication uuid; ver integer; result jsonb; w jsonb; chart jsonb;
 dui text=lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0';
 starts timestamptz=date_trunc('minute',now())+interval '10 minutes'; work_day date;
BEGIN
 BEGIN
  work_day=(starts AT TIME ZONE 'America/Guatemala')::date;
  SELECT id INTO specialty FROM public.specialties WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO symptom FROM public.symptom_catalog WHERE active ORDER BY id LIMIT 1;
  SELECT id INTO test_id FROM public.lab_test_types WHERE active ORDER BY id LIMIT 1;
  IF test_id IS NULL THEN RAISE EXCEPTION 'No hay catálogo de laboratorio activo para verificar'; END IF;
  SELECT id INTO medication FROM public.medications WHERE active ORDER BY id LIMIT 1;
  IF medication IS NULL THEN
   INSERT INTO public.medications(name,strength,presentation) VALUES('TEST reversible, no uso clínico','TEST','TEST') RETURNING id INTO medication;
  END IF;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (u,u::text||'@doctor-flow.example.test',jsonb_build_object('first_name','Paciente temporal','last_name','Prueba','birth_date','1990-01-01','dui',dui,'phone','7999-0000')),
   (rec,rec::text||'@doctor-flow.example.test','{}'),
   (doc,doc::text||'@doctor-flow.example.test','{"first_name":"Doctor temporal","last_name":"Prueba"}'),
   (other_doc,other_doc::text||'@doctor-flow.example.test','{}');
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
  patient=public.create_walkin_patient('Paciente temporal','Prueba',dui,'7999-0000','1990-01-01','Santa Ana');
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
   OR (public.doctor_native_patients(u::text||'@doctor-flow.example.test')->>'total')::int<>1 THEN
   RAISE EXCEPTION 'Búsqueda por nombre, DUI o correo incompleta'; END IF;
  IF chart->'patient'->>'identification' IS DISTINCT FROM dui
   OR chart->'patient'->>'email' IS DISTINCT FROM u::text||'@doctor-flow.example.test' THEN
   RAISE EXCEPTION 'Identificación o correo del expediente incorrectos'; END IF;
  IF jsonb_array_length(chart->'allergies')<>1 THEN RAISE EXCEPTION 'No se recuperó antecedente autorizado'; END IF;
  w=public.doctor_native_alerts();
  IF (w->>'unread')::int<>2 THEN RAISE EXCEPTION 'Asignación o recordatorio ausentes'; END IF;
  w=public.doctor_native_alerts();
  IF (w->>'unread')::int<>2 THEN RAISE EXCEPTION 'Recordatorio duplicado'; END IF;
  IF jsonb_array_length(w->'upcoming')<>1 THEN RAISE EXCEPTION 'Agenda de recordatorios incorrecta'; END IF;
  encounter=public.doctor_native_start(appointment,gen_random_uuid());
  IF public.doctor_native_start(appointment,gen_random_uuid())<>encounter THEN RAISE EXCEPTION 'Doble inicio duplicó consulta'; END IF;
  BEGIN
   PERFORM public.update_appointment_status(appointment,'completada');
   RAISE EXCEPTION 'Cita finalizada sin consulta completa';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ver=public.doctor_native_save(encounter,0,save_key,'{"subjective":"Borrador parcial"}');
  IF public.doctor_native_save(encounter,0,save_key,'{"subjective":"Borrador parcial"}')<>ver THEN RAISE EXCEPTION 'Reintento de guardado falló'; END IF;
  ver=public.doctor_native_save(encounter,ver,gen_random_uuid(),'{"subjective":"Motivo revisado","objective":"Exploración de prueba","assessment":"Evaluación transaccional","plan":"Indicaciones transaccionales","vitals":{"weight_kg":"70","height_cm":"170","systolic":"120","diastolic":"80","temperature_c":"37","heart_rate":"75"}}');
  PERFORM public.doctor_native_lab(encounter,test_id,'Orden reversible de prueba',lab);
  PERFORM public.doctor_native_lab(encounter,test_id,'Orden reversible de prueba',lab);
  IF (public.doctor_native_patient_labs(patient)->>'total')::int<>1 THEN RAISE EXCEPTION 'No recupera laboratorios del paciente'; END IF;
  PERFORM public.doctor_native_prescribe(encounter,rx,jsonb_build_array(jsonb_build_object('medication_id',medication,'dose',1,'dose_unit','unidad de prueba','frequency_hours',8,'route','oral','quantity',3,'duration_days',1,'observations','No uso clínico, prueba reversible')));
  PERFORM public.doctor_native_prescribe(encounter,rx,'[]');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.clinical_encounters WHERE id=encounter)<>0 OR (SELECT count(*) FROM public.diagnoses WHERE encounter_id=encounter)<>0 THEN RAISE EXCEPTION 'Borrador visible al paciente'; END IF;
  BEGIN
   PERFORM public.doctor_native_alerts();
   RAISE EXCEPTION 'Paciente obtuvo avisos médicos';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',doc,'role','authenticated')::text,true);
  BEGIN
   PERFORM public.publish_lab_result(lab,'No autorizado',false);
   RAISE EXCEPTION 'Doctor publicó resultados sin rol de laboratorio';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  chart=public.doctor_native_chart(patient);
  IF (chart->'history'->0->'vitals'->>'weight_kg')::numeric IS DISTINCT FROM 70 OR jsonb_array_length(chart->'prescriptions')<>1 THEN
   RAISE EXCEPTION 'No persistieron evaluación y receta'; END IF;
  PERFORM public.doctor_native_finish(encounter,ver);
  PERFORM public.doctor_native_finish(encounter,ver);
  BEGIN
   PERFORM public.doctor_native_save(encounter,ver,gen_random_uuid(),'{"subjective":"No debe modificar nota firmada"}');
   RAISE EXCEPTION 'Consulta finalizada editable';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  w=public.doctor_native_workspace(starts-interval '1 hour',starts+interval '1 hour');
  IF w->'appointments'->0->>'status'<>'completed' OR jsonb_array_length(w->'orders')<>1 THEN RAISE EXCEPTION 'Cierre u orden incorrectos'; END IF;
  RESET ROLE;
  INSERT INTO public.care_team_assignments(patient_id,staff_id,starts_at,ends_at) VALUES(patient,other_staff,now()-interval '1 minute',now()+interval '1 hour');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_doc,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  IF NOT private.treats_patient(patient) THEN RAISE EXCEPTION 'La prueba requiere otro médico asignado'; END IF;
  IF (SELECT count(*) FROM public.clinical_encounters WHERE id=encounter)<>0 OR (SELECT count(*) FROM public.diagnoses WHERE encounter_id=encounter)<>0 THEN RAISE EXCEPTION 'Otro médico asignado leyó notas ajenas'; END IF;
  IF jsonb_array_length(public.doctor_native_chart(patient)->'history')<>0 THEN RAISE EXCEPTION 'RPC expone historia de otro médico'; END IF;
  BEGIN
   PERFORM public.my_consultation_history();
   RAISE EXCEPTION 'Doctor sin rol paciente obtuvo historial de paciente';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF (public.doctor_native_alerts()->>'unread')::int<>0 THEN RAISE EXCEPTION 'Avisos ajenos expuestos'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  IF jsonb_array_length(public.my_consultation_history())<>1 OR public.my_consultation_history()->0->>'assessment' IS DISTINCT FROM 'Evaluación transaccional' THEN RAISE EXCEPTION 'Historial propio incompleto'; END IF;
  IF (SELECT assessment FROM public.clinical_encounters WHERE id=encounter) IS DISTINCT FROM 'Evaluación transaccional' THEN RAISE EXCEPTION 'Paciente no ve nota completada'; END IF;
  IF (SELECT weight_kg FROM public.vital_signs WHERE encounter_id=encounter LIMIT 1) IS DISTINCT FROM 70::numeric THEN RAISE EXCEPTION 'Paciente no ve peso guardado'; END IF;
  IF (SELECT count(*) FROM public.prescriptions WHERE id=rx)<>1 THEN RAISE EXCEPTION 'Paciente no ve receta propia'; END IF;
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE;
  result=jsonb_build_object('result','PASS','flow','doctor autorizado → agenda propia → expediente/solicitud/síntomas → borrador/vitales → laboratorio y receta → cierre atómico',
   'security','paciente y otro doctor rechazados; resultado de laboratorio protegido; consulta finalizada inmutable',
   'idempotency','una consulta, una orden y una receta; guardado/cierre reintentables','fixtures','revertidos');
  RAISE EXCEPTION 'Rollback test fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RAISE NOTICE '%',result;
 END;
END $$;
ROLLBACK;
SELECT 'PASS: assignment, reminder deduplication, clinical workflow, own completed history, author-only notes; fixtures rolled back' AS verification;

