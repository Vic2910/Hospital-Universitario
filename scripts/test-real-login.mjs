// Live integration test using only the two explicitly authorized demo identities.
// Validates the same browser adapter, then revokes all sessions opened here.
// Enrollment requires separately approved --enroll-totp. Never enable it implicitly.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { accounts, saveAccounts, totp } from './test-account-tools.mjs';
const root = new URL('../',import.meta.url);
const data = accounts();
const config = JSON.parse(readFileSync(new URL('HospitalUniversitario/HospitalUniversitario/Shared/contract.json',root),'utf8'));
const context = {Date,AbortSignal,fetch};
for (const path of ['HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js','web-preview/api.js']) runInNewContext(readFileSync(new URL(path,root),'utf8'),context);
assert.equal(totp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',59000,8),'94287082','RFC 6238 known vector');
const checks = [];
const enrollTOTP = process.argv.includes('--enroll-totp');
for (const account of data) {
  assert.ok(['medico.demo@hospital.test','paciente.demo@hospital.test'].includes(account.email),'Only authorized fixture emails');
  const saved = new Map();
  const storage = {getItem:key => saved.get(key) ?? null,setItem:(key,value) => saved.set(key,value),removeItem:key => saved.delete(key)};
  const api = new context.HospitalAPI(config,{storage});
  try {
    await assert.rejects(() => api.signIn(account.email,'INVALID-' + account.password),/Credenciales/);
    await api.signIn(account.email,account.password);
    let result = await api.access();
    assert.deepEqual(JSON.parse(JSON.stringify(result.roles)),[account.role]);
    assert.equal(result.access.profile.id,account.id);
    assert.equal(result.access.profile.status,'active');
    assert.equal(account.role === 'doctor' ? result.access.staff_id : result.access.patient_id,account.entity_id);
    const factors = await api.factors();
    if (enrollTOTP && !account.totp_secret) {
      if (factors.some(f => f.status === 'verified')) throw new Error('Existe un factor verificado desconocido; no se modificará.');
      const factor = await api.request('/auth/v1/factors',{factor_type:'totp',friendly_name:'Hospital · ' + account.name},await api.token());
      account.factor_id = factor.id; account.totp_secret = factor.totp.secret;
      saveAccounts(data); // Persist before verification so the factor cannot become inaccessible.
    }
    if (account.factor_id && account.totp_secret) {
      await api.verifyTOTP(account.factor_id,totp(account.totp_secret));
      result = await api.access(); assert.equal(result.access.aal,'aal2');
    } else assert.equal(factors.filter(f => f.status === 'verified').length,0,'An unknown enrolled factor requires user action');
    const profile = await api.rpc('my_profile'); assert.equal(profile.profile.id,account.id);
    const rooms = await api.read('rooms'); assert.equal(rooms.data.length,11);
    const resource = context.HospitalCore.turnResource(account.role);
    const turns = await api.read(resource,null,account.entity_id);
    assert.ok(Array.isArray(turns.data));
    const from = new Date(); from.setHours(0,0,0,0); const to = new Date(from); to.setDate(to.getDate()+1);
    let summaryStatus = 'passed';
    try {
      const summary = await api.rpc('my_activity_summary',{p_facility:result.access.roles[0].facility_id,p_from:from.toISOString(),p_to:to.toISOString(),p_context:account.role === 'doctor' ? 'staff' : 'patient'});
      assert.equal(typeof summary[account.role === 'doctor' ? 'scheduled_appointments' : 'upcoming_appointments'],'number');
    } catch (error) { if (error.status !== 403 || result.access.aal === 'aal2') throw error; summaryStatus = 'requires_mfa'; }
    api.expiry = 0; await api.token(); // Exercise the real refresh endpoint and token rotation.
    assert.equal((await api.access()).access.profile.id,account.id);
    const revoked = await api.token();
    assert.equal(await api.signOut(),null);
    assert.equal(storage.getItem(api.storageKey),null);
    const response = await fetch(config.url + '/rest/v1/rpc/my_access',{method:'POST',headers:{apikey:config.publishableKey,Authorization:'Bearer ' + revoked,'Content-Type':'application/json'},body:'{}'});
    assert.ok([401,403].includes(response.status),'Revoked session must fail even with a previously issued JWT');
    checks.push({role:account.role,email:account.email,status:'passed',mfa:result.access.aal,rooms:rooms.data.length,turns:turns.data.length,summary:summaryStatus,refresh:'passed',revocation:'passed'});
    console.log(`${account.role}: contraseña inválida rechazada; login, rol, perfil, 11 habitaciones, turnos, refresh y revocación APROBADOS; resumen: ${summaryStatus}`);
  } finally { if (api.session) await api.signOut(); }
}
saveAccounts(data);
writeFileSync(new URL('docs/login-verification.json',root),JSON.stringify({project:'kgulityewtcyvjnxeskd',checked_at:new Date().toISOString(),transport:'Supabase Auth + PostgREST HTTPS',accounts:checks,contains_credentials:false},null,2));
console.log('Credenciales y secretos solo en .local/CREDENCIALES_PRUEBA.md; informe sin secretos en docs/login-verification.json.');
