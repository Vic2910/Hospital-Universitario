// Ambulancia del médico: mismo contrato que Swift (HospitalAPI.doctorTransport); HTTP simulado, sin escrituras en producción.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const patient={id:'00000000-0000-4000-8000-000000000041',full_name:'Paciente de traslado local',record_number:'EXP-AMB',dui:'07654321-0',phone:'7000-1111',email:'traslado@example.test',age:52,active_encounter_id:null};
const requests=[],sent=[];let loseResponse=true;
const ui=createApp(['doctor'],{transport:async(url,p)=>{
  if(url.includes('/rest/v1/ambulances?'))return{body:[{code:'AMB-001',status:'disponible',active:true}]};
  if(url.includes('/rest/v1/ambulance_requests?'))return{body:requests};
  if(url.endsWith('/doctor_native_patients'))return{body:{patients:[patient],total:1,has_more:false,next_offset:null}};
  if(url.endsWith('/doctor_native_chart'))return{body:{patient:{...patient,identification:patient.dui},allergies:[],conditions:[],history:[],prescriptions:[]}};
  if(url.endsWith('/rpc/request_medical_transport')){
    sent.push(p);
    // Solo los parámetros de la RPC: el servidor fija solicitante, estado y unidad.
    assert.deepEqual(Object.keys(p).sort(),['p_contact','p_destination','p_key','p_origin','p_patient','p_phone','p_priority','p_reason']);
    assert.equal(p.p_patient,patient.id);assert.equal(p.p_priority,'urgente');
    if(!requests.length)requests.push({id:'00000000-0000-4000-8000-0000000000a1',patient_id:p.p_patient,contact_name:p.p_contact,contact_phone:p.p_phone,
      pickup_location:p.p_origin,destination:p.p_destination,reason:p.p_reason,priority:p.p_priority,status:'pendiente',requested_at:new Date().toISOString(),decision_reason:null,
      patient:{first_name:'Paciente de traslado',last_name:'local'}});
    if(loseResponse){loseResponse=false;throw new TypeError('Respuesta de red perdida');}
    return{body:requests[0].id};
  }
}});
const wait=()=>new Promise(resolve=>setTimeout(resolve,420));
await ui.login();
await ui.click(ui.app.all().find(node=>node.tagName==='button'&&/Ambulancia/.test(node.textContent))?.textContent||'Más');
if(!/Solicita el traslado/.test(ui.app.textContent))await ui.click(ui.app.all().find(node=>node.tagName==='button'&&/^Ambulancia/.test(node.textContent)).textContent);
assert.match(ui.app.textContent,/Unidad AMB-001/);assert.match(ui.app.textContent,/Disponible/);assert.match(ui.app.textContent,/Sin traslados/);

await ui.click('Solicitar ambulancia');
assert.equal(ui.app.textContent.includes(patient.full_name),false,'No aparece el listado de pacientes al abrir');
await ui.click('Revisar y solicitar');
assert.equal(sent.length,0,'Sin paciente no se envía nada');
await ui.input('Buscar paciente para trasladar','traslado');await wait();
await ui.click('Seleccionar paciente '+patient.full_name);assert.match(ui.app.textContent,/EXP-AMB/);
assert.equal(ui.app.all().find(node=>node.attributes?.['aria-label']==='Persona de contacto').value,patient.full_name,'Contacto propuesto desde el paciente');
assert.equal(ui.app.all().find(node=>node.attributes?.['aria-label']==='Teléfono de contacto').value,patient.phone,'Teléfono propuesto desde el paciente');
await ui.input('Origen (lugar de recogida)','Domicilio del paciente');await ui.input('Destino','Hospital Universitario, emergencias');
await ui.input('Prioridad','urgente','change');await ui.input('Motivo del traslado','Traslado local de prueba');
await ui.click('Revisar y solicitar');
assert.equal(sent.length,0,'Confirmación explícita antes de enviar');assert.match(ui.app.textContent,/Domicilio del paciente → Hospital Universitario, emergencias · Urgente/);

// Primera respuesta perdida: se conserva el envío y se reintenta con la misma clave, sin duplicar.
await ui.click('Confirmar solicitud');
assert.equal(sent.length,1);assert.match(ui.app.textContent,/Reintentar el mismo envío/);
await ui.click('Reintentar el mismo envío');
assert.equal(sent.length,2);assert.equal(sent[0].p_key,sent[1].p_key,'Misma clave al reintentar');assert.equal(requests.length,1,'Sin duplicados');
assert.match(ui.get('notice').textContent,/Solicitud de ambulancia enviada/);
assert.match(ui.app.textContent,/Pendiente de autorización/);assert.match(ui.app.textContent,/Paciente de traslado local/);
assert.equal(ui.app.textContent.includes('Nueva solicitud de ambulancia'),false,'El formulario se cierra al confirmar');
console.log('OK Ambulancia doctor: unidad, paciente autorizado, contacto propuesto, confirmación explícita, reintento con la misma clave y listado sin duplicados');
