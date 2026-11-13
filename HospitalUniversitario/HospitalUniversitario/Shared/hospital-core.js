/* Shared by JavaScriptCore (iOS) and the Windows browser preview. No credentials. */
(function (root) {
  'use strict';
  var labels = { doctor: 'Médico', patient: 'Paciente' };
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
        {patient_id:'eq.'+id(patient),status:'in.(programada,confirmada)',starts_at:'gte.'+(p.now || new Date().toISOString())},'starts_at.asc,id.asc',1)];
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
    else if (module === 'appointments') { table='appointments'; select='*,consulting_rooms(code)'; filters[patient ? 'patient_id' : 'doctor_id']='eq.'+id(patient || employee); order='starts_at'; }
    else if (module === 'chart') {
      id(patient);
      return [query('patients','id,first_name,last_name,dui,phone,birth_date,city,patient_code,medical_records(record_code)',{id:'eq.'+patient},'id.asc',1)];
    }
    else if (module === 'history') { table='medical_history';select='*,medical_records!inner(patient_id)';filters['medical_records.patient_id']='eq.'+id(patient);order='created_at'; }
    else if (module === 'laboratory') { table='lab_orders';select='*,lab_test_types(name),clinical_encounters!inner(medical_records!inner(patient_id)),lab_results(summary,published_to_patient_at)';filters['clinical_encounters.medical_records.patient_id']='eq.'+id(patient);order='ordered_at'; }
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
      row=rows.find(function(r){return r.patient_id===a.patient_id && ['programada','confirmada'].indexOf(r.status)>=0 && new Date(r.starts_at)>=new Date(p.now || new Date().toISOString());});
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
      page.sections=[{title:'Datos personales',fields:[field('Nombre',fullName(row)),field('Nombres',row.first_name),field('Apellidos',row.last_name),field('DUI',row.dui),field('Fecha de nacimiento',row.birth_date),field('Edad',root.HospitalCore.applicantAge(row.birth_date)),field('Teléfono',row.phone),field('Correo',a.email),field('Ciudad',row.city),field('Expediente',record ? record.record_code : null)]}];return page;
    }
    if(module==='request') page.specialties=(results[1]||[]).map(function(r){return {id:String(r.id),name:r.name,kind:'specialty'};});
    var visible=rows.slice(0,25);
    page.items=visible.map(function(r){
      var item={id:r.id,title:'',subtitle:null,status:state(r.status),event_at:r.created_at || r.starts_at || r.ordered_at || r.issued_at,row_version:0,details:[],action:null,document_id:null};
      if(module==='request'){item.title=r.specialties ? r.specialties.name : 'Solicitud de atención';item.subtitle=r.reason;item.details=[field('Motivo',r.reason),field('Preferencia',r.preferred_period==='manana'?'Mañana':'Tarde')];}
      if(module==='appointments'){item.title='Cita médica';item.subtitle=r.consulting_rooms ? 'Consultorio '+r.consulting_rooms.code : null;item.details=[field('Horario',range(r))];if(['programada','confirmada'].includes(r.status)) item.action='cancel_appointment';}
      if(module==='history'){item.title=r.history_type;item.subtitle=r.description;item.status='completed';item.details=[field('Descripción',r.description)];}
      if(module==='notifications'){item.title=r.title;item.subtitle=r.body;item.status=r.read_at?'read':'unread';item.action=r.read_at?null:'mark_read';}
      if(module==='laboratory'){item.title=r.lab_test_types?r.lab_test_types.name:'Examen';item.subtitle=r.reason;var published=(r.lab_results||[]).filter(function(v){return !!v.published_to_patient_at;});item.status=published.length?'released':state(r.status);item.details=published.map(function(v){return field('Resultado',v.summary);});}
      if(module==='prescriptions'){item.title=r.prescription_code;item.details=(r.prescription_items||[]).map(function(v){return field(v.medications?v.medications.name:'Medicamento',v.dose+' '+v.dose_unit+' · cada '+v.frequency_hours+' horas · '+v.route+' · '+(v.observations||''));});}
      return item;
    });
    if(module!=='request' && rows.length>25){row=visible[24];page.has_more=true;page.next_cursor={id:row.id,value:row.created_at||row.starts_at||row.ordered_at||row.issued_at};}
    if(p.p_query) {var search=p.p_query.toLowerCase();page.items=page.items.filter(function(r){return JSON.stringify(r).toLowerCase().indexOf(search)>=0;});}
    return page;
  }
  root.HospitalCore.backendAccess=access;
  root.HospitalCore.backendPlan=plan;
  root.HospitalCore.backendPresent=present;
})(typeof globalThis !== 'undefined' ? globalThis : this);
