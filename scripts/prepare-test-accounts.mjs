// Prepare exactly two authorized demonstration identities. No network requests.
// Passwords and the generated SQL are written only under ignored .local/.
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
const local = new URL('../.local/', import.meta.url);
mkdirSync(local, { recursive:true });
const path = new URL('test-accounts.json',local);
const accounts = existsSync(path) ? JSON.parse(readFileSync(path,'utf8')) : ['doctor','patient'].map(role => ({
  role, id:randomUUID(), person_id:randomUUID(), entity_id:randomUUID(),
  email:role === 'doctor' ? 'medico.demo@hospital.test' : 'paciente.demo@hospital.test',
  name:role === 'doctor' ? 'Médico de prueba' : 'Paciente de prueba',
  password:randomBytes(24).toString('base64url')
}));
writeFileSync(path,JSON.stringify(accounts,null,2));
const [doctor,patient] = accounts;
const quote = value => "'" + value.replaceAll("'","''") + "'";
const sql = `-- Authorized demo fixture only. Do not commit this generated file.
do $demo$
declare
  facility uuid;
  department uuid;
  specialty uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('hospital:demo-login-accounts',0));
  if exists(select 1 from auth.users where email in (${accounts.map(a => quote(a.email)).join(',')})) then
    raise exception 'Demo accounts already exist; refusing to reset credentials or duplicate identities';
  end if;
  select id into strict facility from hospital.facilities where name='Sede Central' and active;
  select id into strict department from hospital.departments where name='Medicina interna' and facility_id=facility;
  select id into strict specialty from hospital.specialties where name='Medicina interna';
  ${accounts.map(a => `insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,
    reauthentication_token,phone_change,phone_change_token,raw_app_meta_data,raw_user_meta_data,
    is_super_admin,is_sso_user,is_anonymous,created_at,updated_at)
  values('00000000-0000-0000-0000-000000000000',${quote(a.id)},'authenticated','authenticated',${quote(a.email)},
    extensions.crypt(${quote(a.password)},extensions.gen_salt('bf',12)),now(),'','','','','','','','',
    '{"provider":"email","providers":["email"],"demo_fixture":"hospital-login-2026"}'::jsonb,
    jsonb_build_object('display_name',${quote(a.name)},'is_demo',true),false,false,false,now(),now());
  insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
  values(${quote(a.id)},${quote(a.id)},jsonb_build_object('sub',${quote(a.id)},'email',${quote(a.email)},'email_verified',true,'phone_verified',false),'email',now(),now());
  insert into hospital.persons(id,given_names,family_names) values(${quote(a.person_id)},${quote(a.role === 'doctor' ? 'Médico' : 'Paciente')},'DE PRUEBA');
  update hospital.profiles set person_id=${quote(a.person_id)},status='active',preferred_name=${quote(a.name)} where id=${quote(a.id)};
  insert into hospital.user_role_assignments(profile_id,facility_id,role_id)
    select ${quote(a.id)},facility,id from hospital.roles where code=${quote(a.role)};`).join('\n')}
  insert into hospital.staff_members(id,person_id,employee_code,license_number)
    values(${quote(doctor.entity_id)},${quote(doctor.person_id)},'DEMO-MED-001','DEMO-LIC-NO-CLINICA-001');
  insert into hospital.staff_assignments(staff_id,department_id,job_title)
    values(${quote(doctor.entity_id)},department,'Médico de demostración');
  insert into hospital.staff_specialties(staff_id,specialty_id) values(${quote(doctor.entity_id)},specialty);
  insert into hospital.patients(id,person_id,medical_record_number,blood_group)
    values(${quote(patient.entity_id)},${quote(patient.person_id)},'DEMO-EXP-001','unknown');
  insert into hospital.patient_facility_registrations(patient_id,facility_id) values(${quote(patient.entity_id)},facility);
  -- Fixture linkage prepared by the database owner; not a client self-verification flow.
  insert into hospital.patient_accounts(patient_id,profile_id,verified_by)
    values(${quote(patient.entity_id)},${quote(patient.id)},${quote(doctor.id)});
end
$demo$;
select u.id,u.email,p.status,r.code from auth.users u join hospital.profiles p on p.id=u.id
join hospital.user_role_assignments a on a.profile_id=u.id join hospital.roles r on r.id=a.role_id
where u.id in (${accounts.map(a => quote(a.id)).join(',')});
`;
writeFileSync(new URL('seed-test-accounts.sql',local),sql);
writeFileSync(new URL('CREDENCIALES_PRUEBA.md',local), '# Cuentas de prueba · Hospital Universitario\n\nSolo demostración. No usar con datos de pacientes reales. Archivo excluido de Git.\n\n' + accounts.map(a => `## ${a.name}\n\n- Correo: ${a.email}\n- Contraseña: ${a.password}\n- Rol: ${a.role}\n`).join('\n') + '\nLa configuración de autenticador y los resultados de la prueba se completan después de verificar las cuentas.\n');
console.log('Dos identidades preparadas en .local/. Las contraseñas no se imprimieron.');
