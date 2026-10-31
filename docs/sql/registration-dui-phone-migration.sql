-- Migración: DUI y teléfono en el registro de pacientes.
-- Autorizada explícitamente por el usuario el 2026-10-31 (el registro real debe
-- capturar DUI y teléfono; el esquema previo no tenía dónde guardarlos).
--
-- Formatos (estándar salvadoreño):
--   DUI     : 00000000-0  (8 dígitos + dígito verificador)  -> '^[0-9]{8}-[0-9]$'
--   Teléfono: 0000-0000   (8 dígitos)                       -> '^[0-9]{4}-[0-9]{4}$'
--
-- Efectos:
--   * hospital.persons            + dui, phone (nullable) + CHECK de formato.
--   * hospital.registration_requests + dui, phone (nullable) + CHECK de formato.
--   * private/public.submit_patient_registration  -> firma ampliada con
--     p_dui, p_phone (DEFAULT NULL; valida formato si se envían y los almacena).
--   * private.review_patient_registration         -> al aprobar, copia dui/phone
--     de la solicitud a hospital.persons.
--
-- Idempotente: puede ejecutarse de nuevo sin efecto. Requiere un rol con permiso
-- para alterar hospital.* y las RPC de registro (p. ej. postgres en Supabase).
-- Aplicada en el proyecto kgulityewtcyvjnxeskd el 2026-10-31. Verificación
-- transaccional (ROLLBACK) en docs/sql/test-registration-dui-phone.sql.

begin;

alter table hospital.persons
  add column if not exists dui text,
  add column if not exists phone text;
alter table hospital.registration_requests
  add column if not exists dui text,
  add column if not exists phone text;

alter table hospital.persons drop constraint if exists persons_dui_check;
alter table hospital.persons add constraint persons_dui_check
  check (dui is null or dui ~ '^[0-9]{8}-[0-9]$');
alter table hospital.persons drop constraint if exists persons_phone_check;
alter table hospital.persons add constraint persons_phone_check
  check (phone is null or phone ~ '^[0-9]{4}-[0-9]{4}$');
alter table hospital.registration_requests drop constraint if exists registration_requests_dui_check;
alter table hospital.registration_requests add constraint registration_requests_dui_check
  check (dui is null or dui ~ '^[0-9]{8}-[0-9]$');
alter table hospital.registration_requests drop constraint if exists registration_requests_phone_check;
alter table hospital.registration_requests add constraint registration_requests_phone_check
  check (phone is null or phone ~ '^[0-9]{4}-[0-9]{4}$');

-- submit_patient_signature: firma ampliada con DUI y teléfono.
drop function if exists private.submit_patient_registration(uuid, text, text, date, text);
create function private.submit_patient_registration(
  p_facility uuid, p_given_names text, p_family_names text, p_birth_date date, p_sex text,
  p_dui text default null, p_phone text default null)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare r hospital.registration_requests;pr hospital.profiles;begin
 if not private.authenticated_session()then raise insufficient_privilege using message='Confirme el correo y vuelva a iniciar sesión';end if;
 select * into pr from hospital.profiles where id=auth.uid()for update;
 if pr.id is null or pr.status<>'pending'or pr.person_id is not null
 or exists(select 1 from hospital.user_role_assignments where profile_id=pr.id)then raise insufficient_privilege using message='Esta cuenta requiere gestión del hospital';end if;
 if p_given_names is null or p_family_names is null or length(trim(p_given_names))not between 1 and 100 or length(trim(p_family_names))not between 1 and 100
 or p_birth_date is null or p_birth_date>current_date or p_birth_date<'1900-01-01'or p_sex is null or p_sex not in('female','male','intersex','unknown')
 or(p_dui is not null and p_dui!~'^[0-9]{8}-[0-9]$')
 or(p_phone is not null and p_phone!~'^[0-9]{4}-[0-9]{4}$')
 or not exists(select 1 from hospital.facilities where id=p_facility and active)then raise check_violation using message='Datos de solicitud inválidos';end if;
 select * into r from hospital.registration_requests where profile_id=pr.id;
 if r.id is not null then
  if (r.facility_id,r.given_names,r.family_names,r.birth_date,r.administrative_sex,r.dui,r.phone)is distinct from(p_facility,trim(p_given_names),trim(p_family_names),p_birth_date,p_sex,p_dui,p_phone)then raise unique_violation using message='Ya existe una solicitud para esta cuenta';end if;
  return to_jsonb(r);
 end if;
 insert into hospital.registration_requests(profile_id,facility_id,given_names,family_names,birth_date,administrative_sex,dui,phone)
 values(pr.id,p_facility,trim(p_given_names),trim(p_family_names),p_birth_date,p_sex,p_dui,p_phone)returning * into r;
 return to_jsonb(r);
end
$fn$;

drop function if exists public.submit_patient_registration(uuid, text, text, date, text);
create function public.submit_patient_registration(
  p_facility uuid, p_given_names text, p_family_names text, p_birth_date date, p_sex text,
  p_dui text default null, p_phone text default null)
returns jsonb language plpgsql set search_path='' as $fn$
begin return private.submit_patient_registration($1,$2,$3,$4,$5,$6,$7);exception when serialization_failure or deadlock_detected or unique_violation or exclusion_violation or foreign_key_violation then raise sqlstate 'PT409'using message='Conflicto de versión, referencia o duplicado',detail=SQLSTATE;when data_exception or check_violation or not_null_violation then raise sqlstate 'PT422'using message='Datos inválidos para esta operación',detail=SQLSTATE;end;
$fn$;

-- review_patient_registration: al aprobar, crea la persona con DUI y teléfono.
create or replace function private.review_patient_registration(
  p_request uuid, p_decision text, p_note text, p_expected_version bigint, p_existing_patient uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare r hospital.registration_requests;person0 uuid;patient0 uuid;begin
 select * into r from hospital.registration_requests where id=p_request for update;
 if r.id is null or not private.has_permission(r.facility_id,'patients.write')or r.profile_id=auth.uid()then raise insufficient_privilege using message='Revisión no autorizada';end if;
 if r.status<>'pending'or r.row_version<>p_expected_version then raise serialization_failure using message='Solicitud ya revisada';end if;
 if p_decision is null or p_decision not in('approve','reject')or p_note is null or length(trim(p_note))not between 8 and 1000 then raise check_violation using message='Decisión y constancia de verificación requeridas';end if;
 perform 1 from hospital.profiles where id=r.profile_id and status='pending'and person_id is null for update;
 if not found or not exists(select 1 from auth.users where id=r.profile_id and email_confirmed_at is not null)then raise check_violation using message='Cuenta no apta para revisión';end if;
 if p_decision='approve'then
  if p_existing_patient is not null then
   select person_id into person0 from hospital.patients where id=p_existing_patient and archived_at is null for update;
   if person0 is null or not private.can_patient(p_existing_patient,'patients.write')then raise insufficient_privilege using message='Paciente no disponible';end if;
   if exists(select 1 from hospital.patient_accounts where patient_id=p_existing_patient)or exists(select 1 from hospital.profiles where person_id=person0)then raise unique_violation using message='Expediente ya vinculado';end if;
   patient0=p_existing_patient;
  else
   insert into hospital.persons(given_names,family_names,birth_date,administrative_sex,dui,phone)values(r.given_names,r.family_names,r.birth_date,r.administrative_sex,r.dui,r.phone)returning id into person0;
   insert into hospital.patients(person_id,medical_record_number)values(person0,'HU-'||upper(replace(gen_random_uuid()::text,'-','')))returning id into patient0;
  end if;
  insert into hospital.patient_facility_registrations(patient_id,facility_id)values(patient0,r.facility_id)on conflict do nothing;
  update hospital.profiles set person_id=person0,status='active'where id=r.profile_id;
  insert into hospital.patient_accounts(profile_id,patient_id,verified_by)values(r.profile_id,patient0,auth.uid());
  insert into hospital.user_role_assignments(profile_id,facility_id,role_id,granted_by)select r.profile_id,r.facility_id,id,auth.uid()from hospital.roles where code='patient';
 end if;
 update hospital.registration_requests set status=case when p_decision='approve'then 'approved'else 'rejected'end,
 reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_note),patient_id=patient0,row_version=row_version+1 where id=r.id returning * into r;
 return to_jsonb(r);
end
$fn$;

commit;
