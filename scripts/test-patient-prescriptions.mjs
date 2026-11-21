// Mis recetas: cada campo de prescription_items en su lugar (antes todo caía en Observaciones). Sin red.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const context={console,Date,Intl,Math,JSON,encodeURIComponent,URL,Number,String,Array,Object};context.globalThis=context;
runInNewContext(read('HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js'),context);
runInNewContext(read('web-preview/patient-prescriptions.js'),context);
const core=context.HospitalCore,Parser=context.HospitalPatientPrescriptions;
const access={profile:{id:'00000000-0000-4000-8000-000000000001'},patient_id:'00000000-0000-4000-8000-000000000002',roles:[{code:'patient'}],identity:{first_name:'Paciente',last_name:'Prueba',phone:null},email:'paciente@example.test'};

const plan=core.backendPlan('module',{p_module:'prescriptions'},access);
const path=(plan[0]||plan).path||'';
assert.ok(decodeURIComponent(path).includes('duration_days'),'La consulta pide la duración');

const row={id:'00000000-0000-4000-8000-0000000000c1',prescription_code:'REC-1',status:'entregada',issued_at:'2026-11-21T03:35:43Z',
  prescription_items:[{dose:2,dose_unit:'tabletas',frequency_hours:8,route:'oral',duration_days:5,quantity:10,observations:'No tomar alcohol',medications:{name:'Acetaminofén',strength:'500 mg'}}]};
const page=core.backendPresent('module',{p_module:'prescriptions'},access,[[row]]);
const item=(page.items||[])[0];
assert.ok(item,'Hay un elemento de receta');
assert.deepEqual(JSON.parse(JSON.stringify(item.medicines)),[{name:'Acetaminofén 500 mg',dose:'2 tabletas',frequency:'Cada 8 horas',route:'oral',duration:'5 días',quantity:'10',observations:'No tomar alcohol'}]);

const [record]=Parser.fromItems([item]);
const med=record.medicines[0];
assert.equal(med.dose,'2 tabletas');assert.equal(med.frequency,'Cada 8 horas');assert.equal(med.route,'oral');
assert.equal(med.duration,'5 días');assert.equal(med.quantity,'10');assert.equal(med.observations,'No tomar alcohol');
assert.equal(record.pickup,'Retirada','Una receta entregada se muestra como retirada');
console.log('OK Mis recetas: dosis, frecuencia, vía, duración, cantidad y observaciones en su campo; entregada = retirada');
