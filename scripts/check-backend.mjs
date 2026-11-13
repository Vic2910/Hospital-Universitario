// Read-only connectivity checks. Does not create accounts, patients or sessions.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(new URL('../HospitalUniversitario/HospitalUniversitario/Shared/contract.json',import.meta.url)));
assert.equal(new URL(config.url).host,'uvebpsbbwofthucghccc.supabase.co');
const settings=await fetch(config.url+'/auth/v1/settings',{headers:{apikey:config.publishableKey},signal:AbortSignal.timeout(25000)});
assert.equal(settings.status,200);
const value=await settings.json();
assert.equal(value.disable_signup,false,'El registro público debe estar habilitado');
assert.equal(value.mailer_autoconfirm,true,'El flujo vigente no debe exigir confirmación de correo');
console.log('OK Hospital Móviles: Auth responde con la clave pública. Registro habilitado:',!value.disable_signup,'Confirmación automática:',value.mailer_autoconfirm);
for(const table of ['profiles','patients','user_roles']){
 const response=await fetch(config.url+'/rest/v1/'+table+'?select=*&limit=0',{headers:{apikey:config.publishableKey},signal:AbortSignal.timeout(25000)});
 assert.ok([401,403].includes(response.status),'Anonymous access must be denied: '+table+' ('+response.status+')');
 console.log('OK Sin sesión: acceso a '+table+' rechazado ('+response.status+')');
}
console.log('Solo conectividad y rechazo anónimo; registro real y aislamiento entre usuarios requieren recorrido autenticado.');
