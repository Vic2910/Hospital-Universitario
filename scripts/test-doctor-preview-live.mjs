// Simulated native API contract. Does not create clinical records in Supabase.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const id='00000000-0000-4000-8000-000000000001',enc='00000000-0000-4000-8000-000000000002';
// notes.vitals simula medidas antiguas (presión) que el formulario ya no captura y que deben conservarse.
// planRequired simula el servidor sin la migración doctor-consultation-six-fields.sql.
let failSave=false,conflictOnce=false,started=false,closed=false,version=0,notes={vitals:{systolic:'118',diastolic:'76'}},orders=[],prescriptions=[],finishCalls=0,planRequired=true;
const early='00000000-0000-4000-8000-000000000003',earlyPeriod='["'+new Date(Date.now()+300000).toISOString()+'","'+new Date(Date.now()+900000).toISOString()+'")';
const period='["'+new Date(Date.now()+600000).toISOString()+'","'+new Date(Date.now()+2400000).toISOString()+'")';
const ui=createApp(['doctor'],{transport:async(url,p)=>{
  if(url.endsWith('/rpc/doctor_native_patients'))return {body:{patients:[{id,full_name:'Paciente autorizado',record_number:'EXP-PRUEBA',dui:'01234567-8',email:'paciente@example.test',phone:null,age:35,active_encounter_id:started&&!closed?enc:null}],total:1,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_patient_labs'))return {body:{items:orders,total:orders.length,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_lab_catalog'))return {body:[{id:1,code:'LOCAL',name:'Estudio de catálogo de prueba',category:'Sangre'}]};
  if(url.endsWith('/rpc/doctor_native_lab_orders'))return {body:{items:orders,total:orders.length,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_workspace'))return {body:{doctor_name:'Médico autorizado',facility_name:'Hospital Universitario',appointments:[{id,patient_id:id,patient_name:'Paciente autorizado',record_number:'EXP-PRUEBA',phone:null,ticket_number:null,period,status:closed?'completed':started?'in_progress':'scheduled',encounter_id:started?enc:null,age:35,reason:'Motivo original autorizado',symptoms:['Fiebre'],room_code:'C-1',duration_minutes:30,specialty:'Medicina general'},{id:early,patient_id:early,patient_name:'Paciente temprano',record_number:'EXP-TEMPRANO',phone:null,ticket_number:null,period:earlyPeriod,status:'scheduled',encounter_id:null,reason:'Control temprano',symptoms:[],room_code:'C-2'}],tests:[{id:1,code:'1',name:'Estudio de catálogo de prueba'}],medications:[{id,name:'Medicamento de prueba',strength:'Concentración de catálogo'}],orders,notifications:[],stats:{consultations:1,completed_consultations:closed?1:0,issued_orders:orders.length,pending_orders:orders.length}}};
  if(url.endsWith('/rpc/doctor_native_chart'))return {body:{patient:{id,full_name:'Paciente autorizado',record_number:'EXP-PRUEBA'},allergies:['Antecedente autorizado'],conditions:[],medical_history:[],history:started?[{id:enc,started_at:new Date().toISOString(),status:closed?'closed':'open',...notes,note_id:version?enc:null,note_version:version,row_version:version,vitals:notes.vitals||{}}]:[],prescriptions}};
  if(url.endsWith('/rpc/doctor_native_start')){started=true;return {body:enc};}
  if(url.endsWith('/rpc/doctor_native_save')){if(failSave)return {status:503,body:{}};if(conflictOnce){conflictOnce=false;version++;return {status:409,body:{code:'40001',message:'El borrador cambió. Actualiza antes de guardar'}};}assert.equal(p.p_version,version);version++;notes=p.p_values;return {body:version};}
  if(url.endsWith('/rpc/doctor_native_labs')){orders=[{id:p.p_key,patient_name:'Paciente autorizado',test_name:'Estudio de catálogo de prueba',status:'pendiente',reason:p.p_reason,ordered_at:new Date().toISOString()}];return {body:{order_ids:[p.p_key],count:1}};}
  if(url.endsWith('/rpc/doctor_native_prescribe')){prescriptions=[{id:p.p_key,code:'REC-PRUEBA',issued_at:new Date().toISOString(),status:'pendiente',lines:['Receta autorizada de prueba']}];return {body:p.p_key};}
  if(url.endsWith('/rpc/doctor_native_finish')){finishCalls++;assert.equal(p.p_version,version);if(planRequired&&!String(notes.plan||'').trim())return {status:400,body:{code:'22023',message:'Completa motivo, exploración, diagnóstico y tratamiento'}};closed=true;version++;return {body:null};}
}});
await ui.login();assert.match(ui.app.textContent,/Médico autorizado/);assert.match(ui.app.textContent,/PRÓXIMA CITA/);
await ui.click('Agenda');
const agendaText=ui.app.textContent;
assert.ok(agendaText.indexOf('Paciente temprano')<agendaText.indexOf('Paciente autorizado'),'Orden cronológico ascendente');
assert.match(agendaText,/Programada/);assert.match(agendaText,/Medicina general/);assert.match(agendaText,/Consultorio C-1/);assert.match(agendaText,/EXP-PRUEBA/);
await ui.click('Ver detalle de Paciente autorizado, Programada');
assert.match(ui.app.textContent,/Detalle de consulta/);assert.match(ui.app.textContent,/Fiebre/);
await ui.click('ABRIR CONSULTA MÉDICA');
assert.equal(started,true);assert.match(ui.app.textContent,/En consulta/);
const field=label=>ui.app.all().find(node=>node.attributes['aria-label']===label);
assert.match(field('Síntomas que presentaba').value,/Síntomas referidos por el paciente: Fiebre/,'Precarga los síntomas enviados por el paciente');
assert.match(ui.app.textContent,/Motivo original autorizado/,'Motivo de la solicitud visible');assert.match(ui.app.textContent,/Datos de la cita/);
assert.match(ui.app.textContent,/Médico autorizado/);assert.match(ui.app.textContent,/Cambios pendientes/);assert.match(ui.app.textContent,/Consultorio/);assert.match(ui.app.textContent,/35 años/);
// Solo seis campos: peso, altura, temperatura, síntomas, diagnóstico y observaciones.
for(const label of ['Peso (kg)','Altura (cm)','Temperatura (°C)','Síntomas que presentaba','Diagnóstico','Observaciones'])assert.ok(field(label),'Campo '+label);
for(const gone of ['Presión sistólica (mmHg)','Presión diastólica (mmHg)','Frecuencia cardíaca (lpm)','Plan de tratamiento y recomendaciones','Código del diagnóstico principal (opcional)'])assert.equal(field(gone),undefined,'Sin campo '+gone);
assert.doesNotMatch(ui.app.textContent,/Frecuencia respiratoria|Saturación/);
for(const [label,value] of [['Síntomas que presentaba','Fiebre de dos días'],['Diagnóstico','Faringitis aguda'],['Observaciones','Exploración registrada'],['Peso (kg)','7a0,5'],['Altura (cm)','170'],['Temperatura (°C)','38.2']])await ui.input(label,value);
assert.equal(field('Peso (kg)').value,'70.5','Sin texto en campos numéricos');
await ui.click('Guardar avances');assert.equal(version,1);assert.match(ui.app.textContent,/IMC calculado: 24.4 kg\/m²/);
assert.deepEqual({...notes.vitals},{weight_kg:'70.5',height_cm:'170',temperature_c:'38.2',systolic:'118',diastolic:'76'},'Conserva las medidas antiguas sin mostrarlas');
assert.equal(notes.subjective,'Fiebre de dos días');assert.equal(notes.assessment,'Faringitis aguda');assert.equal(notes.objective,'Exploración registrada');
await ui.input('Temperatura (°C)','60');assert.match(ui.app.textContent,/Valor fuera de rango/);await ui.input('Temperatura (°C)','38.2');
// Conflicto de versión: se muestra la versión guardada y no se sobrescribe sin decisión.
await ui.input('Observaciones','Exploración ampliada');conflictOnce=true;await ui.click('Guardar avances');
assert.match(ui.app.textContent,/Otra sesión guardó esta consulta/);assert.equal(field('Observaciones').value,'Exploración ampliada');
await ui.click('Conservar lo que escribí y guardar');assert.equal(notes.objective,'Exploración ampliada');assert.doesNotMatch(ui.app.textContent,/Otra sesión guardó/);
await ui.click('Solicitar exámenes');await ui.click('Seleccionar Estudio de catálogo de prueba');await ui.input('Motivo e indicaciones clínicas','Motivo de orden');await ui.click('Revisar y enviar exámenes');await ui.click('Confirmar exámenes');assert.equal(orders.length,1);
await ui.click('← Volver a la consulta');
await ui.click('Recetar medicamentos');
for(const round of [1,2]){
  for(const [label,value,event] of [['Medicamento y concentración',id,'change'],['Unidad de dosis','tableta'],['Vía de administración','oral','change'],['Dosis',String(round)],['Cada cuántas horas','8'],['Duración en días','3'],['Cantidad total','9'],['Instrucciones para el paciente','Tomar con agua']])await ui.input(label,value,event||'input');
  await ui.submit('Añadir medicamento');
}
assert.match(ui.app.textContent,/Revisión de la receta · 2 medicamento/);
await ui.click('Revisar y emitir receta');await ui.click('Confirmar y emitir receta');assert.equal(prescriptions.length,1);
await ui.click('← Volver a la consulta');
// No se puede finalizar incompleta.
await ui.input('Diagnóstico','  ');await ui.click('FINALIZAR CONSULTA');
assert.equal(finishCalls,0);assert.doesNotMatch(ui.app.textContent,/¿Estás seguro de que deseas finalizar esta consulta\?/);
await ui.input('Diagnóstico','Faringitis aguda');
// Volver a la consulta desde la confirmación no modifica nada.
await ui.click('FINALIZAR CONSULTA');assert.match(ui.app.textContent,/¿Estás seguro de que deseas finalizar esta consulta\?/);assert.match(ui.app.textContent,/quedará registrada en el expediente del paciente/);
await ui.click('Volver a la consulta');assert.equal(finishCalls,0);assert.equal(closed,false);
// Fallo de guardado: no finaliza y conserva lo escrito.
failSave=true;await ui.click('FINALIZAR CONSULTA');await ui.click('Confirmar y finalizar');
assert.equal(closed,false,'No finaliza si falla guardar');assert.equal(field('Observaciones').value,'Exploración ampliada');assert.match(ui.app.textContent,/Error al guardar/);
failSave=false;
// Servidor sin migración: exige plan. Se explica sin cerrar, sin inventar un plan y sin perder datos.
await ui.click('FINALIZAR CONSULTA');await ui.click('Confirmar y finalizar');
assert.equal(closed,false);assert.match(ui.get('notice').textContent,/doctor-consultation-six-fields\.sql/);assert.equal(String(notes.plan||''),'','No inventa plan');assert.equal(field('Diagnóstico').value,'Faringitis aguda');
// Con la migración aplicada, el cierre funciona con los tres campos obligatorios.
planRequired=false;await ui.click('FINALIZAR CONSULTA');await ui.click('Confirmar y finalizar');
assert.equal(closed,true);assert.equal(finishCalls,2);assert.equal(notes.vitals.weight_kg,'70.5');assert.equal(notes.vitals.height_cm,'170');assert.equal(notes.vitals.temperature_c,'38.2');
assert.match(ui.app.textContent,/Consultas pendientes/);assert.equal(ui.app.textContent.includes('Paciente autorizado'),false,'Al finalizar deja de estar en Pendientes');
await ui.click('FINALIZADAS');assert.match(ui.app.textContent,/Consultas finalizadas/);assert.match(ui.app.textContent,/Paciente autorizado/);assert.match(ui.app.textContent,/Finalizada/);
await ui.click('Ver detalle de Paciente autorizado, Finalizada');await ui.click('VER CONSULTA FINALIZADA');
assert.match(ui.app.textContent,/Consulta finalizada/);
for(const text of ['70.5','38.2','Fiebre de dos días','Faringitis aguda','Exploración ampliada','Síntomas que presentaba','Observaciones','Presión sistólica \\(mmHg\\)'])assert.match(ui.app.textContent,new RegExp(text));
assert.match(ui.app.textContent,/IMC \(calculado\)/);
const lab=ui.calls.find(c=>c.url.endsWith('/doctor_native_labs')),rx=ui.calls.find(c=>c.url.endsWith('/doctor_native_prescribe'));
assert.deepEqual(lab.params.p_tests,[1]);assert.equal(rx.params.p_lines.length,2);assert.equal(rx.params.p_lines[0].duration_days,3);
assert.equal(ui.calls.filter(c=>c.url.endsWith('/doctor_native_start')).length,1,'Sin consultas duplicadas');
for(const call of ui.calls.filter(c=>c.url.includes('/doctor_native_'))){assert.equal('doctor_id' in (call.params||{}),false);assert.equal('user_id' in (call.params||{}),false);}
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Réplica Doctor: agenda → detalle → ABRIR CONSULTA MÉDICA → seis campos (peso, altura, temperatura, síntomas, diagnóstico, observaciones) → medidas antiguas conservadas → guardado y conflicto → exámenes → receta de 2 medicamentos → cierre sin migración explicado → cierre confirmado; mismo contrato que iOS');
