// Simulated client transport; SQL isolation is tested separately with rollback.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const id='00000000-0000-4000-8000-000000000001';
let read=false,fail=false;
const doctor=createApp(['doctor'],{transport:async(url,p,request)=>{
 if(url.endsWith('/rpc/doctor_native_alerts'))return fail?{status:503,body:{}}:{body:{items:[{id,title:'Cita asignada',body:'Aviso autorizado',created_at:'2026-11-19T15:00:00Z',read_at:read?'2026-11-19T16:00:00Z':null,row_version:0}],unread:read?0:1,has_more:false,upcoming:[]}};
 if(url.includes('/notifications?')&&request.method==='PATCH'){assert.match(decodeURIComponent(url),/recipient_id=eq\./);read=true;return {body:null,status:204};}
}});
await doctor.login();
assert.equal((doctor.app.textContent.match(/Hola,/g)||[]).length,1,'Un solo saludo');
const quick=doctor.app.all().find(n=>n.className==='dash-grid');assert.ok(quick);assert.equal(quick.children.length,4);
assert.doesNotMatch(quick.textContent,/Consultas|Recetas/);
const before=doctor.calls.filter(c=>c.url.endsWith('/doctor_native_workspace')).length;
await doctor.click('Notificaciones');assert.match(doctor.app.textContent,/Panel general/);
assert.ok(doctor.app.all().some(n=>n.id==='doctor-notifications-panel'));
assert.match(doctor.app.textContent,/Notificaciones/);assert.match(doctor.app.textContent,/1 sin leer/);
await doctor.click('Marcar como leída');assert.equal(read,true);assert.match(doctor.app.textContent,/0 sin leer/);
assert.equal(doctor.calls.filter(c=>c.url.endsWith('/doctor_native_workspace')).length,before,'Leer avisos no recarga la consulta');
fail=true;await doctor.click('Actualizar avisos');assert.match(doctor.app.textContent,/No se pudieron actualizar/);
await doctor.click('Cerrar notificaciones');assert.equal(doctor.app.all().some(n=>n.id==='doctor-notifications-panel'),false);assert.match(doctor.app.textContent,/Panel general/);
await doctor.click('Más');await doctor.click('Cerrar sesión');assert.ok(doctor.get('password'));assert.doesNotMatch(doctor.app.textContent,/Aviso autorizado/);
const patient=createApp(['patient'],{transport:async(url,p)=>{
 if(url.endsWith('/rpc/my_consultation_history')){assert.equal('patient_id' in p,false);assert.equal('doctor_id' in p,false);return {body:[{id,started_at:'2026-11-19T15:00:00Z',ended_at:'2026-11-19T15:30:00Z',doctor_name:'Médico autor',specialty:'Medicina general',subjective:'Motivo guardado',objective:'Observaciones guardadas',assessment:'Diagnóstico guardado',plan:'Plan guardado',diagnoses:[{diagnosis_code:'TEST'}],vital_signs:[{weight_kg:'70.5',height_cm:'170',temperature_c:'38.2',recorded_at:'2026-11-19T15:20:00Z'}]}]};}
}});
await patient.login();await patient.click('Más');await patient.click('Historial médico　›');
assert.match(patient.app.textContent,/Médico autor/);assert.match(patient.app.textContent,/Diagnóstico guardado/,'La tarjeta muestra el diagnóstico');assert.doesNotMatch(patient.app.textContent,/Sin registrar/,'Sin campos vacíos');
const card=patient.app.all().find(n=>n.attributes['aria-label']?.startsWith('Ver consulta del '));assert.ok(card);await patient.click(card.attributes['aria-label']);
for(const text of ['Datos físicos','Evaluación médica','Motivo guardado','Síntomas actuales','Diagnóstico','Exploración y observaciones','Observaciones guardadas','Diagnóstico guardado','Plan de tratamiento','Plan guardado','Peso (kg)','70.5','Altura (cm)','170','Temperatura (°C)','38.2'])assert.ok(patient.app.textContent.includes(text),text);
console.log('OK Avisos propios: contador, lectura, error y cierre; paciente: consulta completada con autor, observaciones, diagnóstico y medidas');
