// Expedientes del médico con transporte simulado: sin cuentas ni datos clínicos reales.
// El transporte imita doctor_native_patients (solo pacientes autorizados) y doctor_native_chart (solo consultas propias).
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const ids=['00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000012'];
const enc=['00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000022','00000000-0000-4000-8000-000000000023'];
const patients=[
 {id:ids[0],full_name:'Ana Paciente',record_number:'EXP-ANA',patient_code:'PAC-0001',dui:'01234567-8',email:'ana@example.test',phone:'7999-0000',age:35,active_encounter_id:null},
 {id:ids[1],full_name:'Beatriz Paciente',record_number:'EXP-BEA',patient_code:'PAC-0002',dui:'87654321-0',email:'bea@example.test',phone:null,age:40,active_encounter_id:null}
];
// Paciente no autorizado para este médico: el servidor nunca lo devuelve.
const foreign={id:'00000000-0000-4000-8000-000000000099',full_name:'Ana Ajena',record_number:'EXP-AJENA',patient_code:'PAC-9999',dui:'11111111-1'};
const anaHistory=[
 {id:enc[0],started_at:'2026-10-01T15:00:00Z',ended_at:'2026-10-01T15:30:00Z',status:'closed',subjective:'Tos antigua',objective:'Observación antigua',assessment:'Diagnóstico antiguo',plan:'',vitals:{weight_kg:'60'},specialty:'Medicina general',reason:'Control anterior'},
 {id:enc[1],started_at:'2026-11-10T15:00:00Z',ended_at:'2026-11-10T15:30:00Z',status:'closed',subjective:'Fiebre reciente',objective:'Faringe enrojecida',assessment:'Faringitis aguda',plan:'Reposo',diagnosis_code:'J02',vitals:{weight_kg:'61.5',height_cm:'165',temperature_c:'38.2'},specialty:'Medicina general',reason:'Dolor de garganta'},
 {id:enc[2],started_at:'2026-11-19T15:00:00Z',status:'open',subjective:'Borrador en curso',objective:'',assessment:'Borrador no finalizado',plan:'',vitals:{}}
];
let fail=false;
const ui=createApp(['doctor'],{transport:async(url,p)=>{
 if(url.endsWith('/rpc/doctor_native_patients')){
   if(fail)return {status:503,body:{}};
   const q=p.p_query.toLowerCase(),match=patients.filter(x=>!q||[x.full_name,x.dui,x.email,x.record_number,x.patient_code,x.dui.replace('-','')].some(v=>v.toLowerCase().includes(q)));
   const offset=p.p_offset||0;return {body:{patients:match.slice(offset,offset+1),total:match.length,has_more:offset+1<match.length,next_offset:offset+1<match.length?offset+1:null}};
 }
 if(url.endsWith('/rpc/doctor_native_chart')){
   const patient=patients.find(x=>x.id===p.p_patient);assert.ok(patient,'Solo se consulta el expediente de pacientes autorizados');
   const ana=patient.id===ids[0];
   return {body:{patient:{...patient,identification:patient.dui,birth_date:'1990-01-01'},allergies:['Antecedente autorizado de '+patient.full_name],conditions:[],medical_history:['alergia: Antecedente autorizado de '+patient.full_name,'quirurgico: Apendicectomía'],
     history:ana?anaHistory:[],prescriptions:ana?[{id:enc[0],encounter_id:enc[1],code:'REC-ANA',issued_at:'2026-11-10T15:20:00Z',status:'pendiente',lines:['Medicamento de catálogo 500 mg cada 8 horas']}]:[]}};
 }
 if(url.endsWith('/rpc/doctor_native_patient_labs')){
   assert.ok(ids.includes(p.p_patient));return {body:{items:p.p_patient===ids[0]?[{id:ids[0],encounter_id:enc[1],test_name:'Examen de catálogo',reason:'Seguimiento registrado',status:'completado',ordered_at:'2026-11-01T12:00:00Z',result_summary:'Resultado autorizado de Ana',published_at:'2026-11-02T12:00:00Z'}]:[],total:p.p_patient===ids[0]?1:0,has_more:false,next_offset:null}};
 }
}});
const wait=()=>new Promise(resolve=>setTimeout(resolve,420));
const searches=()=>ui.calls.filter(c=>c.url.endsWith('/doctor_native_patients')).length;
await ui.login();await ui.click('Pacientes');
assert.match(ui.app.textContent,/Encuentra un expediente al instante/);assert.match(ui.app.textContent,/Ana Paciente/);
assert.equal(ui.app.all().some(n=>n.tagName==='select'),false,'Sin selector desplegable de pacientes');
assert.equal(ui.app.textContent.includes('Beatriz Paciente'),false);
await ui.click('Cargar más resultados');assert.match(ui.app.textContent,/Beatriz Paciente/);
// Nombre, apellido, nombre y apellido, DUI, código de paciente y de expediente.
for(const [query,expected] of [['Ana','Ana Paciente'],['Paciente','Ana Paciente'],['Beatriz Paciente','Beatriz Paciente'],['012345678','Ana Paciente'],['PAC-0002','Beatriz Paciente'],['EXP-ANA','Ana Paciente']]){
 await ui.input('Buscar expediente',query);await wait();
 assert.match(ui.app.textContent,new RegExp(expected));
 const other=expected==='Ana Paciente'?'Beatriz Paciente':'Ana Paciente';
 if(query!=='Paciente')assert.equal(ui.app.textContent.includes(other),false,'Solo resultados que coinciden con '+query);
 assert.equal(ui.app.textContent.includes('Ana Ajena'),false,'Nunca aparecen pacientes no autorizados');
}
// Espera breve: varias pulsaciones seguidas producen una sola consulta, y repetir el texto no vuelve a consultar.
let before=searches();for(const partial of ['B','Be','Bea'])await ui.input('Buscar expediente',partial);await wait();
assert.equal(searches()-before,1,'Una consulta por búsqueda, no por pulsación');
before=searches();await ui.input('Buscar expediente','Bea');await wait();assert.equal(searches(),before,'Sin consultas repetidas');
await ui.input('Buscar expediente','zzz');await wait();assert.match(ui.app.textContent,/Sin coincidencias/);
assert.equal(ui.app.textContent.includes('Antecedente autorizado'),false,'Los resultados no muestran información clínica');
await ui.input('Buscar expediente','Ana');await wait();
await ui.click('Abrir expediente de Ana Paciente');
const text=()=>ui.app.textContent,count=value=>text().split(value).length-1;
for(const value of ['EXP-ANA','PAC-0001','01234567-8','ana@example.test','7999-0000'])assert.equal(count(value),1,'Se muestra una sola vez: '+value);
assert.match(text(),/Antecedente autorizado de Ana Paciente/);assert.equal(count('Antecedente autorizado de Ana Paciente'),1,'Alergias sin repetir en otros antecedentes');assert.match(text(),/Apendicectomía/);
assert.doesNotMatch(text(),/Faringitis aguda/,'El historial se despliega solo al pulsar el botón');
await ui.click('VER HISTORIAL MÉDICO');
assert.match(text(),/2 consultas finalizadas/);
assert.ok(text().indexOf('Faringitis aguda')<text().indexOf('Diagnóstico antiguo'),'Más reciente primero');
assert.equal(text().includes('Borrador no finalizado'),false,'Las consultas abiertas no aparecen en el historial');
assert.match(text(),/Dolor de garganta/);assert.match(text(),/Reposo/);
await ui.click(ui.app.all().find(n=>n.attributes['aria-label']?.startsWith('Consulta del ')&&n.textContent.includes('Faringitis')).attributes['aria-label']);
for(const value of ['Datos físicos','61.5','165','38.2','Fiebre reciente','Faringitis aguda','J02','Faringe enrojecida','Reposo','REC-ANA','Medicamento de catálogo','Examen de catálogo','Resultado autorizado de Ana'])assert.ok(text().includes(value),'Detalle: '+value);
await ui.click('← Volver al historial');
await ui.click(ui.app.all().find(n=>n.attributes['aria-label']?.startsWith('Consulta del ')&&n.textContent.includes('antiguo')).attributes['aria-label']);
assert.match(text(),/No se emitieron recetas en esta consulta/);assert.match(text(),/No se solicitaron exámenes en esta consulta/);
assert.equal(text().includes('Tratamiento'),false,'No muestra campos vacíos como datos registrados');assert.equal(text().includes('Resultado autorizado de Ana'),false);
// Laboratorio del paciente sin cambios en su flujo.
await ui.click('← Volver al historial');await ui.click('Laboratorios');assert.match(text(),/Resultado autorizado de Ana/);
await ui.click('Ver expediente completo del paciente');assert.match(text(),/Antecedente autorizado de Ana Paciente/);
assert.equal(text().includes('Emitir orden'),false,'No permite ordenar sin consulta abierta');
// Otro paciente: sin historial y sin datos de la selección previa.
await ui.click('Pacientes');await ui.click('← Volver a la búsqueda');await ui.input('Buscar expediente','bea@example.test');await wait();
await ui.click('Abrir expediente de Beatriz Paciente');assert.match(text(),/EXP-BEA/);
await ui.click('VER HISTORIAL MÉDICO');assert.match(text(),/Todavía no hay historial/);
assert.equal(text().includes('Faringitis aguda'),false,'Limpia datos de la selección previa');assert.equal(text().includes('Ana Paciente'),false);
await ui.click('← Volver a la búsqueda');fail=true;await ui.input('Buscar expediente','error');await wait();assert.match(text(),/No se pudo cargar el directorio/);
fail=false;await ui.click('Reintentar búsqueda');await wait();assert.doesNotMatch(text(),/No se pudo cargar el directorio/);
for(const call of ui.calls.filter(c=>c.url.endsWith('/doctor_native_patients'))){assert.equal('p_from' in call.params,false);assert.equal('doctor_id' in call.params,false);}
for(const call of ui.calls.filter(c=>c.url.includes('/doctor_native_'))){assert.equal('doctor_id' in (call.params||{}),false);assert.equal('user_id' in (call.params||{}),false);}
assert.equal(ui.calls.some(c=>/doctor_native_(lab|start|save|prescribe|finish)$/.test(c.url)),false);
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Expedientes: búsqueda por nombre/apellido/DUI/código con espera breve y sin repetir, sin datos clínicos en resultados, cabecera sin duplicados, historial finalizado más reciente primero, detalle con recetas y exámenes, sin consultas abiertas, error y cierre');
