// Portal del paciente con transporte simulado: citas con detalles a la vista y campana de avisos propios.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const hour=3600000,iso=offset=>new Date(Date.now()+offset).toISOString();
const appointments=[
  {id:'00000000-0000-4000-8000-000000000081',starts_at:iso(48*hour),ends_at:iso(48*hour+1800000),status:'programada',consulting_rooms:{code:'C-3'},staff:{employee_code:'MED-1',profiles:null},appointment_requests:{reason:'Dolor de garganta',specialties:{name:'Medicina general'}}},
  {id:'00000000-0000-4000-8000-000000000082',starts_at:iso(96*hour),ends_at:iso(96*hour+1800000),status:'confirmada',consulting_rooms:{code:'C-4'},staff:{employee_code:'MED-2',profiles:null},appointment_requests:null},
  {id:'00000000-0000-4000-8000-000000000083',starts_at:iso(-240*hour),ends_at:iso(-240*hour+1800000),status:'completada',consulting_rooms:{code:'C-1'},staff:{employee_code:'MED-1',profiles:null},appointment_requests:{reason:'Control anterior',specialties:{name:'Cardiología'}}},
  {id:'00000000-0000-4000-8000-000000000084',starts_at:iso(-120*hour),ends_at:iso(-120*hour+1800000),status:'cancelada',cancellation_reason:'Viaje imprevisto',consulting_rooms:null,staff:{employee_code:'MED-3',profiles:null},appointment_requests:null},
  {id:'00000000-0000-4000-8000-000000000085',starts_at:iso(-72*hour),ends_at:iso(-72*hour+1800000),status:'no_asistio',consulting_rooms:{code:'C-2'},staff:{employee_code:'MED-4',profiles:null},appointment_requests:null},
  {id:'00000000-0000-4000-8000-000000000086',starts_at:iso(-5*hour),ends_at:iso(-5*hour+1800000),status:'programada',consulting_rooms:{code:'C-9'},staff:{employee_code:'MED-5',profiles:null},appointment_requests:null}];
let notices=[{id:'00000000-0000-4000-8000-000000000091',recipient_id:'x',title:'Tienes una cita programada',body:'Tu cita es pasado mañana. Revisa los detalles en Mis citas.',kind:'cita',created_at:iso(-hour),read_at:null},
  {id:'00000000-0000-4000-8000-000000000092',recipient_id:'x',title:'Resultados de laboratorio disponibles',body:'Ya puedes consultar los resultados autorizados en Laboratorios.',kind:'laboratorio',created_at:iso(-2*hour),read_at:iso(-hour)}];
const ui=createApp(['patient'],{transport:async(url,params,request)=>{
  if(url.includes('/rest/v1/appointments?')&&url.includes('appointment_requests')){const patient=decodeURIComponent(/patient_id=eq\.([^&]+)/.exec(url)?.[1]||'');return {body:appointments.map((a,i)=>({...a,patient_id:patient,queue_number:24+i,queue_date:a.starts_at.slice(0,10)}))};}
  if(url.includes('/rest/v1/notifications?')&&(request?.method||'GET')==='GET')return {body:notices};
  // lab_results.order_id es UNIQUE: PostgREST devuelve el resultado como OBJETO (relación uno a uno), como en producción.
  if(url.includes('/rest/v1/lab_orders?'))return {body:[{id:'00000000-0000-4000-8000-0000000000b1',encounter_id:'e1',status:'completado',reason:'Control anual',ordered_at:iso(-48*hour),lab_test_types:{name:'Hemograma completo'},
    lab_results:{summary:'Hemoglobina dentro de rango',published_to_patient_at:iso(-hour),published_at:iso(-hour),validated_at:iso(-2*hour),validated_by:'v',parameter_schema:[{key:'hb',label:'Hemoglobina',unit:'g/dL',reference:'12–16'}],result_values:{hb:{value:13.8}}}},
    {id:'00000000-0000-4000-8000-0000000000b2',encounter_id:'e1',status:'pendiente',reason:'Glucosa',ordered_at:iso(-24*hour),lab_test_types:{name:'Glucosa en ayunas'},lab_results:null}]};
  if(url.includes('/rest/v1/notifications?')&&request?.method==='PATCH'){notices=notices.map(n=>({...n,read_at:n.read_at||new Date().toISOString()}));return {body:[notices[0]]};}
}});
await ui.login();
const bell=ui.app.all().find(n=>n.attributes['aria-label']==='Notificaciones');assert.ok(bell);assert.match(bell.textContent,/1/,'Contador de avisos sin leer');
await ui.click('Mis citas');
const text=()=>ui.app.textContent;
// Mis citas: solo las citas activas (próxima y siguientes). Las finalizadas, canceladas, no atendidas o vencidas no aparecen.
for(const value of ['PRÓXIMA CITA','Medicina general','Dolor de garganta','C-3','Médico · MED-1','Siguientes citas','C-4','Cancelar cita','Tienes 2 citas programadas'])assert.ok(text().includes(value),'Visible sin abrir otra pantalla: '+value);
for(const value of ['Historial de citas','Cardiología','Viaje imprevisto','C-1','C-2','C-9','Atendida','No atendida','Cancelada'])assert.equal(text().includes(value),false,'Mis citas no muestra citas anteriores: '+value);
assert.equal(text().includes('Cita asignada'),false,'Ya no hay que pulsar para ver el detalle');assert.equal(text().includes('No hay datos reales'),false);
for(const old of ['Programada','Finalizada'])assert.equal(text().includes(old),false,'Sin etiqueta antigua: '+old);
assert.ok(text().indexOf('Dolor de garganta')<text().indexOf('C-4'),'Próxima primero');
await ui.click('Notificaciones');assert.match(text(),/Mis avisos/);assert.match(text(),/1 sin leer/);assert.match(text(),/Tienes una cita programada/);assert.match(text(),/Resultados de laboratorio disponibles/);
await ui.click('Marcar como leída');assert.equal(ui.calls.some(c=>c.url.includes('/rest/v1/notifications?')&&c.request?.method==='PATCH'),true);
assert.match(text(),/Estás al día/);
// Mi turno (pantalla original): el número de cada cita activa dentro de su tarjeta, leído de queue_number (24 + índice).
await ui.click('Más');await ui.click('Mi turno　›');
for(const value of ['Turno de atención','Tu número','024','025','Información de la cita','C-3','C-4','Medicina general','Médico · MED-1','Pendiente'])assert.ok(text().includes(value),'Turno: '+value);
assert.ok(text().indexOf('024')<text().indexOf('025'),'Cita más próxima primero');
// Turnos anteriores: conservan su número y su estado; la vencida sin atender ya no es activa.
const historyAt=text().indexOf('Turnos anteriores');assert.ok(historyAt>text().indexOf('025'),'Historial después de los activos');
const history=text().slice(historyAt);
for(const value of ['026','Atendida','027','Cancelada','028','No atendida','029'])assert.ok(history.includes(value),'Turnos anteriores: '+value);
assert.equal(text().slice(0,historyAt).includes('029'),false,'La cita vencida (fin ya pasado) no aparece como turno activo');
assert.equal(ui.calls.some(c=>/queue_number=|rpc\/assign/.test(c.url)&&c.request?.method&&c.request.method!=='GET'),false,'El cliente nunca escribe ni calcula el turno');
assert.equal(text().includes('fila numerada'),false);
// Laboratorios: un resultado publicado (objeto incrustado) y una orden pendiente (null) cargan sin error.
await ui.click('Inicio');await ui.click('Laboratorios');
assert.equal(text().includes('is not a function'),false,'Sin error de normalización');assert.equal(text().includes('No pudimos cargar'),false);
for(const value of ['Hemograma completo','Glucosa en ayunas'])assert.ok(text().includes(value),'Laboratorio: '+value);
assert.equal(text().includes('Atendida'),false,'Una orden de laboratorio completada no usa la etiqueta de citas');
// Solicitud enviada y sin cita activa: Mis citas muestra solo esa solicitud y el formulario queda bloqueado.
const pastOnly=appointments.slice(2);
const pending=createApp(['patient'],{transport:async(url)=>{
  if(url.includes('/rest/v1/appointments?')){const patient=decodeURIComponent(/patient_id=eq\.([^&]+)/.exec(url)?.[1]||'');return {body:pastOnly.map((a,i)=>({...a,patient_id:patient,queue_number:30+i,queue_date:a.starts_at.slice(0,10)}))};}
  if(url.endsWith('/rpc/my_attention_requests'))return {body:[{id:'00000000-0000-4000-8000-0000000000c1',created_at:iso(-3*hour),status:'pendiente',specialty_name:'Dermatología',reason:'Manchas en la piel',preferred_period:'manana',symptoms:['Picazón'],other_symptoms:null,appointment_id:null}]};
}});
await pending.login();await pending.click('Mis citas');
for(const value of ['Tu solicitud está en revisión','SOLICITUD DE ATENCIÓN','Dermatología','Manchas en la piel','Picazón','Mañana'])assert.ok(pending.app.textContent.includes(value),'Mis citas con solicitud: '+value);
for(const value of ['Cardiología','Viaje imprevisto','Historial de citas'])assert.equal(pending.app.textContent.includes(value),false,'Sin citas anteriores: '+value);
await pending.click('Salud');assert.match(pending.app.textContent,/Tu solicitud está en revisión/);
assert.equal(pending.app.all().some(n=>n.tagName==='form'&&!n.hidden&&n.className==='attention-form'),false,'No se puede enviar otra solicitud');
console.log('OK Portal del paciente: Mis citas solo con citas activas o la solicitud enviada; Mi turno con el número dentro de cada cita activa (leído de queue_number), Turnos anteriores con su estado, cita vencida fuera de las activas; campana y laboratorios');
