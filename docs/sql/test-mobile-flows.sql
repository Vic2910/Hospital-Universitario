-- Integration checks in PostgreSQL, with simulated JWT claims, NOT real Auth login.
-- All sessions, catalog fixtures and clinical rows are rolled back. No MFA enrollment.
-- Requires the two existing demo identities; never prints their data or credentials.
begin;
do $test$
declare
  doctor_user uuid; patient_user uuid; patient_id0 uuid; staff_id0 uuid; department_id0 uuid;
  facility_id0 uuid; specialty_id0 uuid; session_doctor uuid:=gen_random_uuid(); session_patient uuid:=gen_random_uuid();
  test_id0 uuid:=gen_random_uuid(); medication_id0 uuid:=gen_random_uuid(); unit_id0 uuid; route_id0 uuid;
  appointment_id0 uuid:=gen_random_uuid(); cancelled_id0 uuid:=gen_random_uuid(); encounter_id0 uuid; note_id0 uuid;
  lab_key uuid:=gen_random_uuid(); rx_key uuid:=gen_random_uuid(); request_key0 uuid:=gen_random_uuid();
  planned timestamptz:=date_trunc('minute',now())+interval '10 days';
  result0 jsonb; replay0 jsonb; chart0 jsonb; module0 text; items0 jsonb;
begin
  select id into doctor_user from auth.users where email='medico.demo@hospital.test';
  select id into patient_user from auth.users where email='paciente.demo@hospital.test';
  if doctor_user is null or patient_user is null then raise exception 'Required existing demo identities are missing'; end if;
  select pa.patient_id into patient_id0 from hospital.patient_accounts pa where pa.profile_id=patient_user;
  select s.id into staff_id0 from hospital.staff_members s join hospital.profiles p on p.person_id=s.person_id where p.id=doctor_user;
  select a.department_id into department_id0 from hospital.staff_assignments a where a.staff_id=staff_id0 and a.valid_during@>now() limit 1;
  facility_id0:=private.department_facility(department_id0);
  select ss.specialty_id into specialty_id0 from hospital.staff_specialties ss where ss.staff_id=staff_id0 limit 1;
  select id into unit_id0 from hospital.units order by (code='mg') desc,id limit 1;
  select id into route_id0 from hospital.administration_routes order by (code='oral') desc,id limit 1;
  if patient_id0 is null or department_id0 is null or specialty_id0 is null or unit_id0 is null or route_id0 is null then raise exception 'Required demo links/catalogs are missing'; end if;
  insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
    values(session_doctor,doctor_user,now(),now(),'aal1',now()+interval '1 hour'),(session_patient,patient_user,now(),now(),'aal1',now()+interval '1 hour');
  insert into hospital.test_definitions(id,code,name,kind) values(test_id0,'ROLLBACK-'||test_id0::text,'Estudio de prueba transaccional','laboratory');
  insert into hospital.medications(id,code,generic_name,strength,strength_unit_id,dosage_form)
    values(medication_id0,'ROLLBACK-'||medication_id0::text,'Medicamento de prueba transaccional',1,unit_id0,'Prueba');
  insert into hospital.staff_shifts(staff_id,department_id,period,status) values(staff_id0,department_id0,tstzrange(planned-interval '1 hour',planned+interval '4 hours','[)'),'confirmed');
  insert into hospital.appointments(id,patient_id,department_id,physician_id,specialty_id,period,reason,status,requested_by)
    values(appointment_id0,patient_id0,department_id0,staff_id0,specialty_id0,tstzrange(planned,planned+interval '30 minutes','[)'),'Prueba transaccional','checked_in',doctor_user),
      (cancelled_id0,patient_id0,department_id0,staff_id0,specialty_id0,tstzrange(planned+interval '1 hour',planned+interval '90 minutes','[)'),'Prueba de cancelacion','confirmed',doctor_user);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',doctor_user,'role','authenticated','aal','aal1','session_id',session_doctor)::text,true);
  execute 'set local role authenticated';
  result0:=public.doctor_workspace(facility_id0,date_trunc('day',planned),date_trunc('day',planned)+interval '1 day');
  if jsonb_typeof(result0->'appointments')<>'array' then raise exception 'AAL1 dashboard unavailable'; end if;
  result0:=public.start_consultation(appointment_id0,gen_random_uuid()); encounter_id0:=(result0->>'id')::uuid;
  result0:=public.save_consultation(encounter_id0,null,jsonb_build_object('subjective','Prueba','objective','Prueba','assessment','Prueba','plan','Prueba'),null,null,gen_random_uuid()); note_id0:=(result0->>'id')::uuid;
  chart0:=public.doctor_chart(patient_id0,null,null,'');
  if not exists(select 1 from jsonb_array_elements(chart0->'history') x where x->>'id'=encounter_id0::text) then raise exception 'Own encounter missing in doctor chart'; end if;
  begin perform public.doctor_chart(gen_random_uuid(),null,null,''); raise exception 'Unlinked chart allowed'; exception when insufficient_privilege then null; end;
  begin perform public.save_consultation(encounter_id0,note_id0,jsonb_build_object('plan','Conflicto de prueba'),null,0,gen_random_uuid()); raise exception 'Stale version allowed'; exception when serialization_failure or sqlstate 'PT409' then null; end;
  result0:=public.doctor_issue_lab_order(encounter_id0,test_id0,'Prueba transaccional',lab_key);
  replay0:=public.doctor_issue_lab_order(encounter_id0,test_id0,'Prueba transaccional',lab_key);
  if result0->>'id' is distinct from replay0->>'id' or result0->>'status'<>'ordered' then raise exception 'Lab issuance/idempotency failed'; end if;
  items0:=jsonb_build_array(jsonb_build_object('medication_id',medication_id0,'dose',0.5,'dose_unit_id',unit_id0,'route_id',route_id0,
    'interval_hours',8,'instructions','Prueba, no uso clinico','starts_on',current_date,'ends_on',null,'quantity',3));
  result0:=public.mobile_issue_prescription(encounter_id0,items0,rx_key);
  replay0:=public.mobile_issue_prescription(encounter_id0,items0,rx_key);
  if result0->>'id' is distinct from replay0->>'id' or result0->>'status'<>'issued' then raise exception 'Prescription issuance/idempotency failed'; end if;
  result0:=public.mobile_module('doctor','prescriptions',facility_id0);
  if not exists(select 1 from jsonb_array_elements(result0->'items') x where x->>'id'=replay0->>'id') then raise exception 'Issued prescription missing'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',patient_user,'role','authenticated','aal','aal1','session_id',session_patient)::text,true);
  execute 'set local role authenticated';
  foreach module0 in array array['appointments','request','chart','history','prescriptions','laboratory','notifications','profile'] loop
    result0:=public.mobile_module('patient',module0,facility_id0);
    if jsonb_typeof(result0->'items')<>'array' or jsonb_typeof(result0->'sections')<>'array' then raise exception 'Invalid patient module: %',module0; end if;
  end loop;
  result0:=public.mobile_module('patient','prescriptions',facility_id0);
  if jsonb_array_length(result0->'items')<1 then raise exception 'Patient prescription missing'; end if;
  result0:=public.mobile_module('patient','laboratory',facility_id0);
  if not exists(select 1 from jsonb_array_elements(result0->'items') x where x->>'title'='Estudio de prueba transaccional' and x->>'status'='pending') then raise exception 'Patient lab state is incorrect'; end if;
  begin perform public.mobile_module('doctor','prescriptions',facility_id0); raise exception 'Role spoofing allowed'; exception when insufficient_privilege then null; end;
  begin perform public.mobile_issue_prescription(encounter_id0,items0,gen_random_uuid()); raise exception 'Patient prescription write allowed'; exception when insufficient_privilege then null; end;
  result0:=public.request_appointment(patient_id0,facility_id0,specialty_id0,'Prueba transaccional',current_date+1,'08:00','09:00',request_key0);
  replay0:=public.request_appointment(patient_id0,facility_id0,specialty_id0,'Prueba transaccional',current_date+1,'08:00','09:00',request_key0);
  if result0->>'id' is distinct from replay0->>'id' or result0->>'status'<>'pending' then raise exception 'Appointment request idempotency failed'; end if;
  result0:=public.mobile_module('patient','appointments',facility_id0);
  select x into result0 from jsonb_array_elements(result0->'items') x where x->>'id'=cancelled_id0::text;
  if result0 is null then raise exception 'Own appointment missing'; end if;
  result0:=public.transition_appointment(cancelled_id0,'cancelled','Prueba transaccional',(result0->>'row_version')::bigint);
  if result0->>'status'<>'cancelled' then raise exception 'Patient cancellation failed'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',patient_user,'role','authenticated','aal','aal1','session_id',session_patient)::text,true);
  execute 'set local role authenticated';
  perform public.mobile_module('patient','appointments',facility_id0);
  perform public.mobile_module('patient','chart',facility_id0);
  execute 'reset role';
  update auth.sessions set not_after=now()-interval '1 minute' where id=session_patient;
  execute 'set local role authenticated';
  begin perform public.mobile_module('patient','chart',facility_id0); raise exception 'Expired session allowed'; exception when insufficient_privilege then null; end;
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',doctor_user,'role','authenticated','aal','aal1','session_id',session_doctor)::text,true);
  execute 'set local role authenticated';
  chart0:=public.doctor_chart(patient_id0,null,null,'');
  select x into result0 from jsonb_array_elements(chart0->'history') x where x->>'id'=encounter_id0::text;
  replay0:=public.close_consultation(encounter_id0,note_id0,(result0->>'note_version')::bigint,(result0->>'row_version')::bigint);
  if replay0->>'status'<>'closed' then raise exception 'Consultation closure failed'; end if;
  begin perform public.mobile_issue_prescription(encounter_id0,items0,gen_random_uuid()); raise exception 'Prescription on closed encounter allowed'; exception when check_violation then null; end;
  execute 'reset role';
  update hospital.user_role_assignments set revoked_at=now() where profile_id=doctor_user and revoked_at is null;
  execute 'set local role authenticated';
  if private.session_active(true) then raise exception 'AAL1 accepted without an active mobile role'; end if;
  begin perform public.doctor_workspace(facility_id0,date_trunc('day',planned),date_trunc('day',planned)+interval '1 day'); raise exception 'Revoked role allowed'; exception when insufficient_privilege then null; end;
  execute 'reset role';
end $test$;
rollback;
select true as transactional_flows_passed;
