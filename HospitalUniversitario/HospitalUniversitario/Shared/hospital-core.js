/* Shared by JavaScriptCore (iOS) and the Windows browser preview. No credentials. */
(function (root) {
  'use strict';
  var labels = { doctor: 'Médico', patient: 'Paciente' };
  function registrationAccount(values) {
    values=values||{};
    var metadata={};
    ['first_name','last_name','birth_date','phone','city'].forEach(function(key){metadata[key]=String(values[key]||'').trim();});
    // Declared identity only. Never look up a clinical patient by DUI or submit a profile_id/role.
    metadata.dui=formatDui(values.dui);
    return metadata;
  }
  function registrationReviewMessage() {
    return 'Cuenta creada. La vinculación de cualquier expediente requiere revisión de identidad en recepción. El DUI declarado no concede acceso a información clínica. Si necesitas revisar una asociación existente, acude a recepción.';
  }
  function routes(access) {
    if (!access || !access.profile || access.profile.status !== 'active') return [];
    return ['doctor', 'patient'].filter(function (code) {
      var linked = code === 'doctor' ? access.staff_id : true;
      return !!linked && (access.roles || []).some(function (role) { return role.code === code; });
    });
  }
  function turnResource(role) {
    if (role === 'doctor') return 'staff_shifts';
    if (role === 'patient') return 'appointments';
    throw new Error('Rol no permitido');
  }
  function weekWindow(now) {
    var first = now ? new Date(now) : new Date();
    if (!isFinite(first.getTime())) throw new Error('Fecha inválida');
    first.setDate(first.getDate() - (first.getDay() + 6) % 7);
    first.setHours(0, 0, 0, 0);
    var last = new Date(first); last.setDate(last.getDate() + 7);
    return '["' + first.toISOString() + '","' + last.toISOString() + '")';
  }
  function periodBounds(value) {
    // PostgreSQL tstzrange: ["2026-10-23 07:00:00-06","2026-10-23 15:00:00-06")
    if (typeof value !== 'string' || value[0] !== '[' || value.slice(-1) !== ')') throw new Error('Intervalo inválido');
    var match = /^\["?([^",]+)"?,"?([^",]+)"?\)$/.exec(value);
    if (!match) throw new Error('Intervalo inválido');
    function normalize(s) { return s.replace(' ', 'T').replace(/([+-]\d{2})$/, '$1:00'); }
    var start = new Date(normalize(match[1])), end = new Date(normalize(match[2]));
    if (!isFinite(start.getTime()) || !isFinite(end.getTime()) || start >= end) throw new Error('Intervalo inválido');
    return { start: start.toISOString(), end: end.toISOString() };
  }
  // Solicitante sin expediente: reglas locales compartidas por iOS y la vista previa web.
  // Solo presentación y validación: no consulta ni escribe en Supabase.
  var applicantDemoSpecialties = ['Medicina general', 'Medicina interna', 'Pediatría', 'Ginecología'];
  var applicantPeriods = { morning: 'Mañana · AM', afternoon: 'Tarde · PM' };
  var applicantStates = {
    pending: { key: 'pending', label: 'Pendiente' },
    identity_verified: { key: 'review', label: 'En revisión' },
    converted: { key: 'accepted', label: 'Aceptada' },
    rejected: { key: 'rejected', label: 'Rechazada' },
    cancelled: { key: 'cancelled', label: 'Cancelada' }
  };
  function localIsoDay(date) {
    var d = date instanceof Date ? date : new Date(date);
    var pad = function (n) { return (n < 10 ? '0' : '') + n; };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  }
  function isIsoDay(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    var parts = value.split('-').map(Number);
    var d = new Date(parts[0], parts[1] - 1, parts[2]);
    return d.getFullYear() === parts[0] && d.getMonth() === parts[1] - 1 && d.getDate() === parts[2];
  }
  function formatDui(value) {
    var digits = String(value == null ? '' : value).replace(/\D/g, '').slice(0, 9);
    return digits.length > 8 ? digits.slice(0, 8) + '-' + digits.slice(8) : digits;
  }
  function applicantAge(birthDate, today) {
    if (!isIsoDay(birthDate)) return null;
    var now = isIsoDay(today) ? today : localIsoDay(new Date());
    var years = Number(now.slice(0, 4)) - Number(birthDate.slice(0, 4));
    if (now.slice(5) < birthDate.slice(5)) years -= 1;
    return years;
  }
  function validatePersonalData(input, today) {
    var given = String(input.given || '').trim(), family = String(input.family || '').trim();
    if (!given || given.length > 100) return { field: 'given', message: 'Introduce tus nombres (máximo 100 caracteres).' };
    if (!family || family.length > 100) return { field: 'family', message: 'Introduce tus apellidos (máximo 100 caracteres).' };
    var age = applicantAge(input.birthDate, today);
    if (age === null || age < 1 || age > 120 || input.birthDate < '1900-01-01') return { field: 'birthDate', message: 'Introduce una fecha de nacimiento válida (edad entre 1 y 120 años).' };
    if (String(input.dui || '').replace(/\D/g, '').length !== 9) return { field: 'dui', message: 'El DUI debe contener 9 dígitos, por ejemplo 01234567-8.' };
    if (!/^[0-9]{4}-[0-9]{4}$/.test(String(input.phone || '').trim())) return { field: 'phone', message: 'Introduce un teléfono válido.' };
    return null;
  }
  function validateApplicantProfile(input, today) {
    var personal = validatePersonalData(input, today);
    if (personal) return personal;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(input.email || '').trim())) return { field: 'email', message: 'Introduce un correo electrónico válido.' };
    if (String(input.password || '').length < 8) return { field: 'password', message: 'La contraseña debe tener al menos 8 caracteres.' };
    if (input.confirm !== input.password) return { field: 'confirm', message: 'La confirmación de contraseña no coincide.' };
    return null;
  }
  function validateAttentionRequest(input, today) {
    if (!input.specialty) return { field: 'specialty', message: 'Elige una especialidad.' };
    var reason = String(input.reason || '').trim();
    if (!reason || reason.length > 2000) return { field: 'reason', message: 'Describe el motivo de la atención (máximo 2000 caracteres).' };
    var now = isIsoDay(today) ? today : localIsoDay(new Date());
    if (!isIsoDay(input.date) || input.date < now) return { field: 'date', message: 'Elige una fecha preferida igual o posterior a hoy.' };
    if (input.period !== 'morning' && input.period !== 'afternoon') return { field: 'period', message: 'Elige la preferencia Mañana o Tarde.' };
    return null;
  }
  // Estado de interfaz a partir de solicitud y cita. 'scheduled' no se guarda en la solicitud:
  // solo se muestra cuando la solicitud está convertida y la cita asociada está programada.
  function applicantStateView(status, appointmentStatus) {
    if (status === 'converted' && appointmentStatus === 'scheduled') return { key: 'scheduled', label: 'Cita programada' };
    return applicantStates[status] || { key: 'unknown', label: 'Estado no disponible' };
  }
  root.HospitalCore = { labels: labels, routes: routes, turnResource: turnResource, weekWindow: weekWindow, periodBounds: periodBounds,
    registrationAccount: registrationAccount, registrationReviewMessage: registrationReviewMessage,
    applicantDemoSpecialties: applicantDemoSpecialties, applicantPeriods: applicantPeriods, localIsoDay: localIsoDay, isIsoDay: isIsoDay,
    formatDui: formatDui, applicantAge: applicantAge, validatePersonalData: validatePersonalData, validateApplicantProfile: validateApplicantProfile,
    validateAttentionRequest: validateAttentionRequest, applicantStateView: applicantStateView };
})(typeof globalThis !== 'undefined' ? globalThis : this);

// Hospital Móviles: endpoint plans and presentation adapters shared by both clients.
// Every request executes with the user's JWT and the existing database RLS.
(function (root) {
  'use strict';
  var uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
  function id(value) { if (!uuid.test(value || '')) throw new Error('Identificador inválido.'); return value; }
  function query(table, select, filters, order, limit) {
    var path = '/rest/v1/' + table + '?select=' + encodeURIComponent(select);
    Object.keys(filters || {}).forEach(function (key) { path += '&' + key + '=' + encodeURIComponent(filters[key]); });
    if (order) path += '&order=' + encodeURIComponent(order);
    return {path:path + '&limit=' + (limit || 26), method:'GET'};
  }
  function state(value) { return ({pendiente:'pending',programada:'scheduled',confirmada:'confirmed',en_revision:'in_progress',agendada:'scheduled',en_proceso:'in_progress',completado:'completed',entregada:'collected',anulada:'cancelled',parcial:'issued',en_atencion:'in_progress',completada:'completed',cancelada:'cancelled',rechazada:'rejected',no_asistio:'no_show',aprobada:'approved',programado:'scheduled'})[value] || value; }
  function range(row) { return '["' + row.starts_at + '","' + row.ends_at + '")'; }
  function fullName(row) { return [row.first_name,row.last_name].filter(Boolean).join(' '); }
  function access(user, profile, roles, patients, staff) {
    if (!user || !uuid.test(user.id) || !profile || profile.id !== user.id) throw new Error('No se encontró tu perfil.');
    var active = roles.filter(function (r) { return r.user_id === user.id && r.active === true; });
    var patient = patients.find(function (r) { return r.profile_id === user.id; });
    var employee = staff.find(function (r) { return r.profile_id === user.id && r.active === true; });
    var codes = [];
    if (employee && active.some(function (r) { return r.role === 'doctor'; })) codes.push('doctor');
    if (active.some(function (r) { return r.role === 'paciente'; })) codes.push('patient');
    return {profile:{id:user.id,status:codes.length ? 'active' : 'denied',preferred_name:fullName(profile),greeting_name:[String(profile.first_name||'').trim().split(/\s+/)[0],String(profile.last_name||'').trim().split(/\s+/)[0]].filter(Boolean).join(' ')},
      roles:codes.map(function (code) { return {code:code,context_id:user.id}; }),patient_id:patient ? patient.id : null,staff_id:employee ? employee.id : null,
      identity:profile,email:user.email || null};
  }
  function plan(kind, p, a) {
    p = p || {};
    if (!a || !a.profile) throw new Error('Inicia sesión.');
    var patient = a.patient_id, employee = a.staff_id, filters = {}, select, table, order;
    if (kind === 'profile' || kind === 'activity') return [];
    if (kind === 'patientDashboard') {
      if (!patient) return [];
      return [query('appointments','id,patient_id,starts_at,ends_at,status,staff!appointments_doctor_id_fkey(employee_code,profiles!staff_profile_id_fkey(first_name,last_name))',
        {patient_id:'eq.'+id(patient),status:'in.(programada,confirmada,en_atencion)',or:'(status.eq.en_atencion,starts_at.gte.'+(p.now || new Date().toISOString())+')'},'starts_at.asc,id.asc',1)];
    }
    if (kind === 'registerPatient') throw new Error('Solo el personal autorizado puede crear pacientes y expedientes.');
    if (kind === 'rooms') return [query('rooms','id,code,floor_id,kind,active',p.cursor ? {id:'gt.'+id(p.cursor.id)} : {},'id.asc')];
    if (kind === 'shifts') {
      id(employee); var bounds = root.HospitalCore.periodBounds(p.window || root.HospitalCore.weekWindow());
      filters = {staff_id:'eq.'+employee,starts_at:'lt.'+bounds.end,ends_at:'gt.'+bounds.start};
      if(p.cursor) filters.or='(starts_at.gt.'+p.cursor.value+',and(starts_at.eq.'+p.cursor.value+',id.gt.'+id(p.cursor.id)+'))';
      return [query('staff_shifts','id,staff_id,starts_at,ends_at,shift_type,status',filters,'starts_at.asc,id.asc')];
    }
    if (kind === 'overview') return [query('announcements','id,title,content,published_at,expires_at',{is_public:'eq.true'},'published_at.desc',100)];
    if (kind === 'workspace') {
      id(employee);
      return [query('appointments','*,patients(first_name,last_name,phone,patient_code)',{doctor_id:'eq.'+employee,starts_at:'gte.'+p.p_from,ends_at:'lte.'+p.p_to},'starts_at.asc,id.asc',1000)];
    }
    if (kind === 'requestAttention') {
      id(patient);
      if (!/^\d+$/.test(String(p.p_specialty)) || !String(p.p_reason || '').trim() || String(p.p_reason).length>2000 || !['manana','tarde'].includes(p.period)) throw new Error('Revisa especialidad, motivo y preferencia.');
      return [{path:'/rest/v1/appointment_requests',method:'POST',body:{id:id(p.p_request_key),patient_id:patient,specialty_id:String(p.p_specialty),preferred_period:p.period,reason:p.p_reason.trim(),status:'pendiente'}}];
    }
    if (kind === 'cancelAppointment') return [{path:'/rest/v1/rpc/cancel_appointment',method:'POST',body:{p_id:id(p.p_id),p_reason:p.p_reason}}];
    if (kind === 'updatePhone') return [{path:'/rest/v1/profiles?id=eq.'+id(a.profile.id),method:'PATCH',body:{phone:p.p_value}}];
    if (kind === 'updateItem' && p.p_resource === 'notifications') return [{path:'/rest/v1/notifications?id=eq.'+id(p.p_id)+'&recipient_id=eq.'+id(a.profile.id),method:'PATCH',body:{read_at:new Date().toISOString()}}];
    if (kind !== 'module') throw new Error('Esta operación todavía no está disponible con Hospital Móviles.');
    var module = p.p_module;
    if (!patient && root.HospitalCore.routes(a).indexOf('patient')>=0 && ['appointments','request','chart','history','laboratory','prescriptions'].indexOf(module)>=0) return [];
    if (module === 'profile') return [];
    if (module === 'request') {
      id(patient);
      return [query('appointment_requests','*,specialties(name)',{patient_id:'eq.'+patient},'created_at.desc,id.desc',100),query('specialties','id,name',{active:'eq.true'},'name.asc',1000)];
    }
    if (module === 'notifications') { table='notifications'; select='*'; filters.recipient_id='eq.'+id(a.profile.id); order='created_at'; }
    else if (module === 'appointments') { table='appointments'; select=patient ? '*,consulting_rooms(code),staff!appointments_doctor_id_fkey(employee_code,profiles!staff_profile_id_fkey(first_name,last_name)),appointment_requests(reason,specialties(name))' : '*,consulting_rooms(code)'; filters[patient ? 'patient_id' : 'doctor_id']='eq.'+id(patient || employee); order='starts_at'; }
    else if (module === 'chart') {
      id(patient);
      return [query('patients','id,first_name,last_name,dui,phone,birth_date,city,patient_code,medical_records(record_code)',{id:'eq.'+patient},'id.asc',1),query('medical_history','history_type,description,medical_records!inner(patient_id)',{'medical_records.patient_id':'eq.'+patient},'created_at.desc,id.desc',100)];
    }
    else if (module === 'history') { return [{path:'/rest/v1/rpc/my_consultation_history',method:'POST',body:{p_from:p.p_from||null,p_to:p.p_to||null,p_cursor:p.p_cursor||null}}]; }
    else if (module === 'laboratory') { table='lab_orders';select='*,lab_test_types(name),clinical_encounters!inner(medical_records!inner(patient_id)),lab_results(summary,published_to_patient_at,published_at,validated_at,validated_by,parameter_schema,result_values)';filters['clinical_encounters.medical_records.patient_id']='eq.'+id(patient);order='ordered_at'; }
    else if (module === 'prescriptions') { table='prescriptions';select='*,clinical_encounters!inner(medical_records!inner(patient_id)),prescription_items(dose,dose_unit,frequency_hours,route,quantity,observations,medications(name))';filters['clinical_encounters.medical_records.patient_id']='eq.'+id(patient);order='issued_at'; }
    else throw new Error('Módulo no disponible.');
    if (p.p_from) filters[order]='gte.'+p.p_from;
    if (p.p_to) filters.and='('+order+'.lte.'+p.p_to+')';
    if (p.p_cursor) filters.or='('+order+'.lt.'+p.p_cursor.value+',and('+order+'.eq.'+p.p_cursor.value+',id.lt.'+id(p.p_cursor.id)+'))';
    return [query(table,select,filters,order+'.desc,id.desc')];
  }
  function field(label,value) { return {label:label,value:value == null || value === '' ? 'Sin registrar' : String(value)}; }
  function present(kind, p, a, results) {
    p=p||{}; var rows=results[0] || [], row, data;
    if(kind==='patientDashboard') {
      row=rows.find(function(r){return r.patient_id===a.patient_id && (r.status==='en_atencion' || (['programada','confirmada'].indexOf(r.status)>=0 && new Date(r.starts_at)>=new Date(p.now || new Date().toISOString())));});
      var doctor=row && row.staff && row.staff.profiles;
      return {next_appointment:row ? {id:row.id,starts_at:row.starts_at,ends_at:row.ends_at,status:state(row.status),doctor_name:(doctor ? fullName(doctor) : '') || (row.staff && row.staff.employee_code ? 'Médico · '+row.staff.employee_code : null)} : null};
    }
    if(kind==='profile') return {person:{given_names:a.identity.first_name,family_names:a.identity.last_name},auth_email:a.email,contacts:a.identity.phone ? [{kind:'phone',value:a.identity.phone}] : [],professional:null};
    if(kind==='activity') return {}; // No invented counters; modules retrieve their own authorized rows.
    if(kind==='overview') return {capacity:null,occupied:null,information:rows.filter(function(r){return !r.expires_at || new Date(r.expires_at)>new Date();}).map(function(r){return {id:r.id,title:r.title,body:r.content};}),on_duty:[]};
    if(kind==='rooms' || kind==='shifts') { data=rows.slice(0,25);row=data[data.length-1];return {data:data,has_more:rows.length>25,next_cursor:rows.length>25 ? {id:row.id,value:kind==='shifts'?row.starts_at:null} : null}; }
    if(kind==='workspace') return {doctor_name:a.profile.preferred_name,facility_name:'Hospital Universitario',appointments:rows.map(function(r){return {id:r.id,patient_id:r.patient_id,patient_name:r.patients ? fullName(r.patients) : 'Paciente',record_number:r.patients ? r.patients.patient_code : '',phone:r.patients ? r.patients.phone : null,ticket_number:null,period:range(r),status:state(r.status),encounter_id:null};}),orders:[],tests:[],notifications:[],stats:{consultations:rows.length,completed_consultations:rows.filter(function(r){return r.status==='completada';}).length,issued_orders:0,pending_orders:0}};
    if(kind!=='module') return null;
    var page={items:[],sections:[],options:[],preferences:[],specialties:[],phone:a.identity.phone || null,emergency:null,has_more:false,next_cursor:null};
    var module=p.p_module;
    if (!a.patient_id && root.HospitalCore.routes(a).indexOf('patient')>=0 && ['appointments','request','chart','history','laboratory','prescriptions'].indexOf(module)>=0) return page;
    if(module==='profile') return page;
    if(module==='chart') {
      row=rows[0]; if(!row) throw new Error('No se encontró tu expediente.');
      var record=Array.isArray(row.medical_records)?row.medical_records[0]:row.medical_records;
      page.sections=[{title:'Datos personales',fields:[field('Nombre',fullName(row)),field('Nombres',row.first_name),field('Apellidos',row.last_name),field('DUI',row.dui),field('Fecha de nacimiento',row.birth_date),field('Edad',root.HospitalCore.applicantAge(row.birth_date)),field('Teléfono',row.phone),field('Correo',a.email),field('Ciudad',row.city),field('Código de paciente',row.patient_code),field('Expediente',record ? record.record_code : null)]}];page.sections.push({title:'Antecedentes registrados',fields:(results[1]||[]).map(function(h){return field(h.history_type,h.description);})});return page;
    }
    if(module==='request') page.specialties=(results[1]||[]).map(function(r){return {id:String(r.id),name:r.name,kind:'specialty'};});
    var visible=rows.slice(0,25);
    page.items=visible.map(function(r){
      var item={id:r.id,title:'',subtitle:null,status:state(r.status),event_at:r.created_at || r.starts_at || r.ordered_at || r.issued_at,row_version:0,details:[],action:null,document_id:null};
      if(module==='request'){item.title=r.specialties ? r.specialties.name : 'Solicitud de atención';item.subtitle=r.reason;item.details=[field('Motivo',r.reason),field('Preferencia',r.preferred_period==='manana'?'Mañana':'Tarde')];}
      if(module==='appointments'){
        // Detalles de la cita en la misma tarjeta: médico, especialidad, consultorio y motivo cuando existen (sin campos vacíos).
        var doctor=r.staff&&r.staff.profiles?fullName(r.staff.profiles):'',request=Array.isArray(r.appointment_requests)?r.appointment_requests[0]:r.appointment_requests;
        var specialty=request&&request.specialties?request.specialties.name:null;
        item.event_at=r.starts_at;item.title=specialty||'Cita médica';item.subtitle=r.consulting_rooms ? 'Consultorio '+r.consulting_rooms.code : null;item.details=[field('Horario',range(r))];
        if(doctor||(r.staff&&r.staff.employee_code))item.details.push(field('Médico',doctor||'Médico · '+r.staff.employee_code));
        if(specialty)item.details.push(field('Especialidad',specialty));
        if(r.consulting_rooms)item.details.push(field('Consultorio',r.consulting_rooms.code));
        if(request&&request.reason)item.details.push(field('Motivo de la consulta',request.reason));
        if(r.status==='cancelada'&&r.cancellation_reason)item.details.push(field('Motivo de cancelación',r.cancellation_reason));
        if(['programada','confirmada'].includes(r.status)) item.action='cancel_appointment';}
      if(module==='history'){
        // Solo consultas finalizadas propias (my_consultation_history). Nunca se presentan campos vacíos como datos registrados.
        item.title=r.specialty||'Consulta médica';item.subtitle=r.reason||r.assessment||r.subjective||null;item.status='completed';item.event_at=r.started_at;
        var real=function(v){return v!=null&&String(v).trim()!=='';};
        var add=function(label,value){if(real(value))item.details.push({label:label,value:String(value).trim()});};
        item.details=[];
        add('Médico',r.doctor_name);add('Especialidad',r.specialty);add('Motivo de consulta',r.reason);
        add('Síntomas que presentaba',r.subjective);add('Diagnóstico',r.assessment);
        (r.diagnoses||[]).forEach(function(d){add('Código diagnóstico',d.diagnosis_code);});
        add('Observaciones',r.objective);add('Tratamiento',r.plan);
        var vitals=(r.vital_signs||[]).slice().sort(function(a,b){return String(b.recorded_at).localeCompare(String(a.recorded_at));})[0]||{};
        [['weight_kg','Peso (kg)'],['height_cm','Altura (cm)'],['temperature_c','Temperatura (°C)'],['systolic','Presión sistólica (mmHg)'],['diastolic','Presión diastólica (mmHg)'],['heart_rate','Frecuencia cardíaca (lpm)']].forEach(function(pair){add(pair[1],vitals[pair[0]]);});
        // Recetas y exámenes por consulta: llegan cuando se aplica supabase/expedientes-historial.sql.
        (r.prescriptions||[]).forEach(function(rx){add('Receta '+(rx.code||''),(rx.lines||[]).join('\n'));});
        (r.lab_orders||[]).forEach(function(o){add('Examen: '+(o.test_name||'Laboratorio'),real(o.result_summary)?'Resultado publicado: '+o.result_summary:'Estado: '+({pendiente:'Pendiente',en_proceso:'En proceso',completado:'Completado · pendiente de publicación',anulada:'Anulada',cancelada:'Cancelada'}[o.status]||'En proceso'));});
        add('Finalizada',r.ended_at);
      }
      if(module==='notifications'){item.title=r.title;item.subtitle=r.body;item.status=r.read_at?'read':'unread';item.action=r.read_at?null:'mark_read';}
      if(module==='laboratory'){
        item.title=r.lab_test_types?r.lab_test_types.name:'Examen';item.subtitle=r.reason;
        var published=(r.lab_results||[]).filter(function(v){return !!v.published_to_patient_at && !!v.published_at && !!v.validated_at && !!v.validated_by;});
        item.status=published.length?'released':r.status==='completado'?'awaiting_release':state(r.status);
        item.details=published.map(function(v){return field('Resultado',v.summary);});
        published.forEach(function(v){(v.parameter_schema||[]).forEach(function(parameter){
          var entry=(v.result_values||{})[parameter.key]||{},value=entry.value==null?'No informado':String(entry.value);
          if(parameter.unit)value+=' '+parameter.unit;
          if(parameter.reference)value+=' · Referencia del laboratorio: '+parameter.reference;
          if(entry.observation)value+=' · Observación: '+entry.observation;
          item.details.push(field(parameter.label,value));
        });});
        if(r.reason)item.details.push(field('Indicaciones',r.reason));
      }
      if(module==='prescriptions'){item.title=r.prescription_code;item.details=(r.prescription_items||[]).map(function(v){return field(v.medications?v.medications.name:'Medicamento',v.dose+' '+v.dose_unit+' · cada '+v.frequency_hours+' horas · '+v.route+' · '+(v.observations||''));});}
      return item;
    });
    if(module!=='request' && rows.length>25){row=visible[24];page.has_more=true;page.next_cursor={id:row.id,value:row.started_at||row.created_at||row.starts_at||row.ordered_at||row.issued_at};}
    if(p.p_query) {var search=p.p_query.toLowerCase();page.items=page.items.filter(function(r){return JSON.stringify(r).toLowerCase().indexOf(search)>=0;});}
    return page;
  }
  root.HospitalCore.backendAccess=access;
  root.HospitalCore.backendPlan=plan;
  root.HospitalCore.backendPresent=present;
})(typeof globalThis !== 'undefined' ? globalThis : this);

// Flujo clínico del médico: espejo exacto de DoctorClinicalRules (Swift) y de las validaciones
// desplegadas en doctor_native_save / doctor_native_finish. Sin credenciales ni llamadas de red.
(function (root) {
  'use strict';
  var zone = 'America/El_Salvador';
  var statusLabels = {scheduled:'Programada',confirmed:'Programada',checked_in:'En espera',in_progress:'En consulta',completed:'Finalizada',cancelled:'Cancelada',no_show:'No asistió',rejected:'Rechazada'};
  // Datos físicos del formulario (columnas reales de public.vital_signs; rangos de doctor_native_save).
  var vitals = [
    {key:'weight_kg',label:'Peso',unit:'kg',integer:false,min:0,max:1000,lowerExclusive:true},
    {key:'height_cm',label:'Altura',unit:'cm',integer:false,min:0,max:300,lowerExclusive:true},
    {key:'temperature_c',label:'Temperatura',unit:'°C',integer:false,min:25,max:50,lowerExclusive:false}];
  // Medidas de consultas anteriores: ya no se capturan, pero se conservan al guardar y se muestran en el historial.
  var recordedVitals = vitals.concat([
    {key:'systolic',label:'Presión sistólica',unit:'mmHg'},{key:'diastolic',label:'Presión diastólica',unit:'mmHg'},{key:'heart_rate',label:'Frecuencia cardíaca',unit:'lpm'}]);
  // Las tres notas del formulario y su columna en clinical_encounters. `plan` ya no se captura: se conserva tal como esté guardado.
  var sections = [['subjective','Síntomas que presentaba'],['assessment','Diagnóstico'],['objective','Observaciones']];
  var pendingFinishMigration = 'El servidor todavía exige el plan de tratamiento para finalizar. Falta aplicar supabase/doctor-consultation-six-fields.sql; lo guardado se conserva.';
  function statusLabel(status) { return statusLabels[status] || 'Programada'; }
  function dayKey(date) {
    var d = date instanceof Date ? date : new Date(date);
    if (!isFinite(d.getTime())) return '';
    return new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(d);
  }
  function todayKey(now) { return dayKey(now || new Date()); }
  function addDays(key, days) {
    var date = new Date(key + 'T12:00:00-06:00'); date.setUTCDate(date.getUTCDate() + days); return dayKey(date);
  }
  // Inicio del día en El Salvador (UTC−6 fijo, sin horario de verano) para pedir la agenda.
  function dayWindow(key, days) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key || '')) throw new Error('Selecciona una fecha válida.');
    var from = new Date(key + 'T00:00:00-06:00'), to = new Date(from.getTime() + (days || 1) * 86400000);
    if (!isFinite(from.getTime())) throw new Error('Selecciona una fecha válida.');
    return {from:from.toISOString(), to:to.toISOString()};
  }
  function start(appointment) {
    var match = /^\["?([^",]+)"?,/.exec(appointment && appointment.period || '');
    if (!match) return null;
    var date = new Date(match[1].replace(' ','T').replace(/([+-]\d{2})$/,'$1:00'));
    return isFinite(date.getTime()) ? date : null;
  }
  // Orden cronológico real por fecha y hora de inicio; nunca por el texto del intervalo.
  function chronological(list) {
    return list.slice().sort(function (a, b) {
      var left = start(a), right = start(b), l = left ? left.getTime() : Infinity, r = right ? right.getTime() : Infinity;
      return l === r ? String(a.id).localeCompare(String(b.id)) : l - r;
    });
  }
  function agenda(appointments, key) {
    var result = {day:[],upcoming:[],completed:[],cancelled:[]};
    chronological(appointments || []).forEach(function (a) {
      var date = start(a), k = date ? dayKey(date) : '9999-12-31';
      if (a.status === 'completed') result.completed.push(a);
      else if (['cancelled','no_show','rejected'].indexOf(a.status) >= 0) result.cancelled.push(a);
      else if (k < key && a.status !== 'in_progress') return; // días previos solo para retomar consultas en atención
      else if (k <= key) result.day.push(a); else result.upcoming.push(a);
    });
    return result;
  }
  // Agenda de dos filtros (espejo de DoctorClinicalRules.pending/finished). Los estados no se modifican.
  var lookbackDays = 2, pendingStates = ['scheduled','confirmed','checked_in','in_progress'];
  function fold(text) { return String(text == null ? '' : text).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim(); }
  function matches(a, query) {
    var words = fold(query).split(/\s+/).filter(Boolean); if (!words.length) return true;
    var hay = fold([a && a.patient_name, a && a.patient_code, a && a.record_number].join(' '));
    return words.every(function (w) { return hay.indexOf(w) >= 0; });
  }
  function finishedAt(a) {
    var d = a && a.finished_at ? new Date(a.finished_at) : null;
    return d && isFinite(d.getTime()) ? d : start(a);
  }
  // PENDIENTES: del día elegido, sin finalizar ni cancelar, hora ascendente; hoy también las en atención de días previos.
  function pending(list, key, today) {
    today = today || todayKey();
    return chronological((list || []).filter(function (a) {
      if (pendingStates.indexOf(a.status) < 0) return false;
      var k = start(a) ? dayKey(start(a)) : '';
      return k === key || (key === today && a.status === 'in_progress' && k !== '' && k < key);
    }));
  }
  // FINALIZADAS: por hora real de finalización (finished_at = ended_at) en la fecha elegida, la última primero.
  function finished(list, key) {
    return (list || []).filter(function (a) { var d = finishedAt(a); return a.status === 'completed' && d && dayKey(d) === key; })
      .sort(function (a, b) { var l = finishedAt(a).getTime(), r = finishedAt(b).getTime(); return l === r ? String(b.id).localeCompare(String(a.id)) : r - l; });
  }
  function sanitize(text, integer) {
    var out = '', separator = false;
    String(text == null ? '' : text).split('').forEach(function (c) {
      if (c >= '0' && c <= '9') out += c;
      else if (!integer && !separator && (c === '.' || c === ',')) { out += '.'; separator = true; }
    });
    return out.slice(0, integer ? 3 : 6);
  }
  function number(text) { return text == null || text === '' ? null : Number(String(text).replace(',','.')); }
  function vitalIssues(values) {
    var issues = {}; values = values || {};
    vitals.forEach(function (v) {
      var raw = values[v.key]; if (raw == null || raw === '') return;
      var n = number(raw);
      if (!isFinite(n) || (v.integer && Math.round(n) !== n)) { issues[v.key] = 'Introduce un número válido.'; return; }
      if ((v.lowerExclusive ? n <= v.min : n < v.min) || n > v.max) issues[v.key] = 'Valor fuera de rango (' + (v.lowerExclusive ? 'mayor que ' : 'desde ') + v.min + ' hasta ' + v.max + ' ' + v.unit + ').';
    });
    return issues;
  }
  // IMC calculado (no se guarda): solo con peso y altura válidos registrados por el médico.
  function bmi(values) {
    var issues = vitalIssues(values), w = number(values && values.weight_kg), h = number(values && values.height_cm);
    if (issues.weight_kg || issues.height_cm || !(w > 0) || !(h > 0)) return null;
    return (w / Math.pow(h / 100, 2)).toFixed(1);
  }
  // Precarga de "Síntomas que presentaba" con lo que envió el paciente (el motivo se muestra aparte).
  function seedSubjective(a) {
    var parts = [], other = String(a && a.other_symptoms || '').trim();
    var symptoms = (a && a.symptoms || []).map(function (s) { return String(s).trim(); }).filter(Boolean);
    if (symptoms.length) parts.push('Síntomas referidos por el paciente: ' + symptoms.join(', '));
    if (other) parts.push('Otros síntomas: ' + other);
    return parts.join('\n');
  }
  function missingSections(note) {
    return sections.filter(function (s) { return !String(note && note[s[0]] || '').trim(); }).map(function (s) { return s[1]; });
  }
  // Minutos de anticipación para abrir una consulta; null = sin límite (modo de pruebas pedido el 20 de noviembre).
  // Para restaurar: 30 aquí y en DoctorClinicalRules.openingLeadMinutes, y aplicar supabase/doctor-start-restore-30min.sql.
  var openingLeadMinutes = null;
  // El servidor conserva la regla de 30 minutos: falta aplicar supabase/doctor-start-anytime.sql.
  var pendingStartMigration = 'El servidor todavía solo permite abrir la consulta desde 30 minutos antes. Para pruebas a cualquier hora falta aplicar supabase/doctor-start-anytime.sql.';
  function startError(message) { return openingLeadMinutes == null && /todavía no puede iniciarse/i.test(String(message || '')) ? pendingStartMigration : null; }
  // Canceladas o finalizadas no se abren.
  function openingBlocker(a, now, lead) {
    var minutes = lead === undefined ? openingLeadMinutes : lead;
    if (!a || a.encounter_id) return null;
    if (['scheduled','confirmed','in_progress'].indexOf(a.status) < 0) return 'Esta cita está ' + statusLabel(a.status).toLowerCase() + '; no puede abrirse una consulta.';
    var date = start(a), reference = now ? new Date(now) : new Date();
    if (minutes != null && date && date.getTime() > reference.getTime() + minutes * 60000) return 'Podrás abrir la consulta desde ' + minutes + ' minutos antes de la hora programada.';
    return null;
  }
  // El cierre falló porque el servidor aún exige `plan` (migración sin aplicar) y el médico no tiene ese campo.
  function finishError(message, note) {
    return /tratamiento/i.test(String(message || '')) && !String(note && note.plan || '').trim() ? pendingFinishMigration : message;
  }
  root.HospitalCore.doctorClinical = {zone:zone,agendaDays:14,lookbackDays:lookbackDays,pending:pending,finished:finished,finishedAt:finishedAt,matches:matches,fold:fold,openingLeadMinutes:openingLeadMinutes,startError:startError,pendingStartMigration:pendingStartMigration,vitals:vitals,recordedVitals:recordedVitals,sections:sections,finishError:finishError,pendingFinishMigration:pendingFinishMigration,statusLabel:statusLabel,dayKey:dayKey,todayKey:todayKey,addDays:addDays,dayWindow:dayWindow,
    start:start,chronological:chronological,agenda:agenda,sanitize:sanitize,vitalIssues:vitalIssues,bmi:bmi,seedSubjective:seedSubjective,missingSections:missingSections,openingBlocker:openingBlocker};
})(typeof globalThis !== 'undefined' ? globalThis : this);

// Una sola solicitud de atención activa por paciente (espejo de AttentionRules en Swift).
(function (root) {
  'use strict';
  var open = ['pendiente','en_revision'], scheduled = ['programada','confirmada','en_atencion','scheduled','confirmed','in_progress'];
  function attentionBlocker(rows, next) {
    var request = (rows || []).filter(function (r) { return open.indexOf(r.status) >= 0; })[0];
    var fmt = function (value, time) { var d = new Date(value); if (!isFinite(d.getTime())) return null;
      var o = {timeZone:'America/El_Salvador',day:'numeric',month:'long',year:'numeric'}; if (time) { o.hour = 'numeric'; o.minute = '2-digit'; }
      return new Intl.DateTimeFormat('es-SV', o).format(d); };
    if (request) return {kind:'request', message:'Ya enviaste una solicitud el ' + (fmt(request.created_at) || 'recientemente') + ' y recepción la está revisando. Podrás enviar otra cuando la programe o la rechace.'};
    if (next && scheduled.indexOf(next.status) >= 0) return {kind:'appointment', message:'Ya tienes una cita programada para el ' + (fmt(next.starts_at, true) || 'próximamente') + '. Si necesitas cambiarla, comunícate con recepción.'};
    return null;
  }
  root.HospitalCore.attentionBlocker = attentionBlocker;
})(typeof globalThis !== 'undefined' ? globalThis : this);
