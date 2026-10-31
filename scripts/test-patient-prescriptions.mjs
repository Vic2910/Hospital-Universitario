import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const open=async ui=>ui.click(ui.app.all().find(node=>node.tagName==='button'&&node.textContent.endsWith('Recetas')).textContent);
for(const mode of ['design','empty-session']){
 const ui=createApp(['patient']);await settle();if(mode==='design'){ui.get('design-patient').listeners.click();await settle();}else await ui.login();
 assert.equal(ui.app.all().some(node=>node.tagName==='button'&&node.children.some(child=>child.tagName==='strong'&&child.textContent==='Paciente')),false,'Card Paciente retirada');
 await open(ui);const cards=ui.app.all().filter(node=>node.className==='patient-rx-card');assert.equal(cards.length,2);assert.match(cards[0].textContent,/Pendiente/);assert.match(cards[1].textContent,/Retirada/);
 assert.ok(ui.app.textContent.indexOf('30 oct 2026')<ui.app.textContent.indexOf('1 oct 2026'));
 for(const text of ['CLARITROMICINA 500 MG / TABLETA','Dosis:','1 tableta','Cada:','12 horas','Vía:','Oral','Durante:','10 días','Cantidad:','20 tabletas','Observaciones:'])assert.ok(cards[1].textContent.includes(text),text);
 assert.match(ui.app.textContent,/Recetas de ejemplo/);assert.equal(ui.app.all().some(node=>['form','select','textarea'].includes(node.tagName)),false);
 const search=ui.app.all().find(node=>node.tagName==='input'&&node.type==='search');await ui.input(search.attributes['aria-label'],'retirada');assert.equal(ui.app.all().filter(node=>node.className==='patient-rx-card').length,1);
 await ui.input(search.attributes['aria-label'],'no coincide');assert.match(ui.app.textContent,/No hay recetas para mostrar/);
 assert.equal(ui.calls.some(call=>/update_record|mobile_issue_prescription/.test(call.url)),false);if(mode==='design')assert.equal(ui.calls.some(call=>call.url.startsWith('https:')),false);
 console.log('OK Recetas '+mode+': acceso nuevo, orden descendente, medicamento/detalle, Pendiente/Retirada, búsqueda y solo lectura');
}
const ids=['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002'];
const live=createApp(['patient'],{transport:async(url,params)=>url.endsWith('/mobile_module')&&params.p_module==='prescriptions'?{body:{items:[{id:ids[0],title:'Receta propia',status:'active',event_at:'2026-10-01T10:00:00-06:00',details:[{label:'Medicamento autorizado',value:'Indicaciones originales'}]},{id:ids[1],title:'Receta retirada',status:'collected',event_at:'2026-10-20T10:00:00-06:00',details:[{label:'Otro medicamento autorizado',value:'Texto original'}]}],sections:[],options:[],preferences:[],has_more:false,next_cursor:null}}:undefined});
await live.login();await open(live);const cards=live.app.all().filter(node=>node.className==='patient-rx-card');assert.match(cards[0].textContent,/Retirada/);assert.match(cards[1].textContent,/Retiro por confirmar/);assert.match(cards[1].textContent,/Indicaciones originales/);assert.equal(live.app.textContent.includes('CLARITROMICINA'),false,'No mezcla ejemplos con recetas reales');
const request=live.calls.findLast(call=>call.url.endsWith('/mobile_module')).params;assert.equal(request.p_role,'patient');assert.equal(request.p_module,'prescriptions');assert.equal(Object.hasOwn(request,'p_patient'),false);
console.log('OK Recetas propias: conserva indicaciones y no confunde tratamiento activo con retiro de farmacia');
