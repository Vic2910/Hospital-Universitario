// Búsqueda y ficha visual de Pacientes del Doctor, sin datos clínicos remotos.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const key=date=>[date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
for(const mode of ['design','session']){
  const ui=createApp(['doctor']);await settle();if(mode==='design'){ui.get('design-doctor').listeners.click();await settle();}else await ui.login();
  await ui.click('Pacientes');assert.match(ui.app.textContent,/Tus pacientes, su evolución/);
  const matches=()=>ui.app.all().filter(node=>node.className==='patient-match-card');assert.equal(matches().length,3);
  assert.equal(ui.app.all().filter(node=>node.tagName==='input'&&node.type==='search').length,1,'Sin búsqueda genérica duplicada');
  await ui.input('DUI o nombre del paciente',' 012345678 ');assert.equal(matches().length,1);assert.match(matches()[0].textContent,/María López/);
  await ui.input('DUI o nombre del paciente','maria');assert.equal(matches().length,1);
  const tomorrow=new Date();tomorrow.setDate(tomorrow.getDate()+1);await ui.input('Fecha de atención',key(tomorrow));assert.equal(matches().length,0,'Fecha y texto se combinan');
  await ui.input('DUI o nombre del paciente','');assert.equal(matches().length,1);assert.match(matches()[0].textContent,/Ana Reyes/);
  await ui.click('Seleccionar a Ana Reyes');assert.match(ui.app.textContent,/Sin consultas previas registradas/);
  assert.equal(ui.app.all().some(node=>node.tagName==='dialog'),false,'La ficha es un ticket dentro de la aplicación');
  assert.match(ui.app.textContent,/ana.reyes@ejemplo.test/);await ui.click('Volver');assert.equal(matches().length,1,'Conserva filtros al volver');
  await ui.click('Todos');assert.equal(matches().length,3);await ui.click('Hoy');assert.equal(matches().length,2);
  await ui.click('Seleccionar a María López');
  for(const text of ['67 años','0123-45678','7123-4567','Consulta de seguimiento','Revisión de resultados','Notas y recetas','Laboratorios del expediente'])assert.ok(ui.app.textContent.includes(text),text);
  assert.equal(ui.app.textContent.includes('Consulta ajena'),false,'No muestra consultas de otro médico');
  assert.equal(ui.app.textContent.includes('Consulta general'),false,'No mezcla el historial de otro paciente');
  await ui.click('Añadir observación');await ui.input('Observación','Nota compartida desde Pacientes');await ui.submit('Guardar');
  await ui.click('Seleccionar a María López');assert.match(ui.app.textContent,/Nota compartida desde Pacientes/);
  await ui.click('Laboratorios');assert.ok(ui.button('Solicitar exámenes'),'Sale de la ficha al cambiar de módulo');
  assert.equal(ui.app.all().some(node=>node.tagName==='button'&&['Ver expediente','Ver solicitudes y resultados'].includes(node.textContent)),false);await ui.click('Más');await ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.startsWith('Expedientes')).textContent);await ui.click('Abrir expediente completo');assert.match(ui.app.textContent,/Nota compartida desde Pacientes/);
  assert.equal(ui.calls.some(call=>/doctor_issue_lab_order|save_consultation/.test(call.url)),false);
  if(mode==='design')assert.equal(ui.calls.some(call=>call.url.startsWith('https:')),false);
  console.log('OK Pacientes '+mode+': DUI/nombre/fecha, coincidencias, ficha interna, historial propio, filtros conservados y seguimiento compartido');
}
