// Multiple selection and published-result views use simulated transport; no production clinical data.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const id='00000000-0000-4000-8000-000000000061',enc='00000000-0000-4000-8000-000000000062';
const tests=[{id:1,code:'LOCAL-1',name:'Examen de sangre local',category:'Sangre'},{id:2,code:'LOCAL-2',name:'Examen de orina local',category:'Orina'},{id:3,code:'LOCAL-3',name:'Examen de heces local',category:'Heces'}];
const patient={id,full_name:'Paciente local autorizado',record_number:'EXP-LOCAL',active_encounter_id:enc};
let orders=[],loseResponse=true,empty=false;
const ui=createApp(['doctor'],{transport:async(url,p)=>{
 if(url.endsWith('/doctor_native_lab_catalog'))return{body:empty?[]:tests};
 if(url.endsWith('/doctor_native_patients'))return{body:{patients:[patient],total:1,has_more:false,next_offset:null}};
 if(url.endsWith('/doctor_native_chart'))return{body:{patient:{...patient},allergies:[],conditions:[],history:[{id:enc,status:'open',started_at:new Date().toISOString(),row_version:0}],prescriptions:[]}};
 if(url.endsWith('/doctor_native_patient_labs')||url.endsWith('/doctor_native_lab_orders'))return{body:{items:orders,total:orders.length,has_more:false,next_offset:null}};
 if(url.endsWith('/doctor_native_labs')){
  assert.deepEqual(p.p_tests,[1,2]);assert.equal(p.p_encounter,enc);assert.equal('doctor_id'in p,false);
  if(!orders.length)orders=p.p_tests.map((test,index)=>({id:patient.id.slice(0,-1)+(index+1),test_name:tests.find(t=>t.id===test).name,patient_name:patient.full_name,record_number:patient.record_number,ordered_at:new Date().toISOString(),reason:p.p_reason,status:'pendiente',parameters:[],result_summary:null}));
  if(loseResponse){loseResponse=false;throw new TypeError('Respuesta perdida local');}
  return{body:{count:2,order_ids:orders.map(o=>o.id)}};
 }
}});
await ui.login();await ui.click('Pacientes');await ui.click('Abrir expediente de '+patient.full_name);await ui.click('Laboratorios');
assert.match(ui.app.textContent,/Solicitar exámenes/);assert.match(ui.app.textContent,/EXP-LOCAL/);assert.equal(ui.app.textContent.includes('LOCAL-1'),false,'No presenta códigos técnicos');
await ui.input('Buscar exámenes','orina');assert.ok(ui.button('Seleccionar Examen de orina local'));
assert.equal(ui.app.all().some(n=>n.attributes['aria-label']==='Seleccionar Examen de sangre local'),false);
await ui.click('Seleccionar Examen de orina local');await ui.input('Buscar exámenes','');await ui.input('Categoría de examen','Sangre','change');
await ui.click('Seleccionar Examen de sangre local');await ui.input('Categoría de examen','all','change');
assert.match(ui.app.textContent,/2 exámenes seleccionados/);
await ui.input('Motivo e indicaciones clínicas','Indicaciones locales para la selección');await ui.click('Revisar y enviar exámenes');
assert.equal(ui.calls.some(c=>c.url.endsWith('/doctor_native_labs')),false);await ui.click('Confirmar exámenes');assert.match(ui.app.textContent,/Envío sin confirmar/);
await ui.click('Reintentar el mismo envío');const sends=ui.calls.filter(c=>c.url.endsWith('/doctor_native_labs'));assert.equal(sends.length,2);assert.deepEqual(sends[0].params,sends[1].params);assert.equal(orders.length,2);
orders[0]={...orders[0],status:'completado',result_summary:'Informe local validado',published_at:new Date().toISOString(),parameters:[{label:'Parámetro local',value:'Valor local',unit:'Unidad local',reference:'Referencia local',observation:'Observación local'}]};orders[1].status='en_proceso';
await ui.click('Volver al listado de pacientes');await ui.click('Actualizar órdenes');assert.match(ui.app.textContent,/Mis órdenes de laboratorio/);assert.match(ui.app.textContent,/Informe local validado/);assert.match(ui.app.textContent,/Valor local Unidad local/);assert.match(ui.app.textContent,/Referencia local/);assert.match(ui.app.textContent,/Observación local/);
assert.ok(ui.app.all().some(n=>n.className==='lab-state is-completed'));assert.ok(ui.app.all().some(n=>n.className==='lab-state is-processing'));
empty=true;await ui.click('Abrir expediente de '+patient.full_name);await ui.click('Inicio');await ui.click('Laboratorios');assert.match(ui.app.textContent,/No hay exámenes activos/);
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Laboratorios doctor: búsqueda, categorías, selección múltiple, confirmación, reintento estable, seguimiento global, parámetros publicados, colores y catálogo vacío');
let release=false;
const ownID='00000000-0000-4000-8000-000000000001';
const patientUI=createApp(['patient'],{transport:async url=>{
 if(url.includes('/lab_orders?')){
  assert.match(decodeURIComponent(url),new RegExp('patient_id=eq.'+ownID));
  return{body:[{id:ownID,reason:'Seguimiento local',status:'completado',ordered_at:new Date().toISOString(),lab_test_types:{name:'Examen propio local'},lab_results:[{summary:'Informe publicado local',published_at:'2026-11-13',validated_at:'2026-11-13',validated_by:ownID,published_to_patient_at:release?'2026-11-13':null,parameter_schema:[{key:'local',label:'Parámetro autorizado',unit:'Unidad local',reference:'Referencia local'}],result_values:{local:{value:'Valor local',observation:'Observación local'}}}]}]};
 }
}});
await patientUI.login();await patientUI.click('Laboratorios');assert.match(patientUI.app.textContent,/pendiente de publicación/);assert.equal(patientUI.app.textContent.includes('Informe publicado local'),false);
release=true;await patientUI.click('Actualizar laboratorios');await patientUI.click('Ver detalle: Examen propio local');
assert.match(patientUI.app.textContent,/Informe publicado local/);assert.match(patientUI.app.textContent,/Valor local Unidad local/);assert.match(patientUI.app.textContent,/Referencia local/);assert.match(patientUI.app.textContent,/Observación local/);
console.log('OK Laboratorios paciente: filtro propio, informe retenido protegido y detalle estructurado solo tras publicación autorizada');
