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
      const today=el('article',null,'doctor-day-summary');
      today.append(el('span','TU JORNADA · HOY','dash-label'),el('h3',dateLabel(new Date())));
      const stats=el('div',null,'doctor-day-stats');
      for(const [value,label] of [[data.count,'Programadas'],[(data.appointments||[]).filter(a=>['scheduled','confirmed','in_progress'].includes(a.status)).length,'Pendientes'],[(data.appointments||[]).filter(a=>a.status==='completed').length,'Finalizadas']]){const item=el('div');item.append(el('strong',String(value)),el('span',label));stats.append(item);}today.append(stats);parent.append(today);
      const next=data.next!==undefined?data.next:(data.appointments||[]).find(a=>a.status==='in_progress'||(['scheduled','confirmed'].includes(a.status)&&new Date(root.HospitalCore.periodBounds(a.period).start)>=new Date()));
      const upcoming=el('article',null,'doctor-next-visit');upcoming.append(el('span','PRÓXIMA CITA','dash-label'));
      if(next){upcoming.append(el('h3',next.patient_name),el('p',dateTime(root.HospitalCore.periodBounds(next.period).start)),el('p',next.room_code?'Consultorio '+next.room_code:'Consultorio no publicado'));}
      else upcoming.append(el('h3','Tu agenda está al día'),el('p','No tienes próximas citas programadas para hoy. Aquí verás la siguiente atención asignada.'));
      upcoming.append(button('Ver agenda',()=>go('consultation'),'module-action'));parent.append(upcoming);
      if (data.demo) parent.append(el('p','Modo diseño · Doctor y datos ficticios. Sin conexión al hospital.','scope-note'));
      parent.append(el('h2','Accesos rápidos','section-title'));
      const grid = el('div',null,'dash-grid');
      for (const [id,label,icon] of [['consultation','Agenda','▦'],['patients','Pacientes','♙'],['laboratory','Laboratorios','⚗'],['admissions','Ingresos hospitalarios','▣']]) {
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
          card.append(el('strong',dateTime(visit.started_at)));if (visit.assessment) card.append(el('p','Diagnóstico: ' + visit.assessment));card.append(el('p',visit.subjective || 'Consulta sin nota registrada'),el('p',visit.objective || '','sched-hint'),el('span',visit.status === 'closed' ? 'Finalizada' : 'En consulta','doctor-status')); results.append(card);
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
    clear() { this.day = dateFor(0); this.selected = ''; this.filter = 'pending'; this.query = ''; }
    static samples(day) {
      const rows = [[0,8,30,'Carlos Mendoza','checked_in'],[0,10,0,'María López','confirmed'],[0,11,30,'Juan Pérez','scheduled'],[0,14,0,'Lucía García','confirmed'],[1,9,0,'María López','confirmed'],[1,11,0,'Carlos Mendoza','scheduled'],[3,10,30,'Lucía García','confirmed'],[7,8,30,'Juan Pérez','scheduled']];
      return rows.flatMap(([offset,hour,minute,patient_name,status],index) => {
        if (dateFor(offset) !== day) return [];
        const from = new Date(day+'T'+String(hour).padStart(2,'0')+':'+String(minute).padStart(2,'0')+':00');
        const to = new Date(from.getTime()+30*60000);
        return [{id:'demo-'+(index+301),patient_name,record_number:'DEMO-'+(index+301),age:[42,67,35,29,67,42,29,35][index],phone:['7123-4567','7234-5678','7356-7890',null,'7234-5678','7123-4567',null,'7356-7890'][index],reason:['Consulta de seguimiento','Revisión de resultados','Evaluación general',null,'Revisión de resultados','Consulta de seguimiento',null,'Evaluación general'][index],symptoms:[['Tos','Fiebre'],null,['Dolor de cabeza'],[],null,['Tos','Fiebre'],[],['Dolor de cabeza']][index],status,period:'["'+from.toISOString()+'","'+to.toISOString()+'")'}];
      });
    }
    // Agenda de dos filtros (paridad con DoctorConsultationAgendaView.swift): PENDIENTES por hora ascendente y
    // FINALIZADAS por hora real de finalización. Los estados no cambian; canceladas y no asistidas no aparecen.
    render(parent,data) {
      const {el,button,repaint} = this.ui;
      const clinical = root.HospitalCore.doctorClinical;
      const today = clinical.todayKey(), zone = clinical.zone;
      const date = new Date(data.day+'T12:00:00-06:00'), valid = Number.isFinite(date.getTime());
      const state = (data.onFilter ? data.stateFilter : this.filter) === 'finished' ? 'finished' : 'pending';
      const setFilter = value => { if (data.onFilter) data.onFilter(value); else { this.filter = value; repaint(); } };
      const change = day => { if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(new Date(day+'T00:00:00').getTime())) return; this.selected = ''; data.onDay(day); };
      const match = item => clinical.matches(item,this.query||'') && clinical.matches(item,data.search||'');
      const lists = () => ({pending:clinical.pending(data.appointments,data.day,today).filter(match),finished:clinical.finished(data.appointments,data.day).filter(match)});
      let current = lists();
      const hero = el('article',null,'agenda-hero');
      const top = el('div',null,'agenda-hero-top'), titles = el('div');
      titles.append(el('span','AGENDA MÉDICA','sched-eyebrow'),el('h2','Consultas'));
      top.append(titles,el('p',valid ? new Intl.DateTimeFormat('es-SV',{weekday:'long',day:'numeric',month:'long',timeZone:zone}).format(date) : 'Selecciona una fecha','agenda-hero-date'));
      hero.append(top);
      const indicators = el('div',null,'agenda-indicators'); indicators.setAttribute('role','group'); indicators.setAttribute('aria-label','Filtrar consultas');
      const counts = {};
      for (const [value,text,icon] of [['pending','Pendientes','◷'],['finished','Finalizadas','✓']]) {
        const item = button(null,() => setFilter(value),'agenda-indicator'+(state === value ? ' is-selected' : ''));
        item.setAttribute('aria-pressed',String(state === value)); item.setAttribute('aria-label',text.toUpperCase());
        counts[value] = el('strong',String(current[value].length)); item.append(el('span',icon,'agenda-indicator-icon'),counts[value],el('small',text.toUpperCase()));
        indicators.append(item);
      }
      hero.append(indicators); parent.append(hero);
      // Fecha compacta: anterior/siguiente, calendario nativo y Hoy.
      const bar = el('div',null,'agenda-datebar');
      const relative = () => { if (data.day === today) return 'HOY'; const diff = Math.round((new Date(data.day+'T12:00:00Z') - new Date(today+'T12:00:00Z'))/86400000); return diff === -1 ? 'AYER' : diff === 1 ? 'MAÑANA' : diff < 0 ? 'HACE '+(-diff)+' DÍAS' : 'EN '+diff+' DÍAS'; };
      const prev = button('‹',() => change(clinical.addDays(data.day,-1)),'agenda-step'); prev.setAttribute('aria-label','Día anterior');
      const next = button('›',() => change(clinical.addDays(data.day,1)),'agenda-step'); next.setAttribute('aria-label','Día siguiente');
      const picker = el('label',null,'agenda-date'); const caption = el('span',null,'agenda-date-text');
      caption.append(el('small',relative()),el('strong',valid ? new Intl.DateTimeFormat('es-SV',{weekday:'short',day:'numeric',month:'short',year:'numeric',timeZone:zone}).format(date) : '—'));
      const input = el('input'); input.type = 'date'; input.value = data.day; input.disabled = this.ui.busy(); input.setAttribute('aria-label','Fecha de consultas');
      input.addEventListener('change',() => change(input.value)); picker.append(el('span','📅','agenda-date-icon'),caption,input);
      const todayButton = button('Hoy',() => change(today),'agenda-today'); todayButton.disabled = data.day === today || this.ui.busy();
      bar.append(prev,picker,next,todayButton); parent.append(bar);
      // Búsqueda compacta: solo repinta la lista para no perder el foco.
      const search = el('label',null,'agenda-search'); const query = el('input'); query.type = 'search'; query.value = this.query || ''; query.placeholder = 'Paciente, código o expediente'; query.setAttribute('aria-label','Buscar consultas');
      search.append(el('span','⌕','agenda-search-icon'),query); parent.append(search);
      if (data.demo) parent.append(el('p','Agenda de ejemplo · Datos precargados, sin reservas reales. No permiten iniciar ni guardar consultas.','consult-demo'));
      const listBox = el('section',null,'agenda-list'); parent.append(listBox);
      const missing = 'No hay datos reales';
      const value = text => typeof text === 'string' && text.trim() ? text.trim() : missing;
      const age = item => Number.isInteger(item.age) && item.age >= 0 ? item.age+' años' : missing;
      const symptoms = item => Array.isArray(item.symptoms) && item.symptoms.some(text => typeof text === 'string' && text.trim()) ? item.symptoms.filter(text => typeof text === 'string' && text.trim()).map(text => text.trim()).join(', ') : missing;
      const time = item => { const text = data.period(item.period); return !text || text === 'Horario no disponible' || text === 'Horario de ejemplo' ? missing : text; };
      const dayText = item => { const start = clinical.start(item); return start ? new Intl.DateTimeFormat('es-SV',{weekday:'short',day:'numeric',month:'short',timeZone:zone}).format(start) : ''; };
      const ticketField = (name,text) => { const node = el('div',null,'consult-field'); node.append(el('span',name),el('p',text)); return node; };
      const paint = () => {
        current = lists(); for (const key of ['pending','finished']) counts[key].textContent = String(current[key].length);
        listBox.replaceChildren();
        const rows = current[state], searching = !!((this.query||'').trim() || (data.search||'').trim());
        const head = el('div',null,'consult-section-head'); head.append(el('h2',state === 'finished' ? 'Consultas finalizadas' : 'Consultas pendientes','section-title'),el('span',state === 'finished' ? 'Última finalizada primero' : 'Por hora','agenda-order')); listBox.append(head);
        if (!rows.length) { const empty = el('article',null,'record-empty'); empty.append(el('span',state === 'finished' ? '✓' : '📅','record-empty-icon'),el('strong',searching ? 'Sin coincidencias' : state === 'finished' ? 'Aún no hay consultas finalizadas' : 'No tienes consultas pendientes'),el('p',searching ? 'Ningún paciente de esta fecha coincide con la búsqueda.' : state === 'finished' ? 'Las consultas que finalices en esta fecha aparecerán aquí.' : 'No hay citas por atender en esta fecha.','sched-hint')); listBox.append(empty); }
        for (const item of rows) {
          const node = this.card(item,{el,button,repaint,data,value,age,symptoms,time,dayText,ticketField,showDate:!!clinical.start(item) && clinical.dayKey(clinical.start(item)) !== data.day,clinical});
          if (state === 'finished') { const finishedAt = item.finished_at ? new Date(item.finished_at) : null; node.append(el('p',finishedAt && Number.isFinite(finishedAt.getTime()) ? '✓ Finalizada a las '+new Intl.DateTimeFormat('es-SV',{timeStyle:'short',timeZone:zone}).format(finishedAt) : '✓ Finalizada · hora de la cita','agenda-finished-at')); }
          listBox.append(node);
        }
        // Canceladas y no atendidas: conservan su estado y su turno; nunca se cuentan como atendidas.
        if (state === 'finished') { const closed = clinical.closedWithoutCare(data.appointments,data.day).filter(match);
          if (closed.length) { const sub = el('div',null,'consult-section-head'); sub.append(el('h2','Canceladas y no atendidas','section-title')); listBox.append(sub);
            for (const item of closed) listBox.append(this.card(item,{el,button,repaint,data,value,age,symptoms,time,dayText,ticketField,showDate:false,clinical})); } }
      };
      query.addEventListener('input',() => { this.query = query.value; paint(); });
      paint();
    }
    card(item,{el,button,repaint,data,value,age,symptoms,time,dayText,ticketField,showDate,clinical}) {
      const status = clinical.statusLabel(item.status);
      const card = el('article',null,'sched-card consult-card'+(item.status === 'in_progress' ? ' is-active' : ''));
      const when = el('div',null,'consult-when'); when.append(el('strong',time(item),'consult-time')); if (showDate) when.append(el('small',dayText(item)));
      const head = el('div',null,'consult-head'), avatar = el('span',value(item.patient_name).split(' ').slice(0,2).map(word => word[0]).join(''),'consult-avatar');
      head.append(avatar,el('h3',value(item.patient_name)),el('span',status,'consult-status'));
      card.append(when,head,el('p','Expediente '+value(item.record_number),'consult-record'),ticketField('Motivo de la consulta',value(item.reason)));
      const meta = el('p',(item.specialty || 'Cita de recepción')+' · '+(item.room_code ? 'Consultorio '+item.room_code : 'Consultorio no publicado'),'sched-hint'); card.append(meta);
      const action = button('Ver detalle',() => { this.selected = this.selected === item.id ? '' : item.id; repaint(); document.querySelector('#consult-ticket-'+item.id)?.focus?.(); },'module-action');
      action.id = 'consult-detail-'+item.id; action.setAttribute('aria-controls','consult-ticket-'+item.id);
      action.setAttribute('aria-label','Ver detalle de '+value(item.patient_name)+', '+status);
      action.setAttribute('aria-expanded',String(this.selected === item.id));
      card.append(action);
      if (this.selected === item.id) {
        const ticket = el('section',null,'consult-ticket'); ticket.id = 'consult-ticket-'+item.id; ticket.tabIndex = -1; ticket.setAttribute('role','region'); ticket.setAttribute('aria-label','Detalle de consulta de '+value(item.patient_name));
        const check = el('span','✓','consult-ticket-check'); check.setAttribute('aria-hidden','true');
        const title = el('h2','Detalle de consulta'); title.tabIndex = -1;
        ticket.append(check,title,el('p',data.demo ? 'Datos de ejemplo · Sin reserva real' : status,'consult-status'));
        const start = clinical.start(item);
        const date = el('div',null,'consult-ticket-date'); date.append(el('span','Fecha y hora'),el('strong',start ? new Intl.DateTimeFormat('es-SV',{weekday:'long',day:'numeric',month:'long',year:'numeric',timeZone:clinical.zone}).format(start) : missingText(value)),el('strong',time(item))); ticket.append(date);
        const details = el('div',null,'consult-ticket-fields'), pair = el('div',null,'consult-demographics'); pair.append(ticketField('Edad',age(item)),ticketField('Teléfono',value(item.phone)));
        details.append(ticketField('Paciente',value(item.patient_name)),ticketField('Expediente',value(item.record_number)),pair,ticketField('Especialidad',item.specialty || 'Cita directa de recepción; sin solicitud vinculada'),ticketField('Consultorio',value(item.room_code)),ticketField('Motivo de la consulta',value(item.reason)),ticketField('Síntomas',symptoms(item)));
        if (item.other_symptoms) details.append(ticketField('Otros síntomas',item.other_symptoms));
        ticket.append(details);
        if (!data.demo && data.onSelect) {
          const blocker = clinical.openingBlocker(item);
          const open = button(item.encounter_id ? (item.status === 'completed' ? 'VER CONSULTA FINALIZADA' : 'CONTINUAR CONSULTA') : 'ABRIR CONSULTA MÉDICA',() => { this.selected = ''; data.onSelect(item.id); },'consult-ticket-primary consult-open');
          open.disabled = !!blocker || this.ui.busy(); ticket.append(open);
          if (blocker) ticket.append(el('p',blocker,'sched-hint'));
        }
        ticket.append(button('Volver a consultas',() => { this.selected = ''; repaint(); document.querySelector('#consult-detail-'+item.id)?.focus?.(); },'module-action'));
        card.append(ticket);
      }
      return card;
    }
  }
  const missingText = value => value('');
  root.HospitalDoctorConsultations = HospitalDoctorConsultations;
})(typeof window !== 'undefined' ? window : globalThis);
