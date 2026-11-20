// Reglas clínicas compartidas (HospitalCore.doctorClinical), espejo de DoctorClinicalRules en Swift.
// Sin red ni datos clínicos: solo valores sintéticos.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const context = {Intl, Date, Math, Number, String, isFinite};
runInNewContext(readFileSync(new URL('../HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js', import.meta.url), 'utf8'), context);
const c = context.HospitalCore.doctorClinical;

// Orden cronológico real en America/El_Salvador (UTC−6), nunca por texto.
const at = (day, time, status, name) => ({id:name, status, patient_name:name,
  period:'["' + new Date(day + 'T' + time + ':00-06:00').toISOString().replace('T',' ').replace('.000Z','+00') + '","x")'});
const agenda = c.agenda([at('2026-11-20','08:30','scheduled','C'), at('2026-11-20','10:00','confirmed','D'), at('2026-11-20','06:00','scheduled','A'),
  at('2026-11-20','07:00','in_progress','B'), at('2026-11-21','06:00','scheduled','Mañana'), at('2026-11-20','05:00','completed','Hecha'),
  at('2026-11-20','09:00','cancelled','Cancelada'), at('2026-11-20','23:30','scheduled','Noche')], '2026-11-20');
assert.deepEqual(Array.from(agenda.day,a => a.patient_name), ['A','B','C','D','Noche'], '23:30 de El Salvador sigue siendo el mismo día aunque en UTC sea el siguiente');
assert.deepEqual(Array.from(agenda.upcoming,a => a.patient_name), ['Mañana']);
assert.deepEqual(Array.from(agenda.completed,a => a.patient_name), ['Hecha']);
assert.deepEqual(Array.from(agenda.cancelled,a => a.patient_name), ['Cancelada']);
assert.deepEqual({...c.dayWindow('2026-11-20', 14)}, {from:'2026-11-20T06:00:00.000Z', to:'2026-12-04T06:00:00.000Z'});
assert.equal(c.addDays('2026-11-30', 1), '2026-12-01');
// Agenda de dos filtros: PENDIENTES por hora; FINALIZADAS por hora real (finished_at) y la última primero; canceladas fuera.
const two=[at('2026-11-20','08:00','scheduled','Ocho'),at('2026-11-20','06:00','confirmed','Seis'),at('2026-11-19','23:30','in_progress','Ayer abierta'),at('2026-11-19','09:00','scheduled','Ayer pendiente'),
  at('2026-11-20','07:00','cancelled','Cancelada'),{...at('2026-11-19','23:00','completed','Tarde'),finished_at:'2026-11-20T06:20:00.123456+00:00'},{...at('2026-11-20','06:30','completed','Diez'),finished_at:'2026-11-20T16:00:00Z'}];
assert.deepEqual(Array.from(c.pending(two,'2026-11-20','2026-11-20'),a=>a.patient_name),['Ayer abierta','Seis','Ocho']);
assert.deepEqual(Array.from(c.pending(two,'2026-11-19','2026-11-20'),a=>a.patient_name),['Ayer pendiente','Ayer abierta']);
assert.deepEqual(Array.from(c.finished(two,'2026-11-20'),a=>a.patient_name),['Diez','Tarde'],'Fecha y hora real de finalización');
assert.equal(c.finished(two,'2026-11-19').length,0);
assert.equal(c.matches({patient_name:'José Pérez',patient_code:'PAC-1',record_number:'EXP-9'},'jose perez'),true);
assert.equal(c.matches({patient_name:'José Pérez'},'ana'),false);
assert.equal(Array.from(c.agenda(two,'2026-11-20').day,a=>a.patient_name).includes('Ayer pendiente'),false,'Días previos no cuentan como citas del día');
assert.throws(() => c.dayWindow('20-11-2026', 1));

// Etiquetas visibles (estados internos sin cambios): Pendiente, En consulta, Atendida, No atendida y Cancelada.
assert.deepEqual(['scheduled','confirmed','in_progress','completed','no_show','cancelled'].map(v => c.statusLabel(v)), ['Pendiente','Pendiente','En consulta','Atendida','No atendida','Cancelada']);

// Datos físicos: solo peso, altura y temperatura; sin texto, rangos de doctor_native_save e IMC calculado.
assert.deepEqual(Array.from(c.vitals, v => v.key), ['weight_kg','height_cm','temperature_c']);
assert.deepEqual(Array.from(c.recordedVitals, v => v.key), ['weight_kg','height_cm','temperature_c','systolic','diastolic','heart_rate'], 'El historial sigue mostrando medidas antiguas');
assert.equal(c.sanitize('7a0,5kg', false), '70.5');
assert.equal(c.sanitize('12.5', true), '125');
assert.deepEqual({...c.vitalIssues({weight_kg:'70.5', height_cm:'170', temperature_c:'36.8', systolic:'80', diastolic:'90'})}, {}, 'Las medidas antiguas conservadas no bloquean');
assert.ok(c.vitalIssues({temperature_c:'60'}).temperature_c);
assert.ok(c.vitalIssues({weight_kg:'0'}).weight_kg);
assert.ok(c.vitalIssues({height_cm:'301'}).height_cm);
assert.ok(c.vitalIssues({temperature_c:'24.9'}).temperature_c);
assert.equal(c.bmi({weight_kg:'70', height_cm:'170'}), '24.2');
assert.equal(c.bmi({weight_kg:'70'}), null, 'No inventa IMC sin altura');
assert.equal(c.vitals.some(v => ['respiratory_rate','oxygen_saturation'].includes(v.key)), false, 'Solo columnas existentes de vital_signs');

// Tres campos obligatorios (síntomas, diagnóstico, observaciones); `plan` ya no se exige en el formulario.
assert.deepEqual([...c.missingSections({subjective:'a', objective:' ', assessment:'', plan:''})], ['Exploración y observaciones','Diagnóstico','Plan de tratamiento']);
assert.deepEqual([...c.missingSections({subjective:'a', objective:'b', assessment:'c', plan:'d'})], [], 'Las cuatro notas que exige doctor_native_finish');
assert.equal(c.statusLabel('no_show'),'No atendida');
assert.equal(c.seedSubjective({reason:'Dolor de garganta', symptoms:['Fiebre',' Tos '], other_symptoms:'Dolor al tragar'}), 'Síntomas referidos por el paciente: Fiebre, Tos\nOtros síntomas: Dolor al tragar', 'El motivo se muestra aparte');
// Servidor sin la migración: se explica la causa sin inventar un plan.
assert.match(c.finishError('Completa motivo, exploración, diagnóstico y tratamiento', {plan:''}), /doctor-consultation-six-fields\.sql/);
assert.equal(c.finishError('Otro error', {plan:''}), 'Otro error');
assert.equal(c.finishError('Completa motivo, exploración, diagnóstico y tratamiento', {plan:'Plan anterior'}), 'Completa motivo, exploración, diagnóstico y tratamiento');

// Apertura: sin límite de hora mientras se hacen pruebas; con 30 minutos la regla original sigue funcionando;
// canceladas no se abren; una consulta existente se continúa.
const now = new Date('2026-11-20T12:00:00Z');
const slot = (minutes, status = 'scheduled', encounter = null) => ({status, encounter_id:encounter, period:'["' + new Date(now.getTime() + minutes * 60000).toISOString() + '","x")'});
assert.equal(c.openingBlocker(slot(20), now), null);
assert.equal(c.openingLeadMinutes, null);
assert.equal(c.openingBlocker(slot(60 * 24 * 3), now), null, 'Una cita de dentro de 3 días puede abrirse');
assert.match(c.openingBlocker(slot(45), now, 30), /30 minutos/);
assert.match(c.startError('La cita todavía no puede iniciarse o ya finalizó'), /doctor-start-anytime\.sql/, 'Explica si el servidor aún tiene la regla');
assert.equal(c.startError('Cita no asignada'), null);
assert.match(c.openingBlocker(slot(0, 'cancelled'), now), /cancelada/);
assert.equal(c.openingBlocker(slot(45, 'in_progress', 'enc'), now), null);
console.log('OK Reglas clínicas compartidas: orden en hora de El Salvador, estados, datos físicos/IMC, tres campos obligatorios, aviso de migración y ventana de apertura');
