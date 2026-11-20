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
  await ui.click('Fiebre');await ui.click('Medicina general');
  await ui.click('Indiferente');await ui.input('Motivo de solicitud','Atención de seguimiento');
  await ui.submit('Solicitar atención',true);
  assert.match(ui.app.textContent,/Solicitud enviada a recepción/);assert.match(ui.app.textContent,/Pendiente/);
  const calls=ui.calls.filter(c=>c.url.endsWith('/rpc/submit_my_attention_request'));
  assert.equal(calls.length,1);assert.equal(calls[0].params.p_period,'indiferente');
  assert.deepEqual(calls[0].params.p_symptoms,[1]);assert.deepEqual(calls[0].params.p_missing,{});
  assert.equal('user_id' in calls[0].params,false);assert.equal('patient_id' in calls[0].params,false);
  assert.equal(ui.calls.some(c=>c.url.includes('/register_patient')||c.url.includes('/schedule_appointment')),false);
  // Una sola solicitud activa: con la pendiente no se muestra el formulario ni se puede enviar otra.
  await ui.click('Inicio');await ui.click('Salud');assert.match(ui.app.textContent,/Tu solicitud está en revisión/);assert.match(ui.app.textContent,/recepción la está revisando/);
  assert.equal(ui.app.textContent.includes('¿Qué síntomas presentas?'),false,'Sin formulario mientras la solicitud está pendiente');
  assert.equal(ui.calls.filter(c=>c.url.endsWith('/rpc/submit_my_attention_request')).length,1);
  // Recepción la rechaza: se puede enviar una nueva.
  rows=rows.map(r=>({...r,status:'rechazada'}));await ui.click('Actualizar');assert.match(ui.app.textContent,/Tus datos/);
  await ui.click('Otro');await ui.click('Medicina general');await ui.input('Motivo de solicitud','Otro motivo');
  await ui.submit('Solicitar atención');assert.match(ui.app.textContent,/Describe el otro síntoma/);
  await ui.input('Describe el otro síntoma','Descripción declarada');await ui.submit('Solicitar atención');
  assert.equal(ui.calls.filter(c=>c.url.endsWith('/rpc/submit_my_attention_request')).length,2);
  // Solo la solicitud reciente a la vista; las anteriores quedan aparte (no se borran).
  rows=[{...rows[0],id:'00000000-0000-4000-8000-0000000000a1',created_at:new Date().toISOString(),reason:'Solicitud reciente',status:'pendiente'},{...rows[0],id:'00000000-0000-4000-8000-0000000000a2',created_at:'2026-11-01T15:00:00Z',reason:'Solicitud antigua',status:'rechazada'}];
  await ui.click('Actualizar');assert.match(ui.app.textContent,/Tu solicitud reciente/);assert.match(ui.app.textContent,/Ver solicitudes anteriores \(1\)/);
  assert.ok(ui.app.textContent.indexOf('Solicitud reciente')<ui.app.textContent.indexOf('Ver solicitudes anteriores'),'La reciente primero; las anteriores en su sección');
  console.log('OK Rutas Home/Salud '+(linked?'con':'sin')+' expediente: formulario, datos, síntomas, envío único, bloqueo con solicitud pendiente y nueva solicitud tras rechazo');
}
// Cita programada vigente: aviso y sin formulario.
const future=new Date(Date.now()+86400000).toISOString(),futureEnd=new Date(Date.now()+86400000+1800000).toISOString();
const booked=createApp(['patient'],{transport:async url=>url.includes('/rest/v1/appointments?')&&url.includes('employee_code')?{body:[{id:'00000000-0000-4000-8000-000000000071',patient_id:decodeURIComponent(/patient_id=eq\.([^&]+)/.exec(url)?.[1]||''),starts_at:future,ends_at:futureEnd,status:'programada',staff:{employee_code:'MED-1',profiles:null}}]}:undefined});
await booked.login();await booked.click('Salud');assert.match(booked.app.textContent,/Ya tienes una cita programada/);
assert.equal(booked.app.textContent.includes('¿Qué síntomas presentas?'),false);
console.log('OK Con una cita programada no se puede enviar otra solicitud');
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
