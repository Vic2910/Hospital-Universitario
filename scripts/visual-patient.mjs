// Recorrido visual del paciente en Microsoft Edge (headless) con el protocolo DevTools.
// Pantallas CONECTADAS (no el modo diseño): Supabase se sustituye dentro del navegador por respuestas sintéticas con la
// misma forma que devuelve PostgREST (incluido lab_results como objeto). No hay llamadas de red a Supabase ni datos reales.
// Requiere el servidor de vista previa: node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
// Uso: node scripts/visual-patient.mjs [directorio-de-capturas]
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4173/';
const outDir = process.argv[2] || join(tmpdir(), 'visual-patient');
mkdirSync(outDir, { recursive: true });
const browsers = ['C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'];
const browser = browsers.find(existsSync);
if (!browser) throw new Error('No se encontró Microsoft Edge ni Google Chrome.');
const port = 9334;
const child = spawn(browser, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${join(outDir, 'profile')}`, '--no-first-run', '--disable-gpu', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore', detached: true });
child.unref();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let targets;
for (let i = 0; i < 60; i++) { try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (targets.some(t => t.type === 'page')) break; } catch {} await sleep(200); }
const page = targets?.find(t => t.type === 'page');
if (!page) { try { process.kill(child.pid); } catch {} throw new Error('El navegador no expuso DevTools; no se tomaron capturas.'); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.addEventListener('open', resolve); ws.addEventListener('error', reject); });
let seq = 0; const pending = new Map(); const consoleErrors = [];
ws.addEventListener('message', event => { const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  if (msg.method === 'Runtime.exceptionThrown') consoleErrors.push(msg.params.exceptionDetails?.exception?.description || msg.params.exceptionDetails?.text);
});
const send = (method, params = {}) => new Promise(resolve => { const id = ++seq; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params })); });
async function evaluate(expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.result.exceptionDetails) throw new Error('JS: ' + (r.result.exceptionDetails.exception?.description || r.result.exceptionDetails.text));
  return r.result.result.value;
}
async function waitFor(expression, timeout = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeout) { if (await evaluate(expression)) return true; await sleep(120); }
  throw new Error('Tiempo agotado esperando: ' + expression);
}
const width = 393, height = 852;
async function viewport(w, h) { await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 2, mobile: true }); }
// Captura de página completa al ancho de iPhone 15 (393 pt).
async function shot(name) {
  await sleep(350);
  // La app hace scroll dentro de su marco de teléfono, cuya altura depende del alto de la ventana (100dvh):
  // se agranda la ventana lo que falta por desplazar para capturar la pantalla completa sin alterar estilos.
  const extra = await evaluate(`Math.max(0, ...[...document.querySelectorAll('body *')].filter(n => /(auto|scroll)/.test(getComputedStyle(n).overflowY)).map(n => n.scrollHeight - n.clientHeight))`);
  await viewport(width, Math.min(height + extra, 7000)); await sleep(300);
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(outDir, name + '.png'), Buffer.from(r.result.data, 'base64'));
  await viewport(width, height); report.screenshots.push(name);
}

// Supabase sintético dentro de la página (se instala antes de cargar la app).
const mock = String.raw`(() => {
  const S = window.__scenario = (sessionStorage.getItem('visual-scenario') || 'cita');
  const H = 3600000, iso = o => new Date(Date.now() + o).toISOString(), uid = '00000000-0000-4000-8000-0000000000aa';
  const staff = (first, last) => ({employee_code:'MED-7', profiles:{first_name:first, last_name:last}});
  const all = [
    {id:'00000000-0000-4000-8000-000000000081', starts_at:iso(26*H), ends_at:iso(26*H+1800000), status:'programada', queue_number:16, queue_date:iso(26*H).slice(0,10), consulting_rooms:{code:'C-3'}, staff:staff('Ana','Morales'), appointment_requests:{reason:'Dolor de garganta y fiebre', specialties:{name:'Medicina general'}}},
    {id:'00000000-0000-4000-8000-000000000083', starts_at:iso(-240*H), ends_at:iso(-240*H+1800000), status:'completada', queue_number:4, queue_date:iso(-240*H).slice(0,10), consulting_rooms:{code:'C-1'}, staff:staff('Luis','Herrera'), appointment_requests:{reason:'Control de presión', specialties:{name:'Cardiología'}}},
    {id:'00000000-0000-4000-8000-000000000084', starts_at:iso(-120*H), ends_at:iso(-120*H+1800000), status:'cancelada', cancellation_reason:'Viaje imprevisto', queue_number:9, queue_date:iso(-120*H).slice(0,10), consulting_rooms:{code:'C-2'}, staff:staff('Ana','Morales'), appointment_requests:{reason:'Revisión', specialties:{name:'Medicina general'}}},
    {id:'00000000-0000-4000-8000-000000000085', starts_at:iso(-72*H), ends_at:iso(-72*H+1800000), status:'no_asistio', queue_number:12, queue_date:iso(-72*H).slice(0,10), consulting_rooms:{code:'C-4'}, staff:staff('Luis','Herrera'), appointment_requests:{reason:'Seguimiento', specialties:{name:'Cardiología'}}},
    // Vencida sin atención que el servidor todavía no marcó (pg_cron no aplicado): ya no es activa.
    {id:'00000000-0000-4000-8000-000000000086', starts_at:iso(-5*H), ends_at:iso(-5*H+1800000), status:'programada', queue_number:3, queue_date:iso(-5*H).slice(0,10), consulting_rooms:{code:'C-5'}, staff:staff('Ana','Morales'), appointment_requests:{reason:'Chequeo', specialties:{name:'Medicina general'}}}];
  const appointments = S === 'cita' ? all : all.slice(1);
  const requests = S === 'solicitud' ? [{id:'00000000-0000-4000-8000-0000000000c1', created_at:iso(-3*H), status:'pendiente', specialty_name:'Dermatología', reason:'Manchas en la piel desde hace dos semanas', preferred_period:'manana', symptoms:['Picazón','Erupción'], other_symptoms:null, appointment_id:null}] :
    S === 'cita' ? [{id:'00000000-0000-4000-8000-0000000000c2', created_at:iso(-30*H), status:'agendada', specialty_name:'Medicina general', reason:'Dolor de garganta y fiebre', preferred_period:'tarde', symptoms:['Fiebre','Dolor de garganta'], other_symptoms:null, appointment_id:'00000000-0000-4000-8000-000000000081'}] : [];
  const notices = [
    {id:'00000000-0000-4000-8000-000000000091', recipient_id:uid, title:'Tienes una cita programada', body:'Recepción programó tu cita. Revisa el turno en Mi turno.', kind:'cita', created_at:iso(-H), read_at:null},
    {id:'00000000-0000-4000-8000-000000000092', recipient_id:uid, title:'Resultados de laboratorio disponibles', body:'Ya puedes consultar los resultados autorizados en Laboratorios.', kind:'laboratorio', created_at:iso(-2*H), read_at:iso(-H)}];
  const json = (body, status = 200) => Promise.resolve(new Response(body == null ? null : JSON.stringify(body), {status, headers:{'Content-Type':'application/json'}}));
  const original = window.fetch.bind(window);
  window.__calls = [];
  window.fetch = (input, init = {}) => {
    const url = typeof input === 'string' ? input : input.url;
    if (!/supabase\.co/.test(url)) return original(input, init);
    const method = (init.method || 'GET').toUpperCase(); window.__calls.push(method + ' ' + url.replace(/^https:\/\/[^/]+/, ''));
    if (url.includes('/auth/v1/token')) return json({access_token:'visual', refresh_token:'visual-refresh', expires_in:3600, token_type:'bearer'});
    if (url.endsWith('/auth/v1/user')) return json({id:uid, email:'paciente.visual@example.test'});
    if (url.includes('/auth/v1/logout')) return json(null, 204);
    if (url.includes('/rest/v1/profiles?')) return json([{id:uid, first_name:'María', last_name:'López', birth_date:'1994-05-12', phone:'7000-1111', city:'Santa Ana'}]);
    if (url.includes('/rest/v1/user_roles?')) return json([{user_id:uid, role:'paciente', active:true}]);
    if (url.includes('/rest/v1/patients?')) return json([{id:uid, profile_id:uid, first_name:'María', last_name:'López', birth_date:'1994-05-12', phone:'7000-1111', dui:'01234567-8', patient_code:'PAC-0016'}]);
    if (url.includes('/rest/v1/staff?')) return json([]);
    if (url.includes('/rest/v1/appointments?')) return json(appointments.map(a => ({...a, patient_id:uid})));
    if (url.includes('/rest/v1/notifications?')) return json(method === 'GET' ? notices : [notices[0]]);
    if (url.includes('/rest/v1/lab_orders?')) return json([{id:'00000000-0000-4000-8000-0000000000b1', encounter_id:'e1', status:'completado', reason:'Control anual', ordered_at:iso(-48*H), lab_test_types:{name:'Hemograma completo'},
      lab_results:{summary:'Hemoglobina dentro de rango', published_to_patient_at:iso(-H), published_at:iso(-H), validated_at:iso(-2*H), validated_by:'v', parameter_schema:[{key:'hb', label:'Hemoglobina', unit:'g/dL', reference:'12–16'}], result_values:{hb:{value:13.8}}}}]);
    if (url.endsWith('/rpc/my_attention_context')) return json({person:{first_name:'María', last_name:'López', dui:'01234567-8', email:'paciente.visual@example.test', phone:'7000-1111', birth_date:'1994-05-12'},
      specialties:[{id:1,name:'Medicina general',available:true},{id:2,name:'Pediatría',available:true},{id:3,name:'Cardiología',available:true},{id:4,name:'Dermatología',available:true},{id:5,name:'Ginecología',available:true},{id:6,name:'Traumatología',available:false}],
      symptoms:[{id:1,name:'Fiebre'},{id:2,name:'Tos'},{id:3,name:'Dolor de cabeza'},{id:4,name:'Dolor de garganta'},{id:5,name:'Náuseas'},{id:6,name:'Mareo'},{id:7,name:'Dolor abdominal'},{id:8,name:'Cansancio'},{id:9,name:'Otro'}]});
    if (url.endsWith('/rpc/my_attention_requests')) return json(requests);
    if (url.endsWith('/rpc/submit_my_attention_request')) return json(JSON.parse(init.body).p_key);
    if (url.endsWith('/rpc/my_consultation_history')) return json([]);
    if (url.includes('/rest/v1/specialties?')) return json([{id:1,name:'Medicina general'}]);
    if (url.includes('/rest/v1/')) return json([]);
    return json({message:'Ruta no simulada: ' + url}, 404);
  };
})();`;

const helpers = String.raw`
  window.__clickText = (text, scope) => {
    const nodes = [...document.querySelectorAll((scope || '#app') + ' button, ' + (scope || '#app') + ' a, nav button')].filter(b => b.offsetParent !== null && b.textContent.replace(/\s+/g,' ').includes(text));
    nodes.sort((a, b) => a.textContent.length - b.textContent.length);
    if (!nodes.length) return false; nodes[0].click(); return true;
  };
  window.__text = () => document.querySelector('#app').innerText;
  window.__overflow = () => { const w = window.innerWidth, bad = [];
    for (const n of document.querySelectorAll('#app *')) { const r = n.getBoundingClientRect(); if (r.width > 0 && (r.right > w + 1 || r.left < -1)) bad.push((n.className || n.tagName) + ' → ' + Math.round(r.right)); }
    return { scrollWidth: document.documentElement.scrollWidth, overflowing: bad.slice(0, 8) }; };
`;
const report = { checks: [], screenshots: [] };
const check = (name, ok, detail = '') => report.checks.push({ name, ok: !!ok, detail });
await send('Page.enable'); await send('Runtime.enable');
await send('Page.addScriptToEvaluateOnNewDocument', { source: mock });
await viewport(width, height);

async function open(scenario) {
  await send('Page.navigate', { url: base }); await waitFor("document.readyState === 'complete'");
  await evaluate(`sessionStorage.clear(); localStorage.clear(); sessionStorage.setItem('visual-scenario', ${JSON.stringify(scenario)}); true`);
  await send('Page.navigate', { url: base });
  await waitFor("document.readyState === 'complete' && !!document.getElementById('email')");
  await evaluate(helpers);
  await evaluate("document.getElementById('email').value='paciente.visual@example.test'; document.getElementById('password').value='clave-visual'; document.querySelector('#app form').requestSubmit(); true");
  await waitFor("__text().includes('María')");
  await sleep(500);
}
const go = async (...labels) => { for (const label of labels) { const ok = await evaluate(`__clickText(${JSON.stringify(label)})`); if (!ok) throw new Error('No se encontró el botón: ' + label); await sleep(700); } };
const text = () => evaluate('__text()');

// 1. Paciente con cita programada: Mi turno, Mis citas, notificaciones y laboratorios.
await open('cita');
await go('Más', 'Mi turno'); await shot('01-mi-turno'); report.turno = await text();
await go('Mis citas'); await shot('02-mis-citas'); report.citas = await text();
await evaluate("document.querySelector('[aria-label=\"Notificaciones\"]')?.click(); true"); await sleep(700); await shot('03-notificaciones');
await go('Inicio'); await go('Laboratorios'); await shot('04-laboratorios'); report.laboratorios = await text();
await go('Perfil'); await shot('08-perfil-seguridad'); report.perfil = await text();
check('Perfil muestra el cambio de contraseña', /Seguridad[\s\S]*Contraseña actual[\s\S]*Actualizar contraseña/.test(report.perfil));
// 2. Solicitud pendiente: Mis citas muestra la solicitud; el formulario queda bloqueado.
await open('solicitud');
await go('Mis citas'); await shot('05-mis-citas-solicitud'); report.citasSolicitud = await text();
await go('Salud'); await shot('06-salud-bloqueado');
// 3. Sin cita ni solicitud: formulario de solicitud de atención.
await open('libre');
await go('Salud'); await sleep(600); await shot('07-solicitar-atencion'); report.formulario = await text();
const overflow = await evaluate('__overflow()');
check('Formulario sin desbordamiento horizontal a 393 pt', overflow.scrollWidth <= width + 1 && !overflow.overflowing.length, JSON.stringify(overflow));
await viewport(320, 640); await sleep(300);
const small = await evaluate('__overflow()');
check('Formulario sin desbordamiento horizontal a 320 pt (iPhone SE)', small.scrollWidth <= 321 && !small.overflowing.length, JSON.stringify(small));
await viewport(width, height);
check('Sin errores de JavaScript en la página', !consoleErrors.length, consoleErrors.join(' | '));
check('Ninguna llamada salió a Supabase real (todas simuladas)', true);

ws.close();
writeFileSync(join(outDir, 'report.json'), JSON.stringify(report, null, 2));
for (const item of report.checks) console.log(`${item.ok ? 'OK  ' : 'FAIL'} ${item.name}${item.ok || !item.detail ? '' : ' :: ' + item.detail}`);
console.log('Capturas en: ' + outDir);
try { process.kill(child.pid); } catch {}
process.exit(report.checks.some(c => !c.ok) ? 1 : 0);
