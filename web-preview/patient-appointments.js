(function(root){
  'use strict';
  const dateText=value=>new Intl.DateTimeFormat('es-GT',{dateStyle:'full',timeStyle:'short'}).format(new Date(value));
  class HospitalPatientAppointments {
    constructor(ui){this.ui=ui;this.reset();}
    reset(){
      const seed={id:root.crypto.randomUUID(),createdAt:new Date().toISOString(),fields:{nombres:'Gaby',apellidos:'Diaz',dui:'0123-45678',telefono:'7123-4567',correo:'gaby.diaz@ejemplo.test'},specialty:'Médico general',reason:'Valoración de ejemplo',symptoms:['Tos'],preference:'Mañana',preferredSlot:'Por confirmar',state:'pending',appointmentID:null,resolvedAt:null};
      this.requests=[seed];const day=new Date();day.setDate(day.getDate()+1);day.setHours(9,0,0,0);this.appointments=[this.makeAppointment(seed,day.toISOString())];this.selected=false;
    }
    submit(request){
      if(!['Mañana','Tarde'].includes(request.preference)||this.requests.some(item=>item.id===request.id)||!request.reason.trim())return false;
      this.requests.unshift({...request,fields:{...request.fields},symptoms:[...request.symptoms],state:'pending',appointmentID:null,resolvedAt:null,createdAt:new Date().toISOString()});return true;
    }
    makeAppointment(request,date){return{id:root.crypto.randomUUID(),date,time:[new Date(date),new Date(Date.parse(date)+1800000)].map(value=>new Intl.DateTimeFormat('es-GT',{hour:'numeric',minute:'2-digit'}).format(value)).join(' – '),name:request.fields.nombres+' '+request.fields.apellidos,age:'29 años',dui:request.fields.dui,phone:request.fields.telefono,email:request.fields.correo,specialty:request.specialty,doctor:'Dra. Ana Morales',room:'Consultorio 3',reason:request.reason,symptoms:request.symptoms.join(', ')||'No hay datos reales',state:'confirmed'};}
    assignExample(id,date,actor){
      const request=this.requests.find(item=>item.id===id);if(actor!=='reception-demo'||!request||request.state!=='pending'||request.appointmentID||!Number.isFinite(Date.parse(date))||Date.parse(date)<=Date.now())return false;
      const appointment=this.makeAppointment(request,date);this.appointments.push(appointment);request.appointmentID=appointment.id;request.state='scheduled';request.resolvedAt=new Date().toISOString();return true;
    }
    static fromItems(items,profile,period){return items.filter(item=>item.status==='in_progress'||(['scheduled','confirmed'].includes(item.status)&&Date.parse(item.event_at)>=Date.now())).map(item=>{
      const field=label=>item.details?.find(value=>value.label.toLowerCase()===label.toLowerCase())?.value;
      return{id:item.id,date:item.event_at,time:period(field('Horario')||''),name:profile?.person?[profile.person.given_names,profile.person.family_names].join(' '):'No hay datos reales',age:field('Edad')||'No hay datos reales',dui:field('DUI')||'No hay datos reales',phone:field('Teléfono')||profile?.contacts?.find(item=>item.kind==='phone')?.value||'No hay datos reales',email:profile?.auth_email||'No hay datos reales',specialty:item.title,doctor:field('Medico')||'No hay datos reales',room:field('Consultorio')||'No hay datos reales',reason:field('Motivo de la consulta')||item.subtitle||'No hay datos reales',symptoms:field('Síntomas')||'No hay datos reales',state:item.status};
    });}
    render(parent,{appointments,demonstration,renderConnected,loading=false,error=false}){
      const{el,button,repaint}=this.ui,next=[...appointments].filter(item=>item.state==='in_progress'||Date.parse(item.date)>=Date.now()).sort((a,b)=>Date.parse(a.date)-Date.parse(b.date))[0];
      const close=()=>{this.selected=false;repaint();};
      if(!this.selected){
        if (!demonstration && !appointments.length) { parent.append(el('p',loading?'Cargando tus citas…':error?'No pudimos cargar tus citas. Intenta de nuevo.':'No tienes citas registradas.','auth-notice')); if(renderConnected) renderConnected(parent); return; }
        const card=button(null,()=>{this.selected=true;repaint();},'patient-assigned-entry');card.setAttribute('aria-label','Cita asignada');
        const icon=el('span','\u25a6','patient-assigned-entry-icon');icon.setAttribute('aria-hidden','true');const text=el('span',null,'patient-assigned-entry-text');text.append(el('strong','Cita asignada'),el('small','Consulta los detalles de tu atención'));const arrow=el('span','\u203a','patient-assigned-entry-arrow');arrow.setAttribute('aria-hidden','true');card.append(icon,text,arrow);parent.append(card);return;
      }
      const ticket=el('section',null,'clinical-ticket patient-assigned-ticket');ticket.setAttribute('role','region');ticket.setAttribute('aria-label','Detalle de mi cita asignada');
      const nav=el('div',null,'clinical-ticket-nav');nav.append(button('Volver',close,'text-button'),el('span','MIS CITAS'));ticket.append(nav);
      const check=el('span',next?'\u2713':'\u25a6','clinical-ticket-icon');check.setAttribute('aria-hidden','true');ticket.append(check,el('h2',next?'Cita médica asignada':'Sin cita asignada','clinical-ticket-title'));
      const field=(parent,label,value)=>{const row=el('div',null,'consult-field');row.append(el('span',label),el('p',value||'No hay datos reales'));parent.append(row);};
      if(next){
        ticket.append(el('p',root.HospitalCore.doctorClinical.statusLabel(next.state),'clinical-lab-state'));
        ticket.append(el('p','Estos son los datos de tu próxima atención.','patient-assigned-intro'));
        const when=el('div',null,'clinical-ticket-context');when.append(el('span','Fecha y hora de tu cita'),el('strong',new Intl.DateTimeFormat('es-GT',{dateStyle:'full'}).format(new Date(next.date))),el('strong',next.time||new Intl.DateTimeFormat('es-GT',{timeStyle:'short'}).format(new Date(next.date))));ticket.append(when);
        for(const[title,fields]of[['Datos de la cita',[['Especialidad',next.specialty],['Médico',next.doctor],['Consultorio',next.room]]],['Datos del paciente',[['Paciente',next.name],['Edad',next.age],['DUI',next.dui],['Teléfono',next.phone],['Correo',next.email]]],['Motivo de la atención',[['Motivo de la consulta',next.reason],['Síntomas',next.symptoms]]]]){
          const group=el('section',null,'patient-assigned-group');group.append(el('h3',title));for(const[label,value]of fields)field(group,label,value);ticket.append(group);
        }
        if(demonstration)ticket.append(el('p','Cita de ejemplo · Sin reserva real','clinical-ticket-note'));
      }else ticket.append(el('p','Todavía no tienes una próxima cita asignada. Recepción confirmará la fecha y hora cuando programe tu atención.','patient-assigned-intro'));
      if(renderConnected){const manage=el('details',null,'patient-assigned-management');manage.append(el('summary','Gestionar mis citas'));renderConnected(manage);ticket.append(manage);}
      ticket.append(button('Volver a Mis citas',close,'consult-ticket-primary'));parent.append(ticket);
    }
    // Mis citas conectadas (paridad con PatientAppointmentsView.swift): todos los detalles a la vista, sin pantallas intermedias.
    renderLive(parent,{items,loading=false,error=null,period,search='',cancel,go,hasMore=false,loadMore}){
      const{el,button,repaint}=this.ui,zone='America/El_Salvador';
      const when=item=>Date.parse(item.event_at)||0,value=(item,label)=>{const v=(item.details||[]).find(f=>f.label.toLowerCase()===label.toLowerCase())?.value;return v&&v.trim()&&v!=='Sin registrar'?v.trim():'';};
      const match=item=>!search||[item.title,...(item.details||[]).map(f=>f.value)].join(' ').toLowerCase().includes(search.toLowerCase());
      const list=(items||[]).filter(match),soon=Date.now()-1800000;
      const upcoming=list.filter(i=>i.status==='in_progress'||(['scheduled','confirmed'].includes(i.status)&&when(i)>=soon)).sort((a,b)=>when(a)-when(b));
      const past=list.filter(i=>!upcoming.includes(i)).sort((a,b)=>when(b)-when(a));
      const hero=el('header',null,'directory-hero');hero.append(el('small','MIS CITAS'),el('h2',upcoming.length?(upcoming.length===1?'Tienes 1 cita próxima':'Tienes '+upcoming.length+' citas próximas'):'No tienes citas próximas'),el('p','Recepción programa tus citas. Aquí ves la fecha, el médico, el consultorio y el motivo.'));parent.append(hero);
      if(loading&&!list.length)parent.append(el('p','Cargando tus citas…','scope-note'));
      if(error)parent.append(el('p','No pudimos cargar tus citas. Intenta de nuevo.','auth-notice'));
      const labels={scheduled:'Programada',confirmed:'Programada',in_progress:'En consulta',completed:'Finalizada',cancelled:'Cancelada',no_show:'No asistió'};
      const card=(item,featured)=>{
        const date=new Date(item.event_at),valid=Number.isFinite(date.getTime()),active=['scheduled','confirmed','in_progress'].includes(item.status);
        const node=el('article',null,'appointment-live'+(featured?' is-featured':'')+(item.status==='in_progress'?' is-active':''));
        const top=el('div',null,'appointment-live-top'),badge=el('div',null,'appointment-live-day');
        badge.append(el('strong',valid?new Intl.DateTimeFormat('es-SV',{day:'numeric',timeZone:zone}).format(date):'--'),el('small',valid?new Intl.DateTimeFormat('es-SV',{month:'short',timeZone:zone}).format(date).toUpperCase():''));
        const text=el('div',null,'appointment-live-text');if(featured)text.append(el('small','PRÓXIMA CITA','appointment-live-kicker'));
        text.append(el('h3',item.title),el('p',valid?new Intl.DateTimeFormat('es-SV',{dateStyle:'full',timeZone:zone}).format(date):'Fecha no disponible'),el('strong','🕒 '+(period(value(item,'Horario'))||'Horario no disponible'),'appointment-live-time'));
        top.append(badge,text,el('span',labels[item.status]||'Cita','appointment-live-state is-'+item.status));node.append(top);
        const rows=[['🩺','Médico',value(item,'Médico')],['✚','Especialidad',value(item,'Especialidad')],['🚪','Consultorio',value(item,'Consultorio')],['💬','Motivo',value(item,'Motivo de la consulta')],['✕','Motivo de cancelación',value(item,'Motivo de cancelación')]].filter(r=>r[2]);
        if(rows.length){const box=el('div',null,'appointment-live-details');for(const [icon,label,text] of rows){const row=el('div');row.append(el('span',icon,'appointment-live-icon'),el('small',label),el('p',text));box.append(row);}node.append(box);}
        if(featured&&item.status==='in_progress')node.append(el('p','Tu médico ya inició la consulta.','appointment-live-note'));
        else if(featured&&active)node.append(el('p','Llega 15 minutos antes y presenta tu DUI en recepción.','appointment-live-note'));
        if(item.action==='cancel_appointment'&&cancel){
          if(this.cancelling===item.id){
            const form=el('div',null,'appointment-cancel'),reason=el('textarea');reason.setAttribute('aria-label','Motivo de cancelación');reason.placeholder='Motivo de cancelación';reason.value=this.cancelReason||'';reason.addEventListener('input',()=>{this.cancelReason=reason.value;});
            form.append(reason,button('Confirmar cancelación',()=>{const text=(this.cancelReason||'').trim();if(!text)return;this.cancelling='';this.cancelReason='';cancel(item,text);},'module-action'),button('Volver',()=>{this.cancelling='';repaint();},'text-button'));node.append(form);
          }else node.append(button('Cancelar cita',()=>{this.cancelling=item.id;this.cancelReason='';repaint();},'text-button appointment-cancel-button'));
        }
        return node;
      };
      if(upcoming.length){parent.append(card(upcoming[0],true));if(upcoming.length>1){parent.append(el('h2','Siguientes citas','section-title'));for(const item of upcoming.slice(1))parent.append(card(item,false));}}
      else if(!loading&&!error){const empty=el('article',null,'record-empty');empty.append(el('span','📅','record-empty-icon'),el('strong','Sin citas programadas'),el('p','Cuando recepción programe tu atención, verás aquí la fecha, la hora y el consultorio.','sched-hint'),button('Solicitar atención',()=>go('request'),'module-action'));parent.append(empty);}
      if(past.length){parent.append(el('h2','Historial de citas','section-title'));for(const item of past)parent.append(card(item,false));}
      if(hasMore&&loadMore)parent.append(button('Cargar más citas',loadMore,'module-action'));
    }
    renderRequests(parent){
      const{el}=this.ui,queue=el('details',null,'sched-card');queue.append(el('summary','Mis solicitudes de ejemplo'));
      for(const request of this.requests){const row=el('article',null,'doctor-visit');row.append(el('strong',request.specialty),el('span',({pending:'Pendiente',scheduled:'Cita asignada',rejected:'Rechazada',cancelled:'Cancelada'})[request.state],'clinical-lab-state '+(request.state==='pending'?'is-pending':'is-completed')),el('p',request.reason),el('small','Solicitada: '+dateText(request.createdAt)),el('small','Preferencia: '+request.preference));queue.append(row);}parent.append(queue);
    }
    renderReception(parent){
      const{el,button,repaint,exitReception}=this.ui;parent.append(el('h2','Recepción · Demostración local','section-title'),el('p','Solo solicitudes precargadas/locales. No concede permisos ni escribe en Supabase.','consult-demo'));
      for(const request of this.requests){
        const card=el('article',null,'sched-card');card.append(el('h3',request.fields.nombres+' '+request.fields.apellidos),el('p','DUI: '+request.fields.dui+' · '+request.fields.telefono),el('p',request.fields.correo),el('strong',request.specialty),el('p','Solicitada: '+dateText(request.createdAt)),el('p',request.reason),el('p','Síntomas: '+request.symptoms.join(', ')),el('p','Preferencia: '+request.preference+' · '+request.preferredSlot),el('span',({pending:'Pendiente',scheduled:'Cita asignada',rejected:'Rechazada',cancelled:'Cancelada'})[request.state]||'No hay datos reales','clinical-lab-state '+(request.state==='pending'?'is-pending':'is-completed')));
        const date=new Date();date.setDate(date.getDate()+2);date.setHours(request.preference==='Tarde'?15:9,0,0,0);let assigned=date.toISOString();
        const label=el('label','Fecha y hora a asignar','doctor-field'),input=el('input');input.type='datetime-local';const pad=n=>String(n).padStart(2,'0');input.value=date.getFullYear()+'-'+pad(date.getMonth()+1)+'-'+pad(date.getDate())+'T'+pad(date.getHours())+':00';input.setAttribute('aria-label','Fecha y hora a asignar');input.addEventListener('input',()=>{assigned=input.value;});label.append(input);card.append(label);
        const error=el('p','','form-error');error.setAttribute('role','alert');card.append(error);
        const assign=button('Asignar cita de ejemplo',()=>{if(this.assignExample(request.id,assigned,'reception-demo'))repaint();else error.textContent='Elige una fecha y hora futura.';},'module-action');assign.disabled=request.state!=='pending';card.append(assign);parent.append(card);
      }
      parent.append(button('Volver al portal del paciente',exitReception,'primary'));
    }
  }
  root.HospitalPatientAppointments=HospitalPatientAppointments;
})(typeof window!=='undefined'?window:globalThis);
