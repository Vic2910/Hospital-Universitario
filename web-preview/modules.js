(function (root) {
  'use strict';
  const labels = {pending:'Pendiente',scheduled:'Programada',confirmed:'Programada',checked_in:'Registrado en recepción',in_progress:'En consulta',completed:'Finalizada',cancelled:'Cancelada',rejected:'Rechazada',open:'Abierta',closed:'Cerrada',issued:'Emitida',draft:'Borrador',ordered:'Emitida',released:'Publicado',unread:'No leída',read:'Leída',no_show:'No atendida',active:'Vigente',expired:'Tratamiento finalizado'};
  const clinical = () => root.HospitalCore.doctorClinical;
  const localDay = date => new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
  const dateTime = value => value && Number.isFinite(new Date(value).getTime()) ? new Intl.DateTimeFormat('es-GT',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'No registrado';
  class HospitalModules {
    constructor(api, ui) { this.api = api; this.ui = ui; this.clear(); }
    clear() {
      this.alertGeneration=(this.alertGeneration||0)+1; this.alerts=[];this.unreadAlerts=0;this.alertsHaveMore=false;this.alertsError=null;this.alertLoading=false;
      this.identity = ''; this.role = ''; this.facility = null; this.access = null; this.screen = '';
      this.data = null; this.workspace = null; this.chart = null; this.context = null; this.selected = '';
      this.patientDirectory=[];this.directoryPage=null;this.directoryQuery='';this.directoryError=null;this.selectedPatient=null;this.lastDirectoryQuery=null;clearTimeout(this.searchTimer);
      this.patientLabs=[];this.patientLabPage=null;this.patientLabsError=null;this.patientStays=null;this.patientStaysError=null;this.recordOpen=false;
      this.labTests=[];this.labCatalogError=null;this.labQuery='';this.labCategory='all';this.labSelected=new Set();this.labReview=false;this.pendingLabs=null;this.labPendingNames=[];this.labPendingPatient=null;
      this.ownLabOrders=[];this.ownLabPage=null;this.ownLabsError=null;
      this.admissions=[];this.admissionsPage=null;this.admissionsError=null;this.admissionForm=false;this.admissionReview=false;
      this.admission={category:'',priority:'normal',reason:'',observations:''};this.pendingAdmission=null;this.pendingAdmissionPatient=null;
      this.items = []; this.lines = []; this.documents = new Map(); this.filters = {from:'',to:'',query:''};
      this.day = localDay(new Date()); this.request = {specialty:'',reason:'',period:'manana',day:this.day,from:'08:00',to:'12:00'};
      this.consultation = {subjective:'',objective:'',assessment:'',plan:'',diagnosis_code:''}; this.vitals={}; this.stateFilter='pending'; this.seedDraft = true;
      this.savedNote=null;this.saveState='idle';this.saveError='';this.conflict=null;this.panel='';this.finishConfirm=false;this.leaveConfirm=false;this.medicationQuery='';this.rxReview=false;
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
    async loadAlerts(more=false) {
      if(this.role!=='doctor'||this.alertLoading)return;
      const generation=this.alertGeneration;this.alertLoading=true;
      try {
        const page=await this.api.doctorRPC('alerts',{p_offset:more?this.alerts.length:0});
        if(generation!==this.alertGeneration)return;
        if(!Array.isArray(page.items))throw new Error('Respuesta de avisos inválida.');
        this.alerts=more?[...this.alerts,...page.items]:page.items;this.unreadAlerts=page.unread;this.alertsHaveMore=page.has_more;this.alertsError=null;
      } catch { if(generation===this.alertGeneration)this.alertsError='No se pudieron actualizar los avisos. Reintenta.'; }
      finally { if(generation===this.alertGeneration)this.alertLoading=false; }
    }
    async load(page, more = false) {
      if (!this.facility) throw new Error('No hay una sede autorizada.');
      if(this.role==='doctor'){await this.loadAlerts(page==='notifications'&&more);if(page==='notifications'){this.screen=page;return;}}
      if(this.role==='doctor'&&page==='admissions'){
        this.screen=page;await this.loadAdmissions(more);
        if(this.admissionForm&&!this.directoryPage)await this.loadPatients();
        return;
      }
      if (page === 'consultation' && this.screen !== page && !this.selected) this.day = clinical().todayKey();
      if (this.screen !== page) { this.screen = page; this.data = null; this.items = []; this.filters = {from:'',to:'',query:''}; }
      if (page === 'home' && this.role === 'doctor') this.day = clinical().todayKey();
      if (this.role === 'doctor' && !['profile','notifications'].includes(page)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(this.day)) throw new Error('Selecciona una fecha de atención válida.');
        // Día elegido y los 13 siguientes en hora de El Salvador (máximo del servidor: 32 días).
        // Desde 2 días antes (consultas en atención o finalizadas tarde) hasta los 14 siguientes; máximo del servidor: 32.
        const window = clinical().dayWindow(clinical().addDays(this.day,-clinical().lookbackDays),clinical().agendaDays+clinical().lookbackDays);
        this.workspace = await this.api.operation('workspace',{p_facility:this.facility,p_from:window.from,p_to:window.to});
        if (!Array.isArray(this.workspace.appointments) || !Array.isArray(this.workspace.orders)) throw new Error('Respuesta de agenda inválida.');
        if (this.selected && !this.workspace.appointments.some(item => item.id === this.selected)) {const patient=this.selectedPatient;this.select('');this.selectedPatient=patient;}
        if(['patients','chart','laboratory'].includes(page)){
          if(!(['patients','chart'].includes(page)&&this.selectedPatient))await this.loadPatients();
          if(!this.selectedPatient&&this.appointment){const a=this.appointment;this.selectedPatient=this.patientDirectory.find(p=>p.id===a.patient_id)||{id:a.patient_id,full_name:a.patient_name,record_number:a.record_number,phone:a.phone,age:a.age,active_encounter_id:a.encounter_id};}
        }
        if ((this.appointment||this.selectedPatient) && ['patients','consultation','chart','laboratory','prescriptions'].includes(page)) await this.loadChart();
        if(page==='laboratory'){await this.loadLabCatalog();await this.loadOwnLabs();if(this.selectedPatient)await this.loadPatientLabs();}
        if(['patients','chart'].includes(page)&&this.selectedPatient)await this.loadPatientLabs();
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
      this.selectedPatient=null;this.patientLabs=[];this.patientLabPage=null;this.patientLabsError=null;this.patientStays=null;this.patientStaysError=null;this.recordOpen=false;
      this.recordHistory=false;this.recordVisit='';this.recordLimit=10;this.stopRecordRefresh?.();
      this.consultation = {subjective:'',objective:'',assessment:'',plan:'',diagnosis_code:''}; this.vitals={};
      this.savedNote=null;this.saveState='idle';this.saveError='';this.conflict=null;this.panel='';this.finishConfirm=false;this.leaveConfirm=false;this.medicationQuery='';this.rxReview=false;
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
        this.savedNote=encounter?this.snapshot():null;
        // Primera apertura: precarga lo que el paciente ya envió; queda como cambio pendiente hasta guardar.
        // Los síntomas que envió el paciente se muestran aparte, de solo lectura; no se copian a la nota médica.
      }
    }
    async loadPatients(more=false) {
      if(this.directoryQuery.trim().length>120)throw new Error('La búsqueda admite hasta 120 caracteres.');
      this.directoryError=null;
      try{
        if(!more)this.lastDirectoryQuery=this.directoryQuery.trim();
        const page=await this.api.doctorRPC('patients',{p_query:this.directoryQuery.trim(),p_offset:more?this.directoryPage?.next_offset||0:0});
        if(!Array.isArray(page.patients))throw new Error('No se pudo interpretar el directorio.');
        this.patientDirectory=more?[...this.patientDirectory,...page.patients]:page.patients;this.directoryPage=page;
      }catch(error){this.patientDirectory=[];this.directoryPage=null;this.directoryError=error.message;if([401,403].includes(error.status))throw error;}
    }
    // Hospitalizaciones del paciente para el expediente médico (doctor_native_patient_hospitalizations: exige relación asistencial).
    async loadPatientStays() {
      const patient=this.selectedPatient?.id||this.appointment?.patient_id;if(!patient)return;
      this.patientStaysError=null;
      try{this.patientStays=root.HospitalCore.hospitalizations.present(await this.api.doctorRPC('patient_hospitalizations',{p_patient:patient}));}
      catch(error){this.patientStays=null;this.patientStaysError=/PGRST202|404|patient_hospitalizations/.test(String(error.message)+error.status)?'Consulta de hospitalizaciones pendiente de migración en el servidor.':error.message;}
    }
    async loadPatientLabs(more=false) {
      const patient=this.selectedPatient?.id||this.appointment?.patient_id;if(!patient)return;
      if(!more)await this.loadPatientStays();
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
      await this.loadChart();if(['laboratory','patients','chart'].includes(this.screen))await this.loadPatientLabs();
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
      try { await this.api.operation(name,parameters); }
      catch (error) { const hint = name === 'startConsultation' ? clinical().startError(error.detail || '') : null; if (hint) throw new Error(hint); throw error; }
      if (after) after();
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
      if(this.role==='doctor'&&page==='notifications'){this.renderNotifications(parent,this.alerts);return;}
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
      if(['patients','chart'].includes(page)) {this.recordsView(parent);return;}
      if(page==='laboratory') {this.directoryView(parent,true);return;}
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
          const card = this.ui.row(item.patient_name,item.record_number+' · '+this.ui.period(item.period),clinical().statusLabel(item.status));
          for (const [id,label] of [['consultation','Atender'],['chart','Expediente']]) card.append(this.ui.button(label,() => { this.select(item.id); this.ui.go(id); },'module-action')); parent.append(card);
        }
        if (page === 'patients') this.ui.doctorPatientHistory(parent,this);
        return;
      }
      if (page === 'consultation') {
        if(!this.appointment)this.ui.doctorConsultations(parent,this);
        else this.consultationForm(parent);
        return;
      }
      if (page === 'notifications') { this.renderNotifications(parent,workspace.notifications); return; }
      if (page === 'prescriptions') { const hero=this.node('header',null,'directory-hero'); hero.append(this.node('small','RECETAS'),this.node('h2','Receta médica'),this.node('p','Elige el paciente de tu agenda; la receta se emite dentro de su consulta abierta.')); parent.append(hero); }
      const picker=this.node('section',null,'rx-patient-card');parent.append(picker);this.stepHead(picker,'','Paciente','Pacientes de tu agenda para la fecha elegida.','body');this.patientPicker(picker);
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
      if(!this.admissionForm){const open=this.command(wrap,'Nueva solicitud',async()=>{this.admissionForm=true;this.admissionReview=false;this.directoryQuery='';},true);open.className+=' admission-new';}
      else{
        const box=this.node('section',null,'admission-form-card admission-steps');box.append(this.node('h2','Nueva solicitud de ingreso'));
        if(this.pendingAdmission)box.append(this.node('p','Envío sin confirmar. Reintenta la misma solicitud para evitar duplicados.','auth-notice'));
        const patient=(this.pendingAdmission&&this.pendingAdmissionPatient)||this.selectedPatient||this.appointment;
        const fields=this.node('fieldset');fields.disabled=!!this.pendingAdmission||this.ui.busy()||this.admissionReview;
        // Paso 1 (paridad con DoctorModuleView.admissionPatientStep): sin texto no se muestra ningún listado.
        const step1=this.block(fields,'1','Paciente a hospitalizar','Busca por nombre, apellido o DUI entre tus pacientes autorizados.','body');
        if(patient){
          const chosen=this.node('div',null,'admission-patient');const info=this.node('div');
          info.append(this.node('strong',patient.full_name||patient.patient_name),this.node('small','Expediente '+(patient.record_number||'no disponible')+(patient.dui?' · DUI '+patient.dui:'')));
          chosen.append(this.node('span',this.initials(patient.full_name||patient.patient_name),'directory-avatar'),info,this.ui.button('Cambiar paciente',()=>{this.select('');this.directoryQuery='';this.ui.repaint();},'text-button'));step1.append(chosen);
        }else{
          const search=this.node('form',null,'record-search');search.setAttribute('role','search');
          const input=this.node('input');input.type='search';input.value=this.directoryQuery||'';input.maxLength=120;input.placeholder='Nombre, apellido o DUI';input.autocomplete='off';input.setAttribute('aria-label','Buscar paciente para hospitalizar');
          search.append(this.node('span','⌕','record-search-icon'),input);step1.append(search);
          const results=this.node('div',null,'record-results');step1.append(results);
          const paint=()=>{
            results.replaceChildren();const q=(this.directoryQuery||'').trim();
            if(q.length<2){results.append(this.node('p','Escribe al menos 2 letras del nombre, apellido o DUI para buscar.','scope-note'));return;}
            if(this.directoryLoading||this.lastDirectoryQuery!==q){results.append(this.node('p','Buscando pacientes…','scope-note'));return;}
            if(this.directoryError){results.append(this.ui.row('No se pudo cargar el directorio',this.directoryError));return;}
            if(!this.patientDirectory.length){results.append(this.node('p','Ningún paciente autorizado coincide con «'+q+'».','scope-note'));return;}
            for(const p of this.patientDirectory){
              const button=this.ui.button(null,()=>this.ui.run(()=>this.openPatient(p)),'record-result');button.setAttribute('aria-label','Seleccionar paciente '+p.full_name);
              const text=this.node('div',null,'record-result-text');text.append(this.node('strong',p.full_name),this.node('small',[p.record_number?'Exp. '+p.record_number:'Sin expediente',p.dui?'DUI '+p.dui:'',p.age!=null?p.age+' años':''].filter(Boolean).join(' · ')));
              button.append(this.node('span',this.initials(p.full_name),'directory-avatar'),text,this.node('span','+','directory-chevron'));results.append(button);
            }
            if(this.directoryPage?.has_more)results.append(this.ui.button('Cargar más pacientes',()=>this.ui.run(()=>this.loadPatients(true)),'module-action'));
          };
          const find=async()=>{const q=(this.directoryQuery||'').trim();if(q.length<2||q===this.lastDirectoryQuery){paint();return;}
            this.directoryLoading=true;paint();try{await this.loadPatients();}catch(error){this.directoryError=error.message;}this.directoryLoading=false;if((this.directoryQuery||'').trim()===q)paint();};
          input.addEventListener('input',()=>{this.directoryQuery=input.value;clearTimeout(this.searchTimer);paint();this.searchTimer=setTimeout(find,this.searchDelay??350);});
          search.addEventListener('submit',event=>{event.preventDefault();clearTimeout(this.searchTimer);find();});
          paint();
        }
        const step2=this.block(fields,'2','Cuidado requerido','La categoría no garantiza disponibilidad ni reserva habitación.','grid');
        this.field(step2,'Categoría de habitación',this.admission,'category','text',(this.admissionsPage?.categories||[]).map(c=>[c,category(c)]));
        if(!this.admissionsPage?.categories.length)step2.append(this.node('p','No hay categorías disponibles en el catálogo. Actualiza o contacta a recepción.','scope-note'));
        this.field(step2,'Prioridad',this.admission,'priority','text',(this.admissionsPage?.priorities||[]).map(p=>[p,p==='urgente'?'Urgente':p==='normal'?'Normal':p]));
        this.detail(step2,'Médico solicitante',this.admissionsPage?.doctor_name);
        const step3=this.block(fields,'3','Motivo clínico','Recepción lo usará para gestionar la cama.','stethoscope');
        this.field(step3,'Motivo clínico del ingreso',this.admission,'reason','textarea').maxLength=10000;
        this.field(step3,'Observaciones e indicaciones (opcional)',this.admission,'observations','textarea').maxLength=10000;
        box.append(fields);
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
        const card=this.ui.row(item.patient_name,category(item.category)+' · '+(item.priority==='urgente'?'Urgente':'Normal')+' · '+dateTime(item.ordered_at),state(item.decision||item.status));card.className+=' admission-card'+(item.priority==='urgente'?' is-urgent':'');
        const detail=this.node('details',null,'admission-detail');detail.append(this.node('summary','Ver detalle de la solicitud'));
        for(const[label,value]of [['Expediente',item.record_number],['Médico solicitante',item.doctor_name],['Motivo clínico',item.reason],['Observaciones',item.observations],['Respuesta de recepción',item.decision_reason]])if(value)this.detail(detail,label,value);
        if(item.assignment){this.detail(detail,'Habitación y cama',item.assignment.room+' · '+item.assignment.bed+' · '+item.assignment.floor);this.detail(detail,'Asignación confirmada',dateTime(item.assignment.assigned_at));}
        else detail.append(this.node('p','Recepción aún no ha confirmado habitación ni cama.'));
        for(const event of item.history||[])detail.append(this.node('p',state(event.decision||event.status)+' · '+dateTime(event.at),'admission-event'));
        card.append(detail);wrap.append(card);
      }
      if(this.admissionsPage?.has_more)this.command(wrap,'Cargar más solicitudes',()=>this.loadAdmissions(true));parent.append(wrap);
    }
    // Expedientes del médico (paridad con DoctorRecordsView.swift): búsqueda con espera breve, expediente sin datos repetidos
    // e historial de consultas finalizadas. La autorización la decide el servidor (treats_patient y e.doctor_id).
    recordsView(parent) {
      const wrap=this.node('section',null,'doctor-records');parent.append(wrap);
      const real=value=>value!=null&&String(value).trim()!=='';
      if(!this.selectedPatient&&this.appointment){const a=this.appointment;this.selectedPatient=this.patientDirectory.find(p=>p.id===a.patient_id)||{id:a.patient_id,full_name:a.patient_name,record_number:a.record_number,phone:a.phone,age:a.age,active_encounter_id:a.encounter_id};}
      const patient=this.selectedPatient;
      if(!patient){
        const hero=this.node('header',null,'directory-hero');
        hero.append(this.node('small','EXPEDIENTES'),this.node('h2','Encuentra un expediente al instante'),this.node('p','Busca por nombre, apellido, DUI, código de paciente o de expediente. Solo aparecen pacientes que tienes autorización para atender.'));
        wrap.append(hero);
        const form=this.node('form',null,'record-search');form.setAttribute('role','search');
        const input=this.node('input');input.type='search';input.value=this.directoryQuery||'';input.maxLength=120;input.placeholder='Nombre, apellido, DUI o código';input.setAttribute('aria-label','Buscar expediente');input.autocomplete='off';
        const status=this.node('span',null,'record-search-status');status.setAttribute('aria-live','polite');
        form.append(this.node('span','⌕','record-search-icon'),input,status);wrap.append(form);
        const results=this.node('div',null,'record-results');wrap.append(results);
        const paint=()=>{
          results.replaceChildren();
          const query=(this.directoryQuery||'').trim();
          status.textContent=this.directoryLoading?'Buscando…':'';
          if(this.directoryError){results.append(this.ui.row('No se pudo cargar el directorio',this.directoryError));results.append(this.ui.button('Reintentar búsqueda',()=>search(true),'module-action'));return;}
          if(this.directoryPage)results.append(this.node('p',query?this.directoryPage.total+' '+(this.directoryPage.total===1?'resultado':'resultados')+' para «'+query+'»':'Tus pacientes autorizados · '+this.directoryPage.total,'record-count'));
          if(this.directoryPage&&!this.patientDirectory.length){const empty=this.node('article',null,'record-empty');empty.append(this.node('span','🔍','record-empty-icon'),this.node('strong','Sin coincidencias'),this.node('p',query?'Ningún paciente autorizado coincide con la búsqueda. Revisa el nombre, el DUI o el código.':'Todavía no tienes pacientes asignados.','sched-hint'));results.append(empty);}
          for(const item of this.patientDirectory){
            const card=this.ui.button(null,()=>this.ui.run(()=>this.openPatient(item)),'record-result');card.setAttribute('aria-label','Abrir expediente de '+item.full_name);
            const text=this.node('div',null,'record-result-text');text.append(this.node('strong',item.full_name));
            const chips=this.node('div',null,'record-chips');
            for(const [show,label] of [[item.patient_code,'Código '+item.patient_code],[item.record_number,'Exp. '+item.record_number],[item.dui,'DUI '+item.dui],[item.age!=null?String(item.age):'',item.age+' años']])if(real(show))chips.append(this.node('span',label,'record-chip'));
            const states=this.node('div',null,'record-chips');states.append(this.node('span',item.record_number?'✓ Expediente activo':'Sin expediente vinculado','record-state'+(item.record_number?' is-ok':' is-warn')));
            if(item.active_encounter_id)states.append(this.node('span','En consulta','record-state is-ok'));
            text.append(chips,states);card.append(this.node('span',this.initials(item.full_name),'directory-avatar'),text,this.node('span','›','directory-chevron'));results.append(card);
          }
          if(this.directoryPage?.has_more)results.append(this.ui.button('Cargar más resultados',()=>this.ui.run(()=>this.loadPatients(true)),'module-action'));
        };
        // Espera breve; no repite la misma consulta; actualiza solo los resultados para no perder el foco del buscador.
        const search=async force=>{
          const query=(this.directoryQuery||'').trim();
          if(!force&&query===this.lastDirectoryQuery)return;
          this.directoryLoading=true;paint();
          try{await this.loadPatients();}catch(error){this.directoryError=error.message;}
          this.directoryLoading=false;if((this.directoryQuery||'').trim()===query)paint();
        };
        input.addEventListener('input',()=>{this.directoryQuery=input.value;clearTimeout(this.searchTimer);this.searchTimer=setTimeout(()=>search(false),this.searchDelay??350);});
        form.addEventListener('submit',event=>{event.preventDefault();clearTimeout(this.searchTimer);search(true);});
        paint();return;
      }
      wrap.append(this.ui.button('← Volver a la búsqueda',()=>{this.stopRecordRefresh();this.select('');this.ui.repaint();},'text-button'));
      const chart=this.chart?.patient?.id===patient.id?this.chart:null,p=chart?.patient||{};
      const header=this.node('article',null,'record-header');
      const top=this.node('div',null,'record-header-top'),name=this.node('div');
      name.append(this.node('small','EXPEDIENTE CLÍNICO','consultation-kicker'),this.node('h2',p.full_name||patient.full_name));
      top.append(this.node('span',this.initials(patient.full_name),'consult-avatar'),name);header.append(top);
      const pills=this.node('div',null,'consultation-pills'),code=p.patient_code||patient.patient_code,record=p.record_number||patient.record_number;
      if(real(code))pills.append(this.node('span','Código '+code,'consultation-pill'));
      pills.append(this.node('span',record?'Expediente '+record:'Sin expediente','consultation-pill'));
      if(patient.age!=null)pills.append(this.node('span',patient.age+' años','consultation-pill'));
      if(patient.active_encounter_id)pills.append(this.node('span','En consulta','consultation-pill'));
      header.append(pills);
      const birth=p.birth_date||patient.birth_date,rows=[['Fecha de nacimiento',real(birth)?new Intl.DateTimeFormat('es-SV',{dateStyle:'long',timeZone:'UTC'}).format(new Date(String(birth).slice(0,10)+'T00:00:00Z')):''],['DUI',p.identification||patient.dui],['Teléfono',p.phone||patient.phone],['Correo',p.email||patient.email],['Ciudad',p.address]];
      const grid=this.node('div',null,'record-header-grid');let cells=0;for(const [label,value] of rows)if(real(value)){const cell=this.node('div');cell.append(this.node('small',label),this.node('strong',String(value)));grid.append(cell);cells++;}
      if(cells)header.append(grid);
      wrap.append(header);
      if(!chart){wrap.append(this.node('p',this.ui.busy()?'Cargando expediente…':'No se pudo cargar el expediente.','scope-note'));if(!this.ui.busy())this.command(wrap,'Reintentar',()=>this.loadChart());return;}
      // Información clínica: alergias y condiciones no se repiten en "Otros antecedentes".
      const summary=this.node('section',null,'consultation-section clinical-card');wrap.append(summary);
      const head=this.node('div',null,'consultation-block-head');const icon=this.node('span','✚','consultation-block-icon');const title=this.node('div');title.append(this.node('h3','Información clínica','clinical-section-title'),this.node('p','Antecedentes registrados en el expediente','scope-note'));head.append(icon,title);summary.append(head);
      const grouped=['alergia','alergias','condicion','enfermedad'],others=(chart.medical_history||[]).filter(entry=>!grouped.includes(String(entry).split(':')[0].trim().toLowerCase()));
      const groups=[['Grupo sanguíneo',real(chart.blood_type)?[chart.blood_type]:[]],['Alergias',chart.allergies||[]],['Condiciones',chart.conditions||[]],['Otros antecedentes',others],['Medicamentos registrados',chart.medications||[]]].filter(([,values])=>values.length);
      if(!groups.length)summary.append(this.node('p','Sin antecedentes clínicos registrados.','scope-note'));
      for(const [label,values] of groups)this.detail(summary,label,values.join('\n'));
      // Hospitalización (mismo episodio que ve el paciente en Habitaciones).
      const stays=this.node('section',null,'consultation-section clinical-card record-stays');wrap.append(stays);
      stays.append(this.node('h3','Hospitalización','clinical-section-title'));
      if(this.patientStaysError)stays.append(this.node('p',this.patientStaysError,'scope-note'));
      else if(!this.patientStays)stays.append(this.node('p','Cargando hospitalizaciones…','scope-note'));
      else{
        const S=this.patientStays,list=[S.active,...S.previous].filter(Boolean);
        if(!list.length)stays.append(this.node('p','Sin hospitalizaciones registradas.','scope-note'));
        for(const e of list){
          const line=[e.room?'Habitación '+e.room:'Habitación por confirmar',e.room_kind].filter(Boolean).join(' · ');
          const when='Ingreso: '+[e.admitted_date,e.admitted_time].filter(Boolean).join(' · ')+(e.discharged_date?' · Alta: '+[e.discharged_date,e.discharged_time].filter(Boolean).join(' · '):'');
          stays.append(this.ui.row(line,[when,e.doctor?'Responsable: '+e.doctor:null,e.reason?'Motivo: '+e.reason:null].filter(Boolean).join(' · '),e.status_label));
        }
      }
      const actions=this.node('div',null,'record-actions');
      if(patient.active_encounter_id)actions.append(this.ui.button('Continuar consulta',()=>this.ui.go('consultation'),'module-action'));
      actions.append(this.ui.button('Laboratorios',()=>this.ui.go('laboratory'),'module-action'),this.ui.button('Solicitar ingreso',()=>{this.admissionForm=true;this.ui.go('admissions');},'module-action'));
      wrap.append(actions);
      const entries=(chart.history||[]).filter(e=>e.status==='closed').sort((a,b)=>(Date.parse(b.started_at)||0)-(Date.parse(a.started_at)||0)||String(b.id).localeCompare(String(a.id)));
      const toggle=this.ui.button((this.recordHistory?'OCULTAR HISTORIAL MÉDICO':'VER HISTORIAL MÉDICO'),()=>{this.recordHistory=!this.recordHistory;this.recordVisit='';this.ui.repaint();},'primary record-history-toggle');
      toggle.setAttribute('aria-expanded',String(!!this.recordHistory));wrap.append(toggle,this.node('p',entries.length?entries.length+' '+(entries.length===1?'consulta finalizada':'consultas finalizadas'):'Sin consultas finalizadas','record-count'));
      this.startRecordRefresh(patient.id);
      if(!this.recordHistory)return;
      const zone=clinical().zone,day=v=>new Intl.DateTimeFormat('es-SV',{dateStyle:'full',timeZone:zone}).format(new Date(v)),hour=v=>new Intl.DateTimeFormat('es-SV',{timeStyle:'short',timeZone:zone}).format(new Date(v));
      const doctor=e=>e.doctor_name||this.workspace?.doctor_name||'Médico responsable';
      const visit=entries.find(e=>e.id===this.recordVisit);
      if(visit){
        const box=this.node('section',null,'record-visit');box.setAttribute('role','region');box.setAttribute('aria-label','Detalle de consulta');
        box.append(this.ui.button('← Volver al historial',()=>{this.recordVisit='';this.ui.repaint();},'text-button'));
        const vh=this.node('div',null,'record-visit-head');vh.append(this.node('small','🔒 Finalizada · solo lectura'),this.node('strong',(chart.patient?.full_name?chart.patient.full_name+' · ':'')+day(visit.started_at)+' · '+hour(visit.started_at)+(visit.ended_at?' – '+hour(visit.ended_at)+' · '+Math.max(0,Math.round((Date.parse(visit.ended_at)-Date.parse(visit.started_at))/60000))+' min':'')),this.node('span','🩺 '+doctor(visit)));if(real(visit.specialty))vh.append(this.node('span',visit.specialty));if(real(visit.reason))vh.append(this.node('span','Motivo: '+visit.reason));box.append(vh);
        const reported=(visit.reported_symptoms||[]).filter(real);if(reported.length||real(visit.reported_other)){const g=this.node('div',null,'record-visit-group');g.append(this.node('h3','Síntomas iniciales · reportados por el paciente'));const chips=this.node('div',null,'record-chips');for(const sym of reported)chips.append(this.node('span',sym,'record-chip'));g.append(chips);if(real(visit.reported_other))g.append(this.node('p','Otros: '+visit.reported_other));box.append(g);}
        const vitals=clinical().recordedVitals.filter(v=>real(visit.vitals?.[v.key]));
        if(vitals.length){const g=this.node('div',null,'record-visit-group');g.append(this.node('h3','Datos físicos'));for(const v of vitals)this.detail(g,v.label+' ('+v.unit+')',String(visit.vitals[v.key]));const bmi=clinical().bmi(visit.vitals||{});if(bmi)this.detail(g,'IMC (calculado)',bmi+' kg/m²');box.append(g);}
        const ev=this.node('div',null,'record-visit-group');ev.append(this.node('h3','Evaluación médica'));
        for(const [label,value] of [['Síntomas',visit.subjective],['Diagnóstico',visit.assessment],['Código diagnóstico',visit.diagnosis_code],['Observaciones',visit.objective],['Tratamiento',visit.plan]])if(real(value))this.detail(ev,label,value);box.append(ev);
        const rx=(chart.prescriptions||[]).filter(r=>r.encounter_id===visit.id),unlinked=(chart.prescriptions||[]).length&&(chart.prescriptions||[]).every(r=>!r.encounter_id);
        const rg=this.node('div',null,'record-visit-group');rg.append(this.node('h3','Recetas'));
        if(!rx.length)rg.append(this.node('p',unlinked?'El servidor todavía no indica a qué consulta pertenece cada receta. Puedes verlas en Recetas.':'No se emitieron recetas en esta consulta.','scope-note'));
        for(const r of rx)this.detail(rg,r.code+' · '+(r.status==='pendiente'?'Pendiente de entrega':r.status),(r.lines||[]).join('\n'));box.append(rg);
        const labs=(this.patientLabs||[]).filter(o=>o.encounter_id===visit.id),lg=this.node('div',null,'record-visit-group');lg.append(this.node('h3','Exámenes'));
        if(!labs.length)lg.append(this.node('p','No se solicitaron exámenes en esta consulta.','scope-note'));
        for(const o of labs)this.detail(lg,o.test_name+' · '+(o.published_at?'Resultado publicado':o.status),o.published_at&&real(o.result_summary)?o.result_summary:'Resultado aún no publicado.');
        box.append(lg);wrap.append(box);return;
      }
      const timeline=this.node('section',null,'record-timeline');timeline.setAttribute('aria-label','Historial médico');wrap.append(timeline);
      if(!entries.length){const empty=this.node('article',null,'record-empty');empty.append(this.node('span','📋','record-empty-icon'),this.node('strong','Todavía no hay historial'),this.node('p','Este paciente aún no tiene consultas finalizadas contigo. Las consultas abiertas no aparecen aquí.','sched-hint'));timeline.append(empty);return;}
      const limit=this.recordLimit||10;
      for(const entry of entries.slice(0,limit)){
        const card=this.ui.button(null,()=>{this.recordVisit=entry.id;this.ui.repaint();},'record-entry');card.setAttribute('aria-label','Consulta del '+day(entry.started_at)+' a las '+hour(entry.started_at));
        const top=this.node('div',null,'record-entry-top');top.append(this.node('strong',day(entry.started_at)),this.node('time',hour(entry.started_at)));card.append(top);
        card.append(this.node('small','🩺 '+doctor(entry)+(real(entry.specialty)?' · '+entry.specialty:''),'record-entry-doctor'));
        for(const [label,value] of [['Motivo',entry.reason],['Diagnóstico',entry.assessment],['Observaciones',entry.objective],['Tratamiento',entry.plan]])if(real(value)){const line=this.node('div',null,'record-entry-line');line.append(this.node('span',label),this.node('p',value));card.append(line);}
        timeline.append(card);
      }
      if(entries.length>limit)timeline.append(this.ui.button('Mostrar consultas anteriores ('+(entries.length-limit)+')',()=>{this.recordLimit=limit+10;this.ui.repaint();},'module-action'));
    }
    // Actualización periódica del expediente abierto; se descarta si cambió la selección o la pantalla.
    startRecordRefresh(patient){
      if(this.recordTimerPatient===patient)return;this.stopRecordRefresh();this.recordTimerPatient=patient;
      this.recordTimer=setInterval(async()=>{
        if(this.selectedPatient?.id!==patient||!['patients','chart'].includes(this.screen)||this.ui.busy())return;
        try{const chart=await this.api.operation('patientChart',{p_patient:patient,p_from:null,p_to:null,p_query:''});if(this.selectedPatient?.id===patient){this.context=this.chart=chart;this.ui.repaint();}}catch{/* Se conserva lo mostrado. */}
      },60000);this.recordTimer?.unref?.();
    }
    stopRecordRefresh(){clearInterval(this.recordTimer);this.recordTimer=null;this.recordTimerPatient=null;}
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
      const heading=this.node('article',null,'doctor-alert-heading');
      heading.append(this.node('span','🔔','doctor-alert-symbol'),this.node('h2','Tu centro de avisos'),this.node('p',this.unreadAlerts+' sin leer · Citas y novedades del hospital'));
      parent.append(heading,this.node('p','Recordatorio 15 minutos antes. Los avisos se actualizan mientras la vista está abierta.','scope-note'));
      if(this.alertsError)parent.append(this.node('p',this.alertsError,'scope-note'));
      this.command(parent,'Actualizar avisos',()=>this.loadAlerts());
      const items = [...notifications].sort((a,b)=>b.created_at.localeCompare(a.created_at)).filter(item => this.matches(item.title+' '+item.body,this.search));
      if (!items.length) parent.append(this.ui.row('Sin notificaciones','No hay avisos recientes.'));
      for (const item of items) {
        const card = this.ui.row(item.title,item.body,item.read_at ? 'Leída' : 'No leída');card.className+=' doctor-alert-card'+(item.read_at?'':' is-unread'); card.append(this.node('p',dateTime(item.created_at)));
        if (!item.read_at) this.command(card,'Marcar como leída',() => this.mutation('updateItem',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version},'Notificación leída.')); parent.append(card);
      }
      if(this.alertsHaveMore)this.command(parent,'Cargar más avisos',()=>this.loadAlerts(true));
    }
    // Flujo de consulta (paridad con DoctorModuleView.swift): detalle → apertura → bloques A–C → guardado → finalización.
    snapshot(){const vitals=Object.fromEntries(Object.entries(this.vitals).filter(([,v])=>String(v??'').trim()!=='').sort(([a],[b])=>a.localeCompare(b)));return JSON.stringify({...this.consultation,vitals});}
    get pendingChanges(){return this.savedNote!==null&&this.snapshot()!==this.savedNote;}
    finishBlockers(){
      const values=clinical().missingSections(this.consultation).map(name=>'Completa: '+name);
      if(Object.keys(clinical().vitalIssues(this.vitals)).length)values.push('Corrige los datos físicos marcados');
      if(this.lines.length)values.push('Emite o retira los medicamentos de la receta en preparación');
      if(this.conflict)values.push('Resuelve la diferencia con la versión guardada');
      return values;
    }
    // doctor_native_save con control de versión. Ante un error lo escrito permanece; ante un conflicto se muestra la versión real.
    async saveNote(){
      const encounter=this.encounter;
      if(!encounter||encounter.status!=='open')throw new Error('La consulta no está abierta para edición.');
      if(this.conflict)throw new Error('Resuelve primero la diferencia con la versión guardada.');
      if(!Object.values(this.consultation).every(v=>v.length<=10000)||this.consultation.diagnosis_code.length>50){this.saveState='failed';throw new Error('Cada sección admite hasta 10 000 caracteres y el código hasta 50.');}
      const issue=Object.values(clinical().vitalIssues(this.vitals))[0];
      if(issue){this.saveState='failed';throw new Error('Revisa los datos físicos: '+issue);}
      const vitals=Object.fromEntries(Object.entries(this.vitals).filter(([,v])=>String(v??'').trim()!==''));
      this.saveState='saving';
      try{await this.api.operation('saveConsultation',{p_encounter:encounter.id,p_values:{...this.consultation,vitals},p_expected_version:this.noteVersion,p_request_key:this.keys.save});}
      catch(error){
        this.saveState='failed';
        if(error.code==='40001'){
          const patient=this.selectedPatient?.id||this.appointment?.patient_id;
          this.context=this.chart=await this.api.operation('patientChart',{p_patient:patient,p_from:null,p_to:null,p_query:''});
          this.conflict=this.encounter||null;
          throw new Error('Otra sesión guardó esta consulta. Revisa la versión guardada antes de sobrescribirla.');
        }
        throw error;
      }
      this.keys.save=root.crypto.randomUUID();this.seedDraft=true;this.saveState='saved';
      try{await this.load(this.screen);}catch{throw new Error('Consulta guardada. No se pudo recargar; usa Actualizar.');}
      this.ui.message('Consulta guardada correctamente.');
    }
    async resolveConflict(keepMine){
      const server=this.conflict;if(!server)return;
      this.conflict=null;this.noteID=server.note_id||null;this.noteVersion=server.note_version??0;
      const mine={consultation:{...this.consultation},vitals:{...this.vitals}};
      for(const key of Object.keys(this.consultation))this.consultation[key]=server[key]||'';
      this.vitals={...(server.vitals||{})};this.savedNote=this.snapshot();
      if(keepMine){this.consultation=mine.consultation;this.vitals=mine.vitals;await this.saveNote();}
      else this.saveState='idle';
    }
    // Guarda los cambios pendientes y después ejecuta doctor_native_finish con la versión recién guardada.
    async finishConsultation(){
      const blockers=this.finishBlockers();
      if(blockers.length){this.finishConfirm=false;throw new Error(blockers.join('. ')+'.');}
      // Finalizar guarda primero; si el guardado falla no se cierra y se explica.
      try{await this.saveNote();}catch(error){if(this.conflict)throw error;throw new Error('No se ha guardado la consulta. Guarda los cambios antes de finalizar la atención.');}
      const saved=this.encounter;
      if(!saved?.note_id||saved.status!=='open')throw new Error('Actualiza la consulta antes de finalizar.');
      // Hasta aplicar supabase/doctor-consultation-six-fields.sql el servidor exige `plan`; se informa sin cerrar ni perder datos.
      try{await this.api.operation('closeConsultation',{p_encounter:saved.id,p_note:saved.note_id,p_note_version:saved.note_version,p_expected_version:saved.row_version});}
      catch(error){const message=clinical().finishError(error.detail||'',this.consultation);if(message===(error.detail||''))throw error;throw new Error(message);}
      this.select('');
      try{await this.load('consultation');}catch{/* La consulta ya quedó finalizada; la agenda se recarga con Actualizar. */}
      this.ui.message('Consulta finalizada. La información quedó registrada en el expediente del paciente.');
    }
    consultationForm(parent) {
      const appointment=this.appointment;if(!appointment)return;
      const open=this.encounter?.status==='open';
      const back=this.ui.button('← Volver a la agenda',()=>{if(open&&this.pendingChanges){this.leaveConfirm=true;this.ui.repaint();}else{this.select('');this.ui.repaint();}},'text-button');
      parent.append(back);
      if(this.leaveConfirm){
        const box=this.node('section',null,'consultation-leave');box.setAttribute('role','alertdialog');box.setAttribute('aria-label','Tienes cambios sin guardar');
        box.append(this.node('h3','Tienes cambios sin guardar'),this.node('p','Lo escrito desde el último guardado se perderá si sales sin guardar.'));
        this.command(box,'Guardar y volver a la agenda',async()=>{this.leaveConfirm=false;await this.saveNote();this.select('');},true);
        box.append(this.ui.button('Salir sin guardar',()=>{this.leaveConfirm=false;this.select('');this.ui.repaint();},'module-action'),this.ui.button('Seguir en la consulta',()=>{this.leaveConfirm=false;this.ui.repaint();},'text-button'));
        parent.append(box);
      }
      this.patientHero(parent,appointment);
      if(!appointment.encounter_id){
        this.consultationInfo(parent,appointment,null);
        const reported=this.block(parent,'','Síntomas reportados','Podrás revisarlos y precisarlos al abrir la consulta.','list');
        this.reportedSymptoms(reported,appointment);
        const blocker=clinical().openingBlocker(appointment);
        const start=this.command(parent,'ABRIR CONSULTA MÉDICA',()=>this.mutation('startConsultation',{p_appointment:this.selected,p_request_key:this.keys.start},'Consulta abierta. Estado: En consulta.',()=>{this.keys.start=root.crypto.randomUUID();this.seedDraft=true;}),true);
        start.className+=' consultation-open';start.disabled||=!!blocker;
        if(blocker)parent.append(this.node('p',blocker,'auth-notice'));
        return;
      }
      const encounter=this.encounter;
      if(!encounter){parent.append(this.ui.row('Consulta no cargada','Actualiza para continuar; lo escrito no se envía hasta guardar.'));this.command(parent,'Actualizar consulta',()=>this.loadChart());return;}
      if(encounter.status!=='open'){
        const done=this.node('article',null,'consultation-done');done.append(this.node('h3','✓ Consulta finalizada'),this.node('p','La información quedó registrada en el expediente y en el historial del paciente. Ya no puede editarse desde la app.'));
        parent.append(done);this.consultationRecord(parent,encounter);return;
      }
      if(this.panel){this.clinicalPanel(parent,appointment);return;}
      const editor=this.node('div',null,'consultation-editor');parent.append(editor);
      const status=this.node('div',null,'consultation-save-state');status.setAttribute('role','status');
      const statusText=this.node('span');status.append(statusText);
      const refreshStatus=()=>{statusText.textContent=this.saveState==='saving'?'Guardando…':this.saveState==='failed'?'Error al guardar · Lo escrito sigue en pantalla.':this.pendingChanges?'Cambios pendientes de guardar':this.saveState==='saved'?'Guardado correctamente':'Sin cambios pendientes';status.setAttribute('data-state',this.pendingChanges&&this.saveState!=='failed'?'pending':this.saveState);};
      refreshStatus();this.command(status,'Guardar avances',()=>this.saveNote());editor.append(status);
      editor.addEventListener('input',refreshStatus);
      if(this.conflict){
        const box=this.node('section',null,'consultation-conflict');box.append(this.node('h3','Otra sesión guardó esta consulta'),this.node('p','Esta es la versión guardada en el expediente. Elige cuál conservar; nada se sobrescribe sin tu confirmación.'));
        for(const [key,label] of [['subjective','Síntomas guardados'],['assessment','Diagnóstico guardado'],['objective','Observaciones guardadas']])this.detail(box,label,this.conflict[key]||'Sin registrar');
        this.command(box,'Usar la versión guardada',()=>this.resolveConflict(false));this.command(box,'Conservar lo que escribí y guardar',()=>this.resolveConflict(true),true);editor.append(box);
      }
      this.consultationInfo(editor,appointment,encounter);
      const history=this.node('details',null,'consultation-history clinical-card');history.append(this.node('summary','Expediente e historial previo'));this.chartView(history);editor.append(history);
      // A. Datos físicos: peso, altura y temperatura (public.vital_signs, rangos de doctor_native_save).
      // Las medidas antiguas que ya no se capturan siguen en this.vitals y se reenvían sin cambios.
      const measures=this.block(editor,'A','Datos físicos','Registra solo lo que midas; los campos vacíos no se guardan.','body');
      const grid=this.node('div',null,'consultation-measures');measures.append(grid);
      const bmi=this.node('p',null,'consultation-bmi');bmi.setAttribute('aria-live','polite');
      const issues={};
      const paintIssues=()=>{const found=clinical().vitalIssues(this.vitals);for(const v of clinical().vitals){issues[v.key].textContent=found[v.key]||this.range(v);issues[v.key].setAttribute('data-state',found[v.key]?'error':'hint');}const value=clinical().bmi(this.vitals);bmi.textContent=value?'IMC calculado: '+value+' kg/m² · no se guarda como medición.':'';bmi.hidden=!value;};
      const icons={weight_kg:'⚖️',height_cm:'📏',temperature_c:'🌡️'};
      for(const v of clinical().vitals){
        const holder=this.node('div',null,'consultation-measure');grid.append(holder);
        holder.append(this.node('span',icons[v.key]||'•','consultation-measure-icon'));
        const input=this.field(holder,v.label+' ('+v.unit+')',this.vitals,v.key,'text');input.inputMode='decimal';input.autocomplete='off';input.placeholder='—';
        holder.append(this.node('span',v.unit,'consultation-unit'));
        const issue=this.node('small',null,'consultation-issue');issue.setAttribute('aria-live','polite');holder.append(issue);issues[v.key]=issue;
        input.addEventListener('input',()=>{const clean=clinical().sanitize(input.value,v.integer);if(clean!==input.value)input.value=clean;if(clean)this.vitals[v.key]=clean;else delete this.vitals[v.key];paintIssues();});
      }
      measures.append(bmi);paintIssues();
      // B. Síntomas → subjective, Diagnóstico → assessment (y public.diagnoses), Observaciones → objective.
      const evaluation=this.block(editor,'B','Evaluación médica','Los tres campos son obligatorios para finalizar la consulta.','stethoscope');
      const note=(label,key,placeholder,hint,before)=>{
        const holder=this.node('div',null,'consultation-note');evaluation.append(holder);
        const done=String(this.consultation[key]||'').trim()!=='';
        const badge=this.node('small',done?'Completo':'Obligatorio','consultation-required');badge.setAttribute('data-state',done?'done':'missing');holder.append(badge);
        if(before)before(holder);
        const input=this.field(holder,label,this.consultation,key,'textarea');input.maxLength=10000;input.required=true;input.placeholder=placeholder;input.rows=5;
        input.addEventListener('input',()=>{const ok=input.value.trim()!=='';badge.textContent=ok?'Completo':'Obligatorio';badge.setAttribute('data-state',ok?'done':'missing');});
        if(hint)holder.append(this.node('small',hint,'scope-note'));
      };
      // Síntomas del paciente: referencia de solo lectura (appointment_requests), separada de la evaluación médica.
      const reported=this.node('div',null,'consultation-readonly');reported.append(this.node('small','Reportados por el paciente · solo lectura','consultation-kicker'));this.reportedSymptoms(reported,appointment);evaluation.append(reported);
      note('Síntomas actuales','subjective','Síntomas que encuentras en la consulta, cuándo iniciaron y cómo han evolucionado','Lo que registras tú; los síntomas del paciente se conservan arriba sin cambios.');
      note('Exploración y observaciones','objective','Hallazgos de la exploración física y observaciones clínicas');
      note('Diagnóstico','assessment','Diagnóstico principal y, si aplica, diagnósticos adicionales');
      note('Plan de tratamiento','plan','Tratamiento, indicaciones y seguimiento');
      // C. Formularios existentes de laboratorio y receta, abiertos sin salir de la consulta.
      const services=this.block(editor,'C','Servicios adicionales','Opcionales. Quedan asociados a esta consulta.','grid');
      const service=(label,caption,badge,open)=>{
        const card=this.node('div',null,'consultation-service');services.append(card);
        const button=this.command(card,label,open,true);button.className+=' consultation-action';
        card.append(this.node('p',caption,'scope-note'));if(badge)card.append(this.node('small',badge,'consultation-service-badge'));
      };
      service('Solicitar exámenes','Elige pruebas del catálogo de laboratorio y revísalas antes de enviarlas.',this.pendingLabs?'Envío pendiente de confirmar':'',async()=>{this.panel='labs';if(!this.labTests.length)await this.loadLabCatalog();});
      service('Recetar medicamentos','Añade uno o varios medicamentos y revisa la receta antes de emitirla.',this.lines.length?this.lines.length+' medicamento(s) sin emitir':'',async()=>{this.panel='rx';});
      const finish=this.node('section',null,'consultation-finish clinical-card');
      const blockers=this.finishBlockers();
      if(blockers.length){const list=this.node('div',null,'consultation-blockers');list.append(this.node('strong','Para finalizar falta'));for(const b of blockers)list.append(this.node('p','○ '+b));finish.append(list);}
      else finish.append(this.node('p','✓ Todo listo para finalizar','consultation-ready'));
      this.command(finish,'Guardar consulta',()=>this.saveNote());
      const close=this.command(finish,'FINALIZAR CONSULTA',async()=>{const blockers=this.finishBlockers();if(blockers.length)throw new Error('Para finalizar falta: '+blockers.join('. ')+'.');this.finishConfirm=true;},true);close.className+=' consultation-finish-button';
      editor.append(finish);
      if(this.finishConfirm){
        // Cancelar este cuadro solo vuelve a la consulta: no cancela la cita ni modifica datos.
        const dialog=this.node('section',null,'consultation-confirm');dialog.setAttribute('role','alertdialog');dialog.setAttribute('aria-modal','true');dialog.setAttribute('aria-labelledby','finish-title');
        const title=this.node('h2','¿Estás seguro de que deseas finalizar esta consulta?');title.id='finish-title';
        dialog.append(title,this.node('p','Una vez finalizada, la información clínica quedará registrada en el expediente del paciente y la consulta pasará al historial médico.'));
        const buttons=this.node('div',null,'consultation-confirm-actions');
        buttons.append(this.ui.button('Volver a la consulta',()=>{this.finishConfirm=false;this.ui.repaint();},'module-action'));
        this.command(buttons,'Confirmar y finalizar',async()=>{this.finishConfirm=false;await this.finishConsultation();},true);
        dialog.append(buttons);parent.append(dialog);
      }
    }
    stepHead(parent,letter,title,caption,icon){
      const head=this.node('div',null,'consultation-block-head');const mark=this.node('span',{body:'🧍',stethoscope:'🩺',grid:'➕',list:'📋',calendar:'📅',lab:'🧪',rx:'💊',sign:'✍️'}[icon]||'•','consultation-block-icon');
      if(letter)mark.append(this.node('b',letter,'consultation-block-letter'));
      const text=this.node('div');text.append(this.node('h3',letter?letter+'. '+title:title,'clinical-section-title'));if(caption)text.append(this.node('p',caption,'scope-note'));
      head.append(mark,text);parent.append(head);return head;
    }
    range(v){return (v.lowerExclusive?'Mayor que ':'Desde ')+v.min+' hasta '+v.max+' '+v.unit+' · opcional';}
    block(parent,letter,title,caption,icon){
      const group=this.node('section',null,'consultation-section clinical-card');const head=this.node('div',null,'consultation-block-head');
      const mark=this.node('span',{body:'🧍',stethoscope:'🩺',grid:'➕',list:'📋',calendar:'📅'}[icon]||'•','consultation-block-icon');
      if(letter)mark.append(this.node('b',letter,'consultation-block-letter'));
      const text=this.node('div');text.append(this.node('h3',letter?letter+'. '+title:title,'clinical-section-title'));if(caption)text.append(this.node('p',caption,'scope-note'));
      head.append(mark,text);group.append(head);parent.append(group);return group;
    }
    // Tarjeta del paciente: nombre, código (si el servidor lo publica), expediente, edad y estado.
    patientHero(parent,appointment){
      const hero=this.node('article',null,'consultation-patient');
      const top=this.node('div',null,'consultation-patient-top');
      const name=this.node('div');name.append(this.node('small','PACIENTE','consultation-kicker'),this.node('h2',appointment.patient_name));
      top.append(this.node('span',this.initials(appointment.patient_name),'consult-avatar'),name);hero.append(top);
      const pills=this.node('div',null,'consultation-pills');
      const code=appointment.patient_code||(this.context?.patient?.id===appointment.patient_id?this.context?.patient?.patient_code:null);
      if(code)pills.append(this.node('span','Código '+code,'consultation-pill'));
      pills.append(this.node('span','Expediente '+(appointment.record_number||'no disponible'),'consultation-pill'),this.node('span',appointment.age==null?'Edad no registrada':appointment.age+' años','consultation-pill'),this.node('strong',clinical().statusLabel(appointment.status),'consultation-status'));
      hero.append(pills);parent.append(hero);
    }
    reportedSymptoms(parent,appointment){
      const box=this.node('div',null,'consultation-reported');box.append(this.node('small','Referidos por el paciente en su solicitud','consultation-kicker'));
      const symptoms=(appointment.symptoms||[]).map(s=>String(s).trim()).filter(Boolean),other=String(appointment.other_symptoms||'').trim();
      if(!symptoms.length&&!other)box.append(this.node('p','El paciente no indicó síntomas en la solicitud.','scope-note'));
      const chips=this.node('div',null,'consultation-chips');for(const s of symptoms)chips.append(this.node('span',s,'consultation-chip'));if(symptoms.length)box.append(chips);
      if(other)box.append(this.node('p','Otros: '+other));parent.append(box);
    }
    // Datos de la cita y de la solicitud, cargados automáticamente. Solo lectura.
    consultationInfo(parent,appointment,encounter){
      const info=this.block(parent,'','Datos de la cita','Información registrada por recepción y por el paciente.','calendar');const grid=this.node('div',null,'consultation-info-grid');info.append(grid);
      const start=clinical().start(appointment),zone=clinical().zone;
      const day=start?new Intl.DateTimeFormat('es-SV',{dateStyle:'full',timeZone:zone}).format(start):'No disponible';
      const time=date=>new Intl.DateTimeFormat('es-SV',{timeStyle:'short',timeZone:zone}).format(date);
      const hours=start?time(start)+(appointment.duration_minutes>0?' – '+time(new Date(start.getTime()+appointment.duration_minutes*60000)):''):'No disponible';
      const rows=[['📅','Fecha de la consulta',day.charAt(0).toUpperCase()+day.slice(1)],['🕒','Hora de la consulta',hours],['🩺','Médico responsable',this.workspace?.doctor_name||'No disponible'],['🏥','Especialidad',appointment.specialty||'Cita directa de recepción'],['🚪','Consultorio',appointment.room_code||'No asignado']];
      if(encounter)rows.push(['▶️','Consulta abierta a las',time(new Date(encounter.started_at))]);
      else if(appointment.ticket_number)rows.push(['🎫','Turno',appointment.ticket_number]);
      for(const [icon,label,value] of rows){const tile=this.node('div',null,'consultation-tile');tile.append(this.node('span',icon,'consultation-tile-icon'));this.detail(tile,label,value);grid.append(tile);}
      const reason=this.node('div',null,'consultation-reason');reason.append(this.node('strong','Motivo de consulta enviado por el paciente'),this.node('p',appointment.reason||'La cita no tiene una solicitud de atención vinculada.'));info.append(reason);
    }
    clinicalPanel(parent,appointment){
      const panel=this.node('section',null,'consultation-panel');panel.setAttribute('role','region');panel.setAttribute('aria-label',this.panel==='labs'?'Solicitar exámenes':'Recetar medicamento');
      panel.append(this.ui.button('← Volver a la consulta',()=>{this.panel='';this.rxReview=false;this.ui.repaint();},'text-button'),this.node('h2',this.panel==='labs'?'Solicitar exámenes':'Recetar medicamento'),this.node('p',appointment.patient_name+' · Expediente '+appointment.record_number,'scope-note'));
      if(this.panel==='labs'){panel.append(this.node('p','Las órdenes quedarán asociadas a esta consulta. El laboratorio registrará y validará los resultados.','scope-note'));this.labSelectionView(panel);}
      else this.prescriptionForm(panel);
      parent.append(panel);
    }
    consultationRecord(parent,encounter){
      const card=this.ui.row(dateTime(encounter.started_at),'',encounter.status==='open'?'En consulta':'Finalizada');
      for(const [key,label] of [['subjective','Síntomas actuales'],['objective','Exploración y observaciones'],['assessment','Diagnóstico'],['diagnosis_code','Código diagnóstico'],['plan','Plan de tratamiento']])if(String(encounter[key]||'').trim())this.detail(card,label,encounter[key]);
      for(const v of clinical().recordedVitals)if(encounter.vitals?.[v.key]!=null)this.detail(card,v.label+' ('+v.unit+')',encounter.vitals[v.key]);
      const bmi=clinical().bmi(encounter.vitals||{});if(bmi)this.detail(card,'IMC (calculado)',bmi+' kg/m²');parent.append(card);
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
      for (const encounter of this.chart.history) this.consultationRecord(parent,encounter);
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
      const box=this.node('section',null,'admission-form-card lab-selection');box.append(this.node('h2','Solicitar exámenes'));this.stepHead(box,'1','Elige los exámenes','Toca para seleccionar. Hasta 30 por envío.','lab');
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
      this.stepHead(fields,'2','Resumen y motivo','Revisa la selección e indica el motivo clínico.','list');
      fields.append(this.node('h3','Resumen · '+this.labSelected.size+' exámenes seleccionados','lab-summary-title'));
      const chips=this.node('div',null,'record-chips');for(const test of this.labTests.filter(t=>this.labSelected.has(Number(t.id))))chips.append(this.node('span','• '+test.name,'record-chip'));fields.append(chips);
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
      const head=this.node('div',null,'admission-list-header');head.append(this.node('h2','Mis órdenes de laboratorio'));this.command(head,'Actualizar órdenes',()=>this.loadOwnLabs());parent.append(head);
      if(this.pendingLabs){parent.append(this.node('p','Envío sin confirmar · '+(this.labPendingPatient?.full_name||this.labPendingPatient?.patient_name||'')+' · '+this.labPendingNames.join(' · '),'auth-notice'));this.command(parent,'Reintentar el mismo envío',()=>this.sendLabs(),true);}
      if(this.ownLabsError)parent.append(this.ui.row('No se pudieron cargar las órdenes',this.ownLabsError));
      if(!this.ownLabOrders.length&&!this.ownLabsError){const empty=this.node('article',null,'record-empty');empty.append(this.node('span','🧪','record-empty-icon'),this.node('strong','Sin órdenes'),this.node('p','Todavía no has solicitado exámenes de laboratorio.','sched-hint'));parent.append(empty);}
      for(const order of this.ownLabOrders)this.labOrderView(parent,order);
      if(this.ownLabPage?.has_more)this.command(parent,'Cargar más órdenes',()=>this.loadOwnLabs(true));
    }
    labOrderView(parent,order){
      const card=this.node('article',null,'lab-order-card'+(order.result_summary!=null?' has-result':''));const top=this.node('div',null,'lab-order-top');top.append(this.node('span',order.result_summary!=null?'✓':'🧪','lab-order-icon'),this.node('h3',order.test_name));card.append(top);
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
        const label=m=>[m.name,m.strength,m.presentation].filter(Boolean).join(' · ');
        form.className+=' rx-form';this.stepHead(form,'1','Medicamento','Busca en el catálogo activo del hospital.','rx');
        const search=this.field(form,'Buscar en el catálogo de medicamentos',this,'medicationQuery','search');
        search.addEventListener('input',()=>{const start=search.selectionStart;this.ui.repaint();const input=document.querySelector('[aria-label="Buscar en el catálogo de medicamentos"]');input?.focus?.();if(start!=null)input?.setSelectionRange?.(start,start);});
        const visible=medications.filter(m=>this.matches(label(m),this.medicationQuery));
        this.field(form,'Medicamento y concentración',this.rx,'medication','text',visible.map(m=>[m.id,label(m)]));
        if(medications.length&&!visible.length)form.append(this.node('p','Ningún medicamento coincide con la búsqueda.'));
        if(!medications.length)form.append(this.node('p','No hay medicamentos activos publicados.'));
        this.stepHead(form,'2','Indicación','Dosis, vía, frecuencia, duración e instrucciones.','list');
        const grid=this.node('div',null,'rx-grid');form.append(grid);
        this.field(grid,'Unidad de dosis',this.rx,'unit');
        this.field(grid,'Vía de administración',this.rx,'route','text',[['oral','Oral'],['inyectable','Inyectable']]);
        for(const [label,key,type] of [['Dosis','dose','number'],['Cada cuántas horas','interval','number'],['Duración en días','days','number'],['Cantidad total','quantity','number']])this.field(grid,label,this.rx,key,type);
        this.field(form,'Instrucciones para el paciente',this.rx,'instructions','textarea');
        finish();
        this.lines.forEach((line,index)=>{
          const medication=medications.find(m=>m.id===line.medication_id);
          const card=this.ui.row(medication?[medication.name,medication.strength].filter(Boolean).join(' · '):'Medicamento no disponible',line.dose+' '+line.dose_unit+' · cada '+line.frequency_hours+' h · '+line.duration_days+' días · '+line.route);card.className+=' rx-line';
          this.detail(card,'Indicaciones',line.observations);
          this.command(card,'Retirar medicamento',async()=>{this.lines.splice(index,1);});parent.append(card);
        });
        const reviewHead=this.node('section',null,'rx-review-head');this.stepHead(reviewHead,'3','Revisión de la receta','Revisa cada línea antes de emitir.','sign');reviewHead.append(this.node('h3','Revisión de la receta · '+this.lines.length+' medicamento(s)'));parent.append(reviewHead);
        if(!this.lines.length)parent.append(this.node('p','Añade uno o varios medicamentos para revisarlos antes de emitir.','scope-note'));
        else if(!this.rxReview)this.command(parent,'Revisar y emitir receta',async()=>{this.rxReview=true;},true);
        else {
          const review=this.node('section',null,'consultation-confirm rx-review');review.setAttribute('role','alertdialog');review.append(this.node('h3','¿Emitir esta receta?'),this.node('p','Se emitirá con '+this.lines.length+' medicamento(s) para esta consulta. Los reintentos no duplican la receta.'));
          this.command(review,'Confirmar y emitir receta',()=>this.mutation('nativePrescription',{p_encounter:this.encounter.id,p_key:this.keys.rx,p_lines:this.lines.map(l=>({...l}))},'Receta emitida.',()=>{this.keys.rx=root.crypto.randomUUID();this.lines=[];this.rxReview=false;}),true);
          review.append(this.ui.button('Seguir editando',()=>{this.rxReview=false;this.ui.repaint();},'text-button'));parent.append(review);
        }
      } else parent.append(this.ui.row('Emisión de recetas','Abre la consulta desde la agenda para emitir recetas.'));
      parent.append(this.node('h2','Recetas de mis consultas de este paciente','section-title'));
      for(const rx of this.context?.prescriptions||[]){
        const card=this.ui.row(rx.code,dateTime(rx.issued_at),rx.status==='pendiente'?'Pendiente de entrega':rx.status);card.className+=' rx-issued';
        for(const line of rx.lines||[])card.append(this.node('p',line));parent.append(card);
      }
    }
  }
  root.HospitalModules = HospitalModules;
})(typeof globalThis !== 'undefined' ? globalThis : this);
