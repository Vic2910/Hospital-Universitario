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
    static fromItems(items,profile,period){return items.filter(item=>['scheduled','confirmed'].includes(item.status)&&Date.parse(item.event_at)>=Date.now()).map(item=>{
      const field=label=>item.details?.find(value=>value.label.toLowerCase()===label.toLowerCase())?.value;
      return{id:item.id,date:item.event_at,time:period(field('Horario')||''),name:profile?.person?[profile.person.given_names,profile.person.family_names].join(' '):'No hay datos reales',age:field('Edad')||'No hay datos reales',dui:field('DUI')||'No hay datos reales',phone:field('Teléfono')||profile?.contacts?.find(item=>item.kind==='phone')?.value||'No hay datos reales',email:profile?.auth_email||'No hay datos reales',specialty:item.title,doctor:field('Medico')||'No hay datos reales',room:field('Consultorio')||'No hay datos reales',reason:field('Motivo de la consulta')||item.subtitle||'No hay datos reales',symptoms:field('Síntomas')||'No hay datos reales',state:item.status};
    });}
    render(parent,{appointments,demonstration,renderConnected,requests}){
      const{el,button,repaint,go}=this.ui,next=[...appointments].filter(item=>Date.parse(item.date)>=Date.now()).sort((a,b)=>Date.parse(a.date)-Date.parse(b.date))[0];
      const field=(parent,label,value)=>{const row=el('div',null,'consult-field');row.append(el('span',label),el('p',value));parent.append(row);};
      if(this.selected&&next){
        const ticket=el('section',null,'consult-ticket');ticket.setAttribute('role','region');ticket.setAttribute('aria-label','Detalle de mi próxima cita');const check=el('span','\u2713','consult-ticket-check');check.setAttribute('aria-hidden','true');ticket.append(check,el('h2','Detalle de consulta','consult-ticket-title'),el('p',demonstration?'Datos de ejemplo · Sin reserva real':'Cita asignada','sched-hint'));
        const when=el('div',null,'consult-ticket-date');when.append(el('span','Fecha y hora'),el('strong',new Intl.DateTimeFormat('es-GT',{dateStyle:'full'}).format(new Date(next.date))));when.append(el('strong',next.time||new Intl.DateTimeFormat('es-GT',{timeStyle:'short'}).format(new Date(next.date))));ticket.append(when);
        const details=el('div',null,'consult-ticket-fields');
        for(const[label,value]of[['Paciente',next.name],['Edad',next.age],['Teléfono',next.phone],['Motivo de la consulta',next.reason],['Síntomas',next.symptoms],['Especialidad',next.specialty],['Médico',next.doctor],['Consultorio',next.room],['DUI',next.dui],['Correo',next.email]])field(details,label,value);
        ticket.append(details,button('Volver a Mis citas',()=>{this.selected=false;repaint();},'consult-ticket-primary'));parent.append(ticket);return;
      }
      const card=el('article',null,'sched-card');card.append(el('h2','Próxima cita','section-title'));
      if(next){card.append(el('strong',next.name),el('strong',dateText(next.date)),el('p',next.specialty),el('p',next.doctor),el('p',next.room),el('span','Cita asignada','clinical-lab-state is-completed'));if(demonstration)card.append(el('small','Cita de ejemplo · Sin reserva real','sched-hint'));field(card,'Edad',next.age);field(card,'Teléfono',next.phone);field(card,'Motivo de la consulta',next.reason);field(card,'Síntomas',next.symptoms);card.append(button('Ver detalle de la cita',()=>{this.selected=true;repaint();},'module-action'));}else card.append(el('p','Todavía no tienes una próxima cita asignada.','sched-hint'));parent.append(card,button('Solicitar atención',()=>go('request'),'primary'));
      if(requests){const queue=el('article',null,'sched-card');queue.append(el('h2','Mis solicitudes de ejemplo','section-title'),el('p','Recepción debe asignar la cita. La preferencia no confirma disponibilidad.','sched-hint'));
      for(const request of requests){const row=el('article',null,'doctor-visit');row.append(el('strong',request.specialty),el('span',request.state==='pending'?'Pendiente':request.state==='scheduled'?'Cita asignada':request.state==='rejected'?'Rechazada':'Cancelada','clinical-lab-state '+(request.state==='pending'?'is-pending':'is-completed')),el('p',request.reason),el('small','Solicitada: '+dateText(request.createdAt)),el('small','Preferencia: '+request.preference+' · '+request.preferredSlot));queue.append(row);}parent.append(queue);}if(renderConnected)renderConnected(parent);
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
