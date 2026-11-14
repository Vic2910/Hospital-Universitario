// Authorized patient directory with simulated transport, no production accounts.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const ids=['00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000012'];
const patients=[
 {id:ids[0],full_name:'Ana Paciente',record_number:'EXP-ANA',dui:'01234567-8',email:'ana@example.test',phone:'7999-0000',age:35,active_encounter_id:null},
 {id:ids[1],full_name:'Beatriz Paciente',record_number:'EXP-BEA',dui:'87654321-0',email:'bea@example.test',phone:null,age:40,active_encounter_id:null}
];
let fail=false;
const ui=createApp(['doctor'],{transport:async(url,p)=>{
 if(url.endsWith('/rpc/doctor_native_patients')){
   if(fail)return {status:503,body:{}};
   const q=p.p_query.toLowerCase(),match=patients.filter(x=>!q||[x.full_name,x.dui,x.email,x.dui.replace('-','')].some(v=>v.toLowerCase().includes(q)));
   const offset=p.p_offset||0;return {body:{patients:match.slice(offset,offset+1),total:match.length,has_more:offset+1<match.length,next_offset:offset+1<match.length?offset+1:null}};
 }
 if(url.endsWith('/rpc/doctor_native_chart')){
   const patient=patients.find(x=>x.id===p.p_patient);assert.ok(patient);
   return {body:{patient:{...patient,identification:patient.dui,birth_date:'1990-01-01'},allergies:['Antecedente autorizado de '+patient.full_name],conditions:[],medical_history:[],history:[],prescriptions:[]}};
 }
 if(url.endsWith('/rpc/doctor_native_patient_labs')){
   assert.ok(ids.includes(p.p_patient));return {body:{items:p.p_patient===ids[0]?[{id:ids[0],test_name:'Examen de catálogo',reason:'Seguimiento registrado',status:'completado',ordered_at:'2026-11-01T12:00:00Z',result_summary:'Resultado autorizado de Ana'}]:[],total:p.p_patient===ids[0]?1:0,has_more:false,next_offset:null}};
 }
}});
await ui.login();await ui.click('Pacientes');
assert.match(ui.app.textContent,/Tus pacientes, siempre a mano/);assert.match(ui.app.textContent,/Ana Paciente/);
assert.equal(ui.app.textContent.includes('Beatriz Paciente'),false);
await ui.click('Cargar más pacientes');assert.match(ui.app.textContent,/Beatriz Paciente/);
for(const query of ['Ana','012345678','ana@example.test']){
 await ui.input('Nombre, DUI o correo',query);await ui.submit('Buscar pacientes');
 assert.match(ui.app.textContent,/Ana Paciente/);assert.equal(ui.app.textContent.includes('Beatriz Paciente'),false);
}
await ui.click('Abrir expediente de Ana Paciente');assert.match(ui.app.textContent,/EXP-ANA/);assert.match(ui.app.textContent,/01234567-8/);assert.match(ui.app.textContent,/ana@example.test/);
await ui.click('Ver laboratorios de este paciente');assert.match(ui.app.textContent,/Resultado autorizado de Ana/);
await ui.click('Ver expediente completo del paciente');assert.match(ui.app.textContent,/Antecedente autorizado de Ana Paciente/);
assert.equal(ui.app.textContent.includes('Emitir orden'),false,'No permite ordenar sin consulta abierta');
await ui.click('Volver al listado de pacientes');await ui.input('Nombre, DUI o correo','bea@example.test');await ui.submit('Buscar pacientes');
await ui.click('Abrir expediente de Beatriz Paciente');assert.match(ui.app.textContent,/EXP-BEA/);assert.match(ui.app.textContent,/todavía no tiene exámenes/);
assert.equal(ui.app.textContent.includes('Resultado autorizado de Ana'),false,'Limpia datos de la selección previa');
await ui.click('Volver al listado de pacientes');fail=true;await ui.submit('Buscar pacientes');assert.match(ui.app.textContent,/No se pudo cargar el directorio/);
fail=false;await ui.click('Reintentar búsqueda');assert.match(ui.app.textContent,/Beatriz Paciente/);
for(const call of ui.calls.filter(c=>c.url.endsWith('/doctor_native_patients'))){assert.equal('p_from' in call.params,false);assert.equal('doctor_id' in call.params,false);}
assert.equal(ui.calls.some(c=>/doctor_native_(lab|start|save|prescribe|finish)$/.test(c.url)),false);
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Directorio sin citas de hoy: nombre/DUI/correo, paginación, expediente, laboratorios por paciente, cambio de selección, error y cierre');
