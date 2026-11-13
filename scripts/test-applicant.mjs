// Pruebas del solicitante sin expediente: reglas compartidas y vista de diseño web.
// Solo datos simulados: no hay llamadas de red ni consultas a Supabase.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';

const root = new URL('../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const context = createContext({ Date, console });
runInContext(read('HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js'), context);
runInContext(read('web-preview/applicant.js'), context);
const core = context.HospitalCore;
const DemoClass = context.HospitalApplicantDemo;

const dayOffset = days => core.localIsoDay(new Date(Date.now() + days * 86400000));
const future = dayOffset(10);
const past = '2000-01-01';

// Reglas compartidas (las mismas que usa iOS mediante JavaScriptCore).
assert.equal(core.formatDui('0123456789'), '01234567-8');
assert.equal(core.formatDui('01234'), '01234', 'formato progresivo mientras se escribe');
assert.equal(core.formatDui(' 12-34 x'), '1234');
assert.equal(core.applicantAge('1995-03-10', '2026-11-12'), 31);
assert.equal(core.applicantAge('1995-11-13', '2026-11-12'), 30, 'el cumpleaños aún no ocurre');
assert.equal(core.applicantAge('2026-02-30', '2026-11-12'), null, 'fecha inexistente');
assert.equal(core.applicantAge(null, '2026-11-12'), null);
const person = { given: 'Ana', family: 'Prueba', birthDate: '1995-03-10', dui: '0123-45678', phone: '7000-1111' };
assert.equal(core.validatePersonalData(person, '2026-11-12'), null);
assert.equal(core.validatePersonalData({ ...person, given: '  ' }, '2026-11-12').field, 'given');
assert.equal(core.validatePersonalData({ ...person, birthDate: '2030-01-01' }, '2026-11-12').field, 'birthDate', 'fecha futura');
assert.equal(core.validatePersonalData({ ...person, birthDate: '1800-01-01' }, '2026-11-12').field, 'birthDate', 'mayor de 120 años');
assert.equal(core.validatePersonalData({ ...person, dui: '1234' }, '2026-11-12').field, 'dui');
assert.equal(core.validatePersonalData({ ...person, phone: 'abc' }, '2026-11-12').field, 'phone');
const account = { ...person, email: 'ana@correo.test', password: 'clave-segura', confirm: 'clave-segura' };
assert.equal(core.validateApplicantProfile(account, '2026-11-12'), null);
assert.equal(core.validateApplicantProfile({ ...account, email: 'sin-arroba' }, '2026-11-12').field, 'email');
assert.equal(core.validateApplicantProfile({ ...account, password: 'corta', confirm: 'corta' }, '2026-11-12').field, 'password');
assert.equal(core.validateApplicantProfile({ ...account, confirm: 'otra-clave!' }, '2026-11-12').field, 'confirm');
const request = { specialty: 'Medicina general', reason: 'Control general', date: future, period: 'morning' };
assert.equal(core.validateAttentionRequest(request), null);
assert.equal(core.validateAttentionRequest({ ...request, specialty: '' }).field, 'specialty');
assert.equal(core.validateAttentionRequest({ ...request, reason: '   ' }).field, 'reason');
assert.equal(core.validateAttentionRequest({ ...request, date: past }).field, 'date', 'fecha anterior a hoy');
assert.equal(core.validateAttentionRequest({ ...request, period: '' }).field, 'period');
// Estados de interfaz frente a valores reales del backend.
const state = (status, appointment) => JSON.parse(JSON.stringify(core.applicantStateView(status, appointment)));
assert.deepEqual(state('pending', null), { key: 'pending', label: 'Pendiente' });
assert.deepEqual(state('identity_verified', null), { key: 'review', label: 'En revisión' });
assert.deepEqual(state('converted', null), { key: 'accepted', label: 'Aceptada' });
assert.deepEqual(state('converted', 'pending'), { key: 'accepted', label: 'Aceptada' }, 'cita pendiente no es programada');
assert.deepEqual(state('converted', 'scheduled'), { key: 'scheduled', label: 'Cita programada' });
assert.deepEqual(state('rejected', null), { key: 'rejected', label: 'Rechazada' });
assert.deepEqual(state('cancelled', null), { key: 'cancelled', label: 'Cancelada' });
assert.deepEqual(state('desconocido', null), { key: 'unknown', label: 'Estado no disponible' });
console.log('OK Reglas compartidas: DUI, edad por fecha de nacimiento, validaciones, solicitud y estados');

// DOM simulado mínimo para ejecutar la vista de diseño sin navegador.
class FakeNode {
  constructor(tag, text, className) {
    Object.assign(this, { tagName: tag, children: [], listeners: {}, attributes: {}, value: '', className: className || '', hidden: false, id: '' });
    this._text = text ?? '';
  }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
  set textContent(value) { this._text = String(value); this.children = []; }
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this._text = ''; this.children = nodes; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  addEventListener(type, callback) { (this.listeners[type] ||= []).push(callback); }
  dispatch(type, event = {}) { for (const callback of this.listeners[type] || []) callback({ preventDefault() {}, target: this, ...event }); }
  all() { return [this, ...this.children.flatMap(child => child.all())]; }
}
const findButton = (scope, text) => scope.all().find(node => node.tagName === 'button' && node.textContent === text);
const findInput = (scope, id) => scope.all().find(node => node.id === id);
const findForm = scope => scope.all().find(node => node.tagName === 'form');

const app = new FakeNode('div');
const messages = [];
let exits = 0;
const demo = new DemoClass({
  el: (tag, text, className) => new FakeNode(tag, text, className),
  button: (text, action, className) => { const node = new FakeNode('button', text, className); node.addEventListener('click', action); return node; },
  header: (title, subtitle) => new FakeNode('header', `${title} ${subtitle}`),
  message: text => messages.push(text),
  rerender: () => demo.render(app),
  exit: () => { exits += 1; },
});
demo.open();
demo.render(app);

// Datos personales: validación y formato automático del DUI.
assert.ok(app.textContent.includes('Completa tus datos'));
assert.ok(app.textContent.includes('Tu cuenta no tiene expediente clínico'));
const dui = findInput(app, 'ap-dui');
dui.value = '012345678';
dui.dispatch('input');
assert.equal(dui.value, '01234567-8', 'DUI con formato automático');
const form = findForm(app);
form.dispatch('submit');
assert.ok(app.textContent.includes('Introduce tus nombres'), 'validación de nombres');
findInput(app, 'ap-given').value = 'Ana';
findInput(app, 'ap-family').value = 'Prueba';
findInput(app, 'ap-birth').value = '2030-01-01';
findInput(app, 'ap-phone').value = '7000-1111';
form.dispatch('submit');
assert.ok(app.textContent.includes('fecha de nacimiento válida'), 'fecha futura rechazada');
findInput(app, 'ap-birth').value = person.birthDate;
form.dispatch('submit');
assert.ok(app.textContent.includes('Inicio'), 'datos válidos llevan al inicio');
assert.ok(app.textContent.includes('Todavía no tienes expediente'));
assert.ok(findButton(app, 'Salir de la demostración'), 'navegación disponible');
console.log('OK Datos personales: DUI automático, fecha de nacimiento y validaciones');

// Solicitud de atención: sin cita, con preferencia obligatoria.
findButton(app, 'Solicitar atención').dispatch('click');
assert.ok(app.textContent.includes('Esta solicitud no reserva ninguna cita'));
const specialty = findInput(app, 'ap-specialty');
specialty.value = 'Medicina general';
specialty.dispatch('change');
const reason = findInput(app, 'ap-reason');
reason.value = 'Control de presión';
reason.dispatch('input');
const date = findInput(app, 'ap-date');
date.value = future;
date.dispatch('change');
findForm(app).dispatch('submit');
assert.ok(app.textContent.includes('Elige la preferencia Mañana o Tarde'), 'preferencia obligatoria');
findButton(app, 'Tarde · PM').dispatch('click');
findForm(app).dispatch('submit');
assert.ok(app.textContent.includes('Mis solicitudes'), 'envío lleva a la lista');
assert.ok(app.textContent.toLowerCase().includes('una solicitud no es una cita'), 'aviso de no cita');
assert.ok(app.textContent.includes('Pendiente'));
assert.equal(app.textContent.includes('Cita programada'), false, 'no se crea cita al solicitar');
assert.equal(app.textContent.includes('Cita de ejemplo'), false);
console.log('OK Solicitud: preferencia obligatoria, Pendiente y sin cita generada');

// Estados: avance de ejemplo hasta cita programada, identificada como ejemplo.
findButton(app, 'Simular avance de recepción (ejemplo)').dispatch('click');
assert.ok(app.textContent.includes('En revisión'));
findButton(app, 'Simular avance de recepción (ejemplo)').dispatch('click');
assert.ok(app.textContent.includes('Aceptada'));
findButton(app, 'Simular avance de recepción (ejemplo)').dispatch('click');
assert.ok(app.textContent.includes('Cita programada'));
assert.ok(app.textContent.includes('Cita de ejemplo: la programa recepción en el sistema real.'));
assert.equal(findButton(app, 'Simular avance de recepción (ejemplo)'), undefined, 'estado final sin más avances');
console.log('OK Estados visibles: Pendiente, En revisión, Aceptada, Cita programada (ejemplo)');

// Ejemplos de estados rechazada y cancelada, identificados como ejemplos.
findButton(app, 'Mostrar ejemplos de rechazada y cancelada').dispatch('click');
assert.ok(app.textContent.includes('Rechazada') && app.textContent.includes('Cancelada'));
assert.ok(app.textContent.includes('Motivo: Ejemplo: la especialidad no tiene agenda en esa fecha.'));
assert.ok(app.textContent.toLowerCase().includes('no es una cita'));
assert.equal(app.textContent.includes('Cita programada') && !app.textContent.includes('Cita de ejemplo'), false, 'los ejemplos no son citas');
assert.ok(/\d{1,2} \w{3}\.? \d{4}/.test(app.textContent), 'fecha legible, no ISO');
console.log('OK Ejemplos rechazada y cancelada con motivo; fecha legible; identificados como no citas');

// Navegación y salida. Sin llamadas de red.
findButton(app, 'Inicio').dispatch('click');
assert.ok(app.textContent.includes('Hola, Ana'));
findButton(app, 'Salir de la demostración').dispatch('click');
assert.equal(exits, 1);
demo.close();
assert.equal(demo.active, false);
assert.equal(demo.person, null, 'al cerrar no quedan datos en memoria');
assert.equal(demo.requests.length, 0);
console.log('OK Navegación y salida sin datos residuales');
