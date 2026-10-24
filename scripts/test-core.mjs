import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const root = new URL('../', import.meta.url);
const contract = JSON.parse(readFileSync(new URL('HospitalUniversitario/HospitalUniversitario/Shared/contract.json', root)));
const context = { Date, console, AbortSignal };
runInNewContext(readFileSync(new URL('HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js', root), 'utf8'), context);
runInNewContext(readFileSync(new URL('web-preview/api.js', root), 'utf8'), context);
const core = context.HospitalCore;
const uuid = '00000000-0000-4000-8000-000000000001';
const plain = value => JSON.parse(JSON.stringify(value));
const access = { profile: { id: uuid, status: 'active', preferred_name: 'Prueba' }, roles: [{ code: 'doctor', facility_id: uuid }], staff_id: uuid, patient_id: null };
let count = 0;
async function test(name, action) { await action(); count++; console.log(`OK ${name}`); }
function storage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) };
}
function response(data, status = 200) { return { ok: status >= 200 && status < 300, status, text: async () => data == null ? '' : JSON.stringify(data) }; }
function session(suffix = '') { return { access_token: 'access' + suffix, refresh_token: 'refresh' + suffix, expires_in: 3600 }; }
function client(fetch, store = storage()) { return new context.HospitalAPI(contract, { fetch, storage: store }); }
await test('Roles: médico activo y vinculado', () => assert.deepEqual(plain(core.routes(access)), ['doctor']));
await test('Roles: rechaza perfil suspendido, sin vínculo y administrador', () => {
  assert.deepEqual(plain(core.routes({ ...access, profile: { status: 'suspended' } })), []);
  assert.deepEqual(plain(core.routes({ ...access, staff_id: null })), []);
  assert.deepEqual(plain(core.routes({ ...access, roles: [{ code: 'administrator' }] })), []);
  assert.deepEqual(plain(core.routes(null)), []);
});
await test('Roles: paciente y doble rol solo con vínculos verificados', () => {
  const both = { ...access, patient_id: uuid, roles: [...access.roles, { code: 'patient' }] };
  assert.deepEqual(plain(core.routes(both)), ['doctor', 'patient']);
  assert.deepEqual(plain(core.routes({ ...both, staff_id: null })), ['patient']);
  assert.equal(core.turnResource('doctor'), 'staff_shifts');
  assert.equal(core.turnResource('patient'), 'queue_tickets');
  assert.throws(() => core.turnResource('administrator'));
});
await test('Consultas: cursor y filtro de propietario son compartidos', () => {
  const cursor = { id: uuid, value: uuid };
  assert.deepEqual(plain(core.readRequest('rooms', cursor)).p_cursor, cursor);
  assert.deepEqual(plain(core.readRequest('queue_tickets', null, uuid)).p_filters, [{ column: 'patient_id', op: 'eq', value: uuid }]);
  const window = core.weekWindow('2026-10-23T12:00:00');
  const shifts = plain(core.readRequest('staff_shifts', null, uuid, window));
  assert.deepEqual(shifts.p_filters, [{ column: 'staff_id', op: 'eq', value: uuid },{ column:'period', op:'overlaps', value:window }]);
  assert.equal(shifts.p_sort,'period');
  const bounds = core.periodBounds(window);
  assert.equal(new Date(bounds.start).getDay(),1);
  assert.equal(new Date(bounds.end).getDay(),1);
  assert.ok(new Date(bounds.end) > new Date(bounds.start));
  assert.throws(() => core.readRequest('profiles'));
  assert.throws(() => core.readRequest('queue_tickets', null, 'invalid'));
});
await test('tstzrange: convierte zonas horarias, fracciones e intervalos nocturnos', () => {
  assert.deepEqual(plain(core.periodBounds('["2026-10-23 22:00:00-06","2026-10-24 06:00:00-06")')), { start: '2026-10-24T04:00:00.000Z', end: '2026-10-24T12:00:00.000Z' });
  assert.equal(core.periodBounds('["2026-10-23 07:00:00.123+00:00","2026-10-23 08:00:00+00:00")').start, '2026-10-23T07:00:00.123Z');
  for (const invalid of ['empty', '[,)', '(2026-10-23,2026-10-24]', '["2026-10-24","2026-10-23")']) assert.throws(() => core.periodBounds(invalid));
});
await test('Auth: credenciales en POST, RPC con bearer y clave pública', async () => {
  const calls = [];
  const api = client(async (url, options) => { calls.push({ url, options }); return response(url.includes('/token?') ? session() : access); });
  await api.signIn('  doctor@example.test ', 'private-test');
  const resolved = await api.access();
  assert.equal(calls[0].url, contract.url + '/auth/v1/token?grant_type=password');
  assert.equal(JSON.parse(calls[0].options.body).email, 'doctor@example.test');
  assert.equal(calls[1].options.headers.Authorization, 'Bearer access');
  assert.equal(calls[1].options.headers.apikey, contract.publishableKey);
  assert.deepEqual(plain(resolved.roles), ['doctor']);
  assert.equal(api.storage.getItem(api.storageKey), 'refresh');
});
await test('Auth: una renovación para solicitudes concurrentes y rota el token', async () => {
  let requests = 0;
  const store = storage({ 'hospital.refresh-token.v1': 'old-refresh' });
  const api = client(async (url, options) => {
    requests++; assert.ok(url.endsWith('grant_type=refresh_token'));
    assert.equal(JSON.parse(options.body).refresh_token, 'old-refresh');
    await Promise.resolve(); return response(session('-new'));
  }, store);
  assert.deepEqual(await Promise.all([api.token(), api.token(), api.token()]), ['access-new', 'access-new', 'access-new']);
  assert.equal(requests, 1); assert.equal(store.getItem(api.storageKey), 'refresh-new');
});
await test('Auth: credenciales inválidas y error de red son visibles', async () => {
  const api = client(async () => response({ message: 'Do not expose backend details' }, 400));
  await assert.rejects(() => api.signIn('x@example.test', 'bad'), /Credenciales/);
  assert.equal(api.session, null);
  const offline = client(async () => { throw new Error('offline'); });
  await assert.rejects(() => offline.signIn('x@example.test', 'bad'), /conexión/);
});
await test('Datos: acepta páginas reales y rechaza contratos incompatibles', async () => {
  const room = { id: uuid, floor_id: uuid, room_type_id: uuid, code: '101', active: true, created_at: '2026-10-23T07:00:00Z', updated_at: '2026-10-23T07:00:00Z', row_version: 1 };
  let data = { data: [room], has_more: true, next_cursor: { id: uuid, value: uuid } };
  const api = client(async (url, options) => {
    if (url.includes('/token?')) return response(session());
    assert.equal(JSON.parse(options.body).p_resource, 'rooms');
    return response(data);
  });
  await api.signIn('test@example.test', 'test');
  assert.equal((await api.read('rooms')).data[0].code, '101');
  data = { ...data, data: [{ ...room, active: 'true' }] };
  await assert.rejects(() => api.read('rooms'), /incompatibles/);
});
await test('Datos: ticket con campos nulos; acceso denegado se propaga', async () => {
  const ticket = Object.fromEntries(Object.entries(contract.models.QueueTicket).map(([field, type]) => [field, type.endsWith('?') ? null : ['Int', 'Int64'].includes(type) ? 1 : type === 'UUID' ? uuid : 'waiting']));
  let denied = false;
  const api = client(async url => response(url.includes('/token?') ? session() : { data: [ticket], has_more: false, next_cursor: null }, denied ? 403 : 200));
  await api.signIn('test@example.test', 'test');
  assert.equal((await api.read('queue_tickets', null, uuid)).data[0].called_at, null);
  denied = true;
  await assert.rejects(() => api.read('queue_tickets', null, uuid), /no tiene acceso/);
});
await test('Logout: scope local y borra credenciales aun sin conexión', async () => {
  let fail = false;
  const api = client(async url => { if (fail) throw new Error('offline'); return response(session()); });
  await api.signIn('test@example.test', 'test'); fail = true;
  assert.match(await api.signOut(), /cierre remoto/);
  assert.equal(api.session, null); assert.equal(api.storage.getItem(api.storageKey), null);
});
console.log(`${count} pruebas completadas. No se modificó Supabase.`);
