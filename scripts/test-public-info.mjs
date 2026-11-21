// Información pública (enunciado: ocupación general, médicos de turno y avisos generales). HTTP simulado; sin Supabase real.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {createApp} from './test-preview.mjs';
const context={console,Date,Intl,Math,JSON,encodeURIComponent,URL};context.globalThis=context;
runInNewContext(readFileSync(new URL('../HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js',import.meta.url),'utf8'),context);
const core=context.HospitalCore,plain=v=>JSON.parse(JSON.stringify(v));
const access={profile:{id:'00000000-0000-4000-8000-000000000001'},patient_id:'00000000-0000-4000-8000-000000000002',roles:[{code:'patient'}]};

// Plan: avisos públicos, camas (sin datos de pacientes) y la RPC public_on_duty.
const plan=core.backendPlan('overview',{},access);
assert.equal(plan.length,3);assert.match(plan[0].path,/\/rest\/v1\/announcements\?/);assert.match(plan[1].path,/\/rest\/v1\/beds\?select=state%2Cactive%2Crooms\(active\)/);
assert.equal(plan[1].path.includes('bed_assignments'),false,'La ocupación no consulta asignaciones de pacientes');
assert.deepEqual(plain(plan[2]),{path:'/rest/v1/rpc/public_on_duty',method:'POST',body:{}});

// Ocupación: solo camas en servicio; las inactivas o de habitaciones inactivas/no visibles no cuentan.
const beds=[{state:'ocupada',active:true,rooms:{active:true}},{state:'disponible',active:true,rooms:{active:true}},{state:'limpieza',active:true,rooms:{active:true}},
  {state:'disponible',active:false,rooms:{active:true}},{state:'ocupada',active:true,rooms:null}];
const future=new Date(Date.now()+86400000).toISOString(),past=new Date(Date.now()-86400000).toISOString();
const overview=core.backendPresent('overview',{},access,[[{id:'00000000-0000-4000-8000-0000000000b1',title:'Aviso vigente',content:'Contenido público',expires_at:future},{id:'00000000-0000-4000-8000-0000000000b2',title:'Aviso vencido',content:'x',expires_at:past}],
  beds,[{name:'Dra. Ana Prueba',specialty:'Cardiología'},{name:'',specialty:'x'}]]);
assert.equal(overview.capacity,3);assert.equal(overview.occupied,1);
assert.deepEqual(plain(overview.on_duty),[{name:'Dra. Ana Prueba',specialty:'Cardiología'}]);
assert.deepEqual(plain(overview.information.map(n=>n.title)),['Aviso vigente']);
const empty=core.backendPresent('overview',{},access,[[],[],null]);
assert.equal(empty.capacity,null);assert.equal(empty.occupied,null);assert.deepEqual(plain(empty.on_duty),[]);
console.log('OK Información pública (núcleo): plan, ocupación sin datos de pacientes, médicos de turno y avisos vigentes');

// Pantalla Información general del paciente con sesión (paridad con HospitalInformationView en Swift).
const ui=createApp(['patient'],{transport:async url=>{
  if(url.includes('/rest/v1/announcements?'))return{body:[{id:'00000000-0000-4000-8000-0000000000b1',title:'Aviso vigente',content:'Contenido público',published_at:past,expires_at:future}]};
  if(url.includes('/rest/v1/beds?'))return{body:beds};
  if(url.endsWith('/rpc/public_on_duty'))return{body:[{name:'Dra. Ana Prueba',specialty:'Cardiología'}]};
}});
await ui.login();await ui.click('Más');
await ui.click(ui.app.all().find(node=>node.tagName==='button'&&/Información general/.test(node.textContent)).textContent);
assert.match(ui.app.textContent,/1 de 3 camas/);assert.match(ui.app.textContent,/Dra\. Ana Prueba/);assert.match(ui.app.textContent,/Aviso vigente/);
assert.equal(ui.app.textContent.includes('Aviso vencido'),false);
console.log('OK Información general: ocupación, médicos de turno y avisos en la pantalla del paciente');
