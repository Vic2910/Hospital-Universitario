// Portal del paciente con transporte simulado: citas con detalles a la vista y campana de avisos propios.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const hour=3600000,iso=offset=>new Date(Date.now()+offset).toISOString();
const appointments=[
  {id:'00000000-0000-4000-8000-000000000081',starts_at:iso(48*hour),ends_at:iso(48*hour+1800000),status:'programada',consulting_rooms:{code:'C-3'},staff:{employee_code:'MED-1',profiles:null},appointment_requests:{reason:'Dolor de garganta',specialties:{name:'Medicina general'}}},
  {id:'00000000-0000-4000-8000-000000000082',starts_at:iso(96*hour),ends_at:iso(96*hour+1800000),status:'confirmada',consulting_rooms:{code:'C-4'},staff:{employee_code:'MED-2',profiles:null},appointment_requests:null},
  {id:'00000000-0000-4000-8000-000000000083',starts_at:iso(-240*hour),ends_at:iso(-240*hour+1800000),status:'completada',consulting_rooms:{code:'C-1'},staff:{employee_code:'MED-1',profiles:null},appointment_requests:{reason:'Control anterior',specialties:{name:'Cardiología'}}},
  {id:'00000000-0000-4000-8000-000000000084',starts_at:iso(-120*hour),ends_at:iso(-120*hour+1800000),status:'cancelada',cancellation_reason:'Viaje imprevisto',consulting_rooms:null,staff:{employee_code:'MED-3',profiles:null},appointment_requests:null}];
let notices=[{id:'00000000-0000-4000-8000-000000000091',recipient_id:'x',title:'Tienes una cita programada',body:'Tu cita es pasado mañana. Revisa los detalles en Mis citas.',kind:'cita',created_at:iso(-hour),read_at:null},
  {id:'00000000-0000-4000-8000-000000000092',recipient_id:'x',title:'Resultados de laboratorio disponibles',body:'Ya puedes consultar los resultados autorizados en Laboratorios.',kind:'laboratorio',created_at:iso(-2*hour),read_at:iso(-hour)}];
const ui=createApp(['patient'],{transport:async(url,params,request)=>{
  if(url.includes('/rest/v1/appointments?')&&url.includes('appointment_requests'))return {body:appointments};
  if(url.includes('/rest/v1/notifications?')&&(request?.method||'GET')==='GET')return {body:notices};
  if(url.includes('/rest/v1/notifications?')&&request?.method==='PATCH'){notices=notices.map(n=>({...n,read_at:n.read_at||new Date().toISOString()}));return {body:[notices[0]]};}
}});
await ui.login();
const bell=ui.app.all().find(n=>n.attributes['aria-label']==='Notificaciones');assert.ok(bell);assert.match(bell.textContent,/1/,'Contador de avisos sin leer');
await ui.click('Mis citas');
const text=()=>ui.app.textContent;
for(const value of ['PRÓXIMA CITA','Medicina general','Dolor de garganta','C-3','Médico · MED-1','Siguientes citas','C-4','Historial de citas','Cardiología','Viaje imprevisto','Cancelar cita'])assert.ok(text().includes(value),'Visible sin abrir otra pantalla: '+value);
assert.equal(text().includes('Cita asignada'),false,'Ya no hay que pulsar para ver el detalle');assert.equal(text().includes('No hay datos reales'),false);
assert.ok(text().indexOf('Dolor de garganta')<text().indexOf('C-4'),'Próxima primero');assert.ok(text().indexOf('Viaje imprevisto')<text().indexOf('Cardiología'),'Historial más reciente primero');
await ui.click('Notificaciones');assert.match(text(),/Mis avisos/);assert.match(text(),/1 sin leer/);assert.match(text(),/Tienes una cita programada/);assert.match(text(),/Resultados de laboratorio disponibles/);
await ui.click('Marcar como leída');assert.equal(ui.calls.some(c=>c.url.includes('/rest/v1/notifications?')&&c.request?.method==='PATCH'),true);
assert.match(text(),/Estás al día/);
console.log('OK Portal del paciente: citas con todos los detalles a la vista (próxima, siguientes e historial) y campana con avisos propios');
