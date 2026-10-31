import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const ui=createApp(['patient']);await settle();ui.get('design-patient').listeners.click();await settle();await ui.click('Mis citas');
assert.match(ui.app.textContent,/Próxima cita/);await ui.click('Ver detalle de la cita');
for(const label of ['Paciente','Edad','Teléfono','Motivo de la consulta','Síntomas','Especialidad','Médico','Consultorio','DUI','Correo'])assert.ok(ui.app.textContent.includes(label),label);
assert.equal(ui.app.textContent.includes('Abrir atención'),false);await ui.click('Volver a Mis citas');
await ui.click('Solicitar atención');assert.equal(ui.app.textContent.includes('Enviar solicitud'),false);
const choice=async value=>{ui.app.all().find(node=>node.attributes['data-choice']===value).listeners.click();await settle();};
await ui.input('Motivo de consulta','Solicitud nueva para recepción');await choice('specialty-0');await choice('slot-0');assert.equal(ui.get('sched-submit').disabled,true);
await ui.input('Preferencia de horario','Tarde','change');assert.equal(ui.get('sched-submit').disabled,false);
const submit=ui.get('sched-submit');submit.listeners.click();submit.listeners.click();await settle();assert.match(ui.get('sched-feedback').textContent,/Pendiente/);
await ui.click('Mis citas');assert.equal(ui.app.all().filter(node=>node.tagName==='p'&&node.textContent==='Solicitud nueva para recepción').length,1);
ui.get('design-reception').listeners.click();await settle();assert.match(ui.app.textContent,/Preferencia: Tarde/);
const previous=ui.app.textContent;await ui.input('Fecha y hora a asignar','2000-01-01T09:00');await ui.click('Asignar cita de ejemplo');assert.match(ui.app.textContent,/Elige una fecha y hora futura/);
const day=new Date();day.setDate(day.getDate()+1);day.setHours(8,0,0,0);const pad=n=>String(n).padStart(2,'0');
await ui.input('Fecha y hora a asignar',day.getFullYear()+'-'+pad(day.getMonth()+1)+'-'+pad(day.getDate())+'T08:00');await ui.click('Asignar cita de ejemplo');assert.equal(ui.button('Asignar cita de ejemplo').disabled,true);
await ui.click('Volver al portal del paciente');await ui.click('Ver detalle de la cita');assert.match(ui.app.textContent,/Solicitud nueva para recepción/);
assert.equal(ui.calls.some(call=>/\/rpc\//.test(call.url)),false,'Flujo local no consulta ni modifica Supabase');
console.log('OK Próxima cita/ticket, formulario único, preferencia obligatoria, Pendiente, recepción local, fecha futura y doble envío');

const actual=createApp(['patient'],{transport:async(url,params)=>{
 if(url.endsWith('/mobile_module')&&params.p_module==='appointments')return{body:{items:[{id:'00000000-0000-4000-8000-000000000051',title:'Especialidad autorizada',subtitle:'Consulta autorizada',status:'confirmed',event_at:new Date(Date.now()+86400000).toISOString(),row_version:1,details:[{label:'Medico',value:'Doctor autorizado'},{label:'Consultorio',value:'Consultorio autorizado'}],action:null,document_id:null}],sections:[],options:[],preferences:[],phone:null,emergency:null,has_more:false,next_cursor:null}};
}});
await actual.login();await actual.click('Mis citas');await actual.click('Ver detalle de la cita');assert.match(actual.app.textContent,/Persona de prueba/);assert.match(actual.app.textContent,/Doctor autorizado/);assert.match(actual.app.textContent,/No hay datos reales/);assert.equal(actual.app.textContent.includes('Gaby'),false);assert.equal(actual.app.textContent.includes('29 años'),false);
const failed=createApp(['patient'],{transport:async(url,params)=>{if(url.endsWith('/mobile_module')&&params.p_module==='appointments')return{status:500,body:{message:'Error de prueba'}};}});
await failed.login();await failed.click('Mis citas');assert.equal(failed.app.textContent.includes('Cita de ejemplo'),false);assert.equal(failed.app.textContent.includes('Ver detalle de la cita'),false);
console.log('OK Próxima cita autorizada sin mezclar fixtures; faltantes explícitos; error de carga sin inventar cita');
