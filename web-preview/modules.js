(function (root) {
  'use strict';
  const labels = {pending:'Pendiente',scheduled:'Programada',confirmed:'Confirmada',checked_in:'Registrado en recepción',in_progress:'En curso',completed:'Finalizada',cancelled:'Cancelada',rejected:'Rechazada',open:'Abierta',closed:'Cerrada',issued:'Emitida',draft:'Borrador',ordered:'Emitida',released:'Publicado',unread:'No leída',read:'Leída',no_show:'No se presentó',active:'Vigente',expired:'Tratamiento finalizado'};
  const localDay = date => new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
  const dateTime = value => value && Number.isFinite(new Date(value).getTime()) ? new Intl.DateTimeFormat('es-GT',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'No registrado';
  class HospitalModules {
    constructor(api, ui) { this.api = api; this.ui = ui; this.clear(); }
    clear() {
      this.identity = ''; this.role = ''; this.facility = null; this.access = null; this.screen = '';
      this.data = null; this.workspace = null; this.chart = null; this.context = null; this.selected = '';
      this.clinicalStage = ''; this.clinicalQuery = ''; this.activeLab = null;
      this.items = []; this.lines = []; this.documents = new Map(); this.filters = {from:'',to:'',query:''};
      this.day = localDay(new Date()); this.request = {specialty:'',reason:'',day:this.day,from:'08:00',to:'12:00'};
      this.consultation = {subjective:'',objective:'',assessment:'',plan:''}; this.seedDraft = true;
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:'',weight:'',height:''}; this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',days:'',starts:this.day,ends:''};
      this.profile = {phone:'',given:'',family:'',emergencyPhone:'',relationship:''};
      this.keys = Object.fromEntries(['request','start','save','lab','rx','emergency'].map(key => [key,root.crypto.randomUUID()]));
    }
    configure(access, role, facility) {
      const identity = access.profile.id + '/' + role + '/' + facility;
      if (this.identity !== identity) { this.clear(); this.identity = identity; }
      this.role = role; this.access = access; this.facility = facility;
    }
    supports(role, page) {
      return role === 'doctor' ? ['home','patients','consultation','chart','laboratory','prescriptions','notifications','profile'].includes(page)
        : ['appointments','request','chart','history','prescriptions','laboratory','notifications','profile'].includes(page);
    }
    async load(page, more = false) {
      if (!this.facility) throw new Error('No hay una sede autorizada.');
      if (page === 'consultation' && this.screen !== page && !this.selected) this.day = localDay(new Date());
      if (this.screen !== page) { this.screen = page; this.data = null; this.items = []; this.filters = {from:'',to:'',query:''}; }
      if (page === 'home' && this.role === 'doctor') this.day = localDay(new Date());
      if (this.role === 'doctor' && !['profile','notifications'].includes(page)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(this.day)) throw new Error('Selecciona una fecha de atención válida.');
        const from = new Date(this.day + 'T00:00:00'), to = new Date(from); to.setDate(to.getDate()+1);
        try { this.workspace = await this.api.rpc('doctor_workspace',{p_facility:this.facility,p_from:from.toISOString(),p_to:to.toISOString()}); }
        catch (error) { this.workspace = this.chart = this.context = null; throw error; }
        if (!Array.isArray(this.workspace.appointments) || !Array.isArray(this.workspace.orders)) throw new Error('Respuesta de agenda inválida.');
        if (this.selected && !this.workspace.appointments.some(item => item.id === this.selected)) this.select('');
        if (this.appointment && ['patients','consultation','chart','laboratory','prescriptions'].includes(page)) await this.loadChart();
      }
      if (this.role === 'patient' || ['prescriptions','profile','notifications'].includes(page)) {
        const from = this.filters.from ? new Date(this.filters.from) : null, to = this.filters.to ? new Date(this.filters.to) : null;
        if ((from && !Number.isFinite(from.getTime())) || (to && !Number.isFinite(to.getTime())) || (from && to && from > to)) throw new Error('Revisa el intervalo de fechas.');
        const result = await this.api.rpc('mobile_module',{p_role:this.role,p_module:page,p_facility:this.facility,
          p_from:from?.toISOString() || null,p_to:to?.toISOString() || null,p_query:this.filters.query,p_cursor:more ? this.data?.next_cursor : null,p_limit:25});
        if (!Array.isArray(result.items) || !Array.isArray(result.options) || (result.has_more && !result.next_cursor)) throw new Error('Respuesta de módulo inválida.');
        this.items = more ? [...this.items,...result.items] : result.items; this.data = result;
        if (page === 'profile') this.profile = {phone:result.phone || '',given:result.emergency?.given_names || '',family:result.emergency?.family_names || '',emergencyPhone:result.emergency?.phones?.[0] || '',relationship:result.emergency?.relationship || ''};
      }
    }
    get appointment() { return this.workspace?.appointments.find(item => item.id === this.selected); }
    get encounter() { return this.context?.history.find(item => item.id === this.appointment?.encounter_id); }
    select(id) {
      this.selected = id; this.chart = this.context = null; this.lines = []; this.seedDraft = true;
      this.clinicalStage = ''; this.activeLab = null;
      this.consultation = {subjective:'',objective:'',assessment:'',plan:''};
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:'',weight:'',height:''};
      this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',days:'',starts:localDay(new Date()),ends:''};
      for (const key of ['start','save','lab','rx']) this.keys[key] = root.crypto.randomUUID();
    }
    async loadChart() {
      try { this.context = await this.api.rpc('doctor_chart',{p_patient:this.appointment.patient_id,p_from:null,p_to:null,p_query:''}); }
      catch (error) { this.context = this.chart = null; throw error; }
      this.chart = this.context;
      if (this.seedDraft) {
        const encounter = this.encounter;
        for (const key of Object.keys(this.consultation)) this.consultation[key] = encounter?.[key] || '';
        this.noteID = encounter?.note_id || null; this.noteVersion = encounter?.note_version || null; this.seedDraft = false;
      }
    }
    async mutation(name, parameters, success, after) {
      await this.api.rpc(name,parameters); if (after) after();
      try { await this.load(this.screen); this.ui.message(success); }
      catch { throw new Error(success + ' No se pudo actualizar la lista; usa Actualizar.'); }
    }
    node(tag,text,className) { return this.ui.el(tag,text,className); }
    command(parent,label,operation,primary = false) {
      const button = this.ui.button(label,() => this.ui.run(operation),primary ? 'primary' : 'module-action'); parent.append(button); return button;
    }
    field(parent,label,state,key,type = 'text',options) {
      const group = this.node('label',null,'module-field'); group.append(this.node('span',label));
      const input = this.node(options ? 'select' : type === 'textarea' ? 'textarea' : 'input');
      if (options) { for (const [value,name] of [['','Seleccionar'],...options]) { const option = this.node('option',name); option.value = value; input.append(option); } }
      else { if (type !== 'textarea') input.type = type; if (type === 'number') { input.min = '0.0001'; input.step = 'any'; } }
      input.value = state[key] || ''; input.disabled = this.ui.busy(); input.setAttribute('aria-label',label);
      input.addEventListener(options ? 'change' : 'input',() => { state[key] = input.value; }); group.append(input); parent.append(group); return input;
    }
    form(parent,label,submit) {
      const form = this.node('form',null,'module-form');
      form.addEventListener('submit',event => { event.preventDefault(); if (form.reportValidity()) this.ui.run(submit); });
      parent.append(form); const finish = () => { const button = this.node('button',label,'primary'); button.type = 'submit'; button.disabled = this.ui.busy(); form.append(button); return button; };
      return {form,finish};
    }
    detail(parent,label,value) { const block = this.node('div',null,'module-detail'); block.append(this.node('strong',label),this.node('p',value || 'No registrado')); parent.append(block); }
    matches(item,search) { return !search || item.toLocaleLowerCase('es').includes(search.toLocaleLowerCase('es')); }
    render(parent,page,search) {
      this.screen = page;
      this.search = search;
      if (this.role === 'doctor' && !['profile','notifications'].includes(page)) this.renderDoctor(parent,page);
      else this.renderData(parent,page);
    }
    filtersView(parent) {
      const group = this.node('div',null,'module-filters');
      this.field(group,'Desde',this.filters,'from','datetime-local'); this.field(group,'Hasta',this.filters,'to','datetime-local');
      this.command(group,'Buscar y actualizar',async () => { this.filters.query = this.search; await this.load(this.screen); }); parent.append(group);
    }
    renderData(parent,page) {
      if (this.role === 'patient' && page === 'chart') {
        const ticket=this.node('section',null,'clinical-ticket patient-own-chart');ticket.setAttribute('role','region');ticket.setAttribute('aria-label','Mi expediente completo');
        const navigation=this.node('div',null,'clinical-ticket-nav');navigation.append(this.ui.button('Volver',()=>this.ui.go('home'),'text-button'),this.node('span','FICHA CLÍNICA'));ticket.append(navigation);
        const fields=(this.data?.sections || []).flatMap(section=>section.fields);
        const value=label=>{const text=fields.find(field=>field.label.toLocaleLowerCase('es')===label.toLocaleLowerCase('es'))?.value;return typeof text==='string'&&text.trim()?text.trim():'No hay datos reales';};
        const icon=this.node('span','\u2713','clinical-ticket-icon');icon.setAttribute('aria-hidden','true');
        ticket.append(icon,this.node('h2','Expediente completo','clinical-ticket-title'),this.node('p',value('Nombre'),'clinical-ticket-patient'));
        const identity=this.node('div',null,'clinical-ticket-context');identity.append(this.node('strong',value('Expediente')),this.node('span','DUI: '+value('DUI')));ticket.append(identity,this.node('small','Tu información médica · Acceso personal de solo lectura','clinical-ticket-note'));
        parent.append(ticket);parent=ticket;
      }
      if (!this.data) this.command(parent,'Actualizar',() => this.load(page));
      else if (page === 'profile') { this.profileForm(parent); return; }
      else if (['appointments','history','laboratory','prescriptions','notifications'].includes(page)) this.filtersView(parent);
      for (const section of this.data?.sections || []) {
        parent.append(this.node('h2',section.title,'section-title')); const card = this.node('article',null,'card');
        if (!section.fields.length) card.append(this.node('p','Sin registros.'));
        for (const field of section.fields) if (this.matches(field.label + ' ' + field.value,this.search)) this.detail(card,field.label,field.value);
        parent.append(card);
      }
      const rows = this.items.filter(item => this.matches(item.title+' '+(item.subtitle || '')+' '+item.details.map(field => field.value).join(' '),this.search));
      if (!rows.length) parent.append(this.ui.row(this.role==='patient' && page==='chart' ? 'Documentos' : 'Sin registros',this.role==='patient' && page==='chart' ? 'No hay documentos publicados en tu expediente.' : 'No hay información que coincida con esta consulta.'));
      for (const item of rows) {
        const card = this.ui.row(item.title,item.subtitle,labels[item.status] || 'Estado no disponible');
        card.append(this.node('p',dateTime(item.event_at),'module-date'));
        const details = this.node('details'); details.append(this.node('summary','Ver detalle'));
        for (const field of item.details) this.detail(details,field.label,field.label === 'Horario' ? this.ui.period(field.value) : field.value); card.append(details);
        if (page !== 'chart' && item.action === 'mark_read') this.command(card,'Marcar como leída',() => this.mutation('update_record',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.'));
        if (page !== 'chart' && item.action === 'cancel_appointment') {
          const cancellation = {reason:''}, {form,finish} = this.form(card,'Confirmar cancelación',async () => {
            if (!cancellation.reason.trim()) throw new Error('Escribe el motivo de cancelación.');
            await this.mutation('transition_appointment',{p_id:item.id,p_status:'cancelled',p_reason:cancellation.reason,p_expected_version:item.row_version},'Cita cancelada.');
          });
          this.field(form,'Motivo de cancelación',cancellation,'reason').required = true; finish();
        }
        if (item.document_id) {
          const signed = this.documents.get(item.document_id);
          if (signed && signed.expires > Date.now()) { const link = this.node('a','Abrir documento autorizado','module-action'); link.href = signed.url; link.target = '_blank'; link.rel = 'noopener noreferrer'; card.append(link); }
          else this.command(card,'Autorizar documento',async () => { const url = await this.api.documentURL(item.document_id); this.documents.set(item.document_id,{url,expires:Date.now()+50000}); });
        }
        parent.append(card);
      }
      if (this.data?.has_more) this.command(parent,'Cargar más',() => this.load(page,true));
    }
    profileForm(parent) {
      const state = this.profile, {form,finish} = this.form(parent,'Guardar teléfono',async () => {
        if (!/^[+]?[0-9() -]{7,25}$/.test(state.phone)) throw new Error('Introduce un teléfono válido.');
        await this.mutation('update_my_phone',{p_value:state.phone},'Teléfono actualizado.');
      }); this.field(form,'Teléfono',state,'phone','tel').required = true; finish();
      if (this.role === 'patient') {
        parent.append(this.node('h2','Contacto de emergencia','section-title'));
        const emergency = this.form(parent,'Guardar contacto',async () => {
          if (![state.given,state.family,state.relationship].every(value => value.trim()) || !/^[+]?[0-9() -]{7,25}$/.test(state.emergencyPhone)) throw new Error('Completa nombre, apellidos, parentesco y teléfono válidos.');
          await this.mutation('set_my_emergency_contact',{p_id:this.data?.emergency?.id || null,p_given_names:state.given,p_family_names:state.family,p_phone:state.emergencyPhone,p_relationship:state.relationship,p_expected_version:this.data?.emergency?.row_version || null,p_request_key:this.keys.emergency},'Contacto actualizado.',() => { this.keys.emergency = root.crypto.randomUUID(); });
        });
        for (const [label,key,type] of [['Nombres','given','text'],['Apellidos','family','text'],['Teléfono de emergencia','emergencyPhone','tel'],['Parentesco','relationship','text']]) this.field(emergency.form,label,state,key,type).required = true;
        emergency.finish();
      }
      parent.append(this.node('h2','Notificaciones','section-title'));
      for (const item of this.data?.preferences || []) {
        const group = this.node('label',null,'module-toggle'), toggle = this.node('input'); toggle.type = 'checkbox'; toggle.checked = item.enabled; toggle.disabled = this.ui.busy();
        toggle.addEventListener('change',() => this.ui.run(async () => {
          const enabled = toggle.checked;
          await this.mutation(item.preference_id ? 'update_record' : 'create_record',item.preference_id ? {p_resource:'notification_preferences',p_id:item.preference_id,p_values:{enabled},p_expected_version:item.row_version} : {p_resource:'notification_preferences',p_values:{profile_id:this.access.profile.id,topic_id:item.id,channel:'in_app',enabled},p_request_key:root.crypto.randomUUID()},'Preferencia guardada.');
        })); group.append(toggle,this.node('span',item.name)); parent.append(group);
      }
      const passwords = {password:'',repeat:''}, passwordForm = this.form(parent,'Actualizar contraseña',async () => {
        const value = passwords.password; passwords.password = ''; const repeated = passwords.repeat; passwords.repeat = '';
        if (value.length < 12 || value !== repeated) throw new Error('Usa al menos 12 caracteres y confirma la misma contraseña.');
        await this.api.changePassword(value); this.ui.message('Contraseña actualizada.');
      });
      this.field(passwordForm.form,'Nueva contraseña',passwords,'password','password').autocomplete = 'new-password';
      this.field(passwordForm.form,'Repetir contraseña',passwords,'repeat','password').autocomplete = 'new-password'; passwordForm.finish();
    }
    patientPicker(parent) {
      const state = {id:this.selected};
      const input = this.field(parent,'Paciente / turno',state,'id','text',(this.workspace?.appointments || []).map(item => [item.id,item.patient_name+' · '+(item.ticket_number || item.record_number)]));
      input.addEventListener('change',() => { this.select(state.id); this.ui.run(() => this.load(this.screen)); });
      if (this.appointment) { this.detail(parent,'Paciente',this.appointment.patient_name); this.detail(parent,'Turno',this.appointment.ticket_number); this.detail(parent,'Teléfono',this.appointment.phone); }
    }
    renderClinical(parent,page) {
      if (this.clinicalPage !== page) { this.clinicalStage = ''; this.activeLab = null; this.clinicalPage = page; }
      const el = (tag,text,style) => this.node(tag,text,style);
      const repaint = () => this.ui.run(async () => {});
      const card = title => { const node=el('section',null,'clinical-lab-card'); node.append(el('h3',title)); return node; };
      const workspace=this.workspace;
      if (!workspace) { parent.append(el('p','No se pudo cargar la información.')); this.command(parent,'Reintentar',()=>this.load(page)); return; }
      const appointment=this.appointment, patient=this.chart?.patient;
      const open = async item => { this.select(item.id); await this.loadChart(); this.clinicalStage=page==='laboratory'?'':'record'; };
      const action = (node,label,route) => node.append(this.ui.button(label,()=>this.ui.go(route),'module-action'));
      if (!this.clinicalStage || !appointment) {
        const intro=el('article',null,'clinical-landing');
        intro.append(el('span',page==='patients'?'TU PRÁCTICA MÉDICA':page==='laboratory'?'ATENCIÓN CLÍNICA':'HISTORIA DEL PACIENTE','sched-eyebrow'),el('h2',page==='patients'?'Tus pacientes, su evolución':page==='laboratory'?'Laboratorio, paso a paso':'Un expediente, toda la información'),el('p','Busca un paciente de tu agenda para consultar su información autorizada.')); parent.append(intro);
        const search=card(page==='laboratory'?'Buscar paciente':'Buscar expediente'), state={query:this.clinicalQuery,day:this.day};
        const input=this.field(search,'DUI o nombre del paciente',state,'query');
        const list=el('div',null,'patient-matches');
        const paint=()=>{list.replaceChildren(); const fold=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f-]/g,'').toLowerCase();
          const rows=workspace.appointments.filter(item=>fold(item.patient_name+' '+(item.dui||'')+' '+item.record_number).includes(fold(this.clinicalQuery)));
          if(!rows.length)list.append(el('p','No hay pacientes asignados que coincidan para esta fecha.','sched-hint'));
          for(const item of rows){const button=this.ui.button(null,()=>this.ui.run(()=>open(item)),'patient-match-card');button.setAttribute('aria-label','Seleccionar a '+item.patient_name);
            button.append(el('h3',item.patient_name),el('p','DUI: '+(item.dui||'No registrado')+' · '+item.record_number),el('p',this.ui.period(item.period)),el('span','Ver ficha e historial'));list.append(button);}
        };
        input.addEventListener('input',()=>{this.clinicalQuery=state.query;paint();});
        const day=this.field(search,'Fecha de atención',state,'day','date');day.addEventListener('change',()=>{this.day=state.day;this.select('');this.ui.run(()=>this.load(page));});
        paint();search.append(list);parent.append(search);
        if(appointment){const selected=card(appointment.patient_name);selected.append(el('p',appointment.record_number));
          this.command(selected,page==='laboratory'?'Solicitar exámenes':'Abrir expediente completo',async()=>{await this.loadChart();this.clinicalStage=page==='laboratory'?'request':'record';});parent.append(selected);}
        if(page==='patients')this.ui.doctorPatientHistory(parent,this);
        return;
      }
      const ticket=el('section',null,'clinical-ticket');ticket.setAttribute('role','region');
      const back=()=>{if(this.activeLab){this.activeLab=null;}else this.clinicalStage='';repaint();};
      ticket.append(this.ui.button('Volver',back,'text-button'),el('h2',this.activeLab?'Detalle de examen':this.clinicalStage==='request'?'Solicitar exámenes':'Expediente completo'));
      parent.append(ticket);
      if(!patient){ticket.append(el('p','No se pudo cargar el expediente.'));this.command(ticket,'Reintentar',()=>this.loadChart());action(ticket,'Ir a consulta','consultation');return;}
      const age=patient.birth_date?(()=>{const birth=new Date(patient.birth_date+'T00:00:00'),now=new Date();let value=now.getFullYear()-birth.getFullYear();if(now.getMonth()<birth.getMonth()||(now.getMonth()===birth.getMonth()&&now.getDate()<birth.getDate()))value--;return value>=0?value+' años':null;})():null;
      const person=card(this.activeLab?'Paciente':'Datos personales');
      if(this.activeLab){for(const[label,value]of[['Nombre completo',patient.full_name],['Edad',age],['Teléfono',patient.phone]])this.detail(person,label,value);}
      else person.append(root.HospitalClinicalIdentity(this.ui.el,{givenName:patient.given_names,familyName:patient.family_names,fullName:patient.full_name,age,dui:patient.dui||patient.identification,email:patient.email,phone:patient.phone,record:patient.record_number}));
      ticket.append(person);
      if(this.clinicalStage==='request'){
        const form=card('Solicitud de laboratorio');this.laboratoryForm(form);ticket.append(form);return;
      }
      const labs=this.chart.laboratories||[],lab=labs.find(item=>item.id===this.activeLab);
      const state=item=>({completed:'Completado',pending:'Pendiente',in_progress:'En Proceso',cancelled:'Cancelado'})[item.status]||'Estado no disponible';
      const actions=node=>{node.append(el('p','Las observaciones y recetas se registran en la consulta abierta.','sched-hint'));action(node,'Añadir observación','consultation');action(node,'Añadir receta',this.encounter?.status==='open'?'prescriptions':'consultation');};
      if(lab){
        const info=card(lab.test_name);this.detail(info,'Fecha de solicitud',dateTime(lab.requested_at));this.detail(info,'Estado',state(lab));this.detail(info,'Indicaciones',lab.instructions);ticket.append(info);
        const results=card('Resultado del examen');
        if(lab.status==='completed'&&lab.released_at){if(lab.narrative)this.detail(results,'Informe',lab.narrative);for(const value of lab.values||[]){const row=el('article',null,'clinical-result-value');row.append(el('h3',value.name),el('strong',[value.value,value.unit].filter(Boolean).join(' ')),el('p','Referencia: '+(value.reference||'No registrada')));results.append(row);}this.detail(results,'Publicado',dateTime(lab.released_at));}
        else results.append(el('p',lab.status==='in_progress'?'El laboratorio está procesando el examen.':'No hay resultados publicados.'));
        ticket.append(results);actions(ticket);return;
      }
      const history=card('Historial clínico de mis consultas');
      for(const visit of this.chart.history||[]){const row=card(dateTime(visit.started_at));for(const[key,label]of[['subjective','Motivo'],['objective','Exploración'],['assessment','Evaluación'],['plan','Plan']])if(visit[key])this.detail(row,label,visit[key]);history.append(row);}
      if(!this.chart.history?.length)history.append(el('p','Sin consultas previas registradas.'));ticket.append(history);
      const notes=card('Notas y recetas');for(const[key,label]of[['allergies','Alergias'],['conditions','Condiciones'],['medical_history','Antecedentes'],['medications','Medicamentos']])this.detail(notes,label,(this.chart[key]||[]).join('\n')||'Sin registros');
      for(const vital of this.chart.vitals||[])this.detail(notes,vital.label,vital.value);actions(notes);ticket.append(notes);
      const laboratory=card('Laboratorios del expediente');laboratory.append(el('p','Más recientes primero · Solicitudes y resultados del paciente','sched-hint'));
      if(!labs.length)laboratory.append(el('p','Este paciente todavía no tiene exámenes registrados.'));
      for(const item of [...labs].sort((a,b)=>Date.parse(b.requested_at)-Date.parse(a.requested_at))){const row=el('article',null,'clinical-lab-history-card');row.append(el('h3',item.test_name),el('p',dateTime(item.requested_at)),el('span',state(item),'clinical-lab-state '+(item.status==='completed'?'is-completed':item.status==='pending'?'is-pending':'is-processing')));row.append(this.ui.button('Ver detalle',()=>{this.activeLab=item.id;repaint();},'clinical-lab-open'));laboratory.append(row);}ticket.append(laboratory);
    }
    renderDoctor(parent,page) {
      if (page === 'home' && this.workspace) { this.ui.doctorDashboard(parent,this); return; }
      if (['patients','chart','laboratory'].includes(page)) { this.renderClinical(parent,page); return; }
      if (page !== 'consultation') {
      const dayState = {day:this.day}, dayInput = this.field(parent,'Fecha de atención',dayState,'day','date');
      dayInput.addEventListener('change',() => { this.day = dayState.day; this.select(''); this.ui.run(() => this.load(page)); });
      }
      const workspace = this.workspace;
      if (!workspace) { parent.append(this.ui.row('Sin información','Actualiza para consultar tu jornada.')); this.command(parent,'Actualizar',() => this.load(page)); return; }
      if (page === 'patients') {
        const appointments = workspace.appointments.filter(item => this.matches(item.patient_name+' '+item.record_number+' '+(item.ticket_number || ''),this.search));
        if (!appointments.length) parent.append(this.ui.row('Sin pacientes','No tienes pacientes asignados para esta fecha.'));
        for (const item of appointments) {
          const card = this.ui.row(item.patient_name,item.record_number+' · '+this.ui.period(item.period),labels[item.status]);
          for (const [id,label] of [['consultation','Atender'],['chart','Expediente']]) card.append(this.ui.button(label,() => { this.select(item.id); this.ui.go(id); },'module-action')); parent.append(card);
        }
        if (page === 'patients') this.ui.doctorPatientHistory(parent,this);
        return;
      }
      if (page === 'consultation') {
        this.ui.doctorConsultations(parent,this);
        if (workspace.appointments.length) { this.patientPicker(parent); this.consultationForm(parent); }
        return;
      }
      if (page === 'notifications') { this.renderNotifications(parent,workspace.notifications); return; }
      this.patientPicker(parent);
      if (page === 'chart') this.chartView(parent);
      if (page === 'laboratory') this.laboratoryForm(parent);
      if (page === 'prescriptions') this.prescriptionForm(parent);
    }
    renderNotifications(parent,notifications) {
      parent.append(this.node('h2','Notificaciones recientes','section-title'));
      const items = notifications.filter(item => this.matches(item.title+' '+item.body,this.search));
      if (!items.length) parent.append(this.ui.row('Sin notificaciones','No hay avisos recientes.'));
      for (const item of items) {
        const card = this.ui.row(item.title,item.body,item.read_at ? 'Leída' : 'No leída'); card.append(this.node('p',dateTime(item.created_at)));
        if (!item.read_at) this.command(card,'Marcar como leída',() => this.mutation('update_record',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.')); parent.append(card);
      }
    }
    consultationForm(parent) {
      if (!this.appointment) return;
      if (!this.appointment.encounter_id) {
        const button = this.command(parent,'Iniciar consulta',() => this.mutation('start_consultation',{p_appointment:this.selected,p_request_key:this.keys.start},'Consulta iniciada.',() => { this.keys.start = root.crypto.randomUUID(); this.seedDraft = true; }),true);
        button.disabled ||= !['checked_in','in_progress'].includes(this.appointment.status); return;
      }
      const encounter = this.encounter; if (!encounter) return;
      if (encounter.status !== 'open') { for (const [key,label] of [['subjective','Motivo'],['objective','Exploración'],['assessment','Evaluación'],['plan','Plan']]) this.detail(parent,label,encounter[key]); return; }
      const {form,finish} = this.form(parent,'Guardar consulta',async () => {
        if (!Object.values(this.consultation).every(value => value.trim() && value.length <= 10000)) throw new Error('Completa todos los campos de la consulta.');
        await this.mutation('save_consultation',{p_encounter:encounter.id,p_note:this.noteID,p_values:{...this.consultation},p_diagnosis:this.diagnosis.selected || null,p_expected_version:this.noteVersion,p_request_key:this.keys.save},'Consulta guardada.',() => { this.keys.save = root.crypto.randomUUID(); this.seedDraft = true; });
      });
      for (const [key,label] of [['subjective','Motivo y síntomas'],['objective','Exploración física'],['assessment','Evaluación clínica'],['plan','Plan e indicaciones']]) this.field(form,label,this.consultation,key,'textarea').required = true; finish();
      this.field(parent,'Buscar diagnóstico por',this.diagnosis,'by','text',[['description','Descripción'],['code','Código CIE-10']]);
      this.field(parent,'Buscar diagnóstico',this.diagnosis,'query');
      this.command(parent,'Buscar diagnóstico',async () => {
        const query = this.diagnosis.query.trim(); if (query.length < 2 || query.length > 120) throw new Error('Escribe entre 2 y 120 caracteres.');
        const result = await this.api.rpc('read_resource',{p_resource:'diagnosis_codes',p_filters:[{column:this.diagnosis.by === 'code' ? 'code' : 'description',op:'ilike',value:'%'+query+'%'}],p_limit:25,p_sort:'code',p_direction:'asc',p_cursor:null}); this.diagnoses = result.data;
      });
      this.field(parent,'Diagnóstico principal',this.diagnosis,'selected','text',this.diagnoses.map(item => [item.id,item.code+' · '+item.description]));
      if (encounter.note_id) {
        const details = this.node('details'); details.append(this.node('summary','Firmar y cerrar consulta'));
        this.command(details,'Confirmar firma y cierre',async () => {
          if (Object.keys(this.consultation).some(key => this.consultation[key] !== (encounter[key] || ''))) throw new Error('Guarda los cambios antes de cerrar la consulta.');
          await this.mutation('close_consultation',{p_encounter:encounter.id,p_note:encounter.note_id,p_note_version:encounter.note_version,p_expected_version:encounter.row_version},'Consulta firmada y cerrada.');
        }); parent.append(details);
      }
    }
    chartView(parent) {
      if (!this.chart) return;
      const patient = this.chart.patient;
      for (const [key,label] of [['full_name','Nombre'],['record_number','Expediente'],['identification','Identificación'],['birth_date','Nacimiento'],['phone','Teléfono'],['email','Correo']]) this.detail(parent,label,patient[key]);
      for (const [key,label] of [['allergies','Alergias'],['conditions','Condiciones'],['medical_history','Antecedentes'],['medications','Medicamentos']]) this.detail(parent,label,(this.chart[key] || []).join('\n') || 'Sin registros');
      for (const vital of this.chart.vitals || []) this.detail(parent,vital.label,vital.value);
      this.detail(parent,'Grupo sanguíneo',this.chart.blood_type);
      const filters = this.node('div',null,'module-filters'); this.field(filters,'Desde',this.filters,'from','datetime-local'); this.field(filters,'Hasta',this.filters,'to','datetime-local');
      this.command(filters,'Buscar historial',async () => {
        if (this.filters.from && this.filters.to && this.filters.from > this.filters.to) throw new Error('Revisa las fechas del historial.');
        this.chart = await this.api.rpc('doctor_chart',{p_patient:this.appointment.patient_id,p_from:this.filters.from ? new Date(this.filters.from).toISOString() : null,p_to:this.filters.to ? new Date(this.filters.to).toISOString() : null,p_query:this.search});
      }); parent.append(filters);
      for (const encounter of this.chart.history) { const card = this.ui.row(dateTime(encounter.started_at),'',labels[encounter.status]); for (const key of ['subjective','objective','assessment','plan']) if (encounter[key]) card.append(this.node('p',encounter[key])); parent.append(card); }
      if (!this.chart.history.length) parent.append(this.ui.row('Sin consultas','No hay consultas propias en este intervalo.'));
    }
    laboratoryForm(parent) {
      if (this.encounter?.status === 'open') {
        const {form,finish} = this.form(parent,'Emitir orden',async () => {
          if (this.encounter?.status !== 'open' || !this.workspace.tests.some(test => test.id === this.lab.test) || this.lab.instructions.length > 10000) throw new Error('Selecciona un estudio válido y una consulta abierta.');
          const measure=(text,min,max)=>{const clean=String(text||'').trim().replace(',','.');const value=Number(clean);return /^\d{1,3}(\.\d{1,2})?$/.test(clean)&&value>=min&&value<=max?value:null;};
          const weight=measure(this.lab.weight,.1,500),height=measure(this.lab.height,20,250);
          if(weight===null||height===null)throw new Error('Revisa peso (0.1–500 kg) y altura (20–250 cm).');
          await this.mutation('doctor_submit_lab_request',{p_encounter:this.encounter.id,p_test:this.lab.test,p_instructions:this.lab.instructions,p_request_key:this.keys.lab,p_weight:weight,p_height:height},'Orden y mediciones registradas.',() => { this.keys.lab = root.crypto.randomUUID(); this.lab = {test:'',instructions:'',weight:'',height:''}; });
        });
        this.detail(form,'Clínica',this.workspace.facility_name); this.detail(form,'Médico emisor',this.workspace.doctor_name);
        this.field(form,'Tipo de laboratorio',this.lab,'test','text',this.workspace.tests.map(test => [test.id,test.name])).required = true;
        this.field(form,'Indicaciones',this.lab,'instructions','textarea');
        this.field(form,'Peso (kg)',this.lab,'weight').required=true;
        this.field(form,'Altura (cm)',this.lab,'height').required=true;
        const submit = finish();
        if (!this.workspace.tests.length) { submit.disabled = true; form.append(this.node('p','No hay estudios activos en el catálogo de la sede.','scope-note')); }
      } else {
        parent.append(this.ui.row('Emisión de órdenes','Selecciona una consulta abierta para emitir una orden.'));
        if(this.appointment)parent.append(this.ui.button('Ir a consulta',()=>this.ui.go('consultation'),'module-action'));
      }
    }
    prescriptionForm(parent) {
      if (this.encounter?.status === 'open') {
        this.detail(parent,'Alergias registradas',(this.context?.allergies || []).join(', ') || 'Sin registros');
        if (this.data && !this.data.options.some(item => item.kind === 'medication')) parent.append(this.ui.row('Sin medicamentos disponibles','No hay medicamentos activos en el catálogo de la sede.'));
        const {form,finish} = this.form(parent,'Añadir medicamento',async () => {
          const rx = this.rx, number = value => /^[0-9]+([.,][0-9]{1,4})?$/.test(value) && Number(value.replace(',','.')) > 0 ? Number(value.replace(',','.')) : null;
          if (!rx.medication || !rx.unit || !rx.route || !number(rx.dose) || !number(rx.interval) || !number(rx.quantity) || !rx.instructions.trim() || rx.instructions.length > 2000 || !rx.starts || (rx.days && (!/^\d{1,5}$/.test(rx.days) || Number(rx.days)<1 || Number(rx.days)>36500)) || (rx.ends && rx.ends < rx.starts) || this.lines.length >= 30) throw new Error('Revisa medicamento, dosis, vía, frecuencia, fechas e indicaciones.');
          if(rx.days){const end=new Date(rx.starts+'T00:00:00');end.setDate(end.getDate()+Number(rx.days)-1);rx.ends=localDay(end);}
          this.lines.push({medication_id:rx.medication,dose:number(rx.dose),dose_unit_id:rx.unit,route_id:rx.route,interval_hours:number(rx.interval),quantity:number(rx.quantity),instructions:rx.instructions,starts_on:rx.starts,ends_on:rx.ends || null});
          rx.medication = ''; rx.dose = ''; rx.instructions = ''; rx.interval = ''; rx.quantity = ''; rx.days = '';
        });
        for (const [label,key,kind] of [['Medicamento','medication','medication'],['Unidad de dosis','unit','unit'],['Vía','route','route']]) this.field(form,label,this.rx,key,'text',(this.data?.options || []).filter(item => item.kind === kind).map(item => [item.id,item.name])).required = true;
        const inputs={};
        for (const [label,key,type] of [['Dosis','dose','number'],['Cada cuántas horas','interval','number'],['Durante (días)','days','number'],['Cantidad a dispensar','quantity','number'],['Observaciones','instructions','textarea'],['Inicio','starts','date'],['Fin (opcional)','ends','date']]) {
          inputs[key]=this.field(form,label,this.rx,key,type);inputs[key].required=!['days','ends'].includes(key);
        }
        inputs.days.min='1';inputs.days.step='1';inputs.days.max='36500';
        const updateEnd=()=>{if(/^\d{1,5}$/.test(this.rx.days)&&Number(this.rx.days)>0&&Number(this.rx.days)<=36500&&this.rx.starts){const end=new Date(this.rx.starts+'T00:00:00');end.setDate(end.getDate()+Number(this.rx.days)-1);this.rx.ends=localDay(end);inputs.ends.value=this.rx.ends;}};
        inputs.days.addEventListener('input',updateEnd);inputs.starts.addEventListener('input',updateEnd);
        inputs.ends.addEventListener('input',()=>{this.rx.days='';inputs.days.value='';});
        form.append(this.node('p','Indica duración en días o fecha final. Sin ambas, hasta nueva indicación.','scope-note'));finish();
        this.lines.forEach((line,index) => {
          const option=id=>this.data?.options.find(item=>item.id===id)?.name || 'No disponible';
          const duration=line.ends_on?((Date.parse(line.ends_on+'T00:00:00Z')-Date.parse(line.starts_on+'T00:00:00Z'))/86400000+1)+' días':'Hasta nueva indicación';
          const card=this.ui.row(option(line.medication_id),'Vista previa de receta');
          for(const[label,value]of[['Dosis',line.dose+' '+option(line.dose_unit_id)],['Cada',line.interval_hours+' horas'],['Vía',option(line.route_id)],['Durante',duration],['Cantidad',String(line.quantity)],['Observaciones',line.instructions]])this.detail(card,label,value);
          this.command(card,'Quitar medicamento',async()=>{this.lines.splice(index,1);});parent.append(card);
        });
        if (this.lines.length) {
          const confirm = this.node('details'); confirm.append(this.node('summary','Emitir y firmar receta'));
          this.command(confirm,'Confirmar emisión',() => this.mutation('mobile_issue_prescription',{p_encounter:this.encounter.id,p_items:this.lines.map(line => ({...line})),p_request_key:this.keys.rx},'Receta emitida.',() => { this.keys.rx = root.crypto.randomUUID(); this.lines = []; }),true); parent.append(confirm);
        }
      } else parent.append(this.ui.row('Emisión de recetas','Selecciona una consulta abierta para emitir una receta.'));
      this.renderData(parent,'prescriptions');
    }
  }
  root.HospitalModules = HospitalModules;
})(typeof globalThis !== 'undefined' ? globalThis : this);
