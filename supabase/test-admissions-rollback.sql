-- Controlled SQL identities and room/bed fixtures exist only inside a reverted subtransaction.
CREATE OR REPLACE FUNCTION pg_temp.verify_admissions() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE d uuid=gen_random_uuid(); o uuid=gen_random_uuid(); r uuid=gen_random_uuid(); u uuid=gen_random_uuid();
 ds uuid=gen_random_uuid(); os uuid=gen_random_uuid(); p uuid; p2 uuid; a uuid; a2 uuid; k uuid=gen_random_uuid();
 room uuid=gen_random_uuid(); bed uuid=gen_random_uuid(); floor_id smallint; w jsonb; denied boolean; result jsonb;
BEGIN
 BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
   (d,d::text||'@admission-flow.example.test','{"first_name":"Doctor reversible","last_name":"Prueba"}'),
   (o,o::text||'@admission-flow.example.test','{}'),(r,r::text||'@admission-flow.example.test','{}'),(u,u::text||'@admission-flow.example.test','{}');
  UPDATE public.user_roles SET active=false WHERE user_id IN (d,o,r);
  INSERT INTO public.user_roles(user_id,role) VALUES(d,'doctor'),(o,'doctor'),(r,'recepcionista');
  INSERT INTO public.staff(id,profile_id,employee_code,category) VALUES(ds,d,'ADMISSION-TEST-'||d,'doctor'),(os,o,'ADMISSION-TEST-'||o,'doctor');
  SELECT id INTO floor_id FROM public.hospital_floors ORDER BY id LIMIT 1;
  IF floor_id IS NULL THEN RAISE EXCEPTION 'Se necesita un piso real configurado'; END IF;
  INSERT INTO public.rooms(id,code,floor_id,kind) VALUES(room,'ADMISSION-TEST-'||room,floor_id,'vip');
  INSERT INTO public.beds(id,room_id,code) VALUES(bed,room,'ADMISSION-TEST-'||bed);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  p=public.create_walkin_patient('Ingreso reversible','Uno',lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0','7999-0000','1990-01-01',NULL);
  p2=public.create_walkin_patient('Ingreso reversible','Dos',lpad((floor(random()*100000000)::bigint)::text,8,'0')||'-0','7999-0000','1990-01-01',NULL);
  RESET ROLE;
  INSERT INTO public.care_team_assignments(patient_id,staff_id) VALUES(p,ds),(p2,ds);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  BEGIN
   PERFORM public.doctor_native_admission_request(p,'vip','No autorizado',NULL,'normal',NULL,k);
   RAISE EXCEPTION 'Otro doctor creó ingreso ajeno' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  BEGIN
   PERFORM public.doctor_native_admissions();
   RAISE EXCEPTION 'Paciente accedió al módulo médico' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  a=public.doctor_native_admission_request(p,'vip','Motivo clínico reversible','Observaciones reversibles','urgente',NULL,k);
  IF public.doctor_native_admission_request(p,'vip','Motivo clínico reversible','Observaciones reversibles','urgente',NULL,k)<>a THEN RAISE EXCEPTION 'Reintento duplicó ingreso'; END IF;
  w=public.doctor_native_admissions();
  IF (w->>'total')::int<>1 OR w->'items'->0->>'status'<>'solicitado' OR w->'items'->0->>'priority'<>'urgente'
   OR w->'items'->0->'assignment'<>'null'::jsonb OR jsonb_array_length(w->'items'->0->'history')<>1 THEN RAISE EXCEPTION 'Solicitud o trazabilidad incorrecta'; END IF;
  BEGIN
   PERFORM public.reception_resolve_admission(a,'asignar',NULL,bed);
   RAISE EXCEPTION 'Doctor asignó cama' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  a2=public.doctor_native_admission_request(p2,'vip','Segunda solicitud reversible',NULL,'normal',NULL,gen_random_uuid());
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r,'role','authenticated')::text,true);
  w=public.reception_admissions(0,'solicitado');
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(w->'items') x WHERE x->>'id'=a::text AND x->>'doctor_name'='Doctor reversible Prueba') THEN RAISE EXCEPTION 'Recepción no recibió la solicitud'; END IF;
  w=public.reception_admission_availability(a);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(w->'beds') x WHERE x->>'bed_id'=bed::text) THEN RAISE EXCEPTION 'Disponibilidad no incluye cama libre'; END IF;
  PERFORM public.reception_resolve_admission(a,'asignar',NULL,bed);
  PERFORM public.reception_resolve_admission(a,'asignar',NULL,bed);
  denied=false;
  BEGIN PERFORM public.reception_resolve_admission(a2,'asignar',NULL,bed);
  EXCEPTION WHEN raise_exception OR unique_violation THEN denied=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Se permitió doble ocupación'; END IF;
  PERFORM public.reception_resolve_admission(a2,'rechazar','Requiere otra modalidad de atención');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated')::text,true);
  w=public.doctor_native_admissions();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(w->'items') x WHERE x->>'id'=a::text AND x->>'status'='hospitalizado'
   AND x->'assignment'->>'bed'='ADMISSION-TEST-'||bed::text AND jsonb_array_length(x->'history')=2) THEN RAISE EXCEPTION 'Doctor no ve asignación'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(w->'items') x WHERE x->>'id'=a2::text AND x->>'status'='cancelado'
   AND x->>'decision'='rechazada' AND x->>'decision_reason'='Requiere otra modalidad de atención') THEN RAISE EXCEPTION 'Doctor no ve rechazo justificado'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
  IF (public.doctor_native_admissions()->>'total')::int<>0 THEN RAISE EXCEPTION 'Otro doctor ve solicitudes ajenas'; END IF;
  RESET ROLE;
  IF (SELECT count(*) FROM public.bed_assignments WHERE bed_id=bed AND released_at IS NULL)<>1 THEN RAISE EXCEPTION 'Asignación duplicada'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  result=jsonb_build_object('result','PASS','flow','doctor solicita → recepción consulta disponibilidad → asigna → doctor ve ingreso; rechazo justificado visible',
   'security','paciente/doctor ajeno rechazados; doctor no asigna; reintento sin duplicar; doble ocupación rechazada','fixtures','revertidos');
  RAISE EXCEPTION 'Rollback admission fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN result;
 END;
END $$;
SELECT pg_temp.verify_admissions() verification;
