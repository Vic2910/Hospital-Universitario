-- Completes the existing doctor/patient mobile flows. Apply after doctor-module.sql.
begin;
grant create on schema private to hospital_api;
set local role hospital_api;

create or replace function private.mobile_module(p_role text,p_module text,p_facility uuid,
  p_from timestamptz default null,p_to timestamptz default null,p_query text default '',
  p_cursor jsonb default null,p_limit integer default 25)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_access jsonb; v_patient uuid; v_staff uuid; v_items jsonb:='[]'; v_options jsonb:='[]';
  v_sections jsonb:='[]'; v_preferences jsonb:='[]'; v_profile jsonb; v_chart jsonb;
  v_page jsonb; v_more boolean; v_last jsonb; v_emergency jsonb; v_directory jsonb;
begin
  if not private.session_active(false) then raise insufficient_privilege using message='Sesion no activa'; end if;
  v_access:=public.my_access();
  if p_role not in ('doctor','patient') or not exists(select 1 from jsonb_array_elements(v_access->'roles') r
    where r->>'code'=p_role and r->>'facility_id'=p_facility::text) then raise insufficient_privilege; end if;
  v_patient:=(v_access->>'patient_id')::uuid; v_staff:=(v_access->>'staff_id')::uuid;
  if (p_role='patient' and (v_patient is null or not private.own_patient(v_patient)))
    or (p_role='doctor' and v_staff is null) then raise insufficient_privilege; end if;
  if p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_query,''))>200
    or (p_from is not null and p_to is not null and p_from>p_to) then raise invalid_parameter_value; end if;
  if p_module is null or p_module not in ('appointments','request','chart','history','prescriptions','laboratory','notifications','profile')
    or (p_role='doctor' and p_module not in ('prescriptions','notifications','profile')) then raise invalid_parameter_value; end if;
  if p_module in ('chart','history','prescriptions','laboratory') and not private.session_active(true) then
    raise insufficient_privilege using message='Sesion o autorizacion insuficiente'; end if;
  if p_role='doctor' and p_module='prescriptions' then perform private.require_doctor(p_facility); end if;

  if p_module='appointments' then
    v_directory:=public.physician_directory(p_facility,null);
    select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',coalesce(s.name,'Consulta medica'),
      'subtitle',a.reason,'status',a.status,'event_at',lower(a.period),'row_version',a.row_version,
      'action',case when a.status in ('scheduled','confirmed') then 'cancel_appointment' end,
      'details',jsonb_build_array(jsonb_build_object('label','Horario','value',a.period::text),
        jsonb_build_object('label','Medico','value',coalesce((select x->>'physician_name' from jsonb_array_elements(v_directory) x where x->>'physician_id'=a.physician_id::text limit 1),'No disponible en el directorio')),
        jsonb_build_object('label','Consultorio','value',coalesce(cr.name,'Por asignar')),
        jsonb_build_object('label','Cancelacion','value',coalesce(a.cancellation_reason,'No aplica'))))),'[]') into v_items
    from hospital.appointments a join hospital.departments d on d.id=a.department_id
      left join hospital.specialties s on s.id=a.specialty_id
      left join hospital.consultation_rooms cr on cr.id=a.consultation_room_id
    where a.patient_id=v_patient and d.facility_id=p_facility;
  elsif p_module='request' then
    select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'kind','specialty') order by s.name),'[]') into v_options from hospital.specialties s;
    select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'title',coalesce(s.name,'Solicitud de atencion'),
      'subtitle',r.reason,'status',r.status,'event_at',r.created_at,'row_version',r.row_version,
      'details',jsonb_build_array(jsonb_build_object('label','Fecha preferida','value',r.preferred_date::text),
        jsonb_build_object('label','Horario preferido','value',r.preferred_start::text||' - '||r.preferred_end::text),
        jsonb_build_object('label','Respuesta de recepcion','value',coalesce(r.decision_reason,'Pendiente de programacion'))))),'[]') into v_items
    from hospital.appointment_requests r left join hospital.specialties s on s.id=r.specialty_id
    where r.patient_id=v_patient and r.facility_id=p_facility;
  elsif p_module='chart' then
    v_chart:=public.patient_chart(v_patient);
    select jsonb_build_array(jsonb_build_object('title','Identificacion','fields',jsonb_build_array(
      jsonb_build_object('label','Nombre','value',concat_ws(' ',v_chart->'person'->>'given_names',v_chart->'person'->>'family_names')),
      jsonb_build_object('label','Expediente','value',v_chart->'patient'->>'medical_record_number'),
      jsonb_build_object('label','Nacimiento','value',coalesce(v_chart->'person'->>'birth_date','No registrado')),
      jsonb_build_object('label','Grupo sanguineo','value',coalesce(v_chart->'patient'->>'blood_group','No registrado')))),
      jsonb_build_object('title','Alergias','fields',coalesce((select jsonb_agg(jsonb_build_object('label',a.name,
        'value',concat_ws(' - ',pa.reaction,pa.severity,pa.status))) from hospital.patient_allergies pa join hospital.allergens a on a.id=pa.allergen_id where pa.patient_id=v_patient),'[]')),
      jsonb_build_object('title','Condiciones','fields',coalesce((select jsonb_agg(jsonb_build_object('label',c.code||' - '||c.description,'value',pc.status))
        from hospital.patient_conditions pc join hospital.diagnosis_codes c on c.id=pc.diagnosis_code_id where pc.patient_id=v_patient),'[]')),
      jsonb_build_object('title','Antecedentes','fields',coalesce((select jsonb_agg(jsonb_build_object('label',h.kind,'value',h.description))
        from hospital.medical_history_entries h where h.patient_id=v_patient and h.entered_in_error_at is null),'[]'))) into v_sections;
    select coalesce(jsonb_agg(jsonb_build_object('id',pd.id,'title',pd.title,'subtitle','Documento de salud','status','released',
      'event_at',pd.released_at,'row_version',pd.row_version,'document_id',pd.document_id,'details','[]'::jsonb)),'[]') into v_items
    from hospital.patient_documents pd where pd.patient_id=v_patient and pd.released_at is not null;
  elsif p_module='history' then
    select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'title',d.name,'subtitle',coalesce(e.chief_complaint,'Atencion medica'),
      'status',e.status,'event_at',e.started_at,'row_version',e.row_version,
      'details',coalesce((select jsonb_agg(jsonb_build_object('label',case n.kind when 'consultation' then 'Consulta' else 'Nota clinica' end,
        'value',concat_ws(E'\n',n.subjective,n.objective,n.assessment,n.plan)) order by n.created_at,n.id)
        from hospital.clinical_notes n where n.encounter_id=e.id and n.status='signed'),'[]'))),'[]') into v_items
    from hospital.encounters e join hospital.departments d on d.id=e.department_id
    where e.patient_id=v_patient and d.facility_id=p_facility;
  elsif p_module='prescriptions' then
    select coalesce(jsonb_agg(jsonb_build_object('id',rx.id,'title','Receta medica','subtitle',coalesce(nullif(concat_ws(' ',n.given_names,n.family_names),''),'Paciente autorizado'),
      'status',case when p_role='doctor' then rx.status
        when exists(select 1 from hospital.prescription_items pi where pi.prescription_id=rx.id and pi.starts_on<=current_date and (pi.ends_on is null or pi.ends_on>=current_date)) then 'active'
        when exists(select 1 from hospital.prescription_items pi where pi.prescription_id=rx.id and pi.starts_on>current_date) then 'scheduled' else 'expired' end,
      'event_at',coalesce(rx.issued_at,rx.created_at),'row_version',rx.row_version,
      'details',coalesce((select jsonb_agg(jsonb_build_object('label',concat_ws(' ',m.generic_name,m.strength::text,su.name,m.dosage_form),
        'value',concat_ws(' - ',concat_ws(' ',i.dose::text,u.name),ar.name,'Cada '||i.interval_hours::text||' horas',
          i.instructions,'Desde '||i.starts_on::text,'Hasta '||coalesce(i.ends_on::text,'indicacion medica'),
          'Cantidad: '||i.quantity::text)) order by i.id)
        from hospital.prescription_items i join hospital.medications m on m.id=i.medication_id
        left join hospital.units u on u.id=i.dose_unit_id left join hospital.units su on su.id=m.strength_unit_id
        left join hospital.administration_routes ar on ar.id=i.route_id where i.prescription_id=rx.id),'[]'))),'[]') into v_items
    from hospital.prescriptions rx join hospital.encounters e on e.id=rx.encounter_id
      join hospital.departments d on d.id=e.department_id left join hospital.patients p on p.id=e.patient_id
      left join hospital.persons n on n.id=p.person_id
    where d.facility_id=p_facility and ((p_role='patient' and e.patient_id=v_patient and rx.status='issued')
      or (p_role='doctor' and rx.prescriber_id=private.current_profile_id() and e.attending_physician_id=v_staff));
    if p_role='doctor' then
      select coalesce(jsonb_agg(x),'[]') into v_options from (
        select jsonb_build_object('id',m.id,'name',concat_ws(' ',m.generic_name,m.strength::text,u.name,m.dosage_form),'kind','medication') x
          from hospital.medications m left join hospital.units u on u.id=m.strength_unit_id where m.active
        union all select jsonb_build_object('id',id,'name',name,'kind','unit') from hospital.units
        union all select jsonb_build_object('id',id,'name',name,'kind','route') from hospital.administration_routes) q;
    end if;
  elsif p_module='laboratory' then
    select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'title',t.name,'subtitle',o.order_number,
      'status',case when lr.id is not null then 'released' when i.status='cancelled' then 'cancelled' when i.status='pending' then 'pending' else 'in_progress' end,
      'event_at',coalesce(o.ordered_at,o.created_at),'row_version',i.row_version,'document_id',lr.document_id,
      'details',jsonb_build_array(jsonb_build_object('label','Indicaciones','value',coalesce(o.clinical_question,'Sin indicaciones adicionales')),
        jsonb_build_object('label','Resultado publicado','value',coalesce(lr.narrative,'No hay resultado publicado')))
        ||coalesce((select jsonb_agg(jsonb_build_object('label',a.name,'value',concat_ws(' ',coalesce(v.value_numeric::text,v.value_text),u.name,v.flag)))
          from hospital.lab_result_values v join hospital.analytes a on a.id=v.analyte_id left join hospital.units u on u.id=v.unit_id where v.result_id=lr.id),'[]'))),'[]') into v_items
    from hospital.diagnostic_orders o join hospital.encounters e on e.id=o.encounter_id
      join hospital.departments d on d.id=e.department_id join hospital.diagnostic_order_items i on i.order_id=o.id
      join hospital.test_definitions t on t.id=i.test_id
      left join lateral(select r.* from hospital.lab_results r where r.order_item_id=i.id and r.status='released' order by r.version desc,r.id limit 1) lr on true
    where e.patient_id=v_patient and d.facility_id=p_facility and o.status<>'draft';
  elsif p_module='notifications' then
    select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'title',n.title,'subtitle',n.body,
      'status',case when n.read_at is null then 'unread' else 'read' end,'event_at',n.created_at,'row_version',n.row_version,
      'action',case when n.read_at is null then 'mark_read' end,'details','[]'::jsonb)),'[]') into v_items
    from hospital.notifications n where n.recipient_id=private.current_profile_id() and (n.expires_at is null or n.expires_at>now());
  elsif p_module='profile' then
    v_profile:=public.my_profile();
    select x into v_emergency from jsonb_array_elements(v_profile->'emergency_contacts') x order by (x->>'is_primary')::boolean desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id',nt.id,'name',nt.name,'enabled',coalesce(np.enabled,true),
      'preference_id',np.id,'row_version',np.row_version) order by nt.name),'[]') into v_preferences
    from hospital.notification_topics nt left join hospital.notification_preferences np on np.topic_id=nt.id and np.profile_id=private.current_profile_id() and np.channel='in_app';
  end if;

  select coalesce(jsonb_agg(x order by (x->>'event_at')::timestamptz desc,(x->>'id')::uuid desc),'[]') into v_page from (
    select x from jsonb_array_elements(v_items) x where
      (p_from is null or (x->>'event_at')::timestamptz>=p_from) and (p_to is null or (x->>'event_at')::timestamptz<=p_to)
      and (coalesce(p_query,'')='' or strpos(lower(concat_ws(' ',x->>'title',x->>'subtitle',
        (select string_agg(f->>'value',' ') from jsonb_array_elements(x->'details') f))),lower(p_query))>0)
      and (p_cursor is null or ((x->>'event_at')::timestamptz,(x->>'id')::uuid)<((p_cursor->>'value')::timestamptz,(p_cursor->>'id')::uuid))
      order by (x->>'event_at')::timestamptz desc,(x->>'id')::uuid desc limit p_limit+1) q;
  v_more:=jsonb_array_length(v_page)>p_limit;
  if v_more then v_page:=v_page-p_limit; end if; v_last:=v_page->-1;
  perform private.audit_read('mobile_'||p_module);
  return jsonb_build_object('items',v_page,'sections',v_sections,'options',v_options,'preferences',v_preferences,
    'phone',(select x->>'value' from jsonb_array_elements(coalesce(v_profile->'contacts','[]')) x where x->>'kind'='phone' order by (x->>'is_primary')::boolean desc limit 1),
    'emergency',v_emergency,'has_more',v_more,'next_cursor',case when v_more then jsonb_build_object('id',v_last->>'id','value',v_last->>'event_at') end);
end $$;
alter function private.mobile_module(text,text,uuid,timestamptz,timestamptz,text,jsonb,integer) owner to hospital_api;

create or replace function private.mobile_issue_prescription(p_encounter uuid,p_items jsonb,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e hospital.encounters; r jsonb; item jsonb; v_id uuid; v_op text; v_index integer:=0;
begin
  if p_request_key is null or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30
    or octet_length(p_items::text)>50000 then raise invalid_parameter_value using message='Receta invalida'; end if;
  select * into e from hospital.encounters where id=p_encounter for update;
  perform private.require_doctor(private.department_facility(e.department_id));
  if e.id is null or e.attending_physician_id<>private.staff_id() or not private.can_encounter(e.id,'clinical.write') then raise insufficient_privilege; end if;
  perform pg_advisory_xact_lock(hashtextextended(private.current_profile_id()::text||p_request_key::text,0));
  v_op:='mobile_prescription:'||md5(jsonb_build_array(p_encounter,p_items)::text);
  v_id:=private.idempotency_lookup(p_request_key,v_op);
  if v_id is not null then select to_jsonb(p) into r from hospital.prescriptions p where id=v_id and prescriber_id=private.current_profile_id(); return r; end if;
  if e.status<>'open' then raise check_violation using message='Atencion cerrada'; end if;
  r:=public.create_record('prescriptions',jsonb_build_object('encounter_id',p_encounter),md5(p_request_key::text||':header')::uuid);
  v_id:=(r->>'id')::uuid;
  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item)<>'object' or not exists(select 1 from hospital.medications where id=(item->>'medication_id')::uuid and active)
      or not (item ?& array['medication_id','dose','dose_unit_id','route_id','interval_hours','instructions','starts_on','ends_on','quantity']) then raise check_violation using message='Medicamento o campos invalidos'; end if;
    if exists(select 1 from jsonb_object_keys(item) k where k not in ('medication_id','dose','dose_unit_id','route_id','interval_hours','instructions','starts_on','ends_on','quantity')) then raise invalid_parameter_value; end if;
    v_index:=v_index+1;
    perform public.create_record('prescription_items',item||jsonb_build_object('prescription_id',v_id),md5(p_request_key::text||':item:'||v_index::text)::uuid);
  end loop;
  r:=public.finalize_clinical_record('prescriptions',v_id,'issue',(r->>'row_version')::bigint);
  perform private.remember_request(p_request_key,v_op,v_id); return r;
end $$;
alter function private.mobile_issue_prescription(uuid,jsonb,uuid) owner to hospital_api;
reset role;
revoke create on schema private from hospital_api;

create or replace function public.mobile_module(p_role text,p_module text,p_facility uuid,
  p_from timestamptz default null,p_to timestamptz default null,p_query text default '',p_cursor jsonb default null,p_limit integer default 25)
returns jsonb language sql security invoker set search_path='' as $$ select private.mobile_module(p_role,p_module,p_facility,p_from,p_to,p_query,p_cursor,p_limit) $$;
create or replace function public.mobile_issue_prescription(p_encounter uuid,p_items jsonb,p_request_key uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.mobile_issue_prescription(p_encounter,p_items,p_request_key) $$;
revoke all on function public.mobile_module(text,text,uuid,timestamptz,timestamptz,text,jsonb,integer),
  private.mobile_module(text,text,uuid,timestamptz,timestamptz,text,jsonb,integer),public.mobile_issue_prescription(uuid,jsonb,uuid),private.mobile_issue_prescription(uuid,jsonb,uuid) from public,anon;
grant execute on function public.mobile_module(text,text,uuid,timestamptz,timestamptz,text,jsonb,integer),
  private.mobile_module(text,text,uuid,timestamptz,timestamptz,text,jsonb,integer),public.mobile_issue_prescription(uuid,jsonb,uuid),private.mobile_issue_prescription(uuid,jsonb,uuid) to authenticated;

insert into hospital.notification_topics(code,name) values('mobile_activity','Seguimiento de atencion') on conflict(code) do nothing;
create or replace function private.notify_mobile_changes()
returns trigger language plpgsql security definer set search_path='' as $$
declare patient0 uuid; staff0 uuid; recipients uuid[]:='{}'; recipient0 uuid; topic0 uuid; title0 text;
begin
  if tg_table_schema<>'hospital' then raise insufficient_privilege; end if;
  if tg_table_name='appointments' then
    if tg_op='UPDATE' and new.status is not distinct from old.status and new.period is not distinct from old.period then return new; end if;
    if new.status not in ('scheduled','confirmed','cancelled') then return new; end if;
    patient0:=new.patient_id; staff0:=new.physician_id; title0:='Actualizacion de cita';
  elsif tg_table_name='lab_results' then
    if new.status<>'released' or old.status='released' then return new; end if;
    select e.patient_id into patient0 from hospital.diagnostic_order_items i join hospital.diagnostic_orders o on o.id=i.order_id
      join hospital.encounters e on e.id=o.encounter_id where i.id=new.order_item_id;
    title0:='Resultado de laboratorio publicado';
  elsif tg_table_name='prescriptions' then
    if new.status<>'issued' or old.status='issued' then return new; end if;
    select e.patient_id into patient0 from hospital.encounters e where e.id=new.encounter_id;
    title0:='Nueva receta disponible';
  elsif tg_table_name='care_assignments' then
    if not (new.valid_during@>now()) then return new; end if;
    if tg_op='UPDATE' and new.staff_id=old.staff_id and new.valid_during=old.valid_during then return new; end if;
    staff0:=new.staff_id; title0:='Paciente asignado a tu atencion';
  elsif tg_table_name='staff_shifts' then
    if tg_op='UPDATE' and new.status=old.status and new.period=old.period then return new; end if;
    staff0:=new.staff_id; title0:='Actualizacion de jornada laboral';
  elsif tg_table_name='patient_allergies' then
    if tg_op='UPDATE' and new.status=old.status and new.reaction is not distinct from old.reaction and new.severity is not distinct from old.severity then return new; end if;
    select coalesce(array_agg(distinct p.id),'{}') into recipients from hospital.care_assignments c
      join hospital.staff_members s on s.id=c.staff_id join hospital.profiles p on p.person_id=s.person_id
      where c.patient_id=new.patient_id and c.valid_during@>now() and s.active and p.status='active'
        and exists(select 1 from hospital.user_role_assignments ra join hospital.roles ro on ro.id=ra.role_id
          where ra.profile_id=p.id and ra.revoked_at is null and ro.code='doctor'
            and ra.facility_id=private.department_facility(c.department_id));
    title0:='Cambio relevante en expediente asignado';
  else raise insufficient_privilege;
  end if;
  if patient0 is not null then
    recipients:=recipients||coalesce((select array_agg(pa.profile_id) from hospital.patient_accounts pa
      join hospital.profiles p on p.id=pa.profile_id where pa.patient_id=patient0 and p.status='active'
        and exists(select 1 from hospital.user_role_assignments ra join hospital.roles ro on ro.id=ra.role_id
          where ra.profile_id=p.id and ra.revoked_at is null and ro.code='patient')),'{}'::uuid[]);
  end if;
  if staff0 is not null then
    recipients:=recipients||coalesce((select array_agg(p.id) from hospital.staff_members s join hospital.profiles p on p.person_id=s.person_id
      where s.id=staff0 and s.active and p.status='active'
        and exists(select 1 from hospital.user_role_assignments ra join hospital.roles ro on ro.id=ra.role_id
          where ra.profile_id=p.id and ra.revoked_at is null and ro.code='doctor')),'{}'::uuid[]);
  end if;
  select id into topic0 from hospital.notification_topics where code='mobile_activity';
  for recipient0 in select distinct x from unnest(recipients) x loop
    if not exists(select 1 from hospital.notification_preferences where profile_id=recipient0 and topic_id=topic0 and channel='in_app' and not enabled) then
      insert into hospital.notifications(recipient_id,topic_id,title,body,expires_at)
        values(recipient0,topic0,title0,'Consulta el detalle autorizado dentro del hospital.',now()+interval '30 days');
    end if;
  end loop;
  return new;
end $$;
alter function private.notify_mobile_changes() owner to postgres;
revoke all on function private.notify_mobile_changes() from public,anon,authenticated,hospital_api,service_role;
drop trigger if exists mobile_appointment_notice on hospital.appointments;
create trigger mobile_appointment_notice after insert or update of status,period on hospital.appointments for each row execute function private.notify_mobile_changes();
drop trigger if exists mobile_result_notice on hospital.lab_results;
create trigger mobile_result_notice after update of status on hospital.lab_results for each row execute function private.notify_mobile_changes();
drop trigger if exists mobile_prescription_notice on hospital.prescriptions;
create trigger mobile_prescription_notice after update of status on hospital.prescriptions for each row execute function private.notify_mobile_changes();
drop trigger if exists mobile_assignment_notice on hospital.care_assignments;
create trigger mobile_assignment_notice after insert or update on hospital.care_assignments for each row execute function private.notify_mobile_changes();
drop trigger if exists mobile_shift_notice on hospital.staff_shifts;
create trigger mobile_shift_notice after insert or update of status,period on hospital.staff_shifts for each row execute function private.notify_mobile_changes();
drop trigger if exists mobile_allergy_notice on hospital.patient_allergies;
create trigger mobile_allergy_notice after insert or update on hospital.patient_allergies for each row execute function private.notify_mobile_changes();
notify pgrst,'reload schema';
commit;
