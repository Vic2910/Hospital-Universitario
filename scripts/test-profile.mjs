import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
for(const role of ['doctor','patient']) {
  const ui=createApp([role]);await ui.login();await ui.click('Más');
  await ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('perfil')).textContent);
  const fields=ui.app.all().filter(node=>node.className==='sched-card identity-field');
  assert.equal(fields.length,2);assert.equal(fields[0].textContent,'NombrePersona');assert.equal(fields[1].textContent,'Apellidode prueba');
  assert.equal(ui.app.textContent.includes('Persona de pruebaNombre'),false,'No sustituir el nombre de registro por el preferido');
  assert.equal(ui.app.all().some(node=>['form','input','textarea','select'].includes(node.tagName)),false);
  for(const text of ['Correo','Teléfono','Cambiar contraseña','Especialidad','Notificaciones recientes'])assert.equal(ui.app.textContent.includes(text),false);
  assert.equal(ui.calls.some(call=>call.url.endsWith('/mobile_module')&&call.params?.p_module==='profile'),false);
  console.log('OK Perfil '+role+': solo nombre y apellido registrados, sin formularios ni lectura de ajustes');
  const design=createApp();await settle();design.get('design-'+role).listeners.click();await settle();await design.click('Más');
  await design.click(design.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('perfil')).textContent);
  const sample=design.app.all().filter(node=>node.className==='sched-card identity-field');assert.equal(sample.length,2);assert.equal(sample[0].textContent,role==='doctor'?'NombreLuis':'NombreMaría');
}
const missing=createApp(['patient'],{transport:async url=>url.endsWith('/my_profile')?{body:{person:{given_names:' ',family_names:null}}}:undefined});await missing.login();await missing.click('Perfil');
assert.equal(missing.app.all().filter(node=>node.className==='sched-card identity-field').every(node=>node.textContent.endsWith('No disponible')),true);
console.log('OK Perfil: faltantes explícitos, sin inventar datos de registro');
