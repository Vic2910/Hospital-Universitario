// DOM integration checks. Transport fixtures never modify the real database.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { webcrypto } from 'node:crypto';
const root = new URL('../', import.meta.url);
const read = name => readFileSync(new URL(name, root), 'utf8');
const contract = JSON.parse(read('HospitalUniversitario/HospitalUniversitario/Shared/contract.json'));
const catalog = JSON.parse(read('HospitalUniversitario/HospitalUniversitario/Shared/screens.json'));
const fixtures = JSON.parse(read('web-preview/design-fixtures.json'));
const uuid = '00000000-0000-4000-8000-000000000001';
class Element {
  constructor(tag) { this.tagName = tag; this.children = []; this.listeners = {}; this.attributes = {}; this.value = ''; this._text = ''; this.classList = { toggle() {} }; if (tag === 'textarea') Object.defineProperty(this,'type',{value:'textarea',writable:false}); }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this._text = ''; this.children = children; }
  setAttribute(name,value) { this.attributes[name] = value; }
  addEventListener(name,callback) { const previous = this.listeners[name]; this.listeners[name] = event => { previous?.(event); callback(event); }; }
  querySelector(selector) {
    if (selector.startsWith('#')) return this.all().find(node => node.id === selector.slice(1)) || null;
    const match = selector.match(/^\[data-choice="([^"]+)"\]$/);
    return match ? this.all().find(node => node.attributes['data-choice'] === match[1]) || null : null;
  }
  reportValidity() { return true; }
  all() { return [this, ...this.children.flatMap(child => child.all())]; }
}
const settle = () => new Promise(resolve => setImmediate(resolve));
const response = (body,status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body, text: async () => body == null ? '' : JSON.stringify(body) });
export function createApp(roleCodes = ['doctor'], options = {}) {
  const body = new Element('body');
  for (const id of ['app','notice','preview-mode','design-patient','design-doctor','live-mode','design-reception']) { const node = new Element(id.startsWith('design-') || id === 'live-mode' ? 'button' : 'div'); node.id = id; if (id === 'notice') node.hidden = true; body.append(node); }
  const find = predicate => body.all().find(predicate);
  const calls = [], stored = new Map();
  const storage = { getItem:key => stored.get(key) ?? null, setItem:(key,value) => stored.set(key,value), removeItem:key => stored.delete(key) };
  let aal = options.mfa || options.missingMFA ? 'aal1' : 'aal2';
  const access = () => ({ profile:{id:uuid,status:options.suspended ? 'suspended' : 'active',preferred_name:'Persona de prueba'}, roles:roleCodes.map(code => ({code,facility_id:uuid})), staff_id:roleCodes.includes('doctor') ? uuid : null, patient_id:roleCodes.includes('patient') ? uuid : null, aal });
  const record = name => Object.fromEntries(Object.entries(contract.models[name]).map(([field,type]) => [field,type.endsWith('?') ? null : type === 'UUID' ? uuid : ['Int','Int64'].includes(type) ? 1 : type === 'Bool' ? true : field === 'code' ? 'VIP-301' : field === 'period' ? '["2026-10-23 07:00:00-06","2026-10-23 15:00:00-06")' : field === 'status' ? (name === 'QueueTicket' ? 'waiting' : 'confirmed') : '2026-10-23T07:00:00-06:00']));
  const fetch = async (url,request) => {
    const params = request?.body && JSON.parse(request.body); calls.push({url,params,request});
    const custom = await options.transport?.(url,params,request);
    if (custom !== undefined) return response(custom.body,custom.status || 200);
    if (url === '/shared/contract.json') return response(contract);
    if (url === '/shared/screens.json') return response(catalog);
    if (url === '/design-fixtures.json') return response(fixtures);
    if (url.includes('/token?')) return response({access_token:'test',refresh_token:'test-refresh',expires_in:3600});
    if (url.endsWith('/auth/v1/user')) return response({factors:options.mfa ? [{id:uuid,factor_type:'totp',status:'verified'}] : []});
    if (url.endsWith('/challenge')) return response({id:uuid});
    if (url.endsWith('/verify')) { if (params.code !== '123456') return response({},422); aal = 'aal2'; return response({access_token:'aal2',refresh_token:'new-refresh',expires_in:3600}); }
    if (url.endsWith('/my_access')) return response(access());
    if (url.includes('/logout')) return response(null,204);
    if (url.endsWith('/my_profile')) return response({person:{given_names:'Persona',family_names:'de prueba'},auth_email:'persona@example.test',contacts:[],professional:null});
    if (url.endsWith('/my_activity_summary')) return options.summaryDenied ? response({},403) : response({upcoming_appointments:2,new_results:1,active_prescriptions:3,scheduled_appointments:12,waiting_patients:4,pending_prescriptions:2,tickets:[]});
    if (url.endsWith('/doctor_workspace')) return response({doctor_name:'Persona de prueba',facility_name:'Sede de prueba',appointments:[],orders:[],tests:[],notifications:[],stats:{consultations:0,completed_consultations:0,issued_orders:0,pending_orders:0}});
    if (url.endsWith('/mobile_module')) return response({items:[],sections:[],options:[],preferences:[],phone:null,emergency:null,has_more:false,next_cursor:null});
    if (url.endsWith('/my_queue_status')) return response({...fixtures.patient.queue,ticket_id:uuid});
    if (url.endsWith('/hospital_overview')) return response({capacity:17,occupied:0,information:[],on_duty:[]});
    if (url.endsWith('/read_resource')) return response({data:[record(({rooms:'Room',staff_shifts:'StaffShift',queue_tickets:'QueueTicket'})[params.p_resource])],has_more:false,next_cursor:null});
    throw new Error('Unexpected request: ' + url);
  };
  const context = {Date,Intl,console,URL,crypto:webcrypto,AbortSignal,fetch,setInterval(){},sessionStorage:storage,document:{body,hidden:false,querySelector:selector => find(node => node.id === selector.slice(1)),createElement:tag => new Element(tag),addEventListener(){}}};
  for (const path of ['HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js','web-preview/api.js','web-preview/modules.js','web-preview/doctor-dashboard.js','web-preview/clinical-labs.js','web-preview/patient-history.js','web-preview/patient-prescriptions.js','web-preview/patient-appointments.js','web-preview/app.js']) runInNewContext(read(path),context);
  const app = find(node => node.id === 'app');
  return {
    calls, stored, body, app,
    get(id) { const node = find(node => node.id === id); assert.ok(node,'Missing #' + id); return node; },
    button(text) { const node = app.all().find(node => node.tagName === 'button' && (node.textContent === text || node.attributes['aria-label'] === text)); assert.ok(node,'Missing button ' + text); return node; },
    async click(text) { const node = this.button(text); assert.equal(node.disabled,false,'Button disabled ' + text); node.listeners.click(); await settle(); },
    async input(label,value,event = 'input') { const node = app.all().find(item => item.attributes['aria-label'] === label); assert.ok(node,'Missing field ' + label); node.value = value; node.listeners[event]?.({target:node}); await settle(); },
    async submit(label,twice = false) { const form = app.all().find(node => node.tagName === 'form' && node.all().some(child => child.tagName === 'button' && child.textContent === label)); assert.ok(form,'Missing form ' + label); const event = {preventDefault(){}}; form.listeners.submit(event); if (twice) form.listeners.submit(event); await settle(); },
    async login() { await settle(); this.get('email').value = 'person@example.test'; this.get('password').value = 'test-password'; app.all().find(node => node.tagName === 'form').listeners.submit({preventDefault(){}}); await settle(); }
  };
}
for (const [codes,role] of [[['doctor'],'doctor'],[['patient'],'patient'],[['doctor','patient'],'patient']]) {
  const ui = createApp(codes); await ui.login();
  if (codes.length > 1) await ui.click(role === 'doctor' ? 'Médico' : 'Paciente');
  assert.match(ui.app.textContent,/Hola, Persona de prueba/);
  assert.equal(ui.app.textContent.includes('Mis citas'),role === 'patient');
  await ui.click('Más'); await ui.click((role === 'doctor' ? 'Mi horario' : 'Mi turno') + '　›');
  const query = ui.calls.findLast(call => call.params?.p_resource);
  assert.equal(query.params.p_resource,role === 'doctor' ? 'staff_shifts' : 'queue_tickets');
  assert.equal(query.params.p_filters[0].column,role === 'doctor' ? 'staff_id' : 'patient_id');
  if (role === 'patient') { assert.match(ui.app.textContent,/A-014/); assert.match(ui.app.textContent,/Personas antes de ti2/); }
  await ui.click('Más'); await ui.click('Habitaciones　›'); assert.match(ui.app.textContent,/VIP-301/);
  await ui.click('Más'); await ui.click('Cerrar sesión'); assert.ok(ui.get('password')); assert.equal(ui.stored.size,0);
  console.log(`OK Login real (transporte de prueba) → Inicio → ${role} → turnos → habitaciones → cierre`);
}
const mfa = createApp(['patient'],{mfa:true}); await mfa.login();
assert.match(mfa.app.textContent,/Hola,/);
assert.equal(mfa.calls.some(call => call.url.endsWith('/auth/v1/user') || call.url.includes('/factors/')),false);
assert.equal(mfa.app.all().some(node => node.id === 'totp'),false);
console.log('OK Login AAL1: portal sin desafio ni consultas de factores MFA');
const suspended = createApp(['patient'],{suspended:true}); await suspended.login(); assert.ok(suspended.get('password')); assert.equal(suspended.stored.size,0);
console.log('OK Cuenta suspendida rechazada y sesión local descartada');
const restricted = createApp(['patient'],{summaryDenied:true}); await restricted.login(); assert.match(restricted.app.textContent,/verificación adicional/); assert.match(restricted.app.textContent,/Hola,/);
console.log('OK Resumen protegido: mantiene login y no inventa contadores');
for (const role of ['patient','doctor']) {
  const ui = createApp(); await settle(); ui.get('design-' + role).listeners.click(); await settle();
  assert.match(ui.get('preview-mode').textContent,/MODO DISEÑO/);
  for (const screen of catalog[role].filter(item => item.id !== 'home')) {
    await ui.click('Más'); await ui.click(screen.title + '　›');
    assert.ok(ui.app.all().some(node => node.tagName === 'h1' && node.textContent === screen.title),screen.id);
    assert.equal(ui.app.textContent.includes('true'),false,'No boolean shown as a badge');
    if (role === 'doctor') assert.equal(ui.app.textContent.includes('Mis citas'),false,'Sin Mis citas en ninguna pantalla del doctor');
  }
  assert.equal(ui.calls.some(call => call.url.startsWith(contract.url)),false);
  ui.get('live-mode').listeners.click(); await settle(); assert.ok(ui.get('password'));
  console.log(`OK Diseño ${role}: todas las pantallas navegables; cero llamadas a Supabase`);
}
assert.equal(catalog.patient.length + catalog.doctor.length,20);
console.log('8 recorridos aprobados; 20 pantallas comprobadas.');

// Agendamiento local: comportamiento completo sin escrituras al servidor.
for (const mode of ['design', 'session']) {
  const ui = createApp(['patient']); await settle();
  if (mode === 'design') { ui.get('design-patient').listeners.click(); await settle(); }
  else await ui.login();
  await ui.click('Mis citas'); await ui.click('Solicitar atención');
  assert.match(ui.app.textContent, /Preparemos tu próxima cita/);
  assert.equal(ui.get('sched-nombres').value, 'Gaby');
  assert.equal(ui.get('sched-apellidos').value, 'Diaz');
  assert.equal(ui.get('sched-dui').value, '0123-45678');
  assert.equal(ui.get('sched-telefono').value, '7123-4567');
  assert.equal(ui.get('sched-correo').value, 'gaby.diaz@ejemplo.test');
  const calls = ui.calls.length;
  const choice = id => ui.app.all().find(node => node.attributes['data-choice'] === id);
  const choose = async id => { const node = choice(id); assert.ok(node, id); node.listeners.click(); await settle(); };
  const selected = id => choice(id).attributes['aria-pressed'] === 'true';
  await ui.click('Tos'); await ui.click('Sangrado');
  assert.ok(selected('symptom-0') && selected('symptom-1'));
  await ui.click('Ninguno');
  assert.ok(selected('symptom-10')); assert.equal(selected('symptom-0'), false); assert.equal(selected('symptom-1'), false);
  await ui.click('Tos'); assert.equal(selected('symptom-10'), false);
  await ui.click('Tos'); assert.equal(selected('symptom-1'), false);
  await ui.input('Preferencia de horario','Mañana','change');await ui.input('Motivo de consulta', 'Consulta de prueba');
  for (let index = 0; index < 6; index++) {
    await choose('specialty-' + index);
    assert.equal(ui.get('sched-submit').disabled, true, 'Cambiar especialidad borra el horario');
    await choose('slot-0');
    assert.equal(ui.get('sched-submit').disabled, false);
  }
  await ui.input('DUI', 'incorrecto'); assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('DUI', '0123-45678');
  await ui.input('Teléfono', '12'); assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('Teléfono', '7123-4567');
  await ui.input('Correo electrónico', 'incorrecto'); assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('Correo electrónico', 'otro@ejemplo.test');
  await ui.input('Nombres', ' '); assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('Nombres', 'Otra persona');
  await ui.input('Motivo de consulta', ' '); assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('Motivo de consulta', 'Consulta de prueba');
  await ui.click('Solicitar atención'); assert.ok(ui.get('sched-feedback'));
  assert.equal(ui.get('sched-submit').disabled, true);
  await ui.input('Apellidos', 'Prueba'); assert.equal(ui.get('sched-feedback').hidden, true);
  assert.equal(ui.get('sched-submit').disabled, false);
  assert.equal(ui.calls.length, calls, 'Editar y preparar no llama a la API');
  if (mode === 'design') {
    ui.get('live-mode').listeners.click(); await settle();
    ui.get('design-patient').listeners.click(); await settle();
    await ui.click('Mis citas'); await ui.click('Solicitar atención');
    assert.equal(ui.get('sched-nombres').value, 'Gaby', 'Borrador descartado al salir');
    assert.equal(ui.calls.some(call => call.url.startsWith(contract.url)), false);
  }
  console.log('OK Agendar cita (' + mode + '): datos, síntomas, seis especialidades, validación y simulación sin API');
}
