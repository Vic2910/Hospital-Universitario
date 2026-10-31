-- Verificación transaccional del registro con DUI y teléfono (ROLLBACK, sin datos reales).
-- Simula el flujo completo con claims JWT y sesiones temporales; nada persiste.
-- Requiere la migración de docs/sql/registration-dui-phone-migration.sql aplicada.
-- Cubre: submit almacena DUI/teléfono, idempotencia, validación de formato,
-- y que la aprobación copia DUI/teléfono a hospital.persons.

begin;

do $test$
declare
  fac uuid:='3d101c8a-8974-4e2c-9144-1e777f632589';      -- Sede CENTRAL
  adminrole uuid:='6064875a-4716-4f4e-9b3a-72fd6918be7e'; -- rol administrator
  tu uuid:=gen_random_uuid(); tadmin uuid:=gen_random_uuid();
  sess uuid:=gen_random_uuid(); asess uuid:=gen_random_uuid();
  req jsonb; req2 jsonb; rid uuid; pver bigint; appr jsonb; per0 uuid;
begin
  -- 1) Cuenta de paciente recién creada (el trigger deja el perfil pending) y su sesión.
  insert into auth.users(id,email,email_confirmed_at,created_at,updated_at)
    values(tu,'zz-reg-'||tu||'@hospital.test',now(),now(),now());
  insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
    values(sess,tu,now(),now(),'aal1',now()+interval '1 hour');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tu,'role','authenticated','aal','aal1','session_id',sess)::text,true);
  execute 'set local role authenticated';

  -- 2) El envío almacena DUI y teléfono.
  req:=public.submit_patient_registration(fac,'Juan','Pérez','1990-05-10','male','01234567-8','7123-4567');
  if req->>'dui' is distinct from '01234567-8' or req->>'phone' is distinct from '7123-4567' then
    raise exception 'DUI/telefono no almacenados: %',req;
  end if;
  rid:=(req->>'id')::uuid;

  -- 3) Idempotencia: mismo dato devuelve la misma solicitud.
  req2:=public.submit_patient_registration(fac,'Juan','Pérez','1990-05-10','male','01234567-8','7123-4567');
  if req2->>'id' is distinct from req->>'id' then raise exception 'Idempotencia fallida'; end if;

  -- 4) Distintos datos para la misma cuenta -> conflicto PT409.
  begin
    perform public.submit_patient_registration(fac,'Juan','Pérez','1990-05-10','male','01234567-9','7123-4567');
    raise exception 'Distintos datos permitidos';
  exception when sqlstate 'PT409' then null; end;

  -- 5) Formatos inválidos -> PT422.
  begin
    perform public.submit_patient_registration(fac,'Juan','Pérez','1990-05-10','male','0123-45678','7123-4567');
    raise exception 'DUI invalido permitido';
  exception when sqlstate 'PT422' then null; end;
  begin
    perform public.submit_patient_registration(fac,'Juan','Pérez','1990-05-10','male','01234567-8','71234567');
    raise exception 'Telefono invalido permitido';
  exception when sqlstate 'PT422' then null; end;
  execute 'reset role';

  -- 6) Un administrador aprueba y la persona nace con DUI y teléfono.
  insert into auth.users(id,email,email_confirmed_at,created_at,updated_at)
    values(tadmin,'zz-admin-'||tadmin||'@hospital.test',now(),now(),now());
  update hospital.profiles set status='active' where id=tadmin;
  insert into hospital.user_role_assignments(profile_id,facility_id,role_id) values(tadmin,fac,adminrole);
  insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
    values(asess,tadmin,now(),now(),'aal2',now()+interval '1 hour');
  select row_version into pver from hospital.registration_requests where id=rid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tadmin,'role','authenticated','aal','aal2','session_id',asess)::text,true);
  execute 'set local role authenticated';
  appr:=public.review_patient_registration(rid,'approve','Prueba de aprobacion transaccional',pver,null);
  if appr->>'status'<>'approved' then raise exception 'Aprobacion fallo: %',appr; end if;
  execute 'reset role';

  select person_id into per0 from hospital.patients where id=(appr->>'patient_id')::uuid;
  if not exists(select 1 from hospital.persons where id=per0 and dui='01234567-8' and phone='7123-4567') then
    raise exception 'DUI/telefono no copiados a persons';
  end if;
end $test$;

rollback;

select true as registration_dui_phone_flows_passed;
