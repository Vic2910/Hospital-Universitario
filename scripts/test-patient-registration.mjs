// In-memory transport only: no production accounts or clinical data.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
async function fill(ui){
  const values={dui:'01234567-8',phone:'7000-1111',city:'Santa Ana',given:'Ana',family:'Prueba',birth:'1995-01-02',email:'ana@example.test',password:'test-password',confirm:'test-password'};
  for(const [key,value] of Object.entries(values))ui.get('reg-'+key).value=value;
}
function accountOnly(ui) {
  const writes=ui.calls.filter(c=>c.url.includes('/rest/v1/') && !['GET','HEAD'].includes(c.request?.method));
  assert.equal(writes.length,0,'Registro/login/actualización no escriben paciente, expediente ni cita');
  assert.equal(ui.app.all().some(n=>n.tagName==='button'&&n.textContent==='Completar registro'),false);
}
const ui=createApp(['patient'],{unregistered:true});await settle();await ui.click('Regístrate');await fill(ui);
await ui.submit('Registrarme',true);
assert.match(ui.app.textContent,/¡Hola, Ana Prueba!/);
assert.match(ui.app.textContent,/Recepción debe crear o vincular/);
const signup=ui.calls.filter(c=>c.url.endsWith('/signup'));
assert.equal(signup.length,1);
assert.deepEqual(signup[0].params.data,{first_name:'Ana',last_name:'Prueba',birth_date:'1995-01-02',phone:'7000-1111',city:'Santa Ana',dui:'01234567-8'});
assert.equal('role' in signup[0].params.data,false);
accountOnly(ui);
await ui.click('Inicio');accountOnly(ui);
await ui.click('Más');
await ui.click('Cerrar sesión');await ui.login();
assert.match(ui.app.textContent,/¡Hola, Ana Prueba!/);accountOnly(ui);
console.log('OK Registro sin confirmación simulada: cuenta y sesión, doble envío bloqueado, sin altas clínicas ni citas');

const resume=createApp(['patient'],{unregistered:true});await resume.login();
assert.match(resume.app.textContent,/¡Hola, Persona de!/);
assert.equal(resume.calls.some(c=>c.url.endsWith('/signup')),false);accountOnly(resume);
console.log('OK Cuenta sin expediente: login y actualizar estado sin formulario de alta clínica');

const confirmation=createApp(['patient'],{unregistered:true,transport:async url=>url.endsWith('/signup')?{body:{user:{id:'00000000-0000-4000-8000-000000000001'}}}:undefined});
await settle();await confirmation.click('Regístrate');await fill(confirmation);await confirmation.submit('Registrarme');
assert.match(confirmation.get('notice').textContent,/servidor todavía exige confirmar/);
assert.ok(confirmation.get('password'));accountOnly(confirmation);
console.log('OK Configuración remota pendiente: informa sin simular sesión ni crear expediente');

let unavailable=true;
const partial=createApp(['patient'],{unregistered:true,transport:async url=>url.includes('/profiles?')&&unavailable?{status:503,body:{}}:undefined});
await settle();await partial.click('Regístrate');await fill(partial);await partial.submit('Registrarme');
unavailable=false;await partial.click('Inicia sesión');await partial.login();
assert.match(partial.app.textContent,/¡Hola, Ana Prueba!/);
assert.equal(partial.calls.filter(c=>c.url.endsWith('/signup')).length,1);accountOnly(partial);
console.log('OK Fallo de lectura tras signup: recupera por login sin duplicar cuenta');

const invalid=createApp(['patient'],{unregistered:true});await settle();await invalid.click('Regístrate');await fill(invalid);invalid.get('reg-dui').value='123';await invalid.submit('Registrarme');
assert.equal(invalid.calls.some(c=>c.url.endsWith('/signup')),false);
console.log('OK Validación antes de Auth');

const linked=createApp(['patient']);await linked.login();await linked.click('Salud');
await linked.input('Especialidad','1','change');
await linked.input('Motivo de la consulta','Consulta de seguimiento');
await linked.input('Preferencia','manana','change');
await linked.submit('Enviar solicitud');
const request=linked.calls.find(c=>c.url.includes('/rest/v1/appointment_requests')&&c.request?.method==='POST');
assert.ok(request);assert.equal(request.params.specialty_id,'1');assert.equal(request.params.preferred_period,'manana');
assert.equal(linked.calls.some(c=>c.url.includes('/rpc/schedule_appointment')),false);
console.log('OK Paciente vinculado conserva solicitudes; recepción programa la cita');
