// Connected UI with simulated transport: no real clinical writes.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const appointment='00000000-0000-4000-8000-000000000010',patient='00000000-0000-4000-8000-000000000011',encounter='00000000-0000-4000-8000-000000000012',test='00000000-0000-4000-8000-000000000013';
let open=false, issued=false, fail=false, deny=false;
const labs=[
  {id:'released',test_name:'Estudio publicado',requested_at:'2026-10-30T12:00:00Z',status:'completed',released_at:'2026-10-30T14:00:00Z',narrative:'Informe autorizado',values:[{name:'Analito autorizado',value:'13',unit:'g/dL',reference:'12–16'}]},
  {id:'pending',test_name:'Estudio pendiente',requested_at:'2026-10-31T12:00:00Z',status:'pending',narrative:'No mostrar borrador',values:[{name:'Valor privado'}]},
  {id:'processing',test_name:'Estudio en proceso',requested_at:'2026-10-31T11:00:00Z',status:'in_progress',values:[]}
];
const ui=createApp(['doctor'],{transport:async(url,params)=>{
  if(url.endsWith('/doctor_workspace'))return{body:{doctor_name:'Médico conectado',facility_name:'Sede autorizada',appointments:[{id:appointment,patient_id:patient,patient_name:'Paciente conectado',dui:'12345678-9',record_number:'REAL-1',period:'["2026-10-31 08:00:00-06","2026-10-31 09:00:00-06")',status:open?'in_progress':'checked_in',encounter_id:open?encounter:null}],tests:[{id:test,name:'Estudio del catálogo'}],orders:[],notifications:[],stats:{consultations:1}}};
  if(url.endsWith('/doctor_chart'))return deny?{status:403,body:{message:'Acceso denegado'}}:{body:{patient:{id:patient,full_name:'Paciente conectado',given_names:'Paciente',family_names:'Conectado',dui:'12345678-9',birth_date:'1990-01-01',record_number:'REAL-1',phone:'7000-0000'},allergies:[],conditions:[],history:open?[{id:encounter,status:'open',started_at:'2026-10-31T12:00:00Z',row_version:1}]:[],laboratories:labs}};
  if(url.endsWith('/start_consultation')){open=true;return{body:{id:encounter}};}
  if(url.endsWith('/doctor_submit_lab_request')){if(fail)return{status:500,body:{message:'Error temporal'}};issued=true;return{body:{id:'new-order'}};}
}});
await ui.login();await ui.click('Pacientes');
assert.equal(ui.app.textContent.includes('Prototipo local'),false);
await ui.input('DUI o nombre del paciente','123456789');
assert.match(ui.app.textContent,/Paciente conectado/);
await ui.click('Seleccionar a Paciente conectado');
assert.match(ui.app.textContent,/Expediente completo/);assert.match(ui.app.textContent,/12345678-9/);
const details=()=>ui.app.all().filter(node=>node.tagName==='button'&&node.textContent==='Ver detalle');
assert.equal(details().length,3);
details()[0].listeners.click();await new Promise(r=>setImmediate(r));
assert.match(ui.app.textContent,/Pendiente/);assert.equal(ui.app.textContent.includes('No mostrar borrador'),false);assert.equal(ui.app.textContent.includes('Valor privado'),false);
await ui.click('Volver');details()[2].listeners.click();await new Promise(r=>setImmediate(r));
assert.match(ui.app.textContent,/Informe autorizado/);assert.match(ui.app.textContent,/12–16/);
await ui.click('Añadir receta');assert.match(ui.app.textContent,/Iniciar consulta/);
assert.equal(ui.calls.some(call=>call.url.endsWith('/mobile_issue_prescription')),false);
await ui.click('Iniciar consulta');assert.ok(open);
await ui.click('Laboratorios');await ui.click('Solicitar exámenes');
await ui.input('Tipo de laboratorio',test,'change');await ui.input('Indicaciones','Seguimiento autorizado');
await ui.input('Peso (kg)','70,5');await ui.input('Altura (cm)','170');
fail=true;await ui.submit('Emitir orden');
const first=ui.calls.findLast(call=>call.url.endsWith('/doctor_submit_lab_request'));
assert.equal(first.params.p_encounter,encounter);assert.equal(first.params.p_test,test);
assert.equal(first.params.p_weight,70.5);assert.equal(first.params.p_height,170);
assert.equal(ui.app.all().find(node=>node.attributes['aria-label']==='Indicaciones').value,'Seguimiento autorizado');
fail=false;await ui.submit('Emitir orden',true);assert.ok(issued);
const writes=ui.calls.filter(call=>call.url.endsWith('/doctor_submit_lab_request'));
assert.equal(writes.length,2,'Doble submit bloqueado');assert.equal(writes[0].params.p_request_key,writes[1].params.p_request_key,'Reintento conserva idempotencia');
await ui.click('Pacientes');deny=true;await ui.click('Seleccionar a Paciente conectado');
assert.equal(ui.app.textContent.includes('Informe autorizado'),false);
assert.equal(ui.app.textContent.includes('Estudio publicado'),false);
assert.equal(ui.app.textContent.includes('María López'),false);
console.log('OK Clinical conectado: búsqueda real, ficha, estados/resultados, consulta obligatoria, envío, reintento idempotente, doble submit y denegación sin datos residuales');
