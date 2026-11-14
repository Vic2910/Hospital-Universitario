// Simulated native API contract. Does not create clinical records in Supabase.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const id='00000000-0000-4000-8000-000000000001',enc='00000000-0000-4000-8000-000000000002';
let started=false,closed=false,version=0,notes={},orders=[],prescriptions=[];
const period='["'+new Date(Date.now()+600000).toISOString()+'","'+new Date(Date.now()+2400000).toISOString()+'")';
const ui=createApp(['doctor'],{transport:async(url,p)=>{
  if(url.endsWith('/rpc/doctor_native_patients'))return {body:{patients:[{id,full_name:'Paciente autorizado',record_number:'EXP-PRUEBA',dui:'01234567-8',email:'paciente@example.test',phone:null,age:35,active_encounter_id:started&&!closed?enc:null}],total:1,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_patient_labs'))return {body:{items:orders,total:orders.length,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_lab_catalog'))return {body:[{id:1,code:'LOCAL',name:'Estudio de catálogo de prueba',category:'Sangre'}]};
  if(url.endsWith('/rpc/doctor_native_lab_orders'))return {body:{items:orders,total:orders.length,has_more:false,next_offset:null}};
  if(url.endsWith('/rpc/doctor_native_workspace'))return {body:{doctor_name:'Médico autorizado',facility_name:'Hospital Universitario',appointments:[{id,patient_id:id,patient_name:'Paciente autorizado',record_number:'EXP-PRUEBA',phone:null,ticket_number:null,period,status:closed?'completed':started?'in_progress':'scheduled',encounter_id:started?enc:null,age:35,reason:'Motivo original autorizado',symptoms:['Fiebre'],room_code:'C-1',duration_minutes:30}],tests:[{id:1,code:'1',name:'Estudio de catálogo de prueba'}],medications:[{id,name:'Medicamento de prueba',strength:'Concentración de catálogo'}],orders,notifications:[],stats:{consultations:1,completed_consultations:closed?1:0,issued_orders:orders.length,pending_orders:orders.length}}};
  if(url.endsWith('/rpc/doctor_native_chart'))return {body:{patient:{id,full_name:'Paciente autorizado',record_number:'EXP-PRUEBA'},allergies:['Antecedente autorizado'],conditions:[],medical_history:[],history:started?[{id:enc,started_at:new Date().toISOString(),status:closed?'closed':'open',...notes,note_id:version?enc:null,note_version:version,row_version:version,vitals:notes.vitals||{}}]:[],prescriptions}};
  if(url.endsWith('/rpc/doctor_native_start')){started=true;return {body:enc};}
  if(url.endsWith('/rpc/doctor_native_save')){assert.equal(p.p_version,version);version++;notes=p.p_values;return {body:version};}
  if(url.endsWith('/rpc/doctor_native_labs')){orders=[{id:p.p_key,patient_name:'Paciente autorizado',test_name:'Estudio de catálogo de prueba',status:'pendiente',reason:p.p_reason,ordered_at:new Date().toISOString()}];return {body:{order_ids:[p.p_key],count:1}};}
  if(url.endsWith('/rpc/doctor_native_prescribe')){prescriptions=[{id:p.p_key,code:'REC-PRUEBA',issued_at:new Date().toISOString(),status:'pendiente',lines:['Receta autorizada de prueba']}];return {body:p.p_key};}
  if(url.endsWith('/rpc/doctor_native_finish')){assert.equal(p.p_version,version);closed=true;version++;return {body:null};}
}});
await ui.login();assert.match(ui.app.textContent,/Médico autorizado/);assert.match(ui.app.textContent,/PRÓXIMA CITA/);
await ui.click('Agenda');await ui.click('Ver detalle de Paciente autorizado');await ui.click('Abrir atención');
assert.match(ui.app.textContent,/Motivo original autorizado/);assert.match(ui.app.textContent,/Fiebre/);
await ui.click('Iniciar consulta');
for(const [label,value] of [['Motivo y síntomas','Motivo revisado'],['Exploración física','Exploración registrada'],['Diagnóstico y evaluación clínica','Evaluación registrada'],['Plan e indicaciones','Tratamiento registrado']])await ui.input(label,value);
await ui.submit('Guardar consulta');assert.equal(version,1);
await ui.click('Emitir orden de laboratorio');await ui.click('Seleccionar Estudio de catálogo de prueba');await ui.input('Motivo e indicaciones clínicas','Motivo de orden');await ui.click('Revisar y enviar exámenes');await ui.click('Confirmar exámenes');assert.equal(orders.length,1);
await ui.click('Inicio');await ui.click('Recetas');
for(const [label,value,event] of [['Medicamento y concentración',id,'change'],['Unidad de dosis','unidad'],['Vía','oral','change'],['Dosis','1'],['Cada cuántas horas','8'],['Duración en días','3'],['Cantidad total','9'],['Indicaciones de receta','Indicaciones registradas']])await ui.input(label,value,event||'input');
await ui.submit('Añadir medicamento');await ui.click('Emitir receta autorizada');assert.equal(prescriptions.length,1);
await ui.click('Consultas');await ui.click('Confirmar firma y cierre');assert.equal(closed,true);
const lab=ui.calls.find(c=>c.url.endsWith('/doctor_native_labs')),rx=ui.calls.find(c=>c.url.endsWith('/doctor_native_prescribe'));
assert.deepEqual(lab.params.p_tests,[1]);assert.equal(rx.params.p_lines[0].duration_days,3);
for(const call of ui.calls.filter(c=>c.url.includes('/doctor_native_'))){assert.equal('doctor_id' in (call.params||{}),false);assert.equal('user_id' in (call.params||{}),false);}
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Réplica Doctor: Dashboard → agenda → paciente/síntomas → borrador → laboratorio/receta → cierre; mismo contrato que iOS');
