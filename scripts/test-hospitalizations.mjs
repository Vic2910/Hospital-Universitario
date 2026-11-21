// Hospitalizaciones (HospitalCore.hospitalizations + plan/present). Transporte simulado: no llama a Supabase.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const context = { console }; context.globalThis = context; vm.createContext(context);
vm.runInContext(readFileSync(new URL('../HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js', import.meta.url), 'utf8'), context);
const C = context.HospitalCore, H = C.hospitalizations;
const auth = { profile: { id: '11111111-1111-4111-8111-111111111111' }, patient_id: '22222222-2222-4222-8222-222222222222', staff_id: null };

// Escenario A: sin hospitalización → estado vacío, sin ejemplos.
assert.deepEqual(JSON.parse(JSON.stringify(H.present([]))), { active: null, previous: [] });
assert.equal(C.backendPlan('hospitalizations', {}, { ...auth, patient_id: null }).length, 0, 'Sin expediente no se consulta');
const plan = C.backendPlan('hospitalizations', {}, auth);
assert.equal(plan[0].path, '/rest/v1/rpc/my_hospitalizations'); assert.deepEqual(JSON.parse(JSON.stringify(plan[0].body)), {}, 'No se envía patient_id del paciente');
const doc = C.backendPlan('hospitalizations', { patient: auth.patient_id }, { ...auth, patient_id: null, staff_id: auth.patient_id });
assert.equal(doc[0].path, '/rest/v1/rpc/doctor_native_patient_hospitalizations');
console.log('OK Escenario A: estado vacío y RPC por identidad');

// Escenario B: ingreso activo con habitación real.
const active = { id: 'a1', status: 'hospitalizado', ordered_at: '2026-11-18T15:00:00Z', doctor_name: 'Ana Ruiz', reason: 'Observación', hospital_name: 'Hospital Universitario',
  assignments: [{ room: '204', room_kind: 'semiprivada', bed: 'A', floor: 'Segundo piso', assigned_at: '2026-11-18T15:30:00Z', released_at: null }] };
let r = H.present([active]);
assert.equal(r.active.room, '204'); assert.equal(r.active.room_kind, 'Semiprivada'); assert.equal(r.active.status_label, 'Hospitalizado');
assert.equal(r.active.admitted_date, '18 de noviembre de 2026'); assert.equal(r.active.admitted_time, '9:30 a. m.');
assert.ok(!JSON.stringify(r.active.sections).includes('Sin registrar'), 'No se presentan campos vacíos');
assert.ok(!r.active.sections.some(s => s.title === 'Alta médica'), 'Sin alta no hay sección de alta');
console.log('OK Escenario B: hospitalización activa');

// Escenario C: traslado conserva historial y actualiza la habitación actual.
r = H.present([{ ...active, assignments: [{ room: '201', room_kind: 'semiprivada', assigned_at: '2026-11-18T15:30:00Z', released_at: '2026-11-19T15:00:00Z' }, { room: 'VIP-302', room_kind: 'vip', assigned_at: '2026-11-19T15:00:00Z', released_at: null }] }]);
assert.equal(r.active.room, 'VIP-302'); assert.equal(r.active.room_kind, 'VIP'); assert.equal(r.active.transfers.length, 2); assert.equal(r.active.transfers[1].until, null);
assert.equal(r.active.admitted_time, '9:30 a. m.', 'El ingreso es la primera asignación');
console.log('OK Escenario C: traslado de habitación');

// Escenario D: alta médica → anteriores, con fecha y hora.
for (const status of ['alta_medica', 'cerrado']) {
  r = H.present([{ ...active, status, discharged_at: '2026-11-22T17:15:00Z', discharged_by_name: 'Ana Ruiz' }]);
  assert.equal(r.active, null); assert.equal(r.previous.length, 1); assert.equal(r.previous[0].status_label, 'Alta médica');
  assert.equal(r.previous[0].discharged_date, '22 de noviembre de 2026'); assert.equal(r.previous[0].discharged_time, '11:15 a. m.');
}
assert.equal(H.present([{ ...active, status: 'cancelado' }, { ...active, id: 'x', status: 'solicitado' }]).previous.length, 0, 'Solicitudes y cancelados no son estancias');
console.log('OK Escenario D: alta médica en hospitalizaciones anteriores');

const kinds = H.kindLabel('vip') + '|' + H.kindLabel('semiprivada');
assert.equal(kinds, 'VIP|Semiprivada');
const sql = readFileSync(new URL('../supabase/hospitalizaciones-paciente.sql', import.meta.url), 'utf8');
assert.match(sql, /treats_patient\(p_patient\)/); assert.match(sql, /profile_id = auth\.uid\(\)/); assert.doesNotMatch(sql, /CREATE TABLE|DELETE FROM/i);
console.log('OK Escenario E (estático): RPC con identidad del paciente y relación asistencial; sin tablas nuevas ni borrados');
