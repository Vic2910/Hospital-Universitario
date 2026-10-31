(function(root){
  'use strict';
  class HospitalPatientHistory {
    static examples=[
      {id:'history-demo-1',startedAt:'2026-10-01T14:25:00-06:00',dateLabel:'1 oct 2026',timeLabel:'14:25',specialty:'Dermatología',doctor:'Dra. Marta Romero',reason:'Citada dermatológico',details:[]},
      {id:'history-demo-2',startedAt:'2026-09-02T13:30:00-06:00',dateLabel:'2 sept 2026',timeLabel:'13:30',specialty:'Cardiología',doctor:'Dr. Diego Santos',reason:'Consulta cardiológica',details:[]},
      {id:'history-demo-3',startedAt:'2026-04-15T08:35:00-06:00',dateLabel:'15 abr 2026',timeLabel:'08:35',specialty:'Medicina general',doctor:'Dra. Laura Campos',reason:'Revisión general',details:[]}
    ];
    constructor(ui){this.ui=ui;this.clear();}
    clear(){this.selected='';}
    static fromItems(items){return items.map(item=>{
      const details=item.details||[],value=(labels,fallback)=>{const text=details.find(field=>labels.some(label=>field.label.toLocaleLowerCase('es')===label.toLocaleLowerCase('es')))?.value??fallback;return typeof text==='string'&&text.trim()?text.trim():'No hay datos reales';};
      const date=new Date(item.event_at),valid=Number.isFinite(date.getTime()),options={timeZone:'America/Guatemala'};
      return{id:item.id,startedAt:item.event_at,dateLabel:valid?new Intl.DateTimeFormat('es-GT',{...options,day:'numeric',month:'short',year:'numeric'}).format(date):'No hay datos reales',timeLabel:valid?new Intl.DateTimeFormat('es-GT',{...options,hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(date):'No hay datos reales',specialty:value(['Especialidad'],item.title),doctor:value(['Médico','Doctor','Doctor solicitante']),reason:value(['Motivo','Motivo de consulta'],item.subtitle),details};
    });}
    render(parent,{records,demonstration,search='',loading=false,error=null,hasMore=false,retry,loadMore}){
      const{el,button,repaint}=this.ui,ordered=[...records].sort((a,b)=>(Date.parse(b.startedAt)||0)-(Date.parse(a.startedAt)||0));
      const fold=value=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
      const notice=()=>el('p','Datos de ejemplo · No son registros clínicos reales','patient-history-notice');
      if(loading)parent.append(el('p','Cargando tu historial…','scope-note'));
      if(error){parent.append(el('p',error,'scope-note'));if(retry)parent.append(button('Reintentar',retry,'module-action'));}
      const selected=ordered.find(record=>record.id===this.selected);
      if(selected){
        const ticket=el('section',null,'clinical-ticket patient-history-detail');ticket.id='patient-history-detail';ticket.tabIndex=-1;ticket.setAttribute('role','region');ticket.setAttribute('aria-label','Detalle de mi consulta');
        const navigation=el('div',null,'clinical-ticket-nav');navigation.append(button('Volver',()=>{this.selected='';repaint();},'text-button'),el('span','MI HISTORIAL'));ticket.append(navigation,el('h2','Detalle de consulta','clinical-ticket-title'));
        const date=el('div',null,'clinical-ticket-context');date.append(el('strong',selected.dateLabel),el('strong',selected.timeLabel));ticket.append(date);if(demonstration)ticket.append(notice());
        for(const[label,text]of[['Especialidad',selected.specialty],['Médico',selected.doctor],['Motivo de la consulta',selected.reason],...(selected.details||[]).map(field=>[field.label,field.value||'No hay datos reales'])]){const field=el('div',null,'consult-field');field.append(el('span',label),el('p',text));ticket.append(field);}parent.append(ticket);return;
      }
      parent.append(el('h2','Mis consultas','section-title'));if(demonstration)parent.append(notice());
      const matches=ordered.filter(record=>fold([record.dateLabel,record.specialty,record.doctor,record.reason].join(' ')).includes(fold(search)));
      if(!matches.length&&!loading&&!error){const empty=el('article',null,'sched-card');empty.append(el('strong','Tu historial está listo para acompañarte'),el('p',search?'No encontramos consultas con esa búsqueda. Prueba con otra fecha, especialidad o médico.':'Aún no hay consultas registradas. Aparecerán aquí cuando estén disponibles.','sched-hint'));parent.append(empty);}
      for(const record of matches){
        const card=button(null,()=>{this.selected=record.id;repaint();document.querySelector('#patient-history-detail')?.focus?.();},'patient-history-card');card.setAttribute('aria-label','Ver consulta del '+record.dateLabel+' con '+record.doctor);
        const header=el('div',null,'patient-history-date');header.append(el('strong',record.dateLabel),el('time',record.timeLabel));
        const reason=el('div',null,'patient-history-reason');reason.append(el('span','Motivo'),el('p',record.reason));
        card.append(header,el('p',record.specialty,'patient-history-specialty'),el('strong',record.doctor,'patient-history-doctor'),reason);parent.append(card);
      }
      if(hasMore&&loadMore)parent.append(button('Cargar más',loadMore,'module-action'));
    }
  }
  root.HospitalPatientHistory=HospitalPatientHistory;
})(typeof window!=='undefined'?window:globalThis);
