-- Extend existing RPC projections; keep hospital_api ownership, RLS and authorization.
begin;
grant create on schema private to hospital_api;
set local role hospital_api;
CREATE OR REPLACE FUNCTION private.doctor_chart(p_patient uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v_facility is null then
    select d.facility_id into v_facility from hospital.appointments a
      join hospital.departments d on d.id=a.department_id
      where a.patient_id=p_patient and a.physician_id=v_staff
        and private.can_patient(p_patient,'clinical.read')
      order by lower(a.period) desc,a.id limit 1;
  end if;
  perform private.require_doctor(v_facility);
  -- Preserve the existing care-link/MFA checks and audit of the chart RPC.
  v_base := public.patient_chart(p_patient);
  select jsonb_build_object(
    'patient', jsonb_build_object('id',p.id,'given_names',n.given_names,'family_names',n.family_names,'dui',n.dui,'full_name',concat_ws(' ',n.given_names,n.family_names),
      'record_number',p.medical_record_number,'birth_date',n.birth_date,'sex',n.administrative_sex,
      'phone',coalesce(n.phone,(select c.value from hospital.person_contacts c where c.person_id = n.id and c.kind = 'phone' order by c.is_primary desc,c.id limit 1)),
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
    'laboratories',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'test_name',t.name,'requested_at',coalesce(o.ordered_at,o.created_at),
      'instructions',o.clinical_question,
      'status',case when r.id is not null then 'completed' when i.status='cancelled' then 'cancelled' when i.status='pending' then 'pending' else 'in_progress' end,
      'narrative',r.narrative,'released_at',r.released_at,
      'values',coalesce((select jsonb_agg(jsonb_build_object('name',a.name,
        'value',coalesce(v.value_numeric::text,v.value_text),'unit',u.name,
        'reference',coalesce(rr.interpretation,concat_ws(' – ',rr.lower_value::text,rr.upper_value::text)))
        order by a.name,v.id)
        from hospital.lab_result_values v join hospital.analytes a on a.id=v.analyte_id
        left join hospital.units u on u.id=v.unit_id left join hospital.lab_reference_ranges rr on rr.id=v.reference_range_id
        where v.result_id=r.id),'[]'::jsonb))
      order by coalesce(o.ordered_at,o.created_at) desc,i.id)
      from hospital.diagnostic_orders o join hospital.encounters e on e.id=o.encounter_id
      join hospital.diagnostic_order_items i on i.order_id=o.id
      join hospital.test_definitions t on t.id=i.test_id
      left join lateral(select x.* from hospital.lab_results x
        where x.order_item_id=i.id and x.status='released' order by x.version desc,x.id limit 1) r on true
      where e.patient_id=p.id and o.status<>'draft' and private.can_encounter(e.id,'clinical.read')),'[]'::jsonb),
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
end $function$
;
CREATE OR REPLACE FUNCTION private.doctor_workspace(p_facility uuid, p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_staff uuid; v_result jsonb;
begin
  v_staff := private.require_doctor(p_facility);
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '2 days' then
    raise invalid_parameter_value using message = 'Intervalo de jornada invalido';
  end if;
  with agenda as (
    select a.*, ae.encounter_id, n.dui,
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
      'patient_name',a.patient_name,'dui',a.dui,'record_number',a.record_number,'phone',a.phone,'ticket_number',a.ticket_number,
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
end $function$
;
reset role;
revoke create on schema private from hospital_api;
notify pgrst,'reload schema';
commit;

