(function(root){
  'use strict';
  // Historial propio del paciente (my_consultation_history). Paridad con PatientHistoryView.swift.
  // Solo muestra campos con valor real; agrupa el detalle en datos físicos, evaluación, recetas y exámenes.
  const PHYSICAL=['Peso (kg)','Altura (cm)','Temperatura (°C)','Presión sistólica (mmHg)','Presión diastólica (mmHg)','Frecuencia cardíaca (lpm)'];
  const EVALUATION=['Atención','Motivo de consulta','Síntomas reportados por el paciente','Otros síntomas reportados','Síntomas actuales','Exploración y observaciones','Diagnóstico','Código diagnóstico','Plan de tratamiento'];
  const real=value=>typeof value==='string'&&value.trim()!=='';
  class HospitalPatientHistory {
    static examples=[
      {id:'history-demo-1',startedAt:'2026-10-01T14:25:00-06:00',dateLabel:'1 oct 2026',timeLabel:'14:25',specialty:'Dermatología',doctor:'Dra. Marta Romero',reason:'Citada dermatológico',diagnosis:'',details:[]},
      {id:'history-demo-2',startedAt:'2026-09-02T13:30:00-06:00',dateLabel:'2 sept 2026',timeLabel:'13:30',specialty:'Cardiología',doctor:'Dr. Diego Santos',reason:'Consulta cardiológica',diagnosis:'',details:[]},
      {id:'history-demo-3',startedAt:'2026-04-15T08:35:00-06:00',dateLabel:'15 abr 2026',timeLabel:'08:35',specialty:'Medicina general',doctor:'Dra. Laura Campos',reason:'Revisión general',diagnosis:'',details:[]}
    ];
    constructor(ui){this.ui=ui;this.clear();}
    clear(){this.selected='';}
    static groups(details){
      const list=(details||[]).filter(field=>real(field.value));
      return [
        ['Datos físicos',list.filter(field=>PHYSICAL.includes(field.label))],
        ['Evaluación médica',EVALUATION.flatMap(label=>list.filter(field=>field.label===label))],
        ['Recetas',list.filter(field=>field.label.startsWith('Receta'))],
        ['Exámenes',list.filter(field=>field.label.startsWith('Examen'))]
      ].filter(([,fields])=>fields.length);
    }
    static fromItems(items){return items.map(item=>{
      const details=(item.details||[]).filter(field=>real(field.value)),value=labels=>details.find(field=>labels.some(label=>field.label.toLocaleLowerCase('es')===label.toLocaleLowerCase('es')))?.value?.trim()||'';
      const date=new Date(item.event_at),valid=Number.isFinite(date.getTime()),options={timeZone:'America/El_Salvador'};
      return{id:item.id,startedAt:item.event_at,dateLabel:valid?new Intl.DateTimeFormat('es-SV',{...options,day:'numeric',month:'short',year:'numeric'}).format(date):'Fecha no disponible',timeLabel:valid?new Intl.DateTimeFormat('es-SV',{...options,hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(date):'',
        specialty:value(['Especialidad'])||item.title||'Consulta médica',doctor:value(['Médico'])||'Médico responsable',reason:value(['Motivo de consulta','Motivo']),diagnosis:value(['Diagnóstico']),details};
    });}
    render(parent,{records,demonstration,search='',loading=false,error=null,hasMore=false,retry,loadMore}){
      const{el,button,repaint}=this.ui,ordered=[...records].sort((a,b)=>(Date.parse(b.startedAt)||0)-(Date.parse(a.startedAt)||0));
      const fold=value=>String(value||'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase();
      const notice=()=>el('p','Datos de ejemplo · No son registros clínicos reales','patient-history-notice');
      if(loading)parent.append(el('p','Cargando tu historial…','scope-note'));
      if(error){parent.append(el('p',error,'scope-note'));if(retry)parent.append(button('Reintentar',retry,'module-action'));}
      const selected=ordered.find(record=>record.id===this.selected);
      if(selected){
        const ticket=el('section',null,'clinical-ticket patient-history-detail');ticket.id='patient-history-detail';ticket.tabIndex=-1;ticket.setAttribute('role','region');ticket.setAttribute('aria-label','Detalle de mi consulta');
        const navigation=el('div',null,'clinical-ticket-nav');navigation.append(button('Volver',()=>{this.selected='';repaint();},'text-button'),el('span','MI HISTORIAL'));ticket.append(navigation,el('h2','Detalle de consulta','clinical-ticket-title'));
        const head=el('div',null,'record-visit-head');head.append(el('strong',selected.dateLabel+(selected.timeLabel?' · '+selected.timeLabel:'')),el('span','🩺 '+selected.doctor),el('span',selected.specialty));ticket.append(head);
        if(demonstration)ticket.append(notice());
        const groups=HospitalPatientHistory.groups(selected.details);
        if(!groups.length)ticket.append(el('p','Esta consulta no tiene información clínica adicional publicada.','scope-note'));
        for(const[title,fields]of groups){const block=el('div',null,'record-visit-group');block.append(el('h3',title));for(const field of fields){const row=el('div',null,'consult-field');row.append(el('span',field.label),el('p',field.value));block.append(row);}ticket.append(block);}
        if(!groups.some(([title])=>title==='Recetas'||title==='Exámenes'))ticket.append(el('p','Tus recetas y resultados también están disponibles en Mis recetas y Mis laboratorios.','sched-hint'));
        parent.append(ticket);return;
      }
      parent.append(el('h2','Mis consultas','section-title'));if(demonstration)parent.append(notice());
      const matches=ordered.filter(record=>fold([record.dateLabel,record.specialty,record.doctor,record.reason,record.diagnosis].join(' ')).includes(fold(search)));
      if(!matches.length&&!loading&&!error){const empty=el('article',null,'record-empty');empty.append(el('span','📋','record-empty-icon'),el('strong',search?'Sin coincidencias':'Todavía no tienes historial de consultas'),el('p',search?'No encontramos consultas con esa búsqueda. Prueba con otra fecha, especialidad o médico.':'Tus consultas aparecerán aquí cuando el médico las finalice.','sched-hint'));parent.append(empty);}
      for(const record of matches){
        const card=button(null,()=>{this.selected=record.id;repaint();document.querySelector('#patient-history-detail')?.focus?.();},'patient-history-card');card.setAttribute('aria-label','Ver consulta del '+record.dateLabel+' con '+record.doctor);
        const header=el('div',null,'patient-history-date');header.append(el('strong',record.dateLabel),el('time',record.timeLabel));
        card.append(header,el('p',record.specialty,'patient-history-specialty'),el('strong',record.doctor,'patient-history-doctor'));
        for(const[label,text]of[['Motivo',record.reason],['Diagnóstico',record.diagnosis]])if(real(text)){const line=el('div',null,'patient-history-reason');line.append(el('span',label),el('p',text));card.append(line);}
        parent.append(card);
      }
      if(hasMore&&loadMore)parent.append(button('Cargar más',loadMore,'module-action'));
    }
  }
  root.HospitalPatientHistory=HospitalPatientHistory;
})(typeof window!=='undefined'?window:globalThis);
