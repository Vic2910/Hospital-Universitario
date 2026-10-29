-- Deployment proposal. Run as database owner after reviewing in staging.
-- Existing hospital tables, clinical permissions, MFA and RLS remain unchanged.
begin;
-- ALTER OWNER requires CREATE on the containing schema. The grant is revoked
-- in this same transaction, before it can become visible to other sessions.
grant create on schema private to hospital_api;
set local role hospital_api;

create or replace function private.require_doctor(p_facility uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_staff uuid; v_access jsonb;
begin
  v_staff := private.staff_id();
  v_access := public.my_access();
  if private.current_profile_id() is null or v_staff is null or p_facility is null
     or not private.has_permission(p_facility, 'clinical.read')
     or not exists (select 1 from jsonb_array_elements(v_access->'roles') r
       where r->>'code' = 'doctor' and r->>'facility_id' = p_facility::text) then
    raise insufficient_privilege using message = 'Acceso medico no autorizado';
  end if;
  return v_staff;
end $$;
alter function private.require_doctor(uuid) owner to hospital_api;
revoke all on function private.require_doctor(uuid) from public, anon, authenticated;

create or replace function private.doctor_workspace(p_facility uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_staff uuid; v_result jsonb;
begin
  v_staff := private.require_doctor(p_facility);
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '2 days' then
    raise invalid_parameter_value using message = 'Intervalo de jornada invalido';
  end if;
  with agenda as (
    select a.*, ae.encounter_id,
      coalesce(nullif(concat_ws(' ', n.given_names, n.family_names), ''), 'Paciente con acceso restringido') patient_name,
      coalesce(p.medical_record_number, 'Acceso demografico pendiente') record_number,
      (select c.value from hospital.person_contacts c where c.person_id = p.person_id and c.kind = 'phone'
        order by c.is_primary desc, c.id limit 1) phone,
      (select q.number::text from hospital.appointment_queue_tickets aq join hospital.queue_tickets q on q.id = aq.ticket_id
        where aq.appointment_id = a.id order by q.created_at desc, q.id limit 1) ticket_number
    from hospital.appointments a
    join hospital.departments d on d.id = a.department_id
    left join hospital.patients p on p.id = a.patient_id
    left join hospital.persons n on n.id = p.person_id
    left join hospital.appointment_encounters ae on ae.appointment_id = a.id
    where a.physician_id = v_staff and d.facility_id = p_facility
      and a.period && tstzrange(p_from, p_to, '[)')
  ), orders as (
    select o.*, e.patient_id, coalesce(nullif(concat_ws(' ', n.given_names,n.family_names), ''), 'Paciente con acceso restringido') patient_name,
      (select c.value from hospital.person_contacts c where c.person_id = p.person_id and c.kind = 'phone'
        order by c.is_primary desc, c.id limit 1) phone,
      (select q.number::text from hospital.appointment_encounters ae
        join hospital.appointment_queue_tickets aq on aq.appointment_id = ae.appointment_id
        join hospital.queue_tickets q on q.id = aq.ticket_id where ae.encounter_id = e.id
        order by q.created_at desc, q.id limit 1) ticket_number,
      (select string_agg(t.name, ', ' order by t.code) from hospital.diagnostic_order_items i
        join hospital.test_definitions t on t.id = i.test_id where i.order_id = o.id) test_name
    from hospital.diagnostic_orders o
    join hospital.encounters e on e.id = o.encounter_id
    join hospital.departments d on d.id = e.department_id
    left join hospital.patients p on p.id = e.patient_id
    left join hospital.persons n on n.id = p.person_id
    where o.ordered_by = private.current_profile_id() and e.attending_physician_id = v_staff
      and d.facility_id = p_facility and coalesce(o.ordered_at, o.created_at) >= p_from
      and coalesce(o.ordered_at, o.created_at) < p_to
  ), identity as (
    select concat_ws(' ',n.given_names,n.family_names) doctor_name, f.name facility_name
    from hospital.staff_members s join hospital.persons n on n.id = s.person_id
    cross join hospital.facilities f where s.id = v_staff and f.id = p_facility
  )
  select jsonb_build_object(
    'doctor_name', coalesce((select doctor_name from identity), 'Medico'),
    'facility_name', coalesce((select facility_name from identity), 'Sede'),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'patient_id',a.patient_id,
      'patient_name',a.patient_name,'record_number',a.record_number,'phone',a.phone,'ticket_number',a.ticket_number,
      'period',a.period::text,'status',a.status,'encounter_id',a.encounter_id) order by lower(a.period),a.id) from agenda a),'[]'::jsonb),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'patient_id',o.patient_id,
      'patient_name',o.patient_name,'ticket_number',o.ticket_number,'phone',o.phone,'test_name',coalesce(o.test_name,'Sin estudios'),
      'issued_at',o.ordered_at,'facility_name',coalesce((select facility_name from identity),'Sede'),
      'doctor_name',coalesce((select doctor_name from identity),'Medico'),'instructions',o.clinical_question,
      'status',o.status,'row_version',o.row_version) order by o.created_at desc,o.id) from orders o),'[]'::jsonb),
    'tests', coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'code',t.code,'name',t.name) order by t.name,t.id)
      from hospital.test_definitions t where t.active and t.kind = 'laboratory'),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc,n.id) from (
      select id,title,body,created_at,read_at,row_version from hospital.notifications
      where recipient_id = private.current_profile_id() and (expires_at is null or expires_at > now())
      order by created_at desc,id limit 100) n),'[]'::jsonb),
    'stats',jsonb_build_object(
      'consultations',(select count(*) from hospital.encounters e join hospital.departments d on d.id = e.department_id
        where e.attending_physician_id = v_staff and d.facility_id = p_facility and e.started_at >= p_from and e.started_at < p_to),
      'completed_consultations',(select count(*) from hospital.encounters e join hospital.departments d on d.id = e.department_id
        where e.attending_physician_id = v_staff and d.facility_id = p_facility and e.status = 'closed'
          and e.started_at >= p_from and e.started_at < p_to),
      'issued_orders',(select count(*) from orders where status <> 'draft' and status <> 'cancelled'),
      'pending_orders',(select count(*) from orders where status in ('ordered','in_progress')))) into v_result;
  perform private.audit_read('doctor_workspace');
  return v_result;
end $$;
alter function private.doctor_workspace(uuid,timestamptz,timestamptz) owner to hospital_api;

create or replace function private.doctor_chart(p_patient uuid, p_from timestamptz, p_to timestamptz, p_query text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_staff uuid := private.staff_id(); v_base jsonb; v_result jsonb; v_facility uuid;
begin
  if p_patient is null or length(coalesce(p_query,'')) > 200 or
     (p_from is not null and p_to is not null and p_from > p_to) then
    raise invalid_parameter_value using message = 'Filtro de historial invalido';
  end if;
  select d.facility_id into v_facility from hospital.encounters e
    join hospital.departments d on d.id = e.department_id
    where e.patient_id = p_patient and e.attending_physician_id = v_staff
      and private.can_encounter(e.id,'clinical.read') order by e.started_at desc,e.id limit 1;
  perform private.require_doctor(v_facility);
  -- Preserve the existing care-link/MFA checks and audit of the chart RPC.
  v_base := public.patient_chart(p_patient);
  select jsonb_build_object(
    'patient', jsonb_build_object('id',p.id,'full_name',concat_ws(' ',n.given_names,n.family_names),
      'record_number',p.medical_record_number,'birth_date',n.birth_date,'sex',n.administrative_sex,
      'phone',(select c.value from hospital.person_contacts c where c.person_id = n.id and c.kind = 'phone' order by c.is_primary desc,c.id limit 1),
      'email',(select c.value from hospital.person_contacts c where c.person_id = n.id and c.kind = 'email' order by c.is_primary desc,c.id limit 1),
      'address',null,
      'identification',(select string_agg(i.kind || ': ' || i.value, '; ' order by i.kind,i.id) from hospital.person_identifiers i where i.person_id = n.id)),
    'blood_type',p.blood_group,
    'allergies',coalesce((select jsonb_agg(concat_ws(' - ',a.name,pa.reaction,pa.severity,pa.status) order by a.name,pa.id)
      from hospital.patient_allergies pa join hospital.allergens a on a.id = pa.allergen_id where pa.patient_id = p.id),'[]'::jsonb),
    'conditions',coalesce((select jsonb_agg(concat_ws(' - ',dc.code,dc.description,pc.status) order by dc.code,pc.id)
      from hospital.patient_conditions pc join hospital.diagnosis_codes dc on dc.id = pc.diagnosis_code_id where pc.patient_id = p.id),'[]'::jsonb),
    'medical_history',coalesce((select jsonb_agg(concat_ws(' - ',h.kind,h.occurred_on::text,h.description) order by h.occurred_on desc,h.id)
      from hospital.medical_history_entries h where h.patient_id = p.id and h.entered_in_error_at is null),'[]'::jsonb),
    'medications',coalesce((select jsonb_agg(concat_ws(' - ',m.generic_name,concat_ws(' ',pi.dose::text,u.name),pi.instructions,pi.starts_on::text,pi.ends_on::text) order by rx.created_at desc,pi.id)
      from hospital.prescriptions rx join hospital.encounters e on e.id = rx.encounter_id
      join hospital.prescription_items pi on pi.prescription_id = rx.id join hospital.medications m on m.id = pi.medication_id
      left join hospital.units u on u.id = pi.dose_unit_id
      where e.patient_id = p.id and rx.status = 'issued' and (pi.ends_on is null or pi.ends_on >= current_date)),'[]'::jsonb),
    'vitals',coalesce((select jsonb_agg(jsonb_build_object('label',case x.key
      when 'measured_at' then 'Fecha de medicion' when 'systolic_mmhg' then 'Presion sistolica'
      when 'diastolic_mmhg' then 'Presion diastolica' when 'pulse_bpm' then 'Pulso'
      when 'respiratory_rate' then 'Frecuencia respiratoria' when 'temperature_c' then 'Temperatura'
      when 'spo2_percent' then 'Saturacion de oxigeno' when 'weight_kg' then 'Peso' when 'height_cm' then 'Talla' end,
      'value',x.value || case x.key when 'systolic_mmhg' then ' mmHg' when 'diastolic_mmhg' then ' mmHg'
      when 'pulse_bpm' then ' lpm' when 'respiratory_rate' then ' rpm' when 'temperature_c' then ' C'
      when 'spo2_percent' then ' %' when 'weight_kg' then ' kg' when 'height_cm' then ' cm' else '' end))
      from jsonb_each_text(coalesce(nullif(v_base->'latest_vitals','null'::jsonb),'{}'::jsonb)) x
      where x.key in ('measured_at','systolic_mmhg','diastolic_mmhg','pulse_bpm','respiratory_rate','temperature_c','spo2_percent','weight_kg','height_cm') and x.value is not null),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.started_at desc,h.id) from (
      select e.id,e.started_at,e.status,e.row_version,cn.id note_id,cn.row_version note_version,
        cn.subjective,cn.objective,cn.assessment,cn.plan
      from hospital.encounters e
      left join lateral (select x.* from hospital.clinical_notes x where x.encounter_id = e.id and x.author_id = private.current_profile_id()
        and x.kind = 'consultation' and x.status in ('draft','signed') order by x.created_at desc,x.id limit 1) cn on true
      where e.patient_id = p.id and e.attending_physician_id = v_staff and private.can_encounter(e.id,'clinical.read')
        and (p_from is null or e.started_at >= p_from) and (p_to is null or e.started_at <= p_to)
        and (coalesce(p_query,'') = '' or strpos(lower(concat_ws(' ',e.chief_complaint,cn.subjective,cn.objective,cn.assessment,cn.plan)),lower(p_query)) > 0)
    )h),'[]'::jsonb)) into v_result
  from hospital.patients p join hospital.persons n on n.id = p.person_id where p.id = p_patient;
  if v_result is null then raise insufficient_privilege using message = 'Expediente no disponible'; end if;
  return v_result;
end $$;
alter function private.doctor_chart(uuid,timestamptz,timestamptz,text) owner to hospital_api;

create or replace function private.doctor_issue_lab_order(p_encounter uuid, p_test uuid, p_instructions text, p_request_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_encounter hospital.encounters; v_order jsonb; v_id uuid; v_operation text;
begin
  if p_request_key is null or p_test is null or length(coalesce(p_instructions,'')) > 10000 then
    raise invalid_parameter_value using message = 'Orden invalida';
  end if;
  select * into v_encounter from hospital.encounters where id = p_encounter for update;
  perform private.require_doctor(private.department_facility(v_encounter.department_id));
  if v_encounter.id is null or v_encounter.attending_physician_id <> private.staff_id()
      or not private.can_encounter(p_encounter,'clinical.write') then
    raise insufficient_privilege using message = 'Orden no autorizada';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(private.current_profile_id()::text || p_request_key::text,0));
  v_operation := 'doctor_lab:' || md5(jsonb_build_array(p_encounter,p_test,coalesce(p_instructions,''))::text);
  v_id := private.idempotency_lookup(p_request_key,v_operation);
  if v_id is not null then
    select to_jsonb(o) into v_order from hospital.diagnostic_orders o where o.id = v_id and o.ordered_by = private.current_profile_id();
    return v_order;
  end if;
  if v_encounter.status <> 'open' or not exists (select 1 from hospital.test_definitions where id = p_test and active and kind = 'laboratory') then
    raise check_violation using message = 'Atencion cerrada o estudio no disponible';
  end if;
  v_order := public.create_record('diagnostic_orders',jsonb_build_object('encounter_id',p_encounter,
    'order_number','LAB-' || replace(p_request_key::text,'-',''),'priority','normal',
    'clinical_question',nullif(trim(p_instructions),'')),md5(p_request_key::text || ':header')::uuid);
  v_id := (v_order->>'id')::uuid;
  perform public.create_record('diagnostic_order_items',jsonb_build_object('order_id',v_id,'test_id',p_test),md5(p_request_key::text || ':item')::uuid);
  v_order := public.finalize_clinical_record('diagnostic_orders',v_id,'order',(v_order->>'row_version')::bigint);
  perform private.remember_request(p_request_key,v_operation,v_id);
  return v_order;
end $$;
alter function private.doctor_issue_lab_order(uuid,uuid,text,uuid) owner to hospital_api;
reset role;
revoke create on schema private from hospital_api;

create or replace function public.doctor_workspace(p_facility uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.doctor_workspace(p_facility,p_from,p_to)
$$;
create or replace function public.doctor_chart(p_patient uuid, p_from timestamptz default null, p_to timestamptz default null, p_query text default '')
returns jsonb language sql security invoker set search_path = '' as $$
  select private.doctor_chart(p_patient,p_from,p_to,p_query)
$$;
create or replace function public.doctor_issue_lab_order(p_encounter uuid, p_test uuid, p_instructions text, p_request_key uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.doctor_issue_lab_order(p_encounter,p_test,p_instructions,p_request_key)
$$;

revoke all on function private.doctor_workspace(uuid,timestamptz,timestamptz),
  private.doctor_chart(uuid,timestamptz,timestamptz,text),private.doctor_issue_lab_order(uuid,uuid,text,uuid),
  public.doctor_workspace(uuid,timestamptz,timestamptz),public.doctor_chart(uuid,timestamptz,timestamptz,text),
  public.doctor_issue_lab_order(uuid,uuid,text,uuid) from public,anon;
grant execute on function private.doctor_workspace(uuid,timestamptz,timestamptz),
  private.doctor_chart(uuid,timestamptz,timestamptz,text),private.doctor_issue_lab_order(uuid,uuid,text,uuid),
  public.doctor_workspace(uuid,timestamptz,timestamptz),public.doctor_chart(uuid,timestamptz,timestamptz,text),
  public.doctor_issue_lab_order(uuid,uuid,text,uuid) to authenticated;

-- In-app events. No APNs tokens, external services or clinical text are emitted.
insert into hospital.notification_topics(code,name) values ('doctor_activity','Actividad medica') on conflict(code) do nothing;

create or replace function private.notify_doctor_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_physician uuid; v_profile uuid; v_topic uuid; v_title text;
begin
  if tg_table_schema <> 'hospital' then raise insufficient_privilege; end if;
  if tg_table_name = 'appointments' then
    if new.status <> 'checked_in' or (tg_op = 'UPDATE' and old.status = 'checked_in') then return new; end if;
    v_physician := new.physician_id;
    v_title := 'Paciente registrado en tu agenda';
  elsif tg_table_name = 'lab_results' then
    if new.status <> 'released' or old.status = 'released' then return new; end if;
    select e.attending_physician_id into v_physician from hospital.diagnostic_order_items i
      join hospital.diagnostic_orders o on o.id = i.order_id join hospital.encounters e on e.id = o.encounter_id
      where i.id = new.order_item_id;
    v_title := 'Resultado de laboratorio disponible';
  elsif tg_table_name = 'clinical_notes' then
    if new.status <> 'signed' or old.status = 'signed' then return new; end if;
    select e.attending_physician_id into v_physician from hospital.encounters e where e.id = new.encounter_id;
    v_title := 'Actualizacion en un expediente asignado';
  else raise insufficient_privilege;
  end if;
  select p.id into v_profile from hospital.profiles p join hospital.staff_members s on s.person_id = p.person_id
    where s.id = v_physician and s.active and p.status = 'active';
  if v_profile is null then return new; end if;
  select id into v_topic from hospital.notification_topics where code = 'doctor_activity';
  if exists(select 1 from hospital.notification_preferences where profile_id = v_profile and topic_id = v_topic and channel = 'in_app' and not enabled) then return new; end if;
  insert into hospital.notifications(recipient_id,topic_id,title,body,expires_at)
    values(v_profile,v_topic,v_title,'Consulta el detalle autorizado dentro del hospital.',now() + interval '30 days');
  return new;
end $$;
alter function private.notify_doctor_activity() owner to postgres;
revoke all on function private.notify_doctor_activity() from public,anon,authenticated,hospital_api,service_role;
-- Trigger-only function owned by the database owner to deliver to another recipient.
-- It cannot be invoked as a client RPC and accepts no recipient or message arguments.
drop trigger if exists doctor_appointment_notice on hospital.appointments;
create trigger doctor_appointment_notice after insert or update of status on hospital.appointments for each row execute function private.notify_doctor_activity();
drop trigger if exists doctor_lab_notice on hospital.lab_results;
create trigger doctor_lab_notice after update of status on hospital.lab_results for each row execute function private.notify_doctor_activity();
drop trigger if exists doctor_chart_notice on hospital.clinical_notes;
create trigger doctor_chart_notice after update of status on hospital.clinical_notes for each row execute function private.notify_doctor_activity();

notify pgrst,'reload schema';
commit;
