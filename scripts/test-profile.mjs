import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const openProfile=async ui=>{await ui.click('Más');await ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('perfil')).textContent);};
for(const role of ['doctor','patient']) {
  const ui=createApp([role],{transport:async url=>url.endsWith('/my_profile')?{body:{person:{given_names:'Persona',family_names:'de prueba'},auth_email:'persona@example.test',contacts:[{kind:'phone',value:'7123-0000'}],professional:null}}:undefined});await ui.login();await openProfile(ui);
  if(role==='doctor'){
    const fields=ui.app.all().filter(node=>node.className==='sched-card identity-field');assert.equal(fields.length,2);assert.equal(fields[0].textContent,'NombrePersona');assert.equal(fields[1].textContent,'Apellidode prueba');
    assert.equal(ui.app.textContent.includes('Correo electrónico'),false);
  }else{
    const fields=ui.app.all().filter(node=>node.className==='profile-contact-row');assert.equal(fields.length,3);assert.match(fields[0].textContent,/Nombre completoPersona de prueba/);assert.match(fields[1].textContent,/persona@example.test/);assert.match(fields[2].textContent,/7123-0000/);assert.equal(ui.app.textContent.includes('maria.lopez@ejemplo.test'),false);
  }
  assert.ok(ui.app.all().find(node=>node.tagName==='input'&&node.attributes['aria-label']==='Teléfono'));
  assert.match(ui.app.textContent,/Actualizar contraseña/);
  if(role==='patient') assert.match(ui.app.textContent,/Contacto de emergencia/);
  assert.equal(ui.calls.some(call=>call.url.endsWith('/mobile_module')&&call.params?.p_module==='profile'),true);
  const design=createApp();await settle();design.get('design-'+role).listeners.click();await settle();await openProfile(design);
  if(role==='patient'){assert.match(design.app.textContent,/Perfil de ejemplo/);assert.match(design.app.textContent,/maria.lopez@ejemplo.test/);assert.equal(design.app.all().filter(node=>node.className==='profile-contact-row').length,3);}
}
const missing=createApp(['patient'],{transport:async url=>url.endsWith('/my_profile')?{body:{person:{given_names:' ',family_names:null},auth_email:null,contacts:[]}}:undefined});await missing.login();await missing.click('Perfil');assert.equal(missing.app.all().filter(node=>node.className==='profile-contact-row').every(node=>node.textContent.endsWith('No disponible')),true);
console.log('OK Perfil Paciente: datos registrados, teléfono, correo, ejemplos aislados y faltantes; Perfil Doctor conservado');
const info=createApp();await settle();info.get('design-patient').listeners.click();await settle();await info.click('Más');await info.click(info.app.all().find(node=>node.tagName==='button'&&node.textContent.startsWith('Información general')).textContent);
for(const text of ['Santa Ana','Metapán','Especialidades','Catálogo de demostración','+503 2484-0668','WhatsApp institucional'])assert.ok(info.app.textContent.includes(text),text);
const anchors=info.app.all().filter(node=>node.tagName==='a');assert.ok(anchors.some(node=>node.href==='tel:+50324840668'));assert.ok(anchors.some(node=>node.href==='https://wa.me/50377423033'));assert.ok(anchors.some(node=>node.href.includes('maps/search/?api=1')));assert.ok(anchors.some(node=>node.href==='https://catolica.edu.sv/contactos-facultades-y-unidades-unidaes/'));assert.equal(info.app.all().filter(node=>node.className==='hospital-specialty').length,6);await info.click('Solicitar atención');assert.ok(info.get('sched-submit'));
console.log('OK Información general: dirección, contactos oficiales enlazados, seis especialidades demo y acceso a Salud');
