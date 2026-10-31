import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const open=async ui=>{await ui.click('Más');await ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.toLowerCase().startsWith('historial')).textContent);};
for(const mode of ['design','empty-session']){
  const ui=createApp(['patient']);await settle();if(mode==='design'){ui.get('design-patient').listeners.click();await settle();}else await ui.login();await open(ui);
  const cards=()=>ui.app.all().filter(node=>node.className==='patient-history-card');
  assert.equal(cards().length,3);assert.match(cards()[0].textContent,/1 oct 2026.*14:25.*Dermatología.*Dra. Marta Romero.*Citada dermatológico/);assert.match(cards()[1].textContent,/2 sept 2026.*13:30.*Cardiología.*Dr. Diego Santos.*Consulta cardiológica/);assert.match(cards()[2].textContent,/15 abr 2026.*08:35.*Medicina general.*Dra. Laura Campos.*Revisión general/);
  for(const [date,doctor,reason]of[['1 oct 2026','Dra. Marta Romero','Citada dermatológico'],['2 sept 2026','Dr. Diego Santos','Consulta cardiológica'],['15 abr 2026','Dra. Laura Campos','Revisión general']]){
    await ui.click('Ver consulta del '+date+' con '+doctor);assert.match(ui.app.textContent,/Detalle de consulta/);assert.ok(ui.app.textContent.includes(reason));assert.ok(ui.app.all().some(node=>node.attributes['aria-label']==='Detalle de mi consulta'));assert.equal(ui.app.all().some(node=>node.tagName==='dialog'),false);assert.equal(cards().length,0);await ui.click('Volver');assert.equal(cards().length,3);
  }
  const search=ui.app.all().find(node=>node.tagName==='input'&&node.type==='search');await ui.input(search.attributes['aria-label'],'dermatologia');assert.equal(cards().length,1);
  await ui.input(search.attributes['aria-label'],'sin coincidencias');assert.match(ui.app.textContent,/No encontramos consultas/);assert.equal(cards().length,0);
  assert.equal(ui.calls.some(call=>/save_consultation|create_record|start_consultation/.test(call.url)),false);
  if(mode==='design')assert.equal(ui.calls.some(call=>call.url.startsWith('https:')),false);
  console.log('OK Historial '+mode+': tres datos exactos, orden, búsqueda, detalle interno y solo lectura');
}
const item={id:'00000000-0000-4000-8000-000000000001',title:'Especialidad propia',subtitle:'Motivo propio',status:'closed',event_at:'2026-10-20T09:00:00-06:00',row_version:1,details:[{label:'Médico',value:'Doctora autorizada'},{label:'Plan',value:'Nota publicada propia'}],action:null,document_id:null};
const live=createApp(['patient'],{transport:async(url,params)=>url.endsWith('/mobile_module')&&params.p_module==='history'?{body:{items:[item],sections:[],options:[],preferences:[],has_more:false,next_cursor:null}}:undefined});await live.login();await open(live);
assert.match(live.app.textContent,/Especialidad propia/);assert.equal(live.app.textContent.includes('Dra. Marta Romero'),false,'No mezclar ejemplos con registros reales');
const request=live.calls.findLast(call=>call.url.endsWith('/mobile_module')).params;assert.equal(request.p_role,'patient');assert.equal(request.p_module,'history');assert.equal(Object.hasOwn(request,'p_patient'),false);
await live.click(live.app.all().find(node=>node.className==='patient-history-card').attributes['aria-label']);assert.match(live.app.textContent,/Nota publicada propia/);
const failed=createApp(['patient'],{transport:async(url,params)=>url.endsWith('/mobile_module')&&params.p_module==='history'?{status:500,body:{message:'Error de prueba'}}:undefined});await failed.login();await open(failed);assert.equal(failed.app.textContent.includes('Dra. Marta Romero'),false);assert.match(failed.app.textContent,/No pudimos cargar/);
console.log('OK Historial real simulado: datos propios, detalle completo y error sin ejemplos falsamente reales');
await import('../web-preview/patient-history.js');const Element=live.app.constructor,parent=new Element('div');const el=(tag,text,className)=>{const node=new Element(tag);if(text!=null)node.textContent=text;if(className)node.className=className;return node;};new globalThis.HospitalPatientHistory({el,button:el,repaint(){}}).render(parent,{records:[],demonstration:false});assert.match(parent.textContent,/Aún no hay consultas registradas/);
console.log('OK Historial vacío: mensaje amable sin pantalla en blanco');
