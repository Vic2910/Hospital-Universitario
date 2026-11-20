// Agenda de dos filtros (PENDIENTES / FINALIZADAS) con transporte simulado y datos sintéticos; sin Supabase.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const zone='America/El_Salvador',key=offset=>new Intl.DateTimeFormat('en-CA',{timeZone:zone}).format(new Date(Date.now()+offset*86400000));
const today=key(0),yesterday=key(-1);
const at=(day,time)=>new Date(day+'T'+time+':00-06:00').toISOString();
const pg=iso=>iso.replace('T',' ').replace('.000Z','+00');
const slot=(day,time)=>'["'+pg(at(day,time))+'","'+pg(new Date(Date.parse(at(day,time))+1800000).toISOString())+'")';
let n=0;const row=(name,day,time,status,extra={})=>({id:'00000000-0000-4000-8000-'+String(++n).padStart(12,'0'),patient_id:'00000000-0000-4000-8000-1'+String(n).padStart(11,'0'),patient_name:name,record_number:'EXP-'+n,phone:null,ticket_number:null,period:slot(day,time),status,encounter_id:['in_progress','completed'].includes(status)?'00000000-0000-4000-8000-2'+String(n).padStart(11,'0'):null,reason:'Motivo '+name,room_code:'C-'+n,duration_minutes:30,...extra});
const appointments=[
 row('Ocho Programada',today,'08:00','scheduled'),row('Seis Confirmada',today,'06:00','confirmed'),row('Siete En Atención',today,'07:00','in_progress'),
 row('Abierta Ayer',yesterday,'23:30','in_progress'),row('Pendiente Ayer',yesterday,'09:00','scheduled'),
 row('Cancelada Hoy',today,'09:00','cancelled'),row('Ausente Hoy',today,'10:00','no_show'),
 row('Hecha Diez',today,'06:30','completed',{finished_at:at(today,'10:00')}),row('Hecha Nueve',today,'07:30','completed',{finished_at:at(today,'09:00')}),
 row('Finalizada Tarde',yesterday,'23:00','completed',{finished_at:at(today,'00:20')}),row('Hecha Ayer',yesterday,'08:00','completed',{finished_at:at(yesterday,'08:40')}),
 row('José Pérez',today,'11:00','scheduled',{patient_code:'PAC-0042'})];
const windows=[];
const ui=createApp(['doctor'],{transport:async(url,p)=>{
 if(url.endsWith('/rpc/doctor_native_workspace')){windows.push(p);return {body:{doctor_name:'Médico autorizado',facility_name:'Hospital Universitario',appointments,orders:[],tests:[],medications:[],notifications:[],stats:{consultations:appointments.length,completed_consultations:4,issued_orders:0,pending_orders:0}}};}
 if(url.endsWith('/rpc/doctor_native_chart'))return {body:{patient:{id:p.p_patient,full_name:'Paciente',record_number:'EXP'},allergies:[],conditions:[],history:[],prescriptions:[]}};
}});
const text=()=>ui.app.textContent,order=names=>names.map(name=>text().indexOf(name));
await ui.login();await ui.click('Consultas');
assert.match(text(),/Consultas pendientes/);assert.match(text(),/HOY/);
const last=windows.at(-1);assert.equal(new Date(last.p_from).toISOString(),new Date(key(-2)+'T00:00:00-06:00').toISOString(),'Pide desde 2 días antes del día elegido');
assert.equal('doctor_id' in last,false,'El cliente no envía la identidad del médico; el servidor filtra por native_doctor_id()');
const pending=order(['Abierta Ayer','Seis Confirmada','Siete En Atención','Ocho Programada','José Pérez']);
assert.ok(pending.every((value,index)=>value>=0&&(index===0||value>pending[index-1])),'Pendientes por hora ascendente y en atención de ayer retomable');
for(const absent of ['Cancelada Hoy','Ausente Hoy','Hecha Diez','Pendiente Ayer'])assert.equal(text().includes(absent),false,'No aparece en Pendientes: '+absent);
assert.match(text(),/5PENDIENTES/);assert.match(text(),/Pendiente/);{const t=text().split('Ocho Programada').join('');const m=t.match(/Programada|Atendida/);assert.equal(m,null,'PENDIENTES solo muestra Pendiente o En consulta: '+(m&&t.slice(Math.max(0,m.index-60),m.index+20)));}assert.match(text(),/3FINALIZADAS/);
await ui.click('FINALIZADAS');assert.match(text(),/Consultas finalizadas/);
const finished=order(['Hecha Diez','Hecha Nueve','Finalizada Tarde']);
assert.ok(finished.every((value,index)=>value>=0&&(index===0||value>finished[index-1])),'Finalizadas por hora real de finalización, la última primero');
for(const absent of ['Seis Confirmada','Siete En Atención','Hecha Ayer'])assert.equal(text().includes(absent),false,'No aparece en Finalizadas de hoy: '+absent);
// Canceladas y no atendidas: sección aparte, después de las atendidas, con su estado.
const closedAt=text().indexOf('Canceladas y no atendidas');assert.ok(closedAt>text().indexOf('Finalizada Tarde'),'Sección aparte tras las atendidas');
assert.ok(text().indexOf('Cancelada Hoy')>closedAt&&text().indexOf('Ausente Hoy')>closedAt);assert.match(text(),/No atendida/);assert.match(text(),/3FINALIZADAS/,'El contador solo cuenta consultas atendidas');
assert.match(text(),/Finalizada a las/);
// Etiquetas visibles: Atendida en finalizadas; Cancelada y No atendida en su sección; Pendiente en PENDIENTES.
assert.match(text().slice(0,closedAt),/Atendida/);assert.match(text().slice(closedAt),/Cancelada/);assert.match(text().slice(closedAt),/No atendida/);
// Búsqueda junto con filtro y fecha.
await ui.input('Buscar consultas','nueve');assert.match(text(),/Hecha Nueve/);assert.equal(text().includes('Hecha Diez'),false);
await ui.input('Buscar consultas','');await ui.click('PENDIENTES');
for(const [query,expected] of [['perez','José Pérez'],['pac-0042','José Pérez'],['jose perez','José Pérez'],['seis','Seis Confirmada']]){
 await ui.input('Buscar consultas',query);assert.match(text(),new RegExp(expected));assert.equal(text().includes('Ocho Programada'),false,'Solo coincidencias: '+query);
}
await ui.input('Buscar consultas','zzz');assert.match(text(),/Sin coincidencias/);await ui.input('Buscar consultas','');
// Fecha anterior: sus pendientes y sus finalizadas reales.
await ui.click('Día anterior');assert.match(text(),/AYER/);
assert.equal(new Date(windows.at(-1).p_from).toISOString(),new Date(key(-3)+'T00:00:00-06:00').toISOString(),'Al cambiar la fecha se consulta de nuevo');
assert.ok(text().indexOf('Pendiente Ayer')>=0&&text().indexOf('Pendiente Ayer')<text().indexOf('Abierta Ayer'));
await ui.click('FINALIZADAS');assert.match(text(),/Hecha Ayer/);assert.equal(text().includes('Finalizada Tarde'),false,'Se agrupa por fecha de finalización, no por fecha de la cita');
await ui.click('Hoy');assert.match(text(),/HOY/);
assert.equal(ui.calls.filter(c=>/doctor_native_(start|save|finish)$/.test(c.url)).length,0,'Consultar la agenda no abre ni modifica consultas');
console.log('OK Agenda: PENDIENTES por hora y FINALIZADAS por hora real de finalización, canceladas excluidas, en atención retomable, búsqueda por nombre/apellido/código, fecha anterior, Hoy y ventana pedida al servidor');
