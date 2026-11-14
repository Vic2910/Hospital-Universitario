import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const contract=JSON.parse(read('HospitalUniversitario/HospitalUniversitario/Shared/contract.json'));
const context={Date,console,AbortSignal};
runInNewContext(read('HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js'),context);
runInNewContext(read('web-preview/api.js'),context);
const c=context.HospitalCore,plain=v=>JSON.parse(JSON.stringify(v)),id='00000000-0000-4000-8000-000000000001';
const registration=plain(c.registrationAccount({first_name:' Ana ',last_name:' Prueba ',dui:'012345678',role:'doctor',profile_id:id,patient_id:id}));
assert.equal(registration.dui,'01234567-8');assert.equal(registration.first_name,'Ana');assert.equal('role'in registration,false);assert.equal('patient_id'in registration,false);assert.equal('profile_id'in registration,false);
for (const invalid of [
  {...contract, url:'https://otro-proyecto.example.test'},
  {...contract, url:contract.url + '/otro'},
  {...contract, publishableKey:'invalid-key'}
]) {
  assert.throws(()=>new context.HospitalAPI(invalid, {fetch:()=>assert.fail('No debe salir a la red')}), /Hospital Móviles/);
}
console.log('OK Configuración: rechazo de otro proyecto o clave incompatible antes de usar la red');
const user={id,email:'ana@example.test',user_metadata:{role:'doctor'}},profile={id,first_name:'Ana',last_name:'Prueba',phone:'7000-1111'};
const pending=c.backendAccess(user,profile,[{user_id:id,role:'paciente',active:true}],[],[]);
assert.equal(pending.profile.status,'active');assert.deepEqual(plain(c.routes(pending)),['patient']);
for(const module of ['appointments','request','chart','history','laboratory','prescriptions']) {
  assert.deepEqual(plain(c.backendPlan('module',{p_module:module},pending)),[],'Sin vínculo no hay consulta clínica');
  assert.deepEqual(plain(c.backendPresent('module',{p_module:module},pending,[])).items,[]);
}
assert.deepEqual(plain(c.backendPlan('patientDashboard',{},pending)),[]);
assert.equal(c.backendPresent('patientDashboard',{},pending,[]).next_appointment,null);
assert.throws(()=>c.backendPlan('requestAttention',{},pending));
const multi=c.backendAccess(user,{...profile,first_name:'María Elena',last_name:'López Pérez'},[{user_id:id,role:'paciente',active:true}],[],[]);
assert.equal(multi.profile.greeting_name,'María López');
const access=c.backendAccess(user,profile,[{user_id:id,role:'paciente',active:true}],[{id,profile_id:id}],[]);
assert.deepEqual(plain(c.routes(access)),['patient']);
const dashboardPath=decodeURIComponent(c.backendPlan('patientDashboard',{now:'2026-11-13T10:00:00Z'},access)[0].path);
assert.match(dashboardPath,/patient_id=eq\./);assert.match(dashboardPath,/status=in\.\(programada,confirmada\)/);
assert.match(dashboardPath,/starts_at=gte\./);assert.match(dashboardPath,/order=starts_at.asc,id.asc/);assert.match(dashboardPath,/limit=1$/);
const other={id,patient_id:'00000000-0000-4000-8000-000000000002',starts_at:'2026-11-14T10:00:00Z',status:'confirmada'};
assert.equal(c.backendPresent('patientDashboard',{now:'2026-11-13T10:00:00Z'},access,[[other]]).next_appointment,null);
assert.deepEqual(plain(c.routes(c.backendAccess(user,profile,[],[{id,profile_id:id}],[]))),[],'User metadata never grants a role');
assert.deepEqual(plain(c.routes(c.backendAccess(user,profile,[{user_id:id,role:'paciente',active:false}],[{id,profile_id:id}],[]))),[]);
const doctor=c.backendAccess(user,profile,[{user_id:id,role:'doctor',active:true}],[],[{id,profile_id:id,active:true}]);
assert.deepEqual(plain(c.routes(doctor)),['doctor']);
assert.throws(()=>c.backendAccess(user,{id:'other'},[],[],[]));
console.log('OK Acceso: roles activos del servidor y vínculos propios; metadatos sin autoridad');
assert.throws(()=>c.backendPlan('registerPatient',{dui:'01234567-8'},pending), /personal autorizado/);
assert.throws(()=>c.backendPlan('registerPatient',{},access), /personal autorizado/);
for(const module of ['appointments','request','chart','history','laboratory','prescriptions']){
  const plan=plain(c.backendPlan('module',{p_module:module},access));
  assert.ok(decodeURIComponent(plan[0].path).includes(id));
  assert.equal(plan[0].method,'GET');
}
assert.throws(()=>c.backendPlan('module',{p_module:'chart'},doctor));
assert.throws(()=>c.backendPlan('unavailable',{},access));
const bounds=c.periodBounds(c.weekWindow('2026-11-13T10:00:00Z'));
assert.equal(new Date(bounds.start).getDay(),1);assert.equal(new Date(bounds.end).getDay(),1);
const shifts=decodeURIComponent(c.backendPlan('shifts',{},doctor)[0].path);
assert.match(shifts,/staff_id=eq\./);assert.match(shifts,/starts_at=lt\./);assert.match(shifts,/ends_at=gt\./);
console.log('OK Consultas: filtros propios, semana, esquema nuevo y rechazo de operaciones inexistentes');
const published={summary:'PUBLICADO',published_to_patient_at:'2026-11-13',published_at:'2026-11-13',validated_at:'2026-11-13',validated_by:id,parameter_schema:[{key:'local',label:'Parámetro local',unit:'Unidad local',reference:'Referencia local'}],result_values:{local:{value:'Valor local',observation:'Observación local'}}};
const page=c.backendPresent('module',{p_module:'laboratory'},access,[[{id,reason:'Examen',status:'completado',ordered_at:'2026-11-13',lab_test_types:{name:'Estudio'},lab_results:[{summary:'NO PUBLICADO',published_to_patient_at:null},published]}]]);
assert.equal(page.items[0].details[0].value,'PUBLICADO');assert.equal(page.items[0].status,'released');assert.match(page.items[0].details[1].value,/Valor local.*Unidad local.*Referencia local.*Observación local/);
const withheld=c.backendPresent('module',{p_module:'laboratory'},access,[[{id,status:'completado',lab_results:[{...published,validated_at:null},{...published,published_to_patient_at:null}]}]]);
assert.equal(withheld.items[0].status,'awaiting_release');assert.equal(withheld.items[0].details.length,0);
const roomPage=c.backendPresent('rooms',{},access,[Array.from({length:26},()=>({id}))]);assert.equal(roomPage.data.length,25);assert.equal(roomPage.has_more,true);
console.log('OK Presentación: resultados publicados y paginación sin filas perdidas');
const stored=new Map(),storage={getItem:k=>stored.get(k)||null,setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)};
const response=(data,status=200)=>({ok:status<300,status,json:async()=>data,text:async()=>JSON.stringify(data)});
let refreshes=0,offline=false;
const api=new context.HospitalAPI(contract,{storage,fetch:async(url,request)=>{
  if(offline)throw new Error('offline');
  if(url.includes('grant_type=refresh_token')){refreshes++;return response({access_token:'renewed',refresh_token:'rotated',expires_in:3600});}
  if(url.includes('/token?'))return response({access_token:'test',refresh_token:'refresh',expires_in:3600});
  return response(null);
}});
await api.signIn('ana@example.test','test-password');api.expiry=0;
await Promise.all([api.token(),api.token()]);assert.equal(refreshes,1);assert.equal(storage.getItem(api.storageKey),'rotated');
offline=true;await api.signOut();assert.equal(stored.size,0);assert.equal(api.context,null);
assert.ok(api.storageKey.includes('uvebpsbbwofthucghccc'));
console.log('OK Sesión: renovación concurrente, aislamiento de proyecto y cierre sin red');
assert.equal(contract.models.Room.floor_id,'Int');assert.equal(contract.models.StaffShift.starts_at,'String');
