// Same native RPC contract as Swift; simulated HTTP, no production writes.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const patient={id:'00000000-0000-4000-8000-000000000031',full_name:'Paciente de ingreso local',record_number:'EXP-LOCAL',dui:'01234567-8',email:'ingreso@example.test',age:34,active_encounter_id:null};
const requests=[];let loseResponse=true,emptyCatalog=false;
const ui=createApp(['doctor'],{transport:async(url,p)=>{
  if(url.endsWith('/doctor_native_admissions'))return{body:{items:requests,total:requests.length,has_more:false,next_offset:null,doctor_name:'Doctor de prueba',categories:emptyCatalog?[]:['vip','semiprivada'],priorities:['normal','urgente']}};
  if(url.endsWith('/doctor_native_patients'))return{body:{patients:[patient],total:1,has_more:false,next_offset:null}};
  if(url.endsWith('/doctor_native_chart'))return{body:{patient:{...patient,identification:patient.dui},allergies:[],conditions:[],history:[],prescriptions:[]}};
  if(url.endsWith('/doctor_native_admission_request')){
    assert.equal(p.p_patient,patient.id);assert.equal(p.p_priority,'urgente');assert.equal(p.p_kind,'semiprivada');assert.equal(p.p_encounter,null);
    assert.equal('ordered_by'in p,false);assert.equal('p_bed'in p,false);
    if(!requests.length)requests.push({id:p.p_key,patient_id:patient.id,patient_name:patient.full_name,record_number:patient.record_number,doctor_name:'Doctor de prueba',category:p.p_kind,priority:p.p_priority,reason:p.p_reason,observations:p.p_instructions,status:'solicitado',ordered_at:new Date().toISOString(),assignment:null,history:[]});
    if(loseResponse){loseResponse=false;throw new TypeError('Respuesta de red perdida');}
    return{body:requests[0].id};
  }
}});
await ui.login();await ui.click('Ingresos hospitalarios');
assert.match(ui.app.textContent,/Sin solicitudes/);
await ui.click('Nueva solicitud');
await ui.click('Seleccionar paciente '+patient.full_name);assert.match(ui.app.textContent,/EXP-LOCAL/);
await ui.input('Categoría de habitación','semiprivada','change');await ui.input('Prioridad','urgente','change');
await ui.input('Motivo clínico del ingreso','Motivo médico local');await ui.input('Observaciones e indicaciones (opcional)','Observación local');
await ui.click('Revisar y enviar solicitud');
assert.equal(ui.calls.some(c=>c.url.endsWith('/doctor_native_admission_request')),false,'Confirmación explícita antes de enviar');
await ui.click('Confirmar envío');
assert.match(ui.app.textContent,/Envío sin confirmar/);
await ui.click('Reintentar el mismo envío');
const sent=ui.calls.filter(c=>c.url.endsWith('/doctor_native_admission_request'));
assert.equal(sent.length,2);assert.deepEqual(sent[0].params,sent[1].params);assert.equal(requests.length,1);
assert.match(ui.app.textContent,/Pendiente de recepción/);assert.match(ui.app.textContent,/Motivo médico local/);
requests[0].status='hospitalizado';requests[0].assignment={room:'LOCAL-ROOM',bed:'LOCAL-BED',floor:'Piso local',assigned_at:new Date().toISOString()};
await ui.click('Actualizar solicitudes');assert.match(ui.app.textContent,/Ingresado/);assert.match(ui.app.textContent,/LOCAL-ROOM · LOCAL-BED/);
requests[0].status='cancelado';requests[0].assignment=null;requests[0].decision='rechazada';requests[0].decision_reason='Justificación local';
await ui.click('Actualizar solicitudes');assert.match(ui.app.textContent,/Rechazada/);assert.match(ui.app.textContent,/Justificación local/);
emptyCatalog=true;await ui.click('Actualizar solicitudes');await ui.click('Nueva solicitud');assert.match(ui.app.textContent,/No hay categorías disponibles/);
await ui.input('Categoría de habitación','vip','change');await ui.input('Motivo clínico del ingreso','No debe enviarse');await ui.click('Revisar y enviar solicitud');
assert.equal(ui.calls.filter(c=>c.url.endsWith('/doctor_native_admission_request')).length,2);
assert.equal(ui.calls.some(c=>/assign_bed|reception_resolve_admission/.test(c.url)),false);
await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
console.log('OK Ingresos doctor: paciente autorizado, categorías/prioridad reales, confirmación, reintento idéntico, seguimiento, asignación/rechazo, catálogo vacío y logout');
