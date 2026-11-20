// Dashboard regression with simulated transport; never creates real accounts.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const id='00000000-0000-4000-8000-000000000001';
const future=new Date(Date.now()+86400000).toISOString();
const ending=new Date(Date.now()+90000000).toISOString();
const appointment={id,patient_id:id,starts_at:future,ends_at:ending,status:'confirmada',staff:{employee_code:'MED-42',profiles:{first_name:'Doctora Real',last_name:'Autorizada'}}};
const clinical=['appointments','appointment_requests','lab_orders','prescriptions','medical_history'];
for (const linked of [false,true]) {
  const ui=createApp(['patient'],{unregistered:!linked,transport:async url=>{
    if(url.includes('/profiles?'))return {body:[{id,first_name:'María Elena',last_name:'López Pérez'}]};
    if(url.includes('/appointments?')&&decodeURIComponent(url).includes('staff!'))return {body:[appointment]};
  }});
  await ui.login();
  assert.match(ui.app.textContent,/¡Hola, María López!/);
  if(linked) {assert.match(ui.app.textContent,/Doctora Real Autorizada/);assert.match(ui.app.textContent,/Pendiente/);}
  else {assert.match(ui.app.textContent,/No tienes citas programadas/);assert.match(ui.app.textContent,/Recepción debe crear o vincular/);}
  for(const label of ['Mis citas','Solicitar atención','Laboratorios','Recetas']) {
    const shortcut=ui.app.all().find(n=>n.tagName==='button'&&n.className==='dash-card'&&n.textContent.endsWith(label));
    assert.ok(shortcut,label);shortcut.listeners.click();await new Promise(r=>setImmediate(r));
    assert.equal(ui.app.all().some(n=>n.className==='dash-greeting'),false,'Navega fuera del Home');
    if(!linked) {
      assert.match(ui.app.textContent,label==='Solicitar atención'?/¿Qué síntomas presentas\?/:/Acércate a recepción/);
      assert.equal(ui.calls.some(c=>clinical.some(t=>c.url.includes('/rest/v1/'+t+'?'))),false,'Sin expediente no consulta tablas clínicas');
    }
    await ui.click('Inicio');
  }
  for(const call of ui.calls.filter(c=>clinical.some(t=>c.url.includes('/rest/v1/'+t+'?')))) {
    const path=decodeURIComponent(call.url);
    assert.ok(path.includes('patient_id=eq.'+id),'Cada lectura clínica filtra al paciente propio');
  }
  assert.equal(ui.calls.some(c=>c.url.includes('/rest/v1/')&&c.request.method!=='GET'&&!/\/rpc\/my_attention_(context|requests)$/.test(c.url)),false);
  await ui.click('Más');await ui.click('Cerrar sesión');
  assert.ok(ui.get('password'));assert.equal(ui.app.textContent.includes('Doctora Real'),false);
  console.log('OK Dashboard '+(linked?'vinculado':'sin expediente')+': nombre, tarjeta, cuatro accesos, filtros y cierre');
}
let fail=true;
const retry=createApp(['patient'],{transport:async url=>url.includes('/appointments?')&&decodeURIComponent(url).includes('staff!')?(fail?{status:503,body:{}}:{body:[appointment]}):undefined});
await retry.login();
assert.match(retry.app.textContent,/No se pudieron cargar tus citas/);
assert.equal(retry.app.textContent.includes('No tienes citas programadas'),false,'Un error no es un vacío');
fail=false;await retry.click('Reintentar');assert.match(retry.app.textContent,/Doctora Real Autorizada/);
console.log('OK Error de Home recuperable y sin datos obsoletos');

let registered=false;
const linking=createApp(['patient'],{unregistered:true,transport:async url=>{
  if(registered&&url.includes('/patients?'))return {body:[{id,profile_id:id}]};
  if(url.includes('/appointments?')&&decodeURIComponent(url).includes('staff!'))return {body:[appointment]};
}});
await linking.login();assert.match(linking.app.textContent,/No tienes citas programadas/);
registered=true;await linking.click('Inicio');assert.match(linking.app.textContent,/Doctora Real Autorizada/);
console.log('OK Vínculo creado por recepción se refleja al actualizar el Home');
