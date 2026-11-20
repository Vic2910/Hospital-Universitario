// Mi horario del médico con transporte simulado: jornada de administración (doctor_schedules, staff_shifts y staff_absences).
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const zone='America/El_Salvador',key=d=>new Intl.DateTimeFormat('en-CA',{timeZone:zone}).format(d);
const today=new Date(),monday=new Date(today.getTime()-((new Date(key(today)+'T12:00:00-06:00').getUTCDay()+6)%7)*86400000),mondayKey=key(monday);
const weekday=new Date(key(today)+'T12:00:00-06:00').getUTCDay();
const schedules=[{id:'s1',doctor_id:'x',weekday,start_time:'07:00:00',end_time:'12:00:00',valid_from:null,valid_until:null,active:true},
  {id:'s2',doctor_id:'x',weekday,start_time:'13:00:00',end_time:'17:00:00',valid_from:null,valid_until:null,active:true}];
// Otro día de la misma semana (lunes a domingo): el siguiente, o el anterior si hoy es domingo.
const tomorrow=new Date(new Date(key(today)+'T00:00:00-06:00').getTime()+(weekday===0?-1:1)*86400000);
const absences=[{id:'a1',staff_id:'x',starts_at:tomorrow.toISOString(),ends_at:new Date(tomorrow.getTime()+86400000).toISOString(),reason:'Capacitación',active:true}];
const calls=[];let rpcReady=false;
const lunchStart=new Date(key(today)+'T12:00:00-06:00').toISOString(),lunchEnd=new Date(key(today)+'T13:00:00-06:00').toISOString();
const ui=createApp(['doctor'],{transport:async url=>{
  if(url.includes('/rest/v1/doctor_schedules?')){calls.push(url);return {body:schedules};}
  if(url.includes('/rest/v1/staff_absences?'))return {body:absences};
  // doctor_native_schedule: sin aplicar → 404; aplicada → descanso registrado «Almuerzo».
  if(url.endsWith('/rpc/doctor_native_schedule'))return rpcReady?{body:{work:[],breaks:[{starts_at:lunchStart,ends_at:lunchEnd,reason:'Almuerzo'}],shifts:[],absences}}:{status:404,body:{code:'PGRST202'}};
}});
await ui.login();
const more=ui.app.all().find(n=>n.tagName==='button'&&/Más/.test(n.textContent));await ui.click(more.textContent);
const entry=ui.app.all().find(n=>n.tagName==='button'&&/Mi horario/.test(n.textContent));assert.ok(entry,'La pantalla existente Mi horario');await ui.click(entry.textContent);
const text=()=>ui.app.textContent;
for(const value of ['MI HORARIO','Hoy','07:00 – 12:00','13:00 – 17:00','⏸Entre jornadas12:00 – 13:00','Ausencia · Capacitación','Todo el día','Día libre','9 h de jornada'])assert.ok(text().includes(value),'Mi horario: '+value);
assert.ok(calls.some(u=>u.includes('doctor_id=eq.')&&u.includes('active=eq.true')),'Solo la jornada propia y activa (RLS por médico)');
assert.equal(text().includes('🍽'),false,'Un hueco sin registro no se presenta como almuerzo');
rpcReady=true;await ui.click('Semana siguiente');assert.equal(text().includes('Hoy'),false,'Otra semana');await ui.click('Esta semana');assert.match(text(),/Hoy/);
assert.match(text(),/🍽Almuerzo12:00 – 13:00/u,'Almuerzo registrado por administración');assert.equal(text().includes('⏸'),false,'El hueco ya cubierto por el almuerzo registrado');
console.log('OK Mi horario: semana con bloques de mañana y tarde, hueco «Entre jornadas» distinto del almuerzo registrado, ausencia, día libre y navegación semanal');
