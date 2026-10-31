(function(root){
  'use strict';
  const missing='No hay datos reales';
  class HospitalPatientPrescriptions {
    static examples=[
      {id:'rx-demo-1',issuedAt:'2026-10-30T09:00:00-06:00',dateLabel:'30 oct 2026',pickup:'Pendiente',medicines:[{name:'MEDICAMENTO DE EJEMPLO',dose:'1 unidad',frequency:'24 horas',route:'Oral',duration:'5 días',quantity:'5 unidades',observations:'Ejemplo de receta pendiente de retirar.'}]},
      {id:'rx-demo-2',issuedAt:'2026-10-01T14:25:00-06:00',dateLabel:'1 oct 2026',pickup:'Retirada',medicines:[{name:'CLARITROMICINA 500 MG / TABLETA',dose:'1 tableta',frequency:'12 horas',route:'Oral',duration:'10 días',quantity:'20 tabletas',observations:'Datos ilustrativos de la referencia visual.'}]}
    ];
    static fromItems(items){return items.map(item=>{
      const fields=item.details||[],state=(fields.find(field=>field.label.toLocaleLowerCase('es')==='estado de retiro')?.value||item.status||'').trim().toLowerCase();
      const pickup=['retirada','dispensed','collected','withdrawn'].includes(state)?'Retirada':['pendiente','pickup_pending','pending'].includes(state)?'Pendiente':'Retiro por confirmar';
      const date=new Date(item.event_at),dateLabel=Number.isFinite(date.getTime())?new Intl.DateTimeFormat('es-GT',{timeZone:'America/Guatemala',day:'numeric',month:'short',year:'numeric'}).format(date):missing;
      const medicines=fields.filter(field=>field.label.toLocaleLowerCase('es')!=='estado de retiro').map(field=>({name:field.label,dose:missing,frequency:missing,route:missing,duration:missing,quantity:missing,observations:field.value||missing}));
      return{id:item.id,issuedAt:item.event_at,dateLabel,pickup,medicines:medicines.length?medicines:[{name:item.title,dose:missing,frequency:missing,route:missing,duration:missing,quantity:missing,observations:item.subtitle||missing}]};
    });}
    constructor(ui){this.ui=ui;}
    render(parent,{records,demonstration,search='',loading=false,error=null,hasMore=false,retry,loadMore}){
      const{el,button}=this.ui,fold=value=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
      parent.append(el('h2','Mis recetas','section-title'));
      if(demonstration)parent.append(el('p','Recetas de ejemplo · No corresponden a una prescripción real','patient-history-notice'));
      if(loading)parent.append(el('p','Cargando tus recetas…','scope-note'));
      if(error){parent.append(el('p',error,'scope-note'));if(retry)parent.append(button('Reintentar',retry,'module-action'));}
      const rows=records.filter(record=>fold([record.dateLabel,record.pickup,...record.medicines.map(medicine=>medicine.name+' '+medicine.observations)].join(' ')).includes(fold(search))).sort((a,b)=>(Date.parse(b.issuedAt)||0)-(Date.parse(a.issuedAt)||0));
      if(!rows.length&&!loading&&!error){const empty=el('article',null,'sched-card');empty.append(el('strong','No hay recetas para mostrar.'),el('p','Tus recetas aparecerán aquí cuando estén disponibles.','sched-hint'));parent.append(empty);}
      for(const record of rows){
        parent.append(el('h3',record.dateLabel,'patient-rx-date'));
        for(const medicine of record.medicines){
          const card=el('article',null,'patient-rx-card');card.append(el('span',record.pickup,'patient-rx-state '+(record.pickup==='Retirada'?'is-collected':record.pickup==='Pendiente'?'is-pending':'is-unknown')));
          const title=el('div',null,'patient-rx-title');const icon=el('span','\u25c7');icon.setAttribute('aria-hidden','true');title.append(icon,el('h3',medicine.name));card.append(title);
          for(const[label,text]of[['Dosis',medicine.dose],['Cada',medicine.frequency],['Vía',medicine.route],['Durante',medicine.duration],['Cantidad',medicine.quantity]]){const line=el('div',null,'patient-rx-line');line.append(el('strong',label+':'),el('span',text));card.append(line);}
          const observation=el('div',null,'patient-rx-observations');observation.append(el('strong','Observaciones:'),el('p',medicine.observations));card.append(observation);parent.append(card);
        }
      }
      if(hasMore&&loadMore)parent.append(button('Cargar más',loadMore,'module-action'));
    }
  }
  root.HospitalPatientPrescriptions=HospitalPatientPrescriptions;
})(typeof window!=='undefined'?window:globalThis);
