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
      this.patientDirectory=[];this.directoryPage=null;this.directoryQuery='';this.directoryError=null;this.selectedPatient=null;
      this.patientLabs=[];this.patientLabPage=null;this.patientLabsError=null;this.recordOpen=false;
      this.labTests=[];this.labCatalogError=null;this.labQuery='';this.labCategory='all';this.labSelected=new Set();this.labReview=false;this.pendingLabs=null;this.labPendingNames=[];this.labPendingPatient=null;
      this.ownLabOrders=[];this.ownLabPage=null;this.ownLabsError=null;
      this.admissions=[];this.admissionsPage=null;this.admissionsError=null;this.admissionForm=false;this.admissionReview=false;
      this.admission={category:'',priority:'normal',reason:'',observations:''};this.pendingAdmission=null;this.pendingAdmissionPatient=null;
      this.items = []; this.lines = []; this.documents = new Map(); this.filters = {from:'',to:'',query:''};
      this.day = localDay(new Date()); this.request = {specialty:'',reason:'',period:'manana',day:this.day,from:'08:00',to:'12:00'};
      this.consultation = {subjective:'',objective:'',assessment:'',plan:'',diagnosis_code:''}; this.vitals={}; this.stateFilter='all'; this.seedDraft = true;
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:''}; this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',days:'',starts:this.day,ends:''};
      this.profile = {phone:'',given:'',family:'',emergencyPhone:'',relationship:''};
      this.keys = Object.fromEntries(['request','start','save','lab','rx','emergency'].map(key => [key,root.crypto.randomUUID()]));
    }
    configure(access, role, facility) {
      const identity = access.profile.id + '/' + role + '/' + facility + '/' + (access.patient_id || '');
      if (this.identity !== identity) { this.clear(); this.identity = identity; }
      this.role = role; this.access = access; this.facility = facility;
    }
    supports(role, page) {
      return role === 'doctor' ? ['home','patients','consultation','chart','laboratory','prescriptions','notifications','profile','admissions'].includes(page)
        : ['appointments','request','chart','history','prescriptions','laboratory','notifications','profile'].includes(page);
    }
    async load(page, more = false) {
      if (!this.facility) throw new Error('No hay una sede autorizada.');
      if(this.role==='doctor'&&page==='admissions'){
        this.screen=page;await this.loadAdmissions(more);
        if(this.admissionForm&&!this.directoryPage)await this.loadPatients();
        return;
      }
      if (page === 'consultation' && this.screen !== page && !this.selected) this.day = localDay(new Date());
      if (this.screen !== page) { this.screen = page; this.data = null; this.items = []; this.filters = {from:'',to:'',query:''}; }
      if (page === 'home' && this.role === 'doctor') this.day = localDay(new Date());
      if (this.role === 'doctor' && !['profile','notifications'].includes(page)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(this.day)) throw new Error('Selecciona una fecha de atención válida.');
        const from = new Date(this.day + 'T00:00:00'), to = new Date(from); to.setDate(to.getDate()+1);
        this.workspace = await this.api.operation('workspace',{p_facility:this.facility,p_from:from.toISOString(),p_to:to.toISOString()});
        if (!Array.isArray(this.workspace.appointments) || !Array.isArray(this.workspace.orders)) throw new Error('Respuesta de agenda inválida.');
        if (this.selected && !this.workspace.appointments.some(item => item.id === this.selected)) {const patient=this.selectedPatient;this.select('');this.selectedPatient=patient;}
        if(['patients','laboratory'].includes(page)){
          await this.loadPatients();
          if(!this.selectedPatient&&this.appointment){const a=this.appointment;this.selectedPatient=this.patientDirectory.find(p=>p.id===a.patient_id)||{id:a.patient_id,full_name:a.patient_name,record_number:a.record_number,phone:a.phone,age:a.age,active_encounter_id:a.encounter_id};}
        }
        if ((this.appointment||this.selectedPatient) && ['patients','consultation','chart','laboratory','prescriptions'].includes(page)) await this.loadChart();
        if(page==='laboratory'){await this.loadLabCatalog();await this.loadOwnLabs();if(this.selectedPatient)await this.loadPatientLabs();}
      }
      if (this.role === 'patient' || ['profile','notifications'].includes(page)) {
        const from = this.filters.from ? new Date(this.filters.from) : null, to = this.filters.to ? new Date(this.filters.to) : null;
        if ((from && !Number.isFinite(from.getTime())) || (to && !Number.isFinite(to.getTime())) || (from && to && from > to)) throw new Error('Revisa el intervalo de fechas.');
        const result = await this.api.operation('module',{p_role:this.role,p_module:page,p_facility:this.facility,
          p_from:from?.toISOString() || null,p_to:to?.toISOString() || null,p_query:this.filters.query,p_cursor:more ? this.data?.next_cursor : null,p_limit:25});
        if (!Array.isArray(result.items) || !Array.isArray(result.options) || (result.has_more && !result.next_cursor)) throw new Error('Respuesta de módulo inválida.');
        this.items = more ? [...this.items,...result.items] : result.items; this.data = result;
        if (page === 'profile') this.profile = {phone:result.phone || '',given:result.emergency?.given_names || '',family:result.emergency?.family_names || '',emergencyPhone:result.emergency?.phones?.[0] || '',relationship:result.emergency?.relationship || ''};
      }
    }
    get appointment() { return this.workspace?.appointments.find(item => item.id === this.selected); }
    get encounter() { return this.context?.history.find(item => item.id === (this.appointment?.encounter_id||this.selectedPatient?.active_encounter_id)); }
    select(id) {
      this.selected = id; this.chart = this.context = null; this.lines = []; this.seedDraft = true;
      this.selectedPatient=null;this.patientLabs=[];this.patientLabPage=null;this.patientLabsError=null;this.recordOpen=false;
      this.consultation = {subjective:'',objective:'',assessment:'',plan:'',diagnosis_code:''}; this.vitals={};
      this.diagnosis = {query:'',by:'description',selected:''}; this.diagnoses = [];
      this.lab = {test:'',instructions:''};
      if(!this.pendingLabs){this.labSelected=new Set();this.labReview=false;}
      this.rx = {medication:'',unit:'',route:'',dose:'',interval:'',quantity:'',instructions:'',days:'',starts:localDay(new Date()),ends:''};
      for (const key of ['start','save','lab','rx']) this.keys[key] = root.crypto.randomUUID();
    }
    async loadChart() {
      const patient=this.selectedPatient?.id||this.appointment?.patient_id;if(!patient)return;
      this.context = await this.api.operation('patientChart',{p_patient:patient,p_from:null,p_to:null,p_query:''});
      this.chart = this.context;
      if (this.seedDraft) {
        const encounter = this.encounter;
        for (const key of Object.keys(this.consultation)) this.consultation[key] = encounter?.[key] || '';
        this.vitals={...(encounter?.vitals||{})};this.noteID = encounter?.note_id || null; this.noteVersion = encounter?.note_version ?? 0; this.seedDraft = false;
      }
    }
    async loadPatients(more=false) {
      if(this.directoryQuery.trim().length>120)throw new Error('La búsqueda admite hasta 120 caracteres.');
      this.directoryError=null;
      try{
        const page=await this.api.doctorRPC('patients',{p_query:this.directoryQuery.trim(),p_offset:more?this.directoryPage?.next_offset||0:0});
        if(!Array.isArray(page.patients))throw new Error('No se pudo interpretar el directorio.');
        this.patientDirectory=more?[...this.patientDirectory,...page.patients]:page.patients;this.directoryPage=page;
      }catch(error){this.patientDirectory=[];this.directoryPage=null;this.directoryError=error.message;if([401,403].includes(error.status))throw error;}
    }
    async loadPatientLabs(more=false) {
      const patient=this.selectedPatient?.id||this.appointment?.patient_id;if(!patient)return;
      this.patientLabsError=null;
      try{
        const page=await this.api.doctorRPC('patient_labs',{p_patient:patient,p_offset:more?this.patientLabPage?.next_offset||0:0});
        if(!Array.isArray(page.items))throw new Error('No se pudo interpretar los exámenes.');
        this.patientLabs=more?[...this.patientLabs,...page.items]:page.items;this.patientLabPage=page;
      }catch(error){this.patientLabs=[];this.patientLabPage=null;this.patientLabsError=error.message;if([401,403].includes(error.status))throw error;}
    }
    async loadLabCatalog(){
      this.labCatalogError=null;
      try{this.labTests=await this.api.doctorRPC('lab_catalog');if(!Array.isArray(this.labTests))throw new Error('Catálogo inválido.');}
      catch(error){this.labTests=[];this.labCatalogError=error.message;if([401,403].includes(error.status))throw error;}
    }
    async loadOwnLabs(more=false){
      this.ownLabsError=null;
      try{const page=await this.api.doctorRPC('lab_orders',{p_offset:more?this.ownLabPage?.next_offset||0:0});if(!Array.isArray(page.items))throw new Error('Lista de órdenes inválida.');this.ownLabOrders=more?[...this.ownLabOrders,...page.items]:page.items;this.ownLabPage=page;}
      catch(error){this.ownLabOrders=[];this.ownLabsError=error.message;if([401,403].includes(error.status))throw error;}
    }
    async sendLabs(){
      if(!this.pendingLabs){
        if(this.encounter?.status!=='open'||!this.labSelected.size||this.labSelected.size>30||![...this.labSelected].every(id=>this.labTests.some(t=>Number(t.id)===id))||!this.lab.instructions.trim()||this.lab.instructions.length>10000)throw new Error('Selecciona exámenes activos e indica el motivo clínico de la consulta.');
        this.pendingLabs={p_encounter:this.encounter.id,p_tests:[...this.labSelected].sort((a,b)=>a-b),p_reason:this.lab.instructions.trim(),p_key:root.crypto.randomUUID()};
        this.labPendingNames=this.labTests.filter(t=>this.labSelected.has(Number(t.id))).map(t=>t.name);
        this.labPendingPatient={...(this.selectedPatient||this.appointment)};
      }
      try{await this.api.doctorRPC('labs',this.pendingLabs);}catch(error){if([400,401,403,409,422].includes(error.status))this.pendingLabs=null;throw error;}
      this.pendingLabs=null;this.labReview=false;this.labSelected=new Set();this.lab.instructions='';
      await this.loadOwnLabs();await this.loadPatientLabs();this.ui.message('Exámenes enviados al laboratorio.');
    }
    async openPatient(patient) {
      const appointment=this.workspace?.appointments.find(a=>a.patient_id===patient.id&&a.encounter_id===patient.active_encounter_id&&patient.active_encounter_id);
      this.select(appointment?.id||'');this.selectedPatient=patient;
      await this.loadChart();if(this.screen==='laboratory')await this.loadPatientLabs();
    }
    async loadAdmissions(more=false){
      this.admissionsError=null;
      try{
        const page=await this.api.doctorRPC('admissions',{p_offset:more?this.admissionsPage?.next_offset||0:0});
        if(!Array.isArray(page.items)||!Array.isArray(page.categories)||!Array.isArray(page.priorities))throw new Error('Respuesta de ingresos inválida.');
        this.admissions=more?[...this.admissions,...page.items]:page.items;this.admissionsPage=page;
      }catch(error){this.admissions=[];this.admissionsError=error.message;if([401,403].includes(error.status))throw error;}
    }
    async sendAdmission(){
      if(!this.pendingAdmission){
        const patient=this.selectedPatient?.id||this.appointment?.patient_id,a=this.admission;
        if(!patient||!this.admissionsPage?.categories.includes(a.category)||!this.admissionsPage?.priorities.includes(a.priority)||!a.reason.trim()||a.reason.length>10000||a.observations.length>10000)throw new Error('Completa paciente autorizado, categoría, prioridad y motivo clínico.');
        this.pendingAdmission={p_patient:patient,p_kind:a.category,p_reason:a.reason.trim(),p_instructions:a.observations.trim(),p_priority:a.priority,p_encounter:this.encounter?.id||null,p_key:root.crypto.randomUUID()};
        this.pendingAdmissionPatient={...(this.selectedPatient||this.appointment)};
      }
      try{
        await this.api.doctorRPC('admission_request',this.pendingAdmission);
      }catch(error){
        if([400,401,403,409,422].includes(error.status))this.pendingAdmission=null;
        throw error;
      }
      this.pendingAdmission=null;this.admissionForm=false;this.admissionReview=false;this.admission={category:'',priority:'normal',reason:'',observations:''};
      await this.loadAdmissions();this.ui.message('Solicitud enviada a recepción. No se ha asignado habitación ni cama.');
    }
    async mutation(name, parameters, success, after) {
      await this.api.operation(name,parameters); if (after) after();
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
        if (page !== 'chart' && item.action === 'mark_read') this.command(card,'Marcar como leída',() => this.mutation('updateItem',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.'));
        if (page !== 'chart' && item.action === 'cancel_appointment') {
          const cancellation = {reason:''}, {form,finish} = this.form(card,'Confirmar cancelación',async () => {
            if (!cancellation.reason.trim()) throw new Error('Escribe el motivo de cancelación.');
            await this.mutation('cancelAppointment',{p_id:item.id,p_status:'cancelled',p_reason:cancellation.reason,p_expected_version:item.row_version},'Cita cancelada.');
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
        await this.mutation('updatePhone',{p_value:state.phone},'Teléfono actualizado.');
      }); this.field(form,'Teléfono',state,'phone','tel').required = true; finish();
      if (this.role === 'patient') {
        parent.append(this.node('h2','Contacto de emergencia','section-title'));
        const emergency = this.form(parent,'Guardar contacto',async () => {
          if (![state.given,state.family,state.relationship].every(value => value.trim()) || !/^[+]?[0-9() -]{7,25}$/.test(state.emergencyPhone)) throw new Error('Completa nombre, apellidos, parentesco y teléfono válidos.');
          await this.mutation('emergencyContact',{p_id:this.data?.emergency?.id || null,p_given_names:state.given,p_family_names:state.family,p_phone:state.emergencyPhone,p_relationship:state.relationship,p_expected_version:this.data?.emergency?.row_version || null,p_request_key:this.keys.emergency},'Contacto actualizado.',() => { this.keys.emergency = root.crypto.randomUUID(); });
        });
        for (const [label,key,type] of [['Nombres','given','text'],['Apellidos','family','text'],['Teléfono de emergencia','emergencyPhone','tel'],['Parentesco','relationship','text']]) this.field(emergency.form,label,state,key,type).required = true;
        emergency.finish();
      }
      parent.append(this.node('h2','Notificaciones','section-title'));
      for (const item of this.data?.preferences || []) {
        const group = this.node('label',null,'module-toggle'), toggle = this.node('input'); toggle.type = 'checkbox'; toggle.checked = item.enabled; toggle.disabled = this.ui.busy();
        toggle.addEventListener('change',() => this.ui.run(async () => {
          const enabled = toggle.checked;
          throw new Error('Las preferencias todavía no están habilitadas en Hospital Móviles.');
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
      if (this.appointment) {
        const a=this.appointment;
        for(const [label,value] of [['Paciente',a.patient_name],['Edad',a.age==null?'No registrada':a.age+' años'],['Expediente',a.record_number],['Consultorio',a.room_code],['Duración',a.duration_minutes==null?'No publicada':a.duration_minutes+' minutos'],['Especialidad',a.specialty||'Cita directa de recepción; sin solicitud vinculada'],['Motivo original',a.reason],['Síntomas declarados',(a.symptoms||[]).join(' · ')],['Otros síntomas',a.other_symptoms]])this.detail(parent,label,value);
      }
    }
    renderDoctor(parent,page) {
      if(page==='admissions'){this.admissionsView(parent);return;}
      if (page === 'home' && this.workspace) { this.ui.doctorDashboard(parent,this); return; }
      if(['patients','laboratory'].includes(page)) {this.directoryView(parent,page==='laboratory');return;}
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
        const filter=this.field(parent,'Estado de citas',this,'stateFilter','text',[['all','Todos'],['scheduled','Programadas'],['confirmed','Confirmadas'],['in_progress','En atención'],['completed','Atendidas'],['cancelled','Canceladas'],['no_show','No asistió']]);
        filter.addEventListener('change',()=>this.ui.go('consultation'));
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
    admissionsView(parent){
      const category=value=>value==='vip'?'VIP':value==='semiprivada'?'Semiprivada':value;
      const state=value=>({solicitado:'Pendiente de recepción',asignado:'Asignado',hospitalizado:'Ingresado',alta_medica:'Alta médica',cerrado:'Cerrado',cancelado:'Cancelado',rechazada:'Rechazada',cancelada:'Cancelada'}[value]||value);
      const wrap=this.node('section',null,'doctor-directory admission-module'),hero=this.node('header',null,'directory-hero');
      hero.append(this.node('small','INGRESOS HOSPITALARIOS'),this.node('h2','Solicita el cuidado que tu paciente necesita'),this.node('p','Tú indicas el motivo clínico. Recepción verifica disponibilidad y confirma la cama.'));wrap.append(hero);
      if(this.admissionsError){wrap.append(this.ui.row('No se pudieron cargar las solicitudes',this.admissionsError));this.command(wrap,'Reintentar solicitudes',()=>this.loadAdmissions());}
      if(!this.admissionForm)this.command(wrap,'Nueva solicitud',async()=>{this.admissionForm=true;this.admissionReview=false;if(!this.directoryPage)await this.loadPatients();},true);
      else{
        const box=this.node('section',null,'admission-form-card');box.append(this.node('h2','Nueva solicitud de ingreso'));
        if(this.pendingAdmission)box.append(this.node('p','Envío sin confirmar. Reintenta la misma solicitud para evitar duplicados.','auth-notice'));
        const patient=(this.pendingAdmission&&this.pendingAdmissionPatient)||this.selectedPatient||this.appointment;
        const fields=this.node('fieldset');fields.disabled=!!this.pendingAdmission||this.ui.busy()||this.admissionReview;
        if(patient){
          this.detail(fields,'Paciente',patient.full_name||patient.patient_name);this.detail(fields,'Expediente',patient.record_number);
          fields.append(this.ui.button('Cambiar paciente',()=>{this.select('');this.ui.repaint();},'text-button'));
        }else{
          fields.append(this.node('h3','1. Selecciona un paciente autorizado'));
          const search=this.node('form',null,'directory-search');this.field(search,'Nombre, DUI o correo',this,'directoryQuery','search').maxLength=120;
          const submit=this.node('button','Buscar pacientes','primary');submit.type='submit';search.append(submit);
          search.addEventListener('submit',event=>{event.preventDefault();if(!this.ui.busy())this.ui.run(()=>this.loadPatients());});fields.append(search);
          if(this.directoryError)fields.append(this.ui.row('No se pudo cargar el directorio',this.directoryError));
          for(const p of this.patientDirectory){const button=this.ui.button(p.full_name+' · '+(p.record_number||'Sin expediente'),()=>this.ui.run(()=>this.openPatient(p)),'directory-patient');button.setAttribute('aria-label','Seleccionar paciente '+p.full_name);fields.append(button);}
          if(!this.patientDirectory.length)fields.append(this.ui.row('Sin pacientes coincidentes','Busca entre tus pacientes autorizados.'));
          if(this.directoryPage?.has_more)this.command(fields,'Cargar más pacientes',()=>this.loadPatients(true));
        }
        this.detail(fields,'Médico solicitante',this.admissionsPage?.doctor_name);
        fields.append(this.node('h3','2. Indica el cuidado requerido'));
        this.field(fields,'Categoría de habitación',this.admission,'category','text',(this.admissionsPage?.categories||[]).map(c=>[c,category(c)]));
        if(!this.admissionsPage?.categories.length)fields.append(this.node('p','No hay categorías disponibles en el catálogo. Actualiza o contacta a recepción.'));
        this.field(fields,'Prioridad',this.admission,'priority','text',(this.admissionsPage?.priorities||[]).map(p=>[p,p==='urgente'?'Urgente':p==='normal'?'Normal':p]));
        this.field(fields,'Motivo clínico del ingreso',this.admission,'reason','textarea').maxLength=10000;
        this.field(fields,'Observaciones e indicaciones (opcional)',this.admission,'observations','textarea').maxLength=10000;
        box.append(fields,this.node('p','La categoría solicitada no garantiza disponibilidad ni reserva habitación.','rose-note'));
        if(this.admissionReview||this.pendingAdmission){
          const payload=this.pendingAdmission;
          box.append(this.node('h3','Confirma el envío a recepción'),this.node('p',category(payload?.p_kind||this.admission.category)+' · '+(payload?.p_priority||this.admission.priority)),this.node('p',payload?.p_reason||this.admission.reason));
          this.command(box,this.pendingAdmission?'Reintentar el mismo envío':'Confirmar envío',()=>this.sendAdmission(),true);
          if(!this.pendingAdmission)box.append(this.ui.button('Seguir editando',()=>{this.admissionReview=false;this.ui.repaint();},'text-button'));
        }else this.command(box,'Revisar y enviar solicitud',async()=>{
          const a=this.admission;if(!patient||!this.admissionsPage?.categories.includes(a.category)||!this.admissionsPage?.priorities.includes(a.priority)||!a.reason.trim()||a.reason.length>10000||a.observations.length>10000)throw new Error('Completa paciente, categoría, prioridad y motivo clínico.');
          this.admissionReview=true;
        },true);
        box.append(this.ui.button('Volver al listado',()=>{this.admissionForm=false;this.admissionReview=false;this.ui.repaint();},'text-button'));wrap.append(box);
      }
      const header=this.node('div',null,'admission-list-header');header.append(this.node('h2','Mis solicitudes'));this.command(header,'Actualizar solicitudes',()=>this.loadAdmissions());wrap.append(header);
      if(!this.admissions.length&&!this.admissionsError)wrap.append(this.ui.row('Sin solicitudes','Todavía no has enviado solicitudes de ingreso.'));
      for(const item of this.admissions){
        const card=this.ui.row(item.patient_name,category(item.category)+' · '+item.priority+' · '+dateTime(item.ordered_at),state(item.decision||item.status));
        const detail=this.node('details',null,'admission-detail');detail.append(this.node('summary','Ver detalle de la solicitud'));
        for(const[label,value]of [['Expediente',item.record_number],['Médico solicitante',item.doctor_name],['Motivo clínico',item.reason],['Observaciones',item.observations],['Respuesta de recepción',item.decision_reason]])if(value)this.detail(detail,label,value);
        if(item.assignment){this.detail(detail,'Habitación y cama',item.assignment.room+' · '+item.assignment.bed+' · '+item.assignment.floor);this.detail(detail,'Asignación confirmada',dateTime(item.assignment.assigned_at));}
        else detail.append(this.node('p','Recepción aún no ha confirmado habitación ni cama.'));
        for(const event of item.history||[])detail.append(this.node('p',state(event.decision||event.status)+' · '+dateTime(event.at),'admission-event'));
        card.append(detail);wrap.append(card);
      }
      if(this.admissionsPage?.has_more)this.command(wrap,'Cargar más solicitudes',()=>this.loadAdmissions(true));parent.append(wrap);
    }
    directoryView(parent,laboratory) {
      const wrap=this.node('section',null,'doctor-directory'),hero=this.node('header',null,'directory-hero');
      hero.append(this.node('small',laboratory?'LABORATORIOS':'MIS PACIENTES'),this.node('h2',laboratory?'Un paciente, toda su información':'Tus pacientes, siempre a mano'),
        this.node('p','Busca por nombre, DUI o correo. Solo aparecen pacientes que tienes autorización para atender.'));
      if(this.directoryPage)hero.append(this.node('span',this.directoryPage.total+' '+(this.directoryPage.total===1?'paciente encontrado':'pacientes encontrados'),'directory-count'));
      wrap.append(hero);
      if(laboratory&&!this.selectedPatient)this.ownLabsView(wrap);
      const search=this.node('form',null,'directory-search');
      const input=this.field(search,'Nombre, DUI o correo',this,'directoryQuery','search');input.maxLength=120;input.placeholder='Busca entre tus pacientes';
      const submit=this.node('button','Buscar pacientes','primary');submit.type='submit';submit.disabled=this.ui.busy();search.append(submit);
      search.addEventListener('submit',event=>{event.preventDefault();if(this.ui.busy())return;this.ui.run(async()=>{this.select('');await this.loadPatients();});});wrap.append(search);
      if(this.directoryError){wrap.append(this.ui.row('No se pudo cargar el directorio',this.directoryError));this.command(wrap,'Reintentar búsqueda',()=>this.loadPatients());}
      const patient=this.selectedPatient;
      if(patient){
        wrap.append(this.ui.button('Volver al listado de pacientes',()=>{this.select('');this.ui.repaint();},'directory-back'));
        const header=this.node('article',null,'directory-selected'),avatar=this.node('span',this.initials(patient.full_name),'directory-avatar');
        const name=this.node('div');name.append(this.node('small','PACIENTE SELECCIONADO'),this.node('h2',patient.full_name),this.node('strong',patient.record_number?'Expediente '+patient.record_number:'Expediente no disponible'),this.node('p',patient.age==null?'Edad no registrada':patient.age+' años'));
        header.append(avatar,name);wrap.append(header);
        const contact=this.node('div',null,'directory-contact');
        for(const [label,value]of [['DUI',patient.dui],['Correo',patient.email],['Teléfono',patient.phone]]){
          const field=this.node('div');field.append(this.node('small',label),this.node('span',value||'No registrado'));contact.append(field);
        }wrap.append(contact);
        if(laboratory){
          wrap.append(this.ui.button(this.recordOpen?'Ocultar expediente completo':'Ver expediente completo del paciente',()=>{this.recordOpen=!this.recordOpen;this.ui.repaint();},'directory-record-toggle'));
          if(this.recordOpen){const record=this.node('section',null,'directory-record');this.chartView(record);wrap.append(record);}
          const labs=this.node('section',null,'directory-labs');labs.append(this.node('h2','Exámenes y resultados del paciente'),this.node('p','Información autorizada de este expediente, sin limitarse a la agenda de hoy.'));
          this.laboratoryForm(labs);wrap.append(labs);
        }else{
          const record=this.node('section',null,'directory-record');this.chartView(record);wrap.append(record);
          wrap.append(this.ui.button('Ver laboratorios de este paciente',()=>this.ui.go('laboratory'),'primary'),this.ui.button('Abrir agenda médica',()=>this.ui.go('consultation'),'text-button'));
          wrap.append(this.ui.button('Solicitar ingreso hospitalario',()=>{this.admissionForm=true;this.ui.go('admissions');},'module-action'));
        }
      }else{
        const list=this.node('div',null,'directory-grid');
        for(const patient of this.patientDirectory){
          const card=this.ui.button(null,()=>this.ui.run(()=>this.openPatient(patient)),'directory-patient');
          card.setAttribute('aria-label','Abrir expediente de '+patient.full_name);
          const text=this.node('div',null,'directory-patient-text');text.append(this.node('strong',patient.full_name),this.node('span',patient.record_number||'Expediente no disponible'),this.node('small',patient.email||'Correo no registrado'),this.node('b',laboratory?'Abrir laboratorios y expediente':'Ver expediente'));
          card.append(this.node('span',this.initials(patient.full_name),'directory-avatar'),text,this.node('span','›','directory-chevron'));list.append(card);
        }wrap.append(list);
        if(!this.patientDirectory.length&&!this.directoryError&&!this.ui.busy())wrap.append(this.ui.row('No se encontraron pacientes',this.directoryQuery?'Prueba otro nombre, DUI o correo dentro de tus pacientes autorizados.':'Aquí aparecerán tus pacientes asignados, sin depender de las citas de hoy.'));
        if(this.directoryPage?.has_more)this.command(wrap,'Cargar más pacientes',()=>this.loadPatients(true));
      }
      parent.append(wrap);
    }
    initials(name) { return String(name||'').split(/\s+/).filter(Boolean).slice(0,2).map(w=>w[0]).join('').toUpperCase(); }
    renderNotifications(parent,notifications) {
      parent.append(this.node('h2','Notificaciones recientes','section-title'));
      const items = notifications.filter(item => this.matches(item.title+' '+item.body,this.search));
      if (!items.length) parent.append(this.ui.row('Sin notificaciones','No hay avisos recientes.'));
      for (const item of items) {
        const card = this.ui.row(item.title,item.body,item.read_at ? 'Leída' : 'No leída'); card.append(this.node('p',dateTime(item.created_at)));
        if (!item.read_at) this.command(card,'Marcar como leída',() => this.mutation('updateItem',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.')); parent.append(card);
      }
    }
    consultationForm(parent) {
      if (!this.appointment) return;
      if (!this.appointment.encounter_id) {
        const button = this.command(parent,'Iniciar consulta',() => this.mutation('startConsultation',{p_appointment:this.selected,p_request_key:this.keys.start},'Consulta iniciada.',() => { this.keys.start = root.crypto.randomUUID(); this.seedDraft = true; }),true);
        button.disabled ||= !['scheduled','confirmed','in_progress'].includes(this.appointment.status); return;
      }
      const encounter = this.encounter; if (!encounter) return;
      if (encounter.status !== 'open') { for (const [key,label] of [['subjective','Motivo'],['objective','Exploración'],['assessment','Evaluación'],['plan','Plan']]) this.detail(parent,label,encounter[key]); return; }
      const {form,finish} = this.form(parent,'Guardar consulta',async () => {
        if (!Object.values(this.consultation).every(value => value.length <= 10000)) throw new Error('Los campos de la consulta exceden el límite.');
        await this.mutation('saveConsultation',{p_encounter:encounter.id,p_values:{...this.consultation,vitals:{...this.vitals}},p_expected_version:this.noteVersion,p_request_key:this.keys.save},'Borrador guardado.',() => { this.keys.save = root.crypto.randomUUID(); this.seedDraft = true; });
      });
      for (const [key,label] of [['subjective','Motivo y síntomas'],['objective','Exploración física'],['assessment','Diagnóstico y evaluación clínica'],['plan','Plan e indicaciones']]) this.field(form,label,this.consultation,key,'textarea');
      this.field(form,'Código diagnóstico opcional (sin catálogo publicado)',this.consultation,'diagnosis_code');
      for(const [key,label] of [['weight_kg','Peso (kg)'],['height_cm','Altura (cm)'],['systolic','Presión sistólica'],['diastolic','Presión diastólica'],['temperature_c','Temperatura (°C)'],['heart_rate','Frecuencia cardíaca']])this.field(form,label,this.vitals,key,'number');
      finish();
      for(const [target,label] of [['chart','Revisar expediente'],['laboratory','Emitir orden de laboratorio'],['prescriptions','Emitir receta'],['admissions','Solicitar ingreso hospitalario']])parent.append(this.ui.button(label,()=>{if(target==='admissions')this.admissionForm=true;this.ui.go(target);},'text-button'));
      if (encounter.note_id) {
        const details = this.node('details'); details.append(this.node('summary','Firmar y cerrar consulta'));
        this.command(details,'Confirmar firma y cierre',async () => {
          if (Object.keys(this.consultation).some(key => this.consultation[key] !== (encounter[key] || ''))) throw new Error('Guarda los cambios antes de cerrar la consulta.');
          if(JSON.stringify(this.vitals)!==JSON.stringify(encounter.vitals||{})||this.lines.length)throw new Error('Guarda los signos vitales y emite o retira los medicamentos pendientes antes de cerrar.');
          await this.mutation('closeConsultation',{p_encounter:encounter.id,p_note:encounter.note_id,p_note_version:encounter.note_version,p_expected_version:encounter.row_version},'Consulta firmada y cerrada.');
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
        this.chart = await this.api.operation('patientChart',{p_patient:this.selectedPatient?.id||this.appointment?.patient_id,p_from:this.filters.from ? new Date(this.filters.from).toISOString() : null,p_to:this.filters.to ? new Date(this.filters.to).toISOString() : null,p_query:this.search});
      }); parent.append(filters);
      for (const encounter of this.chart.history) { const card = this.ui.row(dateTime(encounter.started_at),'',labels[encounter.status]); for (const key of ['subjective','objective','assessment','plan']) if (encounter[key]) card.append(this.node('p',encounter[key])); parent.append(card); }
      if (!this.chart.history.length) parent.append(this.ui.row('Sin consultas','No hay consultas propias en este intervalo.'));
    }
    laboratoryForm(parent) {
      if (this.encounter?.status === 'open'||this.pendingLabs) {
        this.labSelectionView(parent);
      } else parent.append(this.ui.row('Emisión de órdenes','Selecciona una consulta abierta para emitir una orden.'));
      const orders=this.patientLabs;
      if(this.patientLabsError)parent.append(this.ui.row('No se pudieron cargar los exámenes',this.patientLabsError));
      if(this.selectedPatient&&!orders.length&&!this.patientLabsError)parent.append(this.ui.row('Sin exámenes registrados','Este paciente todavía no tiene exámenes registrados.'));
      for (const order of orders) {
        this.labOrderView(parent,order);
      }
      if(this.patientLabPage?.has_more)this.command(parent,'Cargar más exámenes',()=>this.loadPatientLabs(true));
    }
    labSelectionView(parent){
      const box=this.node('section',null,'admission-form-card lab-selection');box.append(this.node('h2','Solicitar exámenes'));
      if(this.labCatalogError){box.append(this.ui.row('No se pudo cargar el catálogo',this.labCatalogError));this.command(box,'Reintentar catálogo',()=>this.loadLabCatalog());}
      const fields=this.node('fieldset');fields.disabled=this.ui.busy()||this.labReview||!!this.pendingLabs;
      const search=this.field(fields,'Buscar exámenes',this,'labQuery','search');search.addEventListener('input',()=>{
        const start=search.selectionStart;this.ui.repaint();const input=document.querySelector('[aria-label="Buscar exámenes"]');input?.focus?.();if(start!=null)input?.setSelectionRange?.(start,start);
      });
      const category=this.field(fields,'Categoría de examen',this,'labCategory','text',[['all','Todas las categorías'],...[...new Set(this.labTests.map(t=>t.category||'Sin categoría'))].sort().map(c=>[c,c])]);category.addEventListener('change',()=>this.ui.repaint());
      const tests=this.labTests.filter(t=>(this.labCategory==='all'||(t.category||'Sin categoría')===this.labCategory)&&this.matches(t.name,this.labQuery));
      const grid=this.node('div',null,'lab-test-grid');
      for(const test of tests){const selected=this.labSelected.has(Number(test.id)),button=this.ui.button(null,()=>{
        if(selected)this.labSelected.delete(Number(test.id));else if(this.labSelected.size<30)this.labSelected.add(Number(test.id));this.ui.repaint();
      },'lab-test-card'+(selected?' is-selected':''));button.setAttribute('aria-label','Seleccionar '+test.name);button.setAttribute('aria-pressed',String(selected));button.append(this.node('span',selected?'✓':'○','lab-test-check'),this.node('strong',test.name),this.node('small',test.category||'Sin categoría'));grid.append(button);}fields.append(grid);
      if(!tests.length)fields.append(this.ui.row('Sin exámenes coincidentes',this.labTests.length?'Prueba otro nombre o categoría.':'No hay exámenes activos. Actualiza o contacta al laboratorio.'));
      fields.append(this.node('h3','Resumen · '+this.labSelected.size+' exámenes seleccionados'));
      for(const test of this.labTests.filter(t=>this.labSelected.has(Number(t.id))))fields.append(this.node('p','• '+test.name));
      this.field(fields,'Motivo e indicaciones clínicas',this.lab,'instructions','textarea').maxLength=10000;box.append(fields);
      if(this.pendingLabs)box.append(this.node('p','Envío sin confirmar. Se reintentará exactamente la misma selección, sin duplicar órdenes.','auth-notice'),this.node('p',this.labPendingPatient?.full_name||this.labPendingPatient?.patient_name),this.node('p',this.labPendingNames.join(' · ')),this.node('p',this.pendingLabs.p_reason));
      if(this.labReview||this.pendingLabs){
        box.append(this.node('h3','Confirma los exámenes antes de enviar'));
        this.command(box,this.pendingLabs?'Reintentar el mismo envío':'Confirmar exámenes',()=>this.sendLabs(),true);
        if(!this.pendingLabs)box.append(this.ui.button('Seguir editando exámenes',()=>{this.labReview=false;this.ui.repaint();},'text-button'));
      }else this.command(box,'Revisar y enviar exámenes',async()=>{
        if(!this.labSelected.size||this.labSelected.size>30||!this.lab.instructions.trim()||this.lab.instructions.length>10000)throw new Error('Selecciona exámenes e indica el motivo clínico.');this.labReview=true;
      },true);
      parent.append(box);
    }
    ownLabsView(parent){
      parent.append(this.node('h2','Mis órdenes de laboratorio'));this.command(parent,'Actualizar órdenes',()=>this.loadOwnLabs());
      if(this.pendingLabs){parent.append(this.node('p','Envío sin confirmar · '+(this.labPendingPatient?.full_name||this.labPendingPatient?.patient_name||'')+' · '+this.labPendingNames.join(' · '),'auth-notice'));this.command(parent,'Reintentar el mismo envío',()=>this.sendLabs(),true);}
      if(this.ownLabsError)parent.append(this.ui.row('No se pudieron cargar las órdenes',this.ownLabsError));
      if(!this.ownLabOrders.length&&!this.ownLabsError)parent.append(this.ui.row('Sin órdenes','Todavía no has solicitado exámenes de laboratorio.'));
      for(const order of this.ownLabOrders)this.labOrderView(parent,order);
      if(this.ownLabPage?.has_more)this.command(parent,'Cargar más órdenes',()=>this.loadOwnLabs(true));
    }
    labOrderView(parent,order){
      const card=this.node('article',null,'lab-order-card');card.append(this.node('h3',order.test_name));
      if(order.patient_name)card.append(this.node('p',order.patient_name));
      card.append(this.node('small',dateTime(order.ordered_at)),this.node('span',({pendiente:'Pendiente',en_proceso:'En proceso',completado:'Completado'})[order.status]||order.status,'lab-state '+(order.status==='completado'?'is-completed':order.status==='en_proceso'?'is-processing':'is-pending')));
      const detail=this.node('details');detail.append(this.node('summary','Ver detalle del examen'));
      if(order.record_number)this.detail(detail,'Expediente',order.record_number);this.detail(detail,'Motivo e indicaciones',order.reason);
      if(order.result_summary!=null){
        this.detail(detail,'Resultado validado y publicado',order.result_summary);
        for(const parameter of order.parameters||[]){this.detail(detail,parameter.label,[parameter.value,parameter.unit].filter(Boolean).join(' '));if(parameter.reference)this.detail(detail,'Referencia del laboratorio',parameter.reference);if(parameter.observation)this.detail(detail,'Observación',parameter.observation);}
        if(order.published_at)this.detail(detail,'Publicado',dateTime(order.published_at));
      }else detail.append(this.node('p','El laboratorio está procesando la orden o aún no ha publicado un resultado validado.'));
      card.append(detail);parent.append(card);
    }
    prescriptionForm(parent) {
      if (this.encounter?.status === 'open') {
        const medications=this.workspace.medications||[];
        const {form,finish}=this.form(parent,'Añadir medicamento',async()=>{
          const rx=this.rx,dose=Number(rx.dose.replace(',','.')),frequency=Number(rx.interval),quantity=Number(rx.quantity),days=Number(rx.days);
          if(!medications.some(m=>m.id===rx.medication)||!Number.isFinite(dose)||dose<=0||dose>100000||!rx.unit.trim()||rx.unit.length>40||!Number.isInteger(frequency)||frequency<1||frequency>720||!Number.isInteger(quantity)||quantity<1||quantity>10000||!Number.isInteger(days)||days<1||days>365||!['oral','inyectable'].includes(rx.route)||!rx.instructions.trim()||rx.instructions.length>2000||this.lines.length>=30)throw new Error('Revisa medicamento, dosis, unidad, frecuencia, vía, cantidad, duración e indicaciones.');
          this.lines.push({medication_id:rx.medication,dose,dose_unit:rx.unit,frequency_hours:frequency,route:rx.route,quantity,duration_days:days,observations:rx.instructions});
          for(const key of ['medication','dose','unit','interval','quantity','days','instructions'])rx[key]='';
        });
        this.field(form,'Medicamento y concentración',this.rx,'medication','text',medications.map(m=>[m.id,[m.name,m.strength,m.presentation].filter(Boolean).join(' · ')]));
        if(!medications.length)form.append(this.node('p','No hay medicamentos activos publicados.'));
        this.field(form,'Unidad de dosis',this.rx,'unit');
        this.field(form,'Vía',this.rx,'route','text',[['oral','Oral'],['inyectable','Inyectable']]);
        for(const [label,key,type] of [['Dosis','dose','number'],['Cada cuántas horas','interval','number'],['Duración en días','days','number'],['Cantidad total','quantity','number'],['Indicaciones de receta','instructions','textarea']])this.field(form,label,this.rx,key,type);
        finish();
        this.lines.forEach((line,index)=>{
          const medication=medications.find(m=>m.id===line.medication_id);
          const card=this.ui.row(medication?[medication.name,medication.strength].filter(Boolean).join(' · '):'Medicamento no disponible',line.dose+' '+line.dose_unit+' · cada '+line.frequency_hours+' h · '+line.duration_days+' días · '+line.route);
          this.detail(card,'Indicaciones',line.observations);
          this.command(card,'Retirar medicamento',async()=>{this.lines.splice(index,1);});parent.append(card);
        });
        if(this.lines.length)this.command(parent,'Emitir receta autorizada',()=>this.mutation('nativePrescription',{p_encounter:this.encounter.id,p_key:this.keys.rx,p_lines:this.lines.map(l=>({...l}))},'Receta emitida.',()=>{this.keys.rx=root.crypto.randomUUID();this.lines=[];}),true);
      } else parent.append(this.ui.row('Emisión de recetas','Selecciona e inicia una consulta asignada para emitir recetas.'));
      parent.append(this.node('h2','Recetas de mis consultas de este paciente','section-title'));
      for(const rx of this.context?.prescriptions||[]){
        const card=this.ui.row(rx.code,dateTime(rx.issued_at),rx.status==='pendiente'?'Pendiente de entrega':rx.status);
        for(const line of rx.lines||[])card.append(this.node('p',line));parent.append(card);
      }
    }
  }
  root.HospitalModules = HospitalModules;
})(typeof globalThis !== 'undefined' ? globalThis : this);
