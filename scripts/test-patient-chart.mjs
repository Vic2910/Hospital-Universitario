import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const response={items:[],sections:[{title:'Datos personales',fields:[{label:'Nombre',value:'Paciente Propio'},{label:'Expediente',value:'EXP-OWN'},{label:'DUI',value:'0123-45678'}]},{title:'Alergias',fields:[{label:'Registro propio',value:'Información autorizada'}]}],options:[],preferences:[],phone:null,emergency:null,has_more:false,next_cursor:null};
const ui=createApp(['patient'],{transport:async(url,params)=>url.endsWith('/mobile_module')&&params.p_module==='chart'?{body:response}:undefined});await ui.login();await ui.click('Más');await ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('expediente')).textContent);
assert.match(ui.app.textContent,/Expediente completo/);assert.match(ui.app.textContent,/Paciente Propio/);assert.match(ui.app.textContent,/EXP-OWN/);assert.match(ui.app.textContent,/0123-45678/);assert.match(ui.app.textContent,/Información autorizada/);
assert.ok(ui.app.all().some(node=>node.attributes['aria-label']==='Mi expediente completo'));
assert.equal(ui.app.all().some(node=>['input','textarea','select','form','dialog'].includes(node.tagName)),false);
assert.equal(ui.app.textContent.includes('María López'),false,'No introducir paciente demo en sesión');
for(const text of ['Solicitar exámenes','Añadir observación','Añadir receta','DUI o nombre del paciente'])assert.equal(ui.app.textContent.includes(text),false);
const requests=ui.calls.filter(call=>call.url.endsWith('/mobile_module')&&call.params.p_module==='chart');assert.equal(requests[0].params.p_role,'patient');assert.equal(Object.hasOwn(requests[0].params,'p_patient'),false,'Paciente resuelto por el servidor, no seleccionado por el cliente');
const missing=createApp(['patient']);await missing.login();await missing.click('Más');await missing.click(missing.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('expediente')).textContent);assert.match(missing.app.textContent,/No hay datos reales/);assert.equal(missing.app.textContent.includes('María López'),false);
const demo=createApp();await new Promise(resolve=>setImmediate(resolve));demo.get('design-patient').listeners.click();await new Promise(resolve=>setImmediate(resolve));await demo.click('Más');await demo.click(demo.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().includes('expediente')).textContent);
assert.match(demo.app.textContent,/Expediente completo/);assert.match(demo.app.textContent,/María López/);assert.equal(demo.app.textContent.includes('Seleccionar a Carlos'),false);assert.equal(demo.app.all().some(node=>node.tagName==='dialog'),false);assert.equal(demo.calls.some(call=>call.url.startsWith('https:')),false);
console.log('OK Expediente Paciente: ticket interno directo, datos autorizados propios, faltantes y diseño aislado sin edición');

await ui.click('Volver');assert.match(ui.app.textContent,/Hola,/);
await demo.click('Volver');assert.match(demo.app.textContent,/Hola,/);
console.log('OK Volver en expediente propio: sesión y diseño regresan a Inicio sin operaciones de edición');
