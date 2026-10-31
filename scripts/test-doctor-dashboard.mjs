// Dashboard del doctor con fixtures; ninguna conexión real ni escritura clínica.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle = () => new Promise(resolve => setImmediate(resolve));
const dateKey = date => [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
const demo = createApp(); await settle(); demo.get('design-doctor').listeners.click(); await settle();
assert.match(demo.app.textContent,/Hola, Dr. Luis Ramírez/);
assert.match(demo.app.textContent,/4Consultas programadas para hoy/);
assert.equal(demo.app.textContent.includes('Historial clínico'),false);
assert.equal(demo.app.textContent.includes('Mi horario'),false);
await demo.click('Pacientes');
assert.match(demo.app.textContent,/Tus pacientes, su evolución/);
await demo.input('DUI o nombre del paciente','Carlos');await demo.click('Seleccionar a Carlos Mendoza');
assert.match(demo.app.textContent,/Historial clínico de mis consultas/);assert.match(demo.app.textContent,/Consulta general/);
assert.equal(demo.app.textContent.includes('Consulta ajena'),false);
await demo.click('Volver');
assert.equal(demo.calls.some(call=>call.url.startsWith('https:')),false);
for (const [label,title] of [['Pacientes','Mis pacientes'],['Consultas','Consultas'],['Laboratorios','Laboratorio'],['Expedientes','Expedientes']]) {
  await demo.click('Inicio'); await demo.click(label);
  assert.ok(demo.app.all().some(node => node.tagName === 'h1' && node.textContent === title),label);
}
await demo.click('Inicio'); await demo.click('Más'); await demo.click(demo.app.all().find(node => node.tagName === 'button' && node.textContent.startsWith('Mi horario')).textContent); assert.match(demo.app.textContent,/Mi horario/);
demo.get('live-mode').listeners.click(); await settle(); demo.get('design-doctor').listeners.click(); await settle();
assert.equal(demo.app.textContent.includes('Consulta general'),false,'Salir descarta selección e historial');
console.log('OK Dashboard diseño: identidad, agenda, accesos, fechas, pacientes, horario y exclusión de otro médico; cero API');

const patient = '00000000-0000-4000-8000-000000000101';
let deny = false;
const live = createApp(['doctor'],{transport:async (url,params) => {
  if (url.endsWith('/doctor_workspace')) return {body:{doctor_name:'Dra. Ana Morales',facility_name:'Sede autorizada',appointments:[
    {id:'a',patient_id:patient,patient_name:'Paciente asignado',record_number:'REAL-1',period:'',status:'confirmed'},
    {id:'b',patient_id:patient,patient_name:'Paciente asignado',record_number:'REAL-1',period:'',status:'completed'},
    {id:'c',patient_id:patient,patient_name:'Paciente asignado',record_number:'REAL-1',period:'',status:'cancelled'}],orders:[],tests:[],notifications:[],stats:{consultations:99}}};
  if (url.endsWith('/doctor_chart')) return deny ? {status:403,body:{message:'Acceso denegado'}} : {body:{history:[{id:'own',started_at:new Date().toISOString(),subjective:'Consulta autorizada',plan:'Plan propio',status:'closed'}]}};
}});
await live.login();
assert.match(live.app.textContent,/Hola, Dra. Ana Morales/);
assert.match(live.app.textContent,/2Consultas programadas para hoy/);
assert.equal(live.app.textContent.includes('Dr. Luis Ramírez'),false,'No inyectar fixtures a la sesión real');
assert.equal(live.app.textContent.includes('Historial clínico'),false);
assert.equal(live.app.textContent.includes('Mi horario'),false);
assert.equal(live.calls.some(call => call.params?.p_resource === 'staff_shifts'),false,'Inicio no carga jornadas');
await live.click('Pacientes');
assert.match(live.app.textContent,/Historial clínico/);
await live.click('Paciente asignado'); assert.match(live.app.textContent,/Consulta autorizada/);
const request = live.calls.findLast(call => call.url.endsWith('/doctor_chart'));
assert.equal(request.params.p_patient,patient); assert.equal(request.params.p_from,null); assert.equal(request.params.p_to,null);
assert.equal(Object.hasOwn(request.params,'p_doctor'),false,'La identidad del médico se resuelve en servidor');
const liveDates = live.app.all().find(node => node.attributes['aria-label'] === 'Filtrar por fecha');
liveDates.checked = true; liveDates.listeners.change();
await live.input('Desde','2026-10-01'); await live.input('Hasta','2026-10-30'); await live.click('Buscar consultas');
const dated = live.calls.findLast(call => call.url.endsWith('/doctor_chart')).params;
assert.equal(new Date(dated.p_from).getDate(),1);
assert.equal(new Date(dated.p_to).getDate(),30);
assert.equal(new Date(dated.p_to).getHours(),23,'Hasta incluye el día completo');
assert.equal(new Date(dated.p_to).getMilliseconds(),999);
deny = true; await live.click('Buscar consultas');
assert.match(live.app.textContent,/No se pudo cargar el historial/);
assert.equal(live.app.textContent.includes('Consulta autorizada'),false,'Una denegación no conserva notas antiguas');
console.log('OK Dashboard sesión simulada: identidad real, conteo de citas, horario propio, RPC por paciente y error sin notas residuales');

await live.click('Inicio');
assert.equal(live.app.textContent.includes('Historial clínico'),false);
assert.equal(live.app.textContent.includes('Consulta autorizada'),false);
await live.click('Más'); await live.click(live.app.all().find(node => node.tagName === 'button' && node.textContent.startsWith('Mi horario')).textContent);
const shifts = live.calls.find(call => call.params?.p_resource === 'staff_shifts');
assert.equal(shifts.params.p_filters[0].column,'staff_id');
assert.equal(shifts.params.p_filters[0].value,'00000000-0000-4000-8000-000000000001');
console.log('OK Distribución: Inicio sin historial ni horario; historial en Pacientes; jornadas en Mi horario');
