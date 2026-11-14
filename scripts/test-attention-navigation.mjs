import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(r=>setImmediate(r));
for(const linked of [false,true]){
  let rows=[];
  const ui=createApp(['patient'],{unregistered:!linked,transport:async(url,params)=>{
    if(url.endsWith('/rpc/my_attention_requests'))return {body:rows};
    if(url.endsWith('/rpc/submit_my_attention_request')){
      rows=[{id:params.p_key,status:'pendiente',reason:params.p_reason,specialty_name:'Medicina general',preferred_period:params.p_period,symptoms:['Fiebre'],appointment_id:null}];
      return {body:params.p_key};
    }
  }});
  await ui.login();await ui.click('Solicitar atención');
  assert.match(ui.app.textContent,/Tus datos/);assert.match(ui.app.textContent,/¿Qué síntomas presentas\?/);
  assert.match(ui.app.textContent,/persona@example.test/);
  assert.equal(ui.app.textContent.includes('Solicita atención en recepción'),false);
  assert.equal(ui.app.textContent.includes('Información del hospital'),false);
  await ui.click('Fiebre');await ui.input('Especialidad','1','change');
  await ui.input('Preferencia','indiferente','change');await ui.input('Motivo de solicitud','Atención de seguimiento');
  await ui.submit('Solicitar atención',true);
  assert.match(ui.app.textContent,/Solicitud enviada a recepción/);assert.match(ui.app.textContent,/Pendiente/);
  const calls=ui.calls.filter(c=>c.url.endsWith('/rpc/submit_my_attention_request'));
  assert.equal(calls.length,1);assert.equal(calls[0].params.p_period,'indiferente');
  assert.deepEqual(calls[0].params.p_symptoms,[1]);assert.deepEqual(calls[0].params.p_missing,{});
  assert.equal('user_id' in calls[0].params,false);assert.equal('patient_id' in calls[0].params,false);
  assert.equal(ui.calls.some(c=>c.url.includes('/register_patient')||c.url.includes('/schedule_appointment')),false);
  await ui.click('Inicio');await ui.click('Salud');assert.match(ui.app.textContent,/Tus datos/);
  await ui.click('Otro');await ui.input('Especialidad','1','change');await ui.input('Motivo de solicitud','Otro motivo');
  await ui.submit('Solicitar atención');assert.match(ui.app.textContent,/Describe el otro síntoma/);
  await ui.input('Describe el otro síntoma','Descripción declarada');await ui.submit('Solicitar atención');
  assert.equal(ui.calls.filter(c=>c.url.endsWith('/rpc/submit_my_attention_request')).length,2);
  console.log('OK Rutas Home/Salud '+(linked?'con':'sin')+' expediente: formulario, datos, síntomas, envío único y seguimiento');
}
const empty=createApp(['patient'],{unregistered:true,transport:async url=>url.endsWith('/rpc/my_attention_context')?{body:{person:{first_name:'Ana',last_name:'Prueba',dui:'01234567-8',phone:'7999-0000',birth_date:'1990-01-01',email:'ana@example.test'},symptoms:[],specialties:[]}}:undefined});
await empty.login();await empty.click('Salud');
assert.match(empty.app.textContent,/Tus datos/);assert.match(empty.app.textContent,/Motivo de solicitud/);
assert.match(empty.app.textContent,/No hay síntomas activos/);assert.match(empty.app.textContent,/No hay especialidades/);
assert.equal(empty.button('Solicitar atención').disabled,true);
console.log('OK Catálogos vacíos mantienen el formulario, sin aviso antiguo ni envío habilitado');

let failure=true;
const retry=createApp(['patient'],{unregistered:true,transport:async url=>url.endsWith('/rpc/my_attention_requests')&&failure?{status:503,body:{}}:undefined});
await retry.login();await retry.click('Salud');assert.match(retry.app.textContent,/Tus datos/);
assert.match(retry.app.textContent,/No se pudo actualizar/);
failure=false;await retry.click('Actualizar');assert.match(retry.app.textContent,/Tus datos/);
assert.equal(retry.app.textContent.includes('No se pudo actualizar'),false);
await retry.click('Más');await retry.click('Cerrar sesión');await settle();assert.ok(retry.get('password'));
console.log('OK Fallo de seguimiento no sustituye formulario; reintento y cierre');
