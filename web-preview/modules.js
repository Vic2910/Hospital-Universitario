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
      this.items = []; this.lines = []; this.documents = new Map(); this.filters = {from:'',to:'',query:''};
      this.day = localDay(new Date()); this.request = {specialty:'',reason:'',day:this.day,from:'08:00',to:'12:00'};
      this.consultation = {subjective:'',objective:'',assessment:'',plan:''}; this.seedDraft = true;
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:''}; this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',starts:this.day,ends:''};
      this.profile = {phone:'',given:'',family:'',emergencyPhone:'',relationship:''};
      this.keys = Object.fromEntries(['request','start','save','lab','rx','emergency'].map(key => [key,root.crypto.randomUUID()]));
    }
    configure(access, role, facility) {
      const identity = access.profile.id + '/' + role + '/' + facility;
      if (this.identity !== identity) { this.clear(); this.identity = identity; }
      this.role = role; this.access = access; this.facility = facility;
    }
    supports(role, page) {
      return role === 'doctor' ? ['home','patients','appointments','consultation','chart','laboratory','prescriptions','notifications','profile'].includes(page)
        : ['appointments','request','chart','history','prescriptions','laboratory','notifications','profile'].includes(page);
    }
    async load(page, more = false) {
      if (!this.facility) throw new Error('No hay una sede autorizada.');
      if (this.screen !== page) { this.screen = page; this.data = null; this.items = []; this.filters = {from:'',to:'',query:''}; }
      if (this.role === 'doctor' && !['profile','notifications'].includes(page)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(this.day)) throw new Error('Selecciona una fecha de atención válida.');
        const from = new Date(this.day + 'T00:00:00'), to = new Date(from); to.setDate(to.getDate()+1);
        this.workspace = await this.api.rpc('doctor_workspace',{p_facility:this.facility,p_from:from.toISOString(),p_to:to.toISOString()});
        if (!Array.isArray(this.workspace.appointments) || !Array.isArray(this.workspace.orders)) throw new Error('Respuesta de agenda inválida.');
        if (this.selected && !this.workspace.appointments.some(item => item.id === this.selected)) this.select('');
        if (this.appointment && ['consultation','chart','laboratory','prescriptions'].includes(page)) await this.loadChart();
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
      this.consultation = {subjective:'',objective:'',assessment:'',plan:''};
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:''};
      this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',starts:localDay(new Date()),ends:''};
      for (const key of ['start','save','lab','rx']) this.keys[key] = root.crypto.randomUUID();
    }
    async loadChart() {
      this.context = await this.api.rpc('doctor_chart',{p_patient:this.appointment.patient_id,p_from:null,p_to:null,p_query:''});
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
      if (!this.data) this.command(parent,'Actualizar',() => this.load(page));
      if (page === 'request') this.requestForm(parent);
      else if (page === 'profile') { this.profileForm(parent); return; }
      else if (['appointments','history','laboratory','prescriptions','notifications'].includes(page)) this.filtersView(parent);
      for (const section of this.data?.sections || []) {
        parent.append(this.node('h2',section.title,'section-title')); const card = this.node('article',null,'card');
        if (!section.fields.length) card.append(this.node('p','Sin registros.'));
        for (const field of section.fields) if (this.matches(field.label + ' ' + field.value,this.search)) this.detail(card,field.label,field.value);
        parent.append(card);
      }
      const rows = this.items.filter(item => this.matches(item.title+' '+(item.subtitle || '')+' '+item.details.map(field => field.value).join(' '),this.search));
      if (!rows.length) parent.append(this.ui.row('Sin registros','No hay información que coincida con esta consulta.'));
      for (const item of rows) {
        const card = this.ui.row(item.title,item.subtitle,labels[item.status] || 'Estado no disponible');
        card.append(this.node('p',dateTime(item.event_at),'module-date'));
        const details = this.node('details'); details.append(this.node('summary','Ver detalle'));
        for (const field of item.details) this.detail(details,field.label,field.label === 'Horario' ? this.ui.period(field.value) : field.value); card.append(details);
        if (item.action === 'mark_read') this.command(card,'Marcar como leída',() => this.mutation('update_record',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.'));
        if (item.action === 'cancel_appointment') {
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
      if (page === 'appointments') parent.append(this.ui.button('Solicitar atención',() => this.ui.go('request'),'primary'));
    }
    requestForm(parent) {
      const values = this.request, {form,finish} = this.form(parent,'Enviar solicitud',async () => {
        if (!values.specialty || !values.reason.trim() || values.reason.length > 2000 || values.day < localDay(new Date()) || values.from >= values.to) throw new Error('Revisa especialidad, motivo, fecha y horario de la solicitud.');
        await this.mutation('request_appointment',{p_patient:this.access.patient_id,p_facility:this.facility,p_specialty:values.specialty,p_reason:values.reason.trim(),p_date:values.day,p_from:values.from,p_to:values.to,p_request_key:this.keys.request},'Solicitud enviada. Recepción confirmará la disponibilidad.',() => { this.keys.request = root.crypto.randomUUID(); values.reason = ''; });
      });
      this.field(form,'Especialidad',values,'specialty','text',(this.data?.options || []).filter(item => item.kind === 'specialty').map(item => [item.id,item.name])).required = true;
      if (this.data && !this.data.options.length) form.append(this.node('p','No hay especialidades disponibles en el catálogo.','scope-note'));
      this.field(form,'Motivo de consulta',values,'reason','textarea').required = true;
      const day = this.field(form,'Fecha preferida',values,'day','date'); day.min = localDay(new Date()); day.required = true;
      this.field(form,'Desde',values,'from','time').required = true; this.field(form,'Hasta',values,'to','time').required = true;
      form.append(this.node('p','La disponibilidad se confirmará al programar.','scope-note')); finish();
      parent.append(this.node('h2','Mis solicitudes','section-title'));
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
    renderDoctor(parent,page) {
      const dayState = {day:this.day}, dayInput = this.field(parent,'Fecha de atención',dayState,'day','date');
      dayInput.addEventListener('change',() => { this.day = dayState.day; this.select(''); this.ui.run(() => this.load(page)); });
      const workspace = this.workspace;
      if (!workspace) { parent.append(this.ui.row('Sin información','Actualiza para consultar tu jornada.')); this.command(parent,'Actualizar',() => this.load(page)); return; }
      if (page === 'home') {
        const grid = this.node('div',null,'metric-grid');
        for (const [key,label,destination] of [['consultations','Consultas del día','consultation'],['completed_consultations','Consultas finalizadas','chart'],['issued_orders','Órdenes emitidas','laboratory'],['pending_orders','Órdenes pendientes','laboratory']]) {
          const node = this.ui.button(null,() => this.ui.go(destination),'metric'); node.append(this.node('strong',String(workspace.stats[key])),this.node('span',label)); grid.append(node);
        } parent.append(grid);
        for (const [id,label] of [['patients','Mis pacientes'],['consultation','Iniciar consulta'],['laboratory','Laboratorio'],['prescriptions','Recetas']]) parent.append(this.ui.button(label,() => this.ui.go(id),'menu-row'));
        this.renderNotifications(parent,workspace.notifications.slice(0,5)); return;
      }
      if (['patients','appointments'].includes(page)) {
        const appointments = workspace.appointments.filter(item => this.matches(item.patient_name+' '+item.record_number+' '+(item.ticket_number || ''),this.search));
        if (!appointments.length) parent.append(this.ui.row('Sin pacientes','No tienes pacientes asignados para esta fecha.'));
        for (const item of appointments) {
          const card = this.ui.row(item.patient_name,item.record_number+' · '+this.ui.period(item.period),labels[item.status]);
          for (const [id,label] of [['consultation','Atender'],['chart','Expediente']]) card.append(this.ui.button(label,() => { this.select(item.id); this.ui.go(id); },'module-action')); parent.append(card);
        } return;
      }
      if (page === 'notifications') { this.renderNotifications(parent,workspace.notifications); return; }
      this.patientPicker(parent);
      if (page === 'consultation') this.consultationForm(parent);
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
          if (!this.workspace.tests.some(test => test.id === this.lab.test) || this.lab.instructions.length > 10000) throw new Error('Selecciona un estudio válido.');
          await this.mutation('doctor_issue_lab_order',{p_encounter:this.encounter.id,p_test:this.lab.test,p_instructions:this.lab.instructions,p_request_key:this.keys.lab},'Orden emitida.',() => { this.keys.lab = root.crypto.randomUUID(); this.lab.test = ''; this.lab.instructions = ''; });
        });
        this.detail(form,'Clínica',this.workspace.facility_name); this.detail(form,'Médico emisor',this.workspace.doctor_name);
        this.field(form,'Tipo de laboratorio',this.lab,'test','text',this.workspace.tests.map(test => [test.id,test.name])).required = true;
        this.field(form,'Indicaciones',this.lab,'instructions','textarea'); const submit = finish();
        if (!this.workspace.tests.length) { submit.disabled = true; form.append(this.node('p','No hay estudios activos en el catálogo de la sede.','scope-note')); }
      } else parent.append(this.ui.row('Emisión de órdenes','Selecciona una consulta abierta para emitir una orden.'));
      for (const order of this.workspace.orders.filter(item => this.matches(item.patient_name+' '+item.test_name,this.search))) {
        const card = this.ui.row(order.test_name,order.patient_name,labels[order.status]);
        for (const [label,value] of [['Turno',order.ticket_number],['Teléfono',order.phone],['Emisión',dateTime(order.issued_at)],['Clínica',order.facility_name],['Médico',order.doctor_name],['Indicaciones',order.instructions]]) this.detail(card,label,value); parent.append(card);
      }
    }
    prescriptionForm(parent) {
      if (this.encounter?.status === 'open') {
        this.detail(parent,'Alergias registradas',(this.context?.allergies || []).join(', ') || 'Sin registros');
        if (this.data && !this.data.options.some(item => item.kind === 'medication')) parent.append(this.ui.row('Sin medicamentos disponibles','No hay medicamentos activos en el catálogo de la sede.'));
        const {form,finish} = this.form(parent,'Añadir medicamento',async () => {
          const rx = this.rx, number = value => /^[0-9]+([.,][0-9]{1,4})?$/.test(value) && Number(value.replace(',','.')) > 0 ? Number(value.replace(',','.')) : null;
          if (!rx.medication || !rx.unit || !rx.route || !number(rx.dose) || !number(rx.interval) || !number(rx.quantity) || !rx.instructions.trim() || rx.instructions.length > 2000 || !rx.starts || (rx.ends && rx.ends < rx.starts) || this.lines.length >= 30) throw new Error('Revisa medicamento, dosis, vía, frecuencia, fechas e indicaciones.');
          this.lines.push({medication_id:rx.medication,dose:number(rx.dose),dose_unit_id:rx.unit,route_id:rx.route,interval_hours:number(rx.interval),quantity:number(rx.quantity),instructions:rx.instructions,starts_on:rx.starts,ends_on:rx.ends || null});
          rx.medication = ''; rx.dose = ''; rx.instructions = ''; rx.interval = ''; rx.quantity = '';
        });
        for (const [label,key,kind] of [['Medicamento','medication','medication'],['Unidad de dosis','unit','unit'],['Vía','route','route']]) this.field(form,label,this.rx,key,'text',(this.data?.options || []).filter(item => item.kind === kind).map(item => [item.id,item.name])).required = true;
        for (const [label,key,type] of [['Dosis','dose','number'],['Cada cuántas horas','interval','number'],['Cantidad a dispensar','quantity','number'],['Indicaciones','instructions','textarea'],['Inicio','starts','date'],['Fin (opcional)','ends','date']]) this.field(form,label,this.rx,key,type).required = key !== 'ends'; finish();
        this.lines.forEach((line,index) => { const card = this.ui.row(this.data?.options.find(item => item.id === line.medication_id)?.name || 'Medicamento',line.dose+' · cada '+line.interval_hours+' horas'); this.command(card,'Quitar medicamento',async () => { this.lines.splice(index,1); }); parent.append(card); });
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
