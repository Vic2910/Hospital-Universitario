// Recorrido visual del solicitante en Microsoft Edge (headless) mediante el protocolo DevTools.
// Requiere el servidor de vista previa en marcha: node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
// Solo usa datos de ejemplo. No modifica Supabase ni la configuración de Auth.
// Uso: node scripts/visual-applicant.mjs [directorio-de-capturas]
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4173/';
const outDir = process.argv[2] || join(process.env.LOCALAPPDATA || tmpdir(), 'Temp', 'opencode', 'visual-applicant');
mkdirSync(outDir, { recursive: true });
const browsers = ['C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'];
const browser = browsers.find(existsSync);
if (!browser) throw new Error('No se encontró Microsoft Edge ni Google Chrome.');
const port = 9333;
const profile = join(outDir, 'profile');
const child = spawn(browser, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', '--disable-gpu', 'about:blank'], { stdio: 'ignore', detached: true });
child.unref();

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function json(path) { return (await fetch(`http://127.0.0.1:${port}${path}`)).json(); }
let targets;
for (let i = 0; i < 50; i++) {
  try { targets = await json('/json/list'); if (targets.some(t => t.type === 'page')) break; } catch {}
  await sleep(200);
}
const page = targets?.find(t => t.type === 'page');
if (!page) {
  try { process.kill(child.pid); } catch {}
  throw new Error('Edge no expuso una página DevTools en el puerto 9333. No se ejecutaron comprobaciones visuales; sigue el recorrido manual documentado.');
}
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.addEventListener('open', resolve); ws.addEventListener('error', reject); });
let seq = 0; const pending = new Map();
ws.addEventListener('message', event => { const msg = JSON.parse(event.data); if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); } });
const send = (method, params = {}) => new Promise(resolve => { const id = ++seq; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params })); });
async function evaluate(expression) {
  const response = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (response.result.exceptionDetails) throw new Error('JS: ' + JSON.stringify(response.result.exceptionDetails.exception?.description || response.result.exceptionDetails.text));
  return response.result.result.value;
}
async function viewport(width, height) {
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
}
async function shot(name) {
  const response = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(outDir, name + '.png'), Buffer.from(response.result.data, 'base64'));
  return name;
}
async function waitFor(expression, timeout = 8000) {
  const start = Date.now();
  while (Date.now() - start < timeout) { if (await evaluate(expression)) return true; await sleep(100); }
  throw new Error('Tiempo agotado esperando: ' + expression);
}

// Helpers ejecutados en la página: eventos reales de entrada, sin tocar la lógica de la app.
const helpers = `
  window.__setValue = (id, value) => {
    const el = document.getElementById(id);
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return el.value;
  };
  window.__click = text => {
    const node = [...document.querySelectorAll('button,a')].find(b => b.textContent.trim() === text && b.offsetParent !== null);
    if (!node) return false; node.click(); return true;
  };
  window.__submit = () => { const form = document.querySelector('#app form'); form.requestSubmit(); return true; };
  window.__messages = () => [...document.querySelectorAll('#app .auth-error, #app .auth-notice, #notice')]
    .filter(node => !node.hidden && node.offsetParent !== null && node.textContent.trim()).map(node => node.textContent.trim());
  window.__overflow = () => {
    const width = window.innerWidth, bad = [];
    for (const node of document.querySelectorAll('#app *')) {
      const rect = node.getBoundingClientRect();
      if (rect.width > 0 && (rect.right > width + 1 || rect.left < -1)) bad.push((node.id || node.className || node.tagName) + ' → ' + Math.round(rect.right));
    }
    return { width, scrollWidth: document.documentElement.scrollWidth, overflowing: bad.slice(0, 12) };
  };
  window.__text = () => document.querySelector('#app').innerText;
`;

const report = { checks: [], screenshots: [], errors: [] };
const check = (name, ok, detail = '') => report.checks.push({ name, ok: !!ok, detail });

await send('Page.enable'); await send('Runtime.enable');
await viewport(393, 852);
await send('Page.navigate', { url: base });
await waitFor("document.readyState === 'complete' && document.querySelector('#app form')");
await evaluate(helpers);
report.screenshots.push(await shot('01-login'));
check('Login real visible sin credenciales', await evaluate("!!document.getElementById('email') && !!document.getElementById('password')"));

// 1. Registro: abrir, validar y enviar.
await evaluate("__click('Regístrate')");
await waitFor("!!document.getElementById('reg-dui')");
report.screenshots.push(await shot('02-registro-vacio'));
check('Registro: campo de fecha de nacimiento sustituye a edad', await evaluate("document.getElementById('reg-birth')?.type === 'date' && !document.getElementById('reg-age')"));
check('Registro: campos obligatorios bloquean el envío', await evaluate("!document.querySelector('#app form').checkValidity()"));

const fill = async (id, value) => evaluate(`__setValue(${JSON.stringify(id)}, ${JSON.stringify(value)})`);
const submit = async () => evaluate('__submit()');
const messages = async () => evaluate('__messages()');

await fill('reg-given', 'Ana'); await fill('reg-family', 'Prueba');
await fill('reg-dui', '012345678');
check('DUI con formato automático 0123-45678', (await evaluate("document.getElementById('reg-dui').value")) === '0123-45678');
await fill('reg-dui', '1234');
await fill('reg-birth', '1995-03-10'); await fill('reg-phone', '7000-1111');
await fill('reg-email', 'ana@correo.test'); await fill('reg-password', 'clave-segura'); await fill('reg-confirm', 'clave-segura');
await submit();
check('DUI inválido muestra mensaje', (await messages()).some(text => /9 dígitos/.test(text)), JSON.stringify(await messages()));

await fill('reg-dui', '012345678'); await fill('reg-birth', '2030-01-01');
await submit();
check('Fecha de nacimiento futura rechazada', (await messages()).some(text => /fecha de nacimiento válida/.test(text)), JSON.stringify(await messages()));

await fill('reg-birth', '1995-03-10'); await fill('reg-phone', 'abc');
await submit();
check('Teléfono incorrecto rechazado', (await messages()).some(text => /teléfono válido/.test(text)), JSON.stringify(await messages()));

await fill('reg-phone', '7000-1111'); await fill('reg-confirm', 'otra-clave');
await submit();
check('Contraseñas distintas rechazadas', (await messages()).some(text => /no coincide/.test(text)), JSON.stringify(await messages()));

await fill('reg-confirm', 'clave-segura');
await submit();
const registered = await messages();
check('Registro válido sin envío a Supabase (aviso de demostración)', registered.some(text => /no se envía a la base de datos/.test(text)), JSON.stringify(registered));
report.screenshots.push(await shot('03-registro-valido'));

// 2. Vista del solicitante: completar datos.
check('Registro permite continuar al recorrido local', await evaluate("__click('Continuar con datos de ejemplo')"));
await waitFor("!!document.getElementById('ap-given')");
report.screenshots.push(await shot('04-completar-datos-vacio'));
await submit();
check('Completar datos: campos vacíos bloquean el envío', await evaluate("!document.querySelector('#app form').checkValidity()"));
await fill('ap-given', 'Ana'); await fill('ap-family', 'Prueba');
await fill('ap-dui', '012345678');
check('Completar datos: DUI formateado', (await evaluate("document.getElementById('ap-dui').value")) === '0123-45678');
await fill('ap-dui', '1234'); await fill('ap-birth', '1995-03-10'); await fill('ap-phone', '7000-1111');
await submit();
check('Completar datos: DUI inválido rechazado', (await messages()).some(text => /9 dígitos/.test(text)));
await fill('ap-dui', '012345678'); await fill('ap-birth', '2030-01-01');
await submit();
check('Completar datos: fecha futura rechazada', (await messages()).some(text => /fecha de nacimiento válida/.test(text)));
await fill('ap-dui', '012345678'); await fill('ap-birth', '1995-03-10'); await fill('ap-phone', 'x');
await submit();
check('Completar datos: teléfono incorrecto rechazado', (await messages()).some(text => /teléfono válido/.test(text)));
await fill('ap-phone', '7000-1111'); await submit();
await waitFor("__text().includes('Todavía no tienes expediente')");
report.screenshots.push(await shot('05-inicio-solicitante'));
check('Inicio sin expediente y aviso de no cita', await evaluate("__text().includes('Todavía no tienes expediente')"));

// 3. Solicitar atención.
await evaluate("__click('Solicitar atención')");
await waitFor("!!document.getElementById('ap-specialty')");
report.screenshots.push(await shot('06-solicitar-vacio'));
await fill('ap-specialty', 'Medicina general'); await fill('ap-reason', 'Control de presión arterial');
await fill('ap-date', '2000-01-01');
check('Solicitud: el campo de fecha bloquea fechas pasadas (min de hoy)', await evaluate("!document.getElementById('ap-date').checkValidity()"));
await submit();
check('Solicitud: fecha pasada no crea ninguna solicitud', (await evaluate("document.querySelectorAll('#app article').length")) === 0);
await fill('ap-date', '2030-06-01');
await submit();
check('Solicitud: preferencia horaria obligatoria', (await messages()).some(text => /Mañana o Tarde/.test(text)), JSON.stringify(await messages()));
await evaluate("__click('Tarde · PM')");
report.screenshots.push(await shot('07-solicitar-completo'));
await submit();
await waitFor("__text().includes('Mis solicitudes') && __text().includes('Pendiente')");
report.screenshots.push(await shot('08-mis-solicitudes'));
check('Solicitud creada como Pendiente y sin cita', await evaluate("__text().includes('Pendiente') && !__text().includes('Cita programada')"));

// 4. Ejemplos rechazada y cancelada.
await evaluate("__click('Mostrar ejemplos de rechazada y cancelada')");
await waitFor("__text().includes('Rechazada') && __text().includes('Cancelada')");
report.screenshots.push(await shot('09-estados-ejemplo'));
check('Ejemplo rechazada y cancelada visibles con motivo', await evaluate("__text().includes('Motivo: Ejemplo') && __text().includes('Rechazada') && __text().includes('Cancelada')"));

// 5. Responsivo: pantallas pequeñas y grandes del iPhone.
const sizes = [[320, 640, 'se'], [375, 667, 'se2'], [393, 852, 'iphone15'], [430, 932, 'promax']];
for (const [width, height, name] of sizes) {
  await viewport(width, height);
  await sleep(300);
  const overflow = await evaluate('__overflow()');
  check(`Sin desbordamiento horizontal en ${width}×${height} (${name})`, overflow.scrollWidth <= width + 1 && overflow.overflowing.length === 0, JSON.stringify(overflow));
  report.screenshots.push(await shot(`10-responsive-${name}-${width}x${height}`));
}

// 6. Login real intacto tras el recorrido de diseño.
await evaluate("document.getElementById('live-mode').click()");
await waitFor("!!document.getElementById('email')");
check('Volver al login real muestra el formulario original', await evaluate("!!document.getElementById('email') && !document.body.classList.contains('design-mode')"));

ws.close();
const failed = report.checks.filter(item => !item.ok);
writeFileSync(join(outDir, 'report.json'), JSON.stringify({ ...report, failed: failed.length }, null, 2));
for (const item of report.checks) console.log(`${item.ok ? 'OK  ' : 'FAIL'} ${item.name}${item.ok || !item.detail ? '' : ' :: ' + item.detail}`);
console.log(`Capturas en: ${outDir}`);
try { process.kill(child.pid); } catch {}
process.exit(failed.length ? 1 : 0);
