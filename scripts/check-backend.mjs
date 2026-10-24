// Read-only connectivity and authorization checks. No account creation or writes.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const config = JSON.parse(readFileSync(new URL('../HospitalUniversitario/HospitalUniversitario/Shared/contract.json', import.meta.url)));
for (const name of ['public_facilities', 'my_access', 'read_resource', 'my_profile', 'my_queue_status', 'my_activity_summary']) {
  const uuid = '00000000-0000-4000-8000-000000000001';
  const body = name === 'read_resource' ? { p_resource: 'rooms' } : name === 'my_queue_status' ? { p_ticket: uuid } : name === 'my_activity_summary' ? { p_facility: uuid, p_from:'2026-10-23T00:00:00Z', p_to:'2026-10-24T00:00:00Z', p_context:'patient' } : {};
  const response = await fetch(`${config.url}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: config.publishableKey, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (name === 'public_facilities') assert.equal(response.status, 200);
  else assert.ok([401, 403].includes(response.status), `${name}: expected access denied, got ${response.status}`);
  console.log(`${name}: HTTP ${response.status} (esperado)`);
}
