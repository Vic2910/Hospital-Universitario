// UI workflows with transport fixtures. No credentials or real clinical writes.
import assert from 'node:assert/strict';
import {createApp,openAttentionRequest} from './test-preview.mjs';
const id = '00000000-0000-4000-8000-000000000001';
const second = '00000000-0000-4000-8000-000000000002';
const third = '00000000-0000-4000-8000-000000000003';
const fourth = '00000000-0000-4000-8000-000000000004';
const emptyPage = () => ({items:[],sections:[],options:[],preferences:[],phone:null,emergency:null,has_more:false,next_cursor:null});
const unverifiedDoctor = createApp(['doctor'],{missingMFA:true});
await unverifiedDoctor.login();
assert.equal(unverifiedDoctor.app.textContent.includes('MFA pendiente'),false);
assert.equal(unverifiedDoctor.calls.some(call => call.url.endsWith('/doctor_workspace')),true);
await unverifiedDoctor.click('Notificaciones');
assert.equal(unverifiedDoctor.calls.some(call => call.url.endsWith('/mobile_module') && call.params.p_module === 'notifications'),true);
console.log('OK Medico AAL1: dashboard y notificaciones sin exigir MFA');
const item = (action,status = 'confirmed') => ({id,title:'Registro de prueba',subtitle:'Detalle de prueba',status,event_at:new Date().toISOString(),row_version:7,details:[],action,document_id:null});

const patient = createApp(['patient']);
await patient.login(); await openAttentionRequest(patient);
assert.ok(patient.get('sched-submit'));
assert.equal(patient.app.textContent.includes('Enviar solicitud'),false);
assert.equal(patient.calls.some(call=>call.params?.p_module==='request'),false);
console.log('OK Solicitar atención reutiliza el formulario único y no envía ejemplos a Supabase');

let cancelled = false;
const appointments = createApp(['patient'],{transport:async (url) => {
  if (url.endsWith('/mobile_module')) return {body:{...emptyPage(),items:[item(cancelled ? null : 'cancel_appointment',cancelled ? 'cancelled' : 'confirmed')]}};
  if (url.endsWith('/transition_appointment')) { cancelled = true; return {body:{id}}; }
}});
await appointments.login(); await appointments.click('Mis citas'); await appointments.click('Cita asignada');
await appointments.input('Motivo de cancelación','No puedo asistir'); await appointments.submit('Confirmar cancelación');
const cancellation = appointments.calls.find(call => call.url.endsWith('/transition_appointment'));
assert.equal(cancellation.params.p_expected_version,7);
assert.equal(cancellation.params.p_status,'cancelled');
assert.match(appointments.app.textContent,/Cancelada/);
console.log('OK Cancelación: motivo, versión del servidor y estado recargado');

let read = false;
const notices = createApp(['patient'],{transport:async (url) => {
  if (url.endsWith('/mobile_module')) return {body:{...emptyPage(),items:[item(read ? null : 'mark_read',read ? 'read' : 'unread')]}};
  if (url.endsWith('/update_record')) { read = true; return {body:{id}}; }
}});
await notices.login(); await notices.click('Más'); await notices.click('Notificaciones　›'); await notices.click('Marcar como leída');
const notification = notices.calls.find(call => call.url.endsWith('/update_record'));
assert.equal(notification.params.p_resource,'notifications'); assert.equal(notification.params.p_expected_version,7);
assert.deepEqual(Object.keys(notification.params.p_values),['read_at']); assert.match(notices.app.textContent,/Leída/);
console.log('OK Notificación: lectura propia, versión e imposibilidad de cambiar destinatario');

let started = false, saved = false, closed = false, issued = false, versionConflict = false;
let savedValues;
const doctor = createApp(['doctor'],{transport:async (url,params) => {
  if (url.endsWith('/doctor_workspace')) return {body:{doctor_name:'Doctor de prueba',facility_name:'Sede de prueba',
    appointments:[{id,patient_id:second,patient_name:'Paciente ficticio',record_number:'TEST',phone:null,ticket_number:'1',period:'["2026-10-28 08:00:00-06","2026-10-28 09:00:00-06")',status:closed ? 'completed' : started ? 'in_progress' : 'checked_in',encounter_id:started ? third : null}],orders:[],tests:[],notifications:[],stats:{consultations:started ? 1 : 0,completed_consultations:closed ? 1 : 0,issued_orders:0,pending_orders:0}}};
  if (url.endsWith('/doctor_chart')) return {body:{patient:{id:second,full_name:'Paciente ficticio',record_number:'TEST'},allergies:[],conditions:[],history:started ? [{id:third,started_at:new Date().toISOString(),status:closed ? 'closed' : 'open',row_version:3,note_id:saved ? fourth : null,note_version:saved ? 2 : null,...savedValues}] : []}};
  if (url.endsWith('/start_consultation')) { started = true; return {body:{id:third}}; }
  if (url.endsWith('/save_consultation')) { if (versionConflict) return {status:409,body:{code:'PT409'}}; saved = true; savedValues = params.p_values; return {body:{id:fourth}}; }
  if (url.endsWith('/mobile_module')) return {body:{...emptyPage(),items:issued ? [item(null,'issued')] : [],options:[{id,name:'Medicamento de prueba',kind:'medication'},{id:second,name:'Unidad de prueba',kind:'unit'},{id:third,name:'Vía de prueba',kind:'route'}]}};
  if (url.endsWith('/mobile_issue_prescription')) { issued = true; return {body:{id:fourth}}; }
  if (url.endsWith('/close_consultation')) { closed = true; return {body:{id:third}}; }
}});
await doctor.login(); await doctor.click('Consultas'); await doctor.input('Paciente / turno',id,'change'); await doctor.click('Iniciar consulta');
for (const label of ['Motivo y síntomas','Exploración física','Evaluación clínica','Plan e indicaciones']) await doctor.input(label,'Dato de prueba: '+label);
await doctor.submit('Guardar consulta');
const save = doctor.calls.find(call => call.url.endsWith('/save_consultation'));
assert.equal(save.params.p_encounter,third); assert.equal(save.params.p_note,null);
assert.equal(save.params.p_expected_version,null); assert.equal(Object.keys(save.params.p_values).length,4);
versionConflict = true;
await doctor.input('Plan e indicaciones','Cambio local sin guardar'); await doctor.submit('Guardar consulta');
assert.match(doctor.get('notice').textContent,/registro cambió/);
const plan = doctor.app.all().find(node => node.attributes['aria-label'] === 'Plan e indicaciones'); assert.equal(plan.value,'Cambio local sin guardar');
versionConflict = false; await doctor.input('Plan e indicaciones',savedValues.plan);
console.log('OK Consulta: inicio, nota y conflicto de versión sin perder el borrador');

await doctor.click('Más'); await doctor.click('Recetas　›');
await doctor.input('Dosis','1'); await doctor.input('Paciente / turno','','change'); await doctor.input('Paciente / turno',id,'change');
assert.equal(doctor.app.all().find(node => node.attributes['aria-label'] === 'Dosis').value,'','Prescription fields must reset when selecting a patient');
await doctor.input('Medicamento',id,'change'); await doctor.input('Unidad de dosis',second,'change'); await doctor.input('Vía',third,'change');
await doctor.input('Dosis','0.5'); await doctor.input('Cada cuántas horas','8'); await doctor.input('Cantidad a dispensar','3'); await doctor.input('Observaciones','Solo prueba de interfaz');await doctor.input('Inicio','2026-10-30');await doctor.input('Durante (días)','10');
await doctor.submit('Añadir medicamento'); await doctor.click('Confirmar emisión');
const prescription = doctor.calls.find(call => call.url.endsWith('/mobile_issue_prescription'));
assert.equal(prescription.params.p_encounter,third); assert.equal(prescription.params.p_items.length,1);
assert.equal(prescription.params.p_items[0].dose,0.5); assert.equal(prescription.params.p_items[0].ends_on,'2026-11-08');assert.equal(prescription.params.p_items[0].starts_on,'2026-10-30');assert.equal(prescription.params.p_items[0].instructions,'Solo prueba de interfaz');assert.equal(Object.hasOwn(prescription.params.p_items[0],'days'),false);
assert.equal('id' in prescription.params.p_items[0],false); assert.equal('prescriber_id' in prescription.params,false);
assert.match(doctor.app.textContent,/Emitida/);
console.log('OK Receta: medicamento, dosis decimal, unidad, vía, cantidad y emisión vinculada');

await doctor.click('Consultas'); await doctor.click('Confirmar firma y cierre');
const closure = doctor.calls.find(call => call.url.endsWith('/close_consultation'));
assert.equal(closure.params.p_note_version,2); assert.equal(closure.params.p_expected_version,3);
assert.equal(doctor.app.all().some(node => node.tagName === 'button' && node.textContent === 'Guardar consulta'),false);
console.log('OK Cierre: firma con versiones y consulta cerrada no editable');

console.log('7 recorridos funcionales aprobados; sin escribir en Supabase.');
