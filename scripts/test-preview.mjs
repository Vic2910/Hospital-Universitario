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
    return match ? this.all().find(node => node.attributes['data-choice'] === match[1]) || null : this.all().find(node => node.tagName === selector) || null;
  }
  reportValidity() { return true; }
  all() { return [this, ...this.children.flatMap(child => child.all())]; }
}
const settle = () => new Promise(resolve => setImmediate(resolve));
const response = (body,status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body, text: async () => body == null ? '' : JSON.stringify(body) });
export async function openAttentionRequest(ui) {
  await ui.click('Salud');
  assert.ok(ui.app.textContent.includes('Enviar solicitud') || ui.get('sched-submit'),'Salud abre directamente Solicitar atención');
  assert.equal(ui.app.textContent.includes('Tu información de salud'),false,'Sin menú intermedio');
}
export function createApp(roleCodes = ['doctor'], options = {}) {
  const body = new Element('body');
  for (const id of ['app','notice','preview-mode','design-patient','design-doctor','live-mode','design-applicant','design-reception']) { const node = new Element(id.startsWith('design-') || id === 'live-mode' ? 'button' : 'div'); node.id = id; if (id === 'notice') node.hidden = true; body.append(node); }
  const find = predicate => body.all().find(predicate);
  const calls = [], stored = new Map(options.stored || []);
  const storage = { getItem:key => stored.get(key) ?? null, setItem:(key,value) => stored.set(key,value), removeItem:key => stored.delete(key) };
  let registered = !options.unregistered;
  let accountMetadata = {first_name:'Persona',last_name:'de prueba',birth_date:'1995-01-02',phone:'7000-1111',city:'Santa Ana'};
  const fetch = async (url,request) => {
    const params = request?.body && JSON.parse(request.body); calls.push({url,params,request});
    const custom = await options.transport?.(url,params,request);
    if (custom !== undefined) return response(custom.body,custom.status || 200);
    if (url === '/shared/contract.json') return response(contract);
    if (url === '/shared/screens.json') return response(catalog);
    if (url === '/design-fixtures.json') return response(fixtures);
    if (url.includes('/token?')) return response({access_token:'test',refresh_token:'test-refresh',expires_in:3600});
    if (url.endsWith('/auth/v1/signup')) { accountMetadata=params.data;return response({access_token:'test',refresh_token:'test-refresh',expires_in:3600}); }
    if (url.endsWith('/auth/v1/user')) return response({id:uuid,email:'persona@example.test'});
    if (url.includes('/logout')) return response(null,204);
    if (url.includes('/rest/v1/profiles?')) return response([{id:uuid,...accountMetadata}]);
    if (url.includes('/rest/v1/user_roles?')) return response(roleCodes.map(code=>({user_id:uuid,role:code==='patient'?'paciente':code,active:!options.suspended})));
    if (url.includes('/rest/v1/patients?')) return response(registered && roleCodes.includes('patient') ? [{id:uuid,profile_id:uuid,first_name:accountMetadata.first_name,last_name:accountMetadata.last_name,birth_date:accountMetadata.birth_date,phone:accountMetadata.phone,dui:'01234567-8',patient_code:'PAC-TEST',medical_records:[{record_code:'EXP-TEST'}]}] : []);
    if (url.includes('/rest/v1/staff?')) return response(roleCodes.includes('doctor')?[{id:uuid,profile_id:uuid,active:!options.suspended,category:'doctor'}]:[]);
    if (url.endsWith('/rpc/doctor_native_workspace')) return response({doctor_name:[accountMetadata.first_name,accountMetadata.last_name].join(' '),facility_name:'Hospital Universitario',appointments:[],orders:[],tests:[],medications:[],notifications:[],stats:{consultations:0,completed_consultations:0,issued_orders:0,pending_orders:0}});
    if (url.endsWith('/rpc/doctor_native_patients')) return response({patients:[],total:0,has_more:false,next_offset:null});
    if (url.endsWith('/rpc/doctor_native_lab_catalog')) return response([]);
    if (url.endsWith('/rpc/doctor_native_lab_orders')) return response({items:[],total:0,has_more:false,next_offset:null});
    if (url.endsWith('/rpc/doctor_native_admissions')) return response({items:[],total:0,has_more:false,next_offset:null,doctor_name:'Doctor de prueba',categories:['vip','semiprivada'],priorities:['normal','urgente']});
    if (url.endsWith('/rpc/doctor_native_patient_labs')) return response({items:[],total:0,has_more:false,next_offset:null});
    if (url.endsWith('/rpc/register_patient')) throw new Error('El cliente no puede crear paciente ni expediente');
    if (url.endsWith('/rpc/my_attention_context')) return response({person:{...accountMetadata,dui:'01234567-8',email:'persona@example.test'},specialties:[{id:1,name:'Medicina general',available:true}],symptoms:[{id:1,name:'Fiebre'},{id:2,name:'Otro'}]});
    if (url.endsWith('/rpc/my_attention_requests')) return response([]);
    if (url.endsWith('/rpc/submit_my_attention_request')) return response(params.p_key);
    if (url.includes('/rest/v1/rooms?')) return response([{id:uuid,floor_id:1,kind:'vip',code:'VIP-301',active:true}]);
    if (url.includes('/rest/v1/staff_shifts?')) return response([{id:uuid,staff_id:uuid,starts_at:'2026-11-13T07:00:00Z',ends_at:'2026-11-13T15:00:00Z',shift_type:'ordinario',status:'programado'}]);
    if (url.includes('/rest/v1/specialties?')) return response([{id:1,name:'Medicina general'}]);
    if (url.includes('/rest/v1/')) return response([]);
    throw new Error('Unexpected request: ' + url);
  };
  const context = {Date,Intl,console,URL,crypto:webcrypto,AbortSignal,fetch,setInterval(){},sessionStorage:storage,document:{body,hidden:false,querySelector:selector => find(node => node.id === selector.slice(1)),createElement:tag => new Element(tag),addEventListener(){}}};
  for (const path of ['HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js','web-preview/api.js','web-preview/modules.js','web-preview/doctor-dashboard.js','web-preview/clinical-labs.js','web-preview/patient-history.js','web-preview/patient-prescriptions.js','web-preview/patient-appointments.js','web-preview/applicant.js','web-preview/app.js']) runInNewContext(read(path),context);
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
  const ui=createApp(codes);await ui.login();
  if(codes.length>1) await ui.click('Paciente');
  assert.match(ui.app.textContent,role==='doctor'?/Hola, Persona de prueba/:/¡Hola, Persona de!/);
  await ui.click('Más');await ui.click((role==='doctor'?'Mi horario':'Mi turno')+'　›');
  if(role==='doctor') assert.ok(ui.calls.some(c=>c.url.includes('/staff_shifts?')));
  else assert.match(ui.get('notice').textContent+ui.app.textContent,/fila numerada|No tienes un turno/);
  await ui.click('Más');await ui.click('Habitaciones　›');assert.match(ui.app.textContent,/VIP-301/);
  await ui.click('Más');await ui.click('Cerrar sesión');assert.ok(ui.get('password'));
  assert.equal(ui.stored.size,0);
  console.log('OK Hospital Móviles: login, roles, horario/citas, habitaciones y cierre ('+role+')');
}
const suspended=createApp(['patient'],{suspended:true});await suspended.login();assert.ok(suspended.get('password'));
assert.equal(suspended.calls.some(c=>c.url.includes('/rpc/')),false);
console.log('OK Rol inactivo rechazado sin servicios adicionales');
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
assert.equal(catalog.patient.length + catalog.doctor.length,21);
console.log('Recorridos actuales aprobados; 21 pantallas comprobadas.');

// Agendamiento local: comportamiento completo sin escrituras al servidor.
for (const mode of ['design']) {
  const ui = createApp(['patient']); await settle();
  if (mode === 'design') { ui.get('design-patient').listeners.click(); await settle(); }
  else await ui.login();
  await openAttentionRequest(ui);
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
  await ui.click('Mañana · AM');await ui.input('Motivo de consulta', 'Consulta de prueba');
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
    await openAttentionRequest(ui);
    assert.equal(ui.get('sched-nombres').value, 'Gaby', 'Borrador descartado al salir');
    assert.equal(ui.calls.some(call => call.url.startsWith(contract.url)), false);
  }
  console.log('OK Agendar cita (' + mode + '): datos, síntomas, seis especialidades, validación y simulación sin API');
}
