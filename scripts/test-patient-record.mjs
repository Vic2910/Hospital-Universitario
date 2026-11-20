// Expediente propio del paciente con transporte simulado: sin buscador, sin selector y sin identificadores en las RPC.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
let history=[];
const ui=createApp(['patient'],{transport:async url=>{ if(url.endsWith('/rpc/my_consultation_history'))return {body:history}; }});
await ui.login();await ui.click('Más');await ui.click('Mi expediente　›');
const text=()=>ui.app.textContent;
for(const value of ['PAC-TEST','EXP-TEST','01234567-8','7000-1111'])assert.equal(text().split(value).length-1,1,'Se muestra una sola vez: '+value);
assert.equal(ui.app.all().some(n=>n.tagName==='select'||n.attributes['aria-label']==='Buscar expediente'),false,'El paciente no busca ni elige expediente');
await ui.click('VER HISTORIAL MÉDICO');assert.match(text(),/Todavía no tienes historial de consultas/);
history=[{id:'00000000-0000-4000-8000-000000000031',started_at:'2026-11-10T15:00:00Z',ended_at:'2026-11-10T15:30:00Z',doctor_name:'Médico autor',specialty:'Medicina general',reason:'Dolor de garganta',subjective:'Fiebre',objective:'',assessment:'Faringitis',plan:null,diagnoses:[],vital_signs:[{temperature_c:'38.2',recorded_at:'2026-11-10T15:20:00Z'}],prescriptions:[{code:'REC-1',lines:['Medicamento 500 mg']}],lab_orders:[{test_name:'Hemograma',status:'pendiente'}]},
 {id:'00000000-0000-4000-8000-000000000032',started_at:'2026-10-01T15:00:00Z',ended_at:'2026-10-01T15:30:00Z',doctor_name:'Médico anterior',specialty:'Medicina general',subjective:'Tos',objective:'Sin hallazgos',assessment:'Resfriado',diagnoses:[],vital_signs:[]}];
await ui.click('Más');await ui.click('Historial médico　›');
assert.ok(text().indexOf('Faringitis')<text().indexOf('Resfriado'),'Más reciente primero');assert.match(text(),/Dolor de garganta/);
await ui.click(ui.app.all().find(n=>n.attributes['aria-label']?.includes('Médico autor')).attributes['aria-label']);
for(const value of ['Datos físicos','38.2','Evaluación médica','Fiebre','Faringitis','Recetas','REC-1','Medicamento 500 mg','Exámenes','Hemograma','Pendiente'])assert.ok(text().includes(value),'Detalle: '+value);
assert.equal(text().includes('Observaciones'),false,'Campos vacíos no aparecen');assert.equal(text().includes('Sin registrar'),false);
for(const call of ui.calls.filter(c=>c.url.endsWith('/rpc/my_consultation_history'))){assert.equal('patient_id' in (call.params||{}),false);assert.equal('p_patient' in (call.params||{}),false);}
console.log('OK Expediente del paciente: identidad sin duplicados, sin buscador ni selector, historial propio más reciente primero, detalle agrupado con recetas y exámenes, sin campos vacíos');
