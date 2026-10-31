// Agenda visual con transporte local: sin registros ni llamadas clínicas reales.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle = () => new Promise(resolve => setImmediate(resolve));
const key = date => [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
for (const mode of ['design','empty-session']) {
  const ui = createApp(['doctor']); await settle();
  if (mode === 'design') { ui.get('design-doctor').listeners.click(); await settle(); } else await ui.login();
  await ui.click('Consultas');
  assert.match(ui.app.textContent,/Tus consultas, a tiempo/);
  assert.equal(ui.app.textContent.includes('Mis citas'),false);
  assert.equal(ui.app.all().find(node => node.attributes['aria-label'] === 'Fecha de consultas').value,key(new Date()));
  if (mode === 'empty-session') {
    assert.match(ui.app.textContent,/0consultas para hoy/);
    assert.match(ui.app.textContent,/No hay consultas para mostrar/);
    assert.equal(ui.app.textContent.includes('Agenda de ejemplo'),false,'Sin agenda de ejemplo en sesión real vacía');
    assert.equal(ui.app.textContent.includes('Carlos Mendoza'),false);
    assert.equal(ui.app.all().some(node => node.tagName === 'button' && node.textContent === 'Iniciar consulta'),false);
    assert.equal(ui.calls.some(call => /start_consultation|save_consultation|doctor_chart/.test(call.url)),false);
    console.log('OK Consultas empty-session: sin ejemplos locales; agenda vacía explícita');
    continue;
  }
  assert.match(ui.app.textContent,/4consultas para hoy/);
  assert.match(ui.app.textContent,/Agenda de ejemplo/);
  assert.equal(ui.get('app').all().some(node => node.textContent === 'Iniciar consulta'),false);
  await ui.click('Ver detalle de Carlos Mendoza');
  assert.match(ui.app.textContent,/Detalle de consulta/);
  assert.match(ui.app.textContent,/42 años/); assert.match(ui.app.textContent,/7123-4567/);
  assert.match(ui.app.textContent,/Consulta de seguimiento/); assert.match(ui.app.textContent,/Tos, Fiebre/);
  assert.equal(ui.app.all().some(node => node.attributes['aria-label'] === 'Detalle de consulta de Carlos Mendoza'),true);
  assert.equal(ui.app.all().some(node => node.tagName === 'button' && node.textContent === 'Abrir atención'),false);
  await ui.click('Volver a consultas');
  assert.equal(ui.app.all().some(node => node.attributes['aria-label'] === 'Detalle de consulta de Carlos Mendoza'),false);
  await ui.click('Mañana');
  assert.match(ui.app.textContent,/2consultas para esta fecha/);
  assert.equal(ui.app.textContent.includes('Lucía García'),false);
  assert.equal(ui.app.textContent.includes('Consulta de demostración'),false);
  await ui.click('En 7 días'); assert.match(ui.app.textContent,/1consulta para esta fecha/); assert.match(ui.app.textContent,/Juan Pérez/);
  await ui.input('Fecha de consultas','2000-01-01','change'); assert.match(ui.app.textContent,/No hay consultas para mostrar/);
  await ui.click('Hoy');
  const search = ui.app.all().find(node => node.tagName === 'input' && node.type === 'search');
  await ui.input(search.attributes['aria-label'],'María');
  assert.match(ui.app.textContent,/María López/); assert.equal(ui.app.textContent.includes('Carlos Mendoza'),false);
  assert.equal(ui.calls.some(call => /start_consultation|save_consultation|doctor_chart/.test(call.url)),false,'Los ejemplos no llaman a escrituras ni expediente');
  assert.equal(ui.calls.some(call => call.url.startsWith('https:')),false);
  console.log('OK Consultas design: hoy, futuras, calendario, búsqueda, detalles y ejemplos sin operaciones clínicas');
}
const owner = '00000000-0000-4000-8000-000000000001';
const live = createApp(['doctor'],{transport:async (url,params) => {
  if (url.endsWith('/doctor_workspace')) {
    const start = new Date(params.p_from); start.setHours(9,0,0,0);
    const end = new Date(start.getTime()+30*60000);
    return {body:{doctor_name:'Doctor autorizado',facility_name:'Sede autorizada',appointments:[{id:owner,patient_id:owner,patient_name:'Paciente real simulado',record_number:'REAL-TEST',period:'["'+start.toISOString()+'","'+end.toISOString()+'")',status:'confirmed',encounter_id:null}],orders:[],tests:[],notifications:[],stats:{consultations:1}}};
  }
  if (url.endsWith('/doctor_chart')) return {body:{patient:{id:owner},history:[]}};
}});
await live.login(); await live.click('Consultas');
assert.equal(live.app.textContent.includes('Agenda de ejemplo'),false); assert.match(live.app.textContent,/Paciente real simulado/);
assert.equal(live.app.textContent.includes('Carlos Mendoza'),false);
await live.click('Mañana');
const query = live.calls.findLast(call => call.url.endsWith('/doctor_workspace')).params;
const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate()+1);
assert.equal(key(new Date(query.p_from)),key(tomorrow));
assert.equal(new Date(query.p_from).getHours(),0);
assert.equal((new Date(query.p_to)-new Date(query.p_from))/3600000,24);
const previousCharts = live.calls.filter(call => call.url.endsWith('/doctor_chart')).length;
await live.click('Ver detalle de Paciente real simulado');
assert.match(live.app.textContent,/No hay datos reales/);
const ticket = live.app.all().find(node => node.attributes['aria-label'] === 'Detalle de consulta de Paciente real simulado');
assert.ok(ticket);
for (const label of ['Paciente','Edad','Teléfono','Fecha y hora','Motivo de la consulta','Síntomas']) assert.ok(ticket.textContent.includes(label),label);
assert.equal(live.calls.filter(call => call.url.endsWith('/doctor_chart')).length,previousCharts,'Abrir ticket no carga ni altera la atención clínica');
await live.click('Abrir atención');
assert.equal(live.calls.findLast(call => call.url.endsWith('/doctor_chart')).params.p_patient,owner);
assert.equal(live.button('Iniciar consulta').disabled,true,'Una cita futura confirmada no permite iniciar atención');
console.log('OK Consultas reales simuladas: datos sin fixtures, filtro RPC por día, selección autorizada y validaciones conservadas');

// Campos opcionales: ceros válidos, texto vacío y ausencia de síntomas.
const populated = createApp(['doctor'],{transport:async (url) => {
  if (url.endsWith('/doctor_workspace')) return {body:{doctor_name:'Doctor de prueba',facility_name:'Sede',appointments:[{id:owner,patient_id:owner,patient_name:'Paciente con datos',record_number:'TEST',phone:'  ',age:0,reason:'Consulta con texto largo '.repeat(20),symptoms:[' ','Tos',''],period:'invalid',status:'cancelled',encounter_id:null}],orders:[],tests:[],notifications:[],stats:{consultations:0}}};
}});
await populated.login(); await populated.click('Consultas'); await populated.click('Ver detalle de Paciente con datos');
const detail = populated.app.all().find(node => node.attributes['aria-label'] === 'Detalle de consulta de Paciente con datos');
assert.match(detail.textContent,/0 años/); assert.match(detail.textContent,/No hay datos reales/); assert.match(detail.textContent,/Tos/); assert.match(detail.textContent,/Cancelada/);
assert.equal(detail.textContent.includes('Confirmada'),false,'El check decorativo no cambia el estado de la cita');
console.log('OK Ticket: campos completos, faltantes explícitos, estado original y apertura/cierre dentro del flujo');
