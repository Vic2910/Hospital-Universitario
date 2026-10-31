(function(root) {
  'use strict';
  const dateLabel = date => new Intl.DateTimeFormat('es-GT',{weekday:'long',day:'numeric',month:'long'}).format(date);
  const dateTime = value => new Intl.DateTimeFormat('es-GT',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value));
  const dayKey = date => [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
  class HospitalDoctorDashboard {
    constructor(ui) { this.ui = ui; this.clear(); }
    clear() { this.query = ''; this.selected = ''; this.from = ''; this.to = ''; this.filterDates = false; this.history = []; this.error = ''; this.searched = false; this.generation = (this.generation || 0) + 1; }
    invalidate() { this.generation++; this.history = []; this.error = ''; this.searched = false; }
    async find(data) {
      this.invalidate();
      if (!data.patients.some(patient => patient.id === this.selected)) return;
      if (this.filterDates && (!this.from || !this.to || this.from > this.to)) { this.error = 'La fecha inicial no puede ser posterior a la final. Completa ambas fechas.'; return; }
      const token = this.generation;
      const from = this.filterDates ? new Date(this.from + 'T00:00:00').toISOString() : null;
      const to = this.filterDates ? new Date(new Date(this.to + 'T00:00:00').setDate(new Date(this.to + 'T00:00:00').getDate()+1) - 1).toISOString() : null;
      try {
        const history = await data.loadHistory(this.selected,from,to);
        if (token !== this.generation) return;
        this.history = [...history].sort((a,b) => b.started_at.localeCompare(a.started_at)); this.searched = true;
      } catch { if (token === this.generation) this.error = 'No se pudo cargar el historial. Intenta buscar de nuevo.'; }
    }
    render(parent,data) {
      const {el,button,go,run} = this.ui;
      const greeting = el('article',null,'dash-greeting');
      const text = el('div',null,'dash-text');
      text.append(el('h2','Hola, ' + data.name),el('p','Tu jornada clínica, en un solo lugar.'));
      const initials = data.name.split(/\s+/).filter(word => !['Dr.','Dra.'].includes(word)).slice(0,2).map(word => word[0]).join('').toUpperCase();
      greeting.append(text,el('span',initials,'dash-avatar')); parent.append(greeting);
      const today = el('article',null,'dash-date doctor-today');
      today.append(el('span','HOY','dash-label'),el('strong',dateLabel(new Date())),el('hr'),el('strong',String(data.count),'dash-time'),el('span','Consultas programadas para hoy'),el('p',data.facility,'dash-medico'));
      parent.append(today);
      if (data.demo) parent.append(el('p','Modo diseño · Doctor y datos ficticios. Sin conexión al hospital.','scope-note'));
      parent.append(el('h2','Accesos rápidos','section-title'));
      const grid = el('div',null,'dash-grid');
      for (const [id,label,icon] of [['patients','Pacientes','♙'],['consultation','Consultas','✚'],['laboratory','Laboratorios','⚗'],['chart','Expedientes','▤']]) {
        const item = button(null,() => go(id),'dash-card'); item.setAttribute('aria-label',label);
        const symbol = el('span',icon,'dash-icon'); symbol.setAttribute('aria-hidden','true'); item.append(symbol,el('strong',label)); grid.append(item);
      }
      parent.append(grid);
    }
    renderHistory(parent,data) {
      const {el,button,go,run} = this.ui;
      if (this.selected && !data.patients.some(patient => patient.id === this.selected)) { this.selected = ''; this.invalidate(); }
      const history = el('article',null,'sched-card doctor-history');
      history.append(el('h2','Historial clínico','section-title'),el('p','Tus consultas con el paciente seleccionado.','sched-hint'));
      const search = el('input'); search.type = 'search'; search.value = this.query; search.placeholder = 'Buscar paciente o expediente'; search.setAttribute('aria-label','Buscar paciente o expediente');
      const label = el('label','Buscar paciente o expediente','doctor-field'); label.append(search); history.append(label,el('p','Pacientes de la agenda seleccionada','sched-hint'));
      const patients = el('div',null,'doctor-patients');
      const paintPatients = () => {
        patients.replaceChildren();
        const matches = data.patients.filter(patient => (patient.name + ' ' + patient.record).toLocaleLowerCase('es').includes(this.query.toLocaleLowerCase('es')));
        if (!matches.length) patients.append(el('p','No hay pacientes que coincidan.','sched-hint'));
        for (const patient of matches) {
          const item = button(null,() => { this.selected = patient.id; run(() => this.find(data)); },'doctor-patient' + (this.selected === patient.id ? ' is-selected' : ''));
          item.setAttribute('aria-label',patient.name); item.setAttribute('aria-pressed',String(this.selected === patient.id));
          const name = el('div'); name.append(el('strong',patient.name),el('small',patient.record));
          item.append(name,el('span',this.selected === patient.id ? '✓' : '○')); patients.append(item);
        }
      };
      search.addEventListener('input',() => { this.query = search.value; paintPatients(); }); paintPatients(); history.append(patients);
      const filter = el('label',null,'doctor-toggle'), toggle = el('input'); toggle.type = 'checkbox'; toggle.checked = this.filterDates; toggle.disabled = this.ui.busy(); toggle.setAttribute('aria-label','Filtrar por fecha');
      filter.append(toggle,el('span','Filtrar por fecha')); history.append(filter);
      const dates = el('div',null,'doctor-dates');
      const results = el('div',null,'doctor-results'); results.setAttribute('aria-live','polite');
      const paintResults = () => {
        results.replaceChildren();
        const patient = data.patients.find(patient => patient.id === this.selected);
        results.append(el('p',patient ? 'Consultas con ' + patient.name : 'Selecciona un paciente para consultar su historial.','sched-sub'));
        if (this.error) results.append(el('p',this.error,'scope-note'));
        if (this.searched && !this.history.length) results.append(el('p','No hay consultas propias en este intervalo.','sched-hint'));
        for (const visit of this.history) {
          const card = el('article',null,'doctor-visit');
          card.append(el('strong',dateTime(visit.started_at)),el('p',visit.subjective || 'Consulta sin nota registrada'),el('p',visit.plan || '','sched-hint'),el('span',visit.status === 'closed' ? 'Finalizada' : 'En curso','doctor-status')); results.append(card);
        }
      };
      const paintDates = () => {
        dates.replaceChildren();
        if (!this.filterDates) return;
        for (const [key,labelText] of [['from','Desde'],['to','Hasta']]) {
          const label = el('label',labelText,'doctor-field'), input = el('input'); input.type = 'date'; input.value = this[key] || dayKey(new Date()); this[key] = input.value; input.disabled = this.ui.busy(); input.setAttribute('aria-label',labelText);
          input.addEventListener('input',() => { this[key] = input.value; this.invalidate(); paintResults(); }); label.append(input); dates.append(label);
        }
      };
      toggle.addEventListener('change',() => { this.filterDates = toggle.checked; this.invalidate(); paintDates(); paintResults(); });
      paintDates(); history.append(dates);
      const submit = button('Buscar consultas',() => run(() => this.find(data)),'module-action'); submit.disabled ||= !this.selected;
      history.append(submit); paintResults(); history.append(results); parent.append(history);
    }
    static demo() {
      const patientA = '00000000-0000-4000-8000-000000000101', patientB = '00000000-0000-4000-8000-000000000102';
      const patients = [{id:patientA,name:'Carlos Mendoza',record:'DEMO-101'},{id:patientB,name:'María López',record:'DEMO-102'}];
      const rows = [[patientA,'doctor-demo',-1,'Consulta de seguimiento','Seguimiento registrado en modo diseño.'],[patientA,'doctor-demo',-7,'Revisión de resultados','Resultados revisados en modo diseño.'],[patientB,'doctor-demo',-2,'Consulta general','Control registrado en modo diseño.'],[patientA,'otro-doctor',-1,'Consulta ajena que debe excluirse','No mostrar']];
      const history = rows.map(([patient,doctor,offset,subjective,plan],index) => {
        const day = new Date(); day.setHours(9,0,0,0); day.setDate(day.getDate()+offset);
        return {id:String(index),patient,doctor,started_at:day.toISOString(),status:'closed',subjective,plan};
      });
      const monday = new Date(); monday.setHours(0,0,0,0); monday.setDate(monday.getDate()-((monday.getDay()+6)%7));
      const shifts = Array.from({length:5},(_,index) => { const day = new Date(monday); day.setDate(day.getDate()+index); return {label:dateLabel(day),detail:index === 3 ? '15:00–23:00 · Tarde' : '07:00–15:00 · Mañana',status:'Confirmado'}; });
      return {name:'Dr. Luis Ramírez',facility:'Sede Central · Medicina interna',count:4,patients,shifts,demo:true,
        loadHistory:async (patient,from,to) => history.filter(row => row.patient === patient && row.doctor === 'doctor-demo' && (!from || row.started_at >= from) && (!to || row.started_at <= to))};
    }
  }
  root.HospitalDoctorDashboard = HospitalDoctorDashboard;
})(typeof window !== 'undefined' ? window : globalThis);

(function(root) {
  'use strict';
  const key = date => [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
  const dateFor = offset => { const date = new Date(); date.setHours(0,0,0,0); date.setDate(date.getDate()+offset); return key(date); };
  class HospitalDoctorConsultations {
    constructor(ui) { this.ui = ui; this.clear(); }
    clear() { this.day = dateFor(0); this.selected = ''; }
    static samples(day) {
      const rows = [[0,8,30,'Carlos Mendoza','checked_in'],[0,10,0,'María López','confirmed'],[0,11,30,'Juan Pérez','scheduled'],[0,14,0,'Lucía García','confirmed'],[1,9,0,'María López','confirmed'],[1,11,0,'Carlos Mendoza','scheduled'],[3,10,30,'Lucía García','confirmed'],[7,8,30,'Juan Pérez','scheduled']];
      return rows.flatMap(([offset,hour,minute,patient_name,status],index) => {
        if (dateFor(offset) !== day) return [];
        const from = new Date(day+'T'+String(hour).padStart(2,'0')+':'+String(minute).padStart(2,'0')+':00');
        const to = new Date(from.getTime()+30*60000);
        return [{id:'demo-'+(index+301),patient_name,record_number:'DEMO-'+(index+301),age:[42,67,35,29,67,42,29,35][index],phone:['7123-4567','7234-5678','7356-7890',null,'7234-5678','7123-4567',null,'7356-7890'][index],reason:['Consulta de seguimiento','Revisión de resultados','Evaluación general',null,'Revisión de resultados','Consulta de seguimiento',null,'Evaluación general'][index],symptoms:[['Tos','Fiebre'],null,['Dolor de cabeza'],[],null,['Tos','Fiebre'],[],['Dolor de cabeza']][index],status,period:'["'+from.toISOString()+'","'+to.toISOString()+'")'}];
      });
    }
    render(parent,data) {
      const {el,button,repaint} = this.ui;
      const date = new Date(data.day+'T00:00:00');
      const label = Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat('es-GT',{weekday:'long',day:'numeric',month:'long'}).format(date) : 'Selecciona una fecha';
      const hero = el('article',null,'sched-intro consult-intro');
      hero.append(el('span','TU AGENDA','sched-eyebrow'),el('h2','Tus consultas, a tiempo'),el('p',label));
      const count = el('div',null,'consult-count'); count.append(el('strong',String(data.appointments.length)),el('span',(data.appointments.length === 1 ? 'consulta' : 'consultas')+(data.day === dateFor(0) ? ' para hoy' : ' para esta fecha'))); hero.append(count); parent.append(hero);
      const dates = el('article',null,'sched-card'); dates.append(el('h2','Buscar por fecha','section-title'));
      const field = el('label','Fecha de consultas','doctor-field'), input = el('input'); input.type = 'date'; input.value = data.day; input.disabled = this.ui.busy(); input.setAttribute('aria-label','Fecha de consultas');
      const change = day => { if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(new Date(day+'T00:00:00').getTime())) return; this.selected = ''; data.onDay(day); };
      input.addEventListener('change',() => change(input.value)); field.append(input); dates.append(field);
      const shortcuts = el('div',null,'consult-days');
      for (const [offset,label] of [[0,'Hoy'],[1,'Mañana'],[7,'En 7 días']]) {
        const target = dateFor(offset), item = button(label,() => change(target),'consult-day' + (data.day === target ? ' is-selected' : ''));
        item.setAttribute('aria-pressed',String(data.day === target)); shortcuts.append(item);
      }
      dates.append(shortcuts,el('p','Elige una fecha para ver tu agenda y próximas consultas.','sched-hint')); parent.append(dates);
      if (data.demo) parent.append(el('p','Agenda de ejemplo · Datos precargados, sin reservas reales. No permiten iniciar ni guardar consultas.','consult-demo'));
      parent.append(el('h2',data.day === dateFor(0) ? 'Consultas de hoy' : 'Consultas del día seleccionado','section-title'));
      const search = (data.search || '').toLocaleLowerCase('es');
      const rows = data.appointments.filter(item => (item.patient_name+' '+item.record_number).toLocaleLowerCase('es').includes(search)).sort((a,b) => a.period.localeCompare(b.period));
      if (!rows.length) {
        const empty = el('article',null,'sched-card'); empty.append(el('strong','No hay consultas para mostrar'),el('p',search ? 'Ningún paciente coincide con tu búsqueda.' : 'Prueba otra fecha para revisar tu agenda.','sched-hint')); parent.append(empty);
      }
      const missing = 'No hay datos reales';
      const value = text => typeof text === 'string' && text.trim() ? text.trim() : missing;
      const age = item => Number.isInteger(item.age) && item.age >= 0 ? item.age+' años' : missing;
      const symptoms = item => Array.isArray(item.symptoms) && item.symptoms.some(text => typeof text === 'string' && text.trim()) ? item.symptoms.filter(text => typeof text === 'string' && text.trim()).map(text => text.trim()).join(', ') : missing;
      const time = item => { const text = data.period(item.period); return !text || text === 'Horario no disponible' || text === 'Horario de ejemplo' ? missing : text; };
      const ticketField = (label,text) => { const node = el('div',null,'consult-field'); node.append(el('span',label),el('p',text)); return node; };
      const labels = {confirmed:'Confirmada',scheduled:'Programada',checked_in:'En espera',in_progress:'En curso',completed:'Finalizada',cancelled:'Cancelada'};
      for (const item of rows) {
        const card = el('article',null,'sched-card consult-card');
        const head = el('div',null,'consult-head'), avatar = el('span',value(item.patient_name).split(' ').slice(0,2).map(word => word[0]).join(''),'consult-avatar');
        head.append(avatar,el('h3',value(item.patient_name))); card.append(head,el('strong',time(item),'consult-time'),el('span',labels[item.status] || 'Pendiente','consult-status'));
        const demographics = el('div',null,'consult-demographics'); demographics.append(ticketField('Edad',age(item)),ticketField('Teléfono',value(item.phone))); card.append(demographics,ticketField('Motivo de la consulta',value(item.reason)),ticketField('Síntomas',symptoms(item)));
        const action = button('Ver detalle',() => { this.selected = item.id; repaint(); document.querySelector('#consult-ticket-'+item.id)?.focus?.(); },'module-action');
        action.id = 'consult-detail-'+item.id; action.setAttribute('aria-controls','consult-ticket-'+item.id);
        action.setAttribute('aria-label','Ver detalle de '+value(item.patient_name));
        action.setAttribute('aria-expanded',String(this.selected === item.id));
        card.append(action);
        if (this.selected === item.id) {
          const ticket = el('section',null,'consult-ticket'); ticket.id = 'consult-ticket-'+item.id; ticket.tabIndex = -1; ticket.setAttribute('role','region'); ticket.setAttribute('aria-label','Detalle de consulta de '+value(item.patient_name));
          const check = el('span','\u2713','consult-ticket-check'); check.setAttribute('aria-hidden','true');
          const title = el('h2','Detalle de consulta'); title.tabIndex = -1;
          ticket.append(check,title,el('p',data.demo ? 'Datos de ejemplo · Sin reserva real' : labels[item.status] || 'Pendiente','sched-hint'));
          const when = el('div',null,'consult-ticket-date'); when.append(el('span','Fecha y hora'),el('strong',time(item) === missing ? missing : label),el('strong',time(item))); ticket.append(when);
          const details = el('div',null,'consult-ticket-fields'), pair = el('div',null,'consult-demographics'); pair.append(ticketField('Edad',age(item)),ticketField('Teléfono',value(item.phone)));
          details.append(ticketField('Paciente',value(item.patient_name)),pair,ticketField('Motivo de la consulta',value(item.reason)),ticketField('Síntomas',symptoms(item))); ticket.append(details);
          if (!data.demo) ticket.append(button('Abrir atención',() => data.onSelect(item.id),'module-action'));
          ticket.append(button('Volver a consultas',() => { this.selected = ''; repaint(); document.querySelector('#consult-detail-'+item.id)?.focus?.(); },'consult-ticket-primary'));
          card.append(ticket);
        }
        parent.append(card);
      }
    }
  }
  root.HospitalDoctorConsultations = HospitalDoctorConsultations;
})(typeof window !== 'undefined' ? window : globalThis);
