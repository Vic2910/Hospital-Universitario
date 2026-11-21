(async function () {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const app = $('#app'), notice = $('#notice');
  let patientNotices = null;
  // Mi horario del médico: semana de HospitalCore.doctorWeek con la jornada real de administración.
  let doctorWeek = null, scheduleWeek = null;
  let api, modules, patientLabModules, patientClinical, doctorDashboard, doctorConsultations, labDesign, patientHistory, patientPrescriptions, appointmentFlow, catalog, fixtures, access = null, roles = [], role = null, page = 'home', search = '', busy = false, design = false;
  let profile = null, summary = null, overview = null, items = [], queue = [], cursor = null, more = false;
  let screenNote = '';
  let stays = null, stayError = null, stayOpen = null; // Hospitalizaciones del paciente (HospitalCore.hospitalizations)
  let notificationsOpen = false;
  let attention = newAttention();
  function newAttention() { return {context:null,rows:[],missing:{},symptoms:new Set(),specialty:'',period:'indiferente',reason:'',other:'',key:crypto.randomUUID(),error:null,confirmation:null}; }
  let passwordDraft = {current:'',next:'',confirm:'',visible:false,error:null,success:null};
  let nextAppointment = null, dashboardError = null;
  let registerOpen = false;
  let registrationDraft = {};
  let labConnected = false;
  let receptionPreview = false;
  const statuses = { pending: 'Pendiente', confirmed: 'Confirmado', cancelled: 'Cancelado', waiting: 'En espera', called: 'Llamado', in_service: 'En atención', completed: 'Finalizado' };
  const glyphs = { home: '⌂', patients: '♙', appointments: '▦', consultation: '✚', health: '♡', profile: '♙', more: '☰', request: '✚', chart: '▤', laboratory: '⚗', prescriptions: '▤' };
  function el(tag, text, className) {
    const node = document.createElement(tag);
    if (text != null) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  function message(text) { notice.textContent = text || ''; notice.hidden = !text; }
  function button(text, action, className) {
    const node = el('button', text, className); node.type = 'button'; node.disabled = busy;
    node.addEventListener('click', action); return node;
  }
  function badge(text) {
    const warning = /espera|pendiente|borrador|proceso/i.test(text);
    return el('span', text, 'badge' + (warning ? ' warning' : /programada|consulta|curso|mañana|tarde/i.test(text) ? ' blue' : ''));
  }
  function row(title, detail, state, icon = false) {
    const card = el('article', null, 'card' + (icon ? ' icon-card' : ''));
    if (icon) card.append(el('span', '✚', 'card-icon'));
    const body = el('div', null, 'card-body'); body.append(el('h3', title));
    if (detail) body.append(el('p', detail)); if (state) body.append(badge(state));
    card.append(body); return card;
  }
  function matches(value) { return !search || value.toLocaleLowerCase('es').includes(search.toLocaleLowerCase('es')); }
  function definition() { return catalog?.[role]?.find(screen => screen.id === page); }
  function clearData() { notificationsOpen=false;doctorWeek=null;scheduleWeek=null; patientLabModules?.clear();patientNotices?.clear();patientClinical?.reset(); receptionPreview=false; appointmentFlow?.reset(); patientHistory?.clear(); labConnected = false; labDesign?.reset(); doctorConsultations?.clear(); doctorDashboard?.clear(); resetSchedule(); modules?.clear(); profile = summary = overview = null; stays = null; stayError = null; stayOpen = null; items = []; queue = []; cursor = null; more = false; screenNote = ''; }
  function reset() { passwordDraft={current:'',next:'',confirm:'',visible:false,error:null,success:null}; attention=newAttention(); nextAppointment = null; dashboardError = null; registrationDraft = {}; access = null; roles = []; role = null; page = 'home'; registerOpen = false; clearData(); }
  async function run(action) {
    if (busy) return;
    busy = true; message(null); render();
    try { await action(); } catch (error) {
      if (error.status === 401) { api.clear(); reset(); }
      if (error.status === 403) {
        const requestDraft = role === 'patient' && ['request','schedule','health'].includes(page) ? {...modules.request} : null;
        const requestKey = modules?.keys.request;
        modules?.clear();patientLabModules?.clear();patientNotices?.clear();
        if (requestDraft) {
          modules.configure(access,role,access.roles.find(item=>item.code===role)?.context_id);
          modules.request=requestDraft;modules.keys.request=requestKey;
        }
      }
      message(error.message || 'No se pudo completar la operación.');
    }
    finally { busy = false; render(); }
  }
  async function resolve() {
    const current = await api.access();
    if (!current.roles.length) throw new Error('Tu cuenta no tiene un rol activo permitido en esta app.');
    access = current.access; roles = current.roles;
    role = roles.length === 1 ? roles[0] : null; page = 'home';
  }
  async function load(append = false) {
    if (design || !role) return;
    try {
      const current = await api.access();
      if (!current.roles.includes(role)) { api.clear(); reset(); throw new Error('El acceso cambió. Inicia sesión de nuevo.'); }
      access = current.access; roles = current.roles; screenNote = '';
      nextAppointment = null; dashboardError = null;
      if (!profile) profile = await api.operation('profile');
      const facility = access.roles.find(item => item.code === role)?.context_id;
      if (role==='patient'&&['request','schedule','health'].includes(page)) { await loadAttention(); return; }
      if (page === 'profile') { profile = await api.operation('profile'); return; }
      modules.configure(access,role,facility);
      if(role==='patient'&&patientNotices){patientNotices.configure(access,role,facility);if(!patientNotices.data)await patientNotices.load('notifications').catch(()=>{});}
      if (modules.supports(role,page)) { await modules.load(page,append);
        // Mis citas también muestra la solicitud enviada mientras recepción no la programe (una sola activa).
        if(role==='patient'&&page==='appointments'&&!append)attention.rows=await api.attentionRPC('my_attention_requests').catch(()=>attention.rows||[]);
        if(role==='patient'&&page==='chart'){patientLabModules.configure(access,role,facility);await patientLabModules.load('laboratory');}return; }
      if (page === 'home') {
        summary = null;
        if(role==='patient') nextAppointment = (await api.operation('patientDashboard')).next_appointment;
      } else if (page === 'rooms' && role === 'patient') {
        // Habitaciones del paciente: hospitalización actual y anteriores (RPC my_hospitalizations). Sin expediente no se consulta.
        stays = null; stayError = null;
        if (design) stays = HospitalCore.hospitalizations.present(stayExamples());
        else if (access?.patient_id) { try { stays = await api.operation('hospitalizations'); } catch (e) { stayError = /my_hospitalizations|PGRST202|404/.test(String(e.message) + e.status) ? 'La consulta de hospitalizaciones aún no está disponible en el servidor (migración pendiente).' : 'No pudimos cargar tu hospitalización. Intenta de nuevo.'; } }
        else stays = {active:null, previous:[]};
      } else if (page === 'rooms' || page === 'turns') {
        if (!append) { items = []; queue = []; cursor = null; more = false; }
        // Turno de la próxima cita: lo asigna el servidor (assign_appointment_queue); la app solo lo lee.
        if(page==='turns' && role==='patient'){if(access?.patient_id)await modules.load('appointments');return;}
        const result = await api.read(page==='rooms'?'rooms':'staff_shifts',append?cursor:null);
        items=append?[...items,...result.data]:result.data;cursor=result.next_cursor;more=result.has_more;
        if(page==='turns'&&role==='doctor'&&!append){
          // Jornada recurrente con descansos registrados (doctor_native_schedule); si la RPC aún no existe, horario básico.
          const ws=scheduleWeek||HospitalCore.doctorWeekStart(),from=new Date(ws+'T00:00:00-06:00'),until=new Date(from.getTime()+7*86400000);
          let recurring=null;try{recurring=await api.doctorRPC('schedule',{p_from:from.toISOString(),p_until:until.toISOString()});}catch{recurring=null;}
          doctorWeek=await api.operation('doctorWeek',{week:ws,recurring});
        }
      } else if (page === 'information') overview = facility ? await api.operation('overview', { p_facility: facility }) : null;
      else if (page === 'profile') profile = await api.operation('profile');
    } catch (error) {
      clearData();
      nextAppointment = null;
      if (page === 'home') dashboardError = error.message;
      if (error.status === 401) { api.clear(); reset(); }
      throw error;
    }
  }
  function go(id) {
    if (busy) return;
    if(role==='doctor'&&id==='notifications'){notificationsOpen=!notificationsOpen;run(async()=>{if(!design&&notificationsOpen)await modules.loadAlerts();});return;}
    if(role==='patient'&&id==='notifications'&&!design&&patientNotices){notificationsOpen=!notificationsOpen;run(async()=>{if(notificationsOpen)await patientNotices.load('notifications');});return;}
    notificationsOpen=false;
    run(async () => { if(role==='patient'&&['chart','laboratory'].includes(page)&&id!==page){labDesign.modal='';patientClinical.reset();} if(receptionPreview){receptionPreview=false;setModeLabel();} if(['request','schedule','health'].includes(page)&&!['request','schedule','health'].includes(id))resetSchedule(); if(id==='appointments'&&page!==id)appointmentFlow.selected=false; if(page === 'history' && id !== page)patientHistory?.clear(); if (page === 'patients' && id !== page) { doctorDashboard?.clear(); labDesign.modal=''; } if(id === 'patients' && page !== id)labDesign.modal=''; page = id; search = ''; items = []; queue = []; more = false; cursor = null; await load(); });
  }
  function displayName() {
    if (design) return fixtures[role].name;
    return access?.profile?.preferred_name || (profile?.person ? `${profile.person.given_names} ${profile.person.family_names}` : role === 'doctor' ? 'Doctor' : 'Paciente');
  }
  function title() { return receptionPreview ? 'Recepción de ejemplo' : role==='patient'&&page==='home' ? 'Mi espacio de salud' : role==='patient'&&['request','schedule','health'].includes(page) ? 'Solicitar atención' : page === 'home' ? (role==='doctor'?'Panel general':'Hola, ' + displayName()) : definition()?.title || ({ more: 'Más', health: 'Mi salud', rooms: 'Habitaciones', schedule: 'Solicitar atención' })[page] || 'Hospital'; }
  function render() {
    app.replaceChildren();
    document.body.classList.toggle('authenticated', !!role);
    if (applicantView.active) return applicantView.render(app);
    if (!access) return registerOpen ? renderRegister() : renderLogin();
    if (!role) return renderRoles();
    renderPortal();
  }
  function authHeader(title, subtitle) {
    const header = el('header', null, 'auth-header');
    const brand = el('div', null, 'auth-brand'); brand.append(el('span', '✚'), el('span', 'Hospital Universitario'));
    header.append(brand, el('h1', title), el('p', subtitle));
    return header;
  }
  function authField(id, label, type, placeholder, autocomplete, trailing) {
    const wrap = el('div', null, 'auth-field');
    const fieldLabel = el('label', label); fieldLabel.htmlFor = id;
    const input = el('input'); Object.assign(input, { id, name: id, type, placeholder, required: true, disabled: busy, autocomplete });
    wrap.append(fieldLabel);
    if (trailing) { const row = el('div', null, 'auth-input'); row.append(input, trailing); wrap.append(row); }
    else wrap.append(input);
    return wrap;
  }
  function revealButton(id) {
    const control = button('Mostrar', () => {
      const field = $('#' + id); field.type = field.type === 'password' ? 'text' : 'password';
      control.textContent = field.type === 'password' ? 'Mostrar' : 'Ocultar';
      control.setAttribute('aria-label', control.textContent === 'Mostrar' ? 'Mostrar contraseña' : 'Ocultar contraseña');
    }, 'field-reveal');
    control.setAttribute('aria-label', 'Mostrar contraseña');
    return control;
  }
  function renderLogin() {
    const view = el('section', null, 'auth-view');
    view.append(authHeader('Iniciar sesión', 'Accede a tu espacio de Médico o Paciente.'));
    const card = el('div', null, 'auth-card');
    const form = el('form');
    form.append(authField('email', 'Correo electrónico', 'email', 'nombre@correo.com', 'username'));
    form.append(authField('password', 'Contraseña', 'password', 'Introduce tu contraseña', 'current-password', revealButton('password')));
    const recovery = el('p', null, 'auth-inline'); recovery.hidden = true;
    const forgotRow = el('div', null, 'auth-row');
    forgotRow.append(button('¿Olvidaste tu contraseña?', () => {
      recovery.textContent = 'Solicita el restablecimiento con el personal del hospital. Enviarán las instrucciones a tu correo electrónico.';
      recovery.hidden = false;
    }, 'field-link'));
    form.append(forgotRow, recovery);
    const submit = el('button', busy ? 'Conectando…' : 'Iniciar sesión', 'primary'); submit.type = 'submit'; submit.disabled = busy || !api;
    form.append(submit);
    form.addEventListener('submit', event => {
      event.preventDefault(); if (!form.reportValidity() || busy) return;
      const email = $('#email').value, password = $('#password').value; $('#password').value = '';
      run(async () => {
        try { await api.signIn(email, password); await resolve(); }
        catch (error) { await api.signOut(); reset(); throw error; }
        if (role) await load();
      });
    });
    card.append(form);
    const switchRow = el('div', null, 'auth-link-row');
    switchRow.append(el('span', '¿No tienes cuenta?'), button('Regístrate', () => { run(async () => { registerOpen = true; }); }, 'link-button'));
    view.append(card, switchRow, el('p', 'Tu perfil y tus permisos son asignados por el hospital.', 'auth-footer'));
    app.append(view);
  }
  function registerProblem(values) {
    return HospitalCore.validateApplicantProfile({ given: values['reg-given'], family: values['reg-family'], birthDate: values['reg-birth'], dui: values['reg-dui'], phone: values['reg-phone'], email: values['reg-email'], password: $('#reg-password').value, confirm: $('#reg-confirm').value }, HospitalCore.localIsoDay(new Date()));
  }
  function renderRegister() {
    const view = el('section', null, 'auth-view');
    view.append(authHeader('Crear cuenta', 'Completa tus datos para solicitar tu acceso.'));
    const card = el('div', null, 'auth-card');
    const form = el('form');
    for (const [id, label, type, placeholder, autocomplete] of [
      ['reg-given', 'Nombres', 'text', 'Tus nombres', 'given-name'],
      ['reg-family', 'Apellidos', 'text', 'Tus apellidos', 'family-name'],
      ['reg-dui', 'DUI', 'text', '00000000-0', 'off'],
      ['reg-birth', 'Fecha de nacimiento', 'date', '', 'bday'],
      ['reg-phone', 'Teléfono', 'tel', '0000-0000', 'tel'],
      ['reg-city', 'Ciudad (opcional)', 'text', 'Tu ciudad', 'address-level2'],
      ['reg-email', 'Correo electrónico', 'email', 'nombre@correo.com', 'username']
    ]) {
      const field = authField(id, label, type, placeholder, autocomplete);
      if (id === 'reg-dui') field.querySelector('input').addEventListener('input', event => {
        event.target.value = HospitalCore.formatDui(event.target.value);
      });
      if (registrationDraft[id]) field.querySelector('input').value = registrationDraft[id];
      if(id==='reg-city') field.querySelector('input').required=false;
      form.append(field);
    }
    form.append(authField('reg-password', 'Contraseña', 'password', 'Contraseña', 'new-password', revealButton('reg-password')));
    form.append(authField('reg-confirm', 'Confirmar contraseña', 'password', 'Repite tu contraseña', 'new-password', revealButton('reg-confirm')));
    const problem = el('p', null, 'auth-error'); problem.hidden = true;
    const done = el('p', null, 'auth-notice'); done.hidden = true;
    const continueDemo = button('Explorar demostración sin crear cuenta', () => {
      registerOpen = false; applicantView.open(); message(null); setModeLabel(); render();
    }, 'primary');
    continueDemo.hidden = !!access;
    form.append(el('p', 'El registro crea únicamente tu cuenta de la app. Recepción gestiona tu expediente y programa tus citas.', 'auth-notice'), problem, done);
    form.append(el('p','Si ya tienes expediente de atención presencial, utiliza tu mismo DUI. No se creará otro expediente: recepción debe verificar tu identidad y confirmar la vinculación. Cualquier asociación existente requiere revisión en recepción.','auth-notice'));
    const submit = el('button', 'Registrarme', 'primary'); submit.type = 'submit'; submit.disabled = busy;
    form.append(submit);
    form.addEventListener('submit', event => {
      event.preventDefault(); problem.hidden = true; done.hidden = true;
      if (!form.reportValidity()) return;
      const values = {};
      for (const id of ['reg-given', 'reg-family', 'reg-dui', 'reg-birth', 'reg-phone', 'reg-city', 'reg-email']) values[id] = $('#' + id)?.value.trim() || '';
      const issue = registerProblem(values);
      if (issue) { problem.textContent = issue.message; problem.hidden = false; return; }
      if (busy) return;
      const password = $('#reg-password')?.value;
      registrationDraft = {...values};
      run(async () => {
        if (!access) {
          const metadata=HospitalCore.registrationAccount({first_name:values['reg-given'],last_name:values['reg-family'],birth_date:values['reg-birth'],phone:values['reg-phone'],city:values['reg-city'],dui:values['reg-dui']});
          if (!await api.signUp(values['reg-email'], password, metadata)) {
            registerOpen=false;
            message('Cuenta creada. El servidor todavía exige confirmar el correo; el hospital debe desactivar ese requisito en Auth. No vuelvas a crear la cuenta.');
            return;
          }
          await resolve();
        }
        registrationDraft = {}; registerOpen = false;
        await resolve();
        if(!access?.patient_id)message(HospitalCore.registrationReviewMessage());
      });

    });
    card.append(form);
    card.append(continueDemo);
    const switchRow = el('div', null, 'auth-link-row');
    switchRow.append(el('span', '¿Ya tienes cuenta?'), button('Inicia sesión', () => { registerOpen = false; render(); }, 'link-button'));
    view.append(card, switchRow);
    app.append(view);
  }
  function renderLiveAttention(content) {
    // Presentación limpia en tres pasos (paridad con PatientAttentionLiveView.swift). La lógica no cambia:
    // mismos campos, validaciones (attentionProblem), envío idempotente y una sola solicitud activa.
    const context=attention.context;
    const hero=el('section',null,'req-hero'),heroTop=el('div',null,'req-hero-top');
    heroTop.append(el('small','NUEVA SOLICITUD'),button('Actualizar',()=>run(loadAttention),'req-refresh'));
    hero.append(heroTop,el('h2','¿Cómo podemos ayudarte?'),el('p','Cuéntanos qué sientes. Recepción revisará tu solicitud y te asignará una cita.'));
    const steps=el('ol',null,'req-steps');for(const [n,label] of [['1','Síntomas'],['2','Especialidad'],['3','Detalles']]){const li=el('li');li.append(el('span',n),el('em',label));steps.append(li);}
    hero.append(steps);content.append(hero);
    const notice=el('div',null,'req-notice');notice.setAttribute('role','note');
    notice.append(el('span','!','req-notice-icon'),el('p','Este formulario no es para emergencias. Ante una emergencia, acude a urgencias. Los síntomas declarados no son diagnósticos.'));content.append(notice);
    if(attention.error)content.append(row('No se pudo actualizar',attention.error));
    if(attention.confirmation){const ok=el('div',null,'req-confirmation');ok.setAttribute('role','status');ok.append(el('span','✓'),el('p',attention.confirmation));content.append(ok);}
    if(!context){content.append(row(busy?'Cargando tus datos…':'No se pudieron cargar tus datos','Pulsa Actualizar para recuperar el formulario.'));return;}
    // Una sola solicitud activa: recepción debe programarla o rechazarla antes de enviar otra.
    const blocker=HospitalCore.attentionBlocker(attention.rows,attention.next);
    if(blocker){
      const card=el('article',null,'record-empty attention-blocked');card.setAttribute('role','status');
      card.append(el('span',blocker.kind==='request'?'⏳':'📅','record-empty-icon'),el('strong',blocker.kind==='request'?'Tu solicitud está en revisión':'Ya tienes una cita programada'),el('p',blocker.message,'sched-hint'),button('Ver mis citas',()=>go('appointments'),'module-action'));
      content.append(card);
    }
    const stepHead=(card,n,title,hint,extra)=>{const head=el('header',null,'req-step-head'),text=el('div');text.append(el('h2',title));if(hint)text.append(el('p',hint));if(extra)text.append(extra);head.append(el('span',n,'req-step-number'),text);card.append(head);};
    const form=el('form',null,'attention-form');if(blocker)form.hidden=true;
    // Tus datos: resumen compacto de la cuenta; solo se piden los datos que faltan.
    const person=context.person,personal=el('article',null,'card attention-card req-card req-person');
    const who=el('header',null,'req-person-head'),name=[person.first_name,person.last_name].filter(Boolean).join(' ');
    const initials=name.split(/\s+/).filter(Boolean).slice(0,2).map(w=>w[0].toUpperCase()).join('')||'—';
    const whoText=el('div');whoText.append(el('h2','Tus datos'),el('strong',name||'Completa tu nombre'),el('small','Recepción verificará tu identidad.'));
    who.append(el('span',initials,'req-avatar'),whoText);personal.append(who);
    const facts=el('dl',null,'req-facts');let factCount=0;const halves=[];
    const shown=value=>/^\d{4}-\d{2}-\d{2}$/.test(value||'')?new Intl.DateTimeFormat('es-SV',{timeZone:'UTC',day:'2-digit',month:'2-digit',year:'numeric'}).format(new Date(value+'T00:00:00Z')):value;
    for(const [key,label] of [['dui','DUI'],['birth_date','Nacimiento'],['phone','Teléfono'],['email','Correo']]){
      if(!person[key])continue;const fact=el('div',null,key==='email'?'req-fact is-wide':'req-fact');if(key!=='email')halves.push(fact);fact.append(el('dt',label),el('dd',shown(person[key])));facts.append(fact);factCount++;
    }
    if(halves.length%2)halves[halves.length-1].className='req-fact is-wide';
    if(factCount)personal.append(facts);
    const missingKeys=[['first_name','Nombres'],['last_name','Apellidos'],['dui','DUI declarado'],['birth_date','Fecha de nacimiento'],['phone','Teléfono']].filter(([key])=>!person[key]);
    if(missingKeys.length){
      const missing=el('div',null,'req-missing');missing.append(el('p','Completa los datos que faltan en tu cuenta:','req-missing-title'));
      for(const [key,label] of missingKeys){
        const field=authField('attention-'+key,label,key==='birth_date'?'date':'text',key==='dui'?'00000000-0':key==='phone'?'0000-0000':label,'off');
        const input=field.querySelector('input');input.value=attention.missing[key]||'';
        input.addEventListener('input',()=>{
          if(key==='dui')input.value=HospitalCore.formatDui(input.value);
          if(key==='phone'){const digits=input.value.replace(/\D/g,'').slice(0,8);input.value=digits.length>4?digits.slice(0,4)+'-'+digits.slice(4):digits;}
          attention.missing[key]=input.value;
        });missing.append(field);
      }
      personal.append(missing);
    }
    if(!person.email)personal.append(el('p','Tu cuenta no publica correo. Contacta al hospital.','req-hint'));
    form.append(personal);
    // Paso 1: síntomas (selección múltiple; la marca de selección es solo visual).
    const symptoms=el('article',null,'card attention-card req-card');
    const count=el('span',attention.symptoms.size?attention.symptoms.size+(attention.symptoms.size===1?' elegido':' elegidos'):'Elige al menos uno','req-count'+(attention.symptoms.size?' is-on':''));
    stepHead(symptoms,'1','¿Qué síntomas presentas?','Selecciona todos los que apliquen.',count);
    const choices=el('div',null,'attention-symptoms req-chips');
    for(const symptom of context.symptoms){
      const control=button(symptom.name,()=>{
        attention.symptoms.has(symptom.id)?attention.symptoms.delete(symptom.id):attention.symptoms.add(symptom.id);render();
      },'attention-symptom req-chip');control.setAttribute('aria-pressed',String(attention.symptoms.has(symptom.id)));choices.append(control);
    }
    symptoms.append(choices);
    if(!context.symptoms.length)symptoms.append(el('p','No hay síntomas activos en el catálogo. Contacta a recepción.','req-hint'));
    const other=context.symptoms.some(s=>s.name==='Otro'&&attention.symptoms.has(s.id));
    if(other) modules.field(symptoms,'Describe el otro síntoma',attention,'other','textarea');
    form.append(symptoms);
    // Paso 2: especialidad en tarjetas (mismo valor que el selector anterior: id de la especialidad).
    const specialtyCard=el('article',null,'card attention-card req-card');
    const available=context.specialties.filter(s=>s.available);
    stepHead(specialtyCard,'2','Especialidad','Elige el área que mejor corresponde a tu malestar.');
    const tiles=el('div',null,'req-tiles');tiles.setAttribute('role','radiogroup');tiles.setAttribute('aria-label','Especialidad');
    for(const s of context.specialties){
      const selected=String(attention.specialty)===String(s.id);
      const tile=button(s.available?s.name:s.name+' · Sin médico disponible',()=>{attention.specialty=String(s.id);render();},'req-tile'+(selected?' is-selected':''));
      tile.setAttribute('role','radio');tile.setAttribute('aria-checked',String(selected));if(!s.available)tile.disabled=true;tiles.append(tile);
    }
    specialtyCard.append(tiles);
    specialtyCard.append(el('p',available.length?'Elegir una especialidad no reserva una cita: recepción confirma la disponibilidad real.':'No hay especialidades con médico activo asignado. Contacta a recepción.','req-hint'));
    form.append(specialtyCard);
    // Paso 3: preferencia de horario (segmentado) y motivo.
    const details=el('article',null,'card attention-card req-card');
    stepHead(details,'3','Detalles de tu solicitud',null);
    details.append(el('p','Preferencia de horario','req-label'));
    const segment=el('div',null,'req-segment');segment.setAttribute('role','radiogroup');segment.setAttribute('aria-label','Preferencia');
    for(const [value,label] of [['manana','Mañana'],['tarde','Tarde'],['indiferente','Indiferente']]){
      const on=attention.period===value,option=button(label,()=>{attention.period=value;render();},'req-segment-option'+(on?' is-selected':''));
      option.setAttribute('role','radio');option.setAttribute('aria-checked',String(on));segment.append(option);
    }
    details.append(segment);
    const reason=modules.field(details,'Motivo de solicitud',attention,'reason','textarea');
    reason.placeholder='Describe brevemente qué te ocurre y desde cuándo.';reason.maxLength=2000;reason.rows=4;
    const counter=el('small',(attention.reason||'').length+' / 2000','req-counter');details.append(counter);
    reason.addEventListener('input',()=>{counter.textContent=reason.value.length+' / 2000';});
    const issue=el('p',null,'auth-error req-issue');issue.hidden=true;details.append(issue);
    const submit=el('button',busy?'Enviando…':'Solicitar atención','primary req-submit');submit.type='submit';submit.disabled=busy||!available.length||!context.symptoms.length;details.append(submit);
    details.append(el('p','Enviar no crea un expediente ni una cita. Recepción revisará tu solicitud.','req-hint req-center'));
    form.append(details);if(!blocker)content.append(form);
    form.addEventListener('submit',event=>{
      event.preventDefault();if(busy)return;
      const problem=attentionProblem();
      if(problem){issue.textContent=problem;issue.hidden=false;return;}
      run(async()=>{
        const missing=Object.fromEntries(Object.entries(attention.missing).filter(([key])=>!context.person[key]));
        const payload={p_key:attention.key,p_specialty:Number(attention.specialty),p_period:attention.period,p_reason:attention.reason.trim(),p_symptoms:[...attention.symptoms].sort((a,b)=>a-b),p_other:other?attention.other.trim():null,p_missing:missing};
        try{await api.attentionRPC('submit_my_attention_request',payload);}
        catch(error){
          const rows=await api.attentionRPC('my_attention_requests').catch(()=>[]);
          if(!rows.some(r=>r.id===attention.key))throw error;
        }
        attention.key=crypto.randomUUID();attention.reason='';attention.symptoms.clear();attention.other='';
        attention.confirmation='Solicitud enviada a recepción. No se creó expediente ni cita.';
        await loadAttention();
      });
    });
    // Solo la solicitud más reciente; las anteriores siguen disponibles aparte, sin mezclarse con el formulario.
    heading(content,'Tu solicitud reciente');
    if(!attention.rows.length&&!attention.error)content.append(row('Todavía no has enviado solicitudes de atención.'));
    const summary=request=>{
      const card=el('article',null,'attention-request');const head=el('div',null,'attention-request-head'),title=el('div');
      title.append(el('strong',request.specialty_name),el('small','Enviada el '+(Number.isFinite(Date.parse(request.created_at))?new Intl.DateTimeFormat('es-SV',{timeZone:'America/El_Salvador',dateStyle:'long',timeStyle:'short'}).format(new Date(request.created_at)):'fecha no disponible')));
      head.append(title,el('span',({pendiente:'Pendiente',en_revision:'En revisión',agendada:'Cita programada',rechazada:'Rechazada',cancelada:'Cancelada'})[request.status]||'Estado no disponible','attention-request-state is-'+request.status));card.append(head,el('p',request.reason));
      if((request.symptoms||[]).length){const chips=el('div',null,'record-chips');for(const sym of request.symptoms)chips.append(el('span',sym,'record-chip'));card.append(chips);}
      if(request.other_symptoms)card.append(el('p','Otros: '+request.other_symptoms));
      card.append(el('small','🕒 Preferencia: '+(({manana:'Mañana',tarde:'Tarde',indiferente:'Indiferente'})[request.preferred_period]||'No disponible')));
      if(request.appointment_id)card.append(button('Ver mi cita',()=>go('appointments'),'text-button'));return card;
    };
    if(attention.rows.length){content.append(summary(attention.rows[0]));
      if(attention.rows.length>1){const older=el('details',null,'attention-older');older.append(el('summary','Ver solicitudes anteriores ('+(attention.rows.length-1)+')'));for(const request of attention.rows.slice(1))older.append(summary(request));content.append(older);}}
  }
  async function loadAttention(){
    attention.error=null;
    try{
      const context=await api.attentionRPC('my_attention_context');
      if(!context?.person||!Array.isArray(context.symptoms)||!Array.isArray(context.specialties))throw new Error('No se pudo interpretar el formulario del hospital.');
      attention.context=context;
      attention.next=null;if(access?.patient_id){try{attention.next=(await api.operation('patientDashboard'))?.next_appointment||null;}catch{attention.next=null;}}
      const rows=await api.attentionRPC('my_attention_requests');
      if(!Array.isArray(rows))throw new Error('No se pudo interpretar el seguimiento.');
      attention.rows=rows;
    }catch(error){attention.rows=[];attention.error=error.message;if(error.status===401)throw error;}
  }
  function attentionProblem(){
    const person={...attention.missing,...Object.fromEntries(Object.entries(attention.context.person).filter(([,v])=>v))};
    if(!person.first_name?.trim()||!person.last_name?.trim()||person.first_name.length>100||person.last_name.length>100)return 'Completa tus nombres y apellidos.';
    if(!/^[0-9]{8}-[0-9]$/.test(person.dui||''))return 'Completa tu DUI con formato 00000000-0.';
    if(!/^[0-9]{4}-[0-9]{4}$/.test(person.phone||''))return 'Completa tu teléfono con formato 0000-0000.';
    const age=HospitalCore.applicantAge(person.birth_date);
    if(age==null||age<0||age>120||person.birth_date>HospitalCore.localIsoDay(new Date())||!person.email)return 'Revisa tu fecha de nacimiento y el correo de tu cuenta.';
    if(!attention.context.specialties.some(s=>s.available&&String(s.id)===String(attention.specialty)))return 'Selecciona una especialidad con médico activo asignado.';
    if(!attention.symptoms.size)return 'Selecciona al menos un síntoma.';
    if(attention.context.symptoms.some(s=>s.name==='Otro'&&attention.symptoms.has(s.id))&&!attention.other.trim())return 'Describe el otro síntoma.';
    if(attention.other.length>1000||!attention.reason.trim()||attention.reason.length>2000)return 'Escribe el motivo (máximo 2000 caracteres) y revisa la descripción de síntomas.';
    if(!['manana','tarde','indiferente'].includes(attention.period))return 'Selecciona una preferencia válida.';
    return null;
  }
  function renderRoles() {
    const view = el('section', null, 'role-picker'); view.append(el('h2', 'Selecciona tu perfil'));
    for (const candidate of roles) view.append(button(HospitalCore.labels[candidate], () => run(async () => { role = candidate; page = 'home'; clearData(); await load(); }), 'primary'));
    view.append(button('Cerrar sesión', logout, 'text-button')); app.append(view);
  }
  function logout() {
    run(async () => {
      const warning = design ? null : await api.signOut(); design = false; reset(); message(warning); setModeLabel();
    });
  }
  function renderPortal() {
    const screen = definition(), portal = el('section', null, 'portal');
    const header = el('header', null, 'hospital-header'), line = el('div', null, 'brand-line');
    const bell = button('🔔', () => go('notifications'), 'bell'); bell.id='notifications-bell';bell.setAttribute('aria-label', 'Notificaciones');if(role==='doctor'||(role==='patient'&&!design)){bell.setAttribute('aria-expanded',String(notificationsOpen));bell.setAttribute('aria-controls','doctor-notifications-panel');bell.setAttribute('aria-haspopup','dialog');}
    if(role==='doctor'&&!design){const count=el('span',String(modules?.unreadAlerts||0),'notification-count');count.hidden=!modules?.unreadAlerts;bell.append(count);}
    if(role==='patient'&&!design&&patientNotices){const unread=patientUnread();const count=el('span',String(unread),'notification-count');count.hidden=!unread;bell.append(count);}
    line.append(el('span', 'Hospital Universitario'), bell);
    if(role==='doctor'&&!design){const alert=el('p',null,'doctor-header-alert');alert.id='doctor-alert-live';alert.setAttribute('role','status');const latest=modules?.alerts?.find(n=>!n.read_at);alert.textContent=latest?latest.title:'';alert.hidden=!latest;header.append(alert);}
    header.append(line, el('h1', title()), el('p', screen?.subtitle || (page === 'schedule' ? 'Elige especialidad y horario' : 'Servicios y consultas del hospital')));
    const searchbox = el('div', null, 'searchbox'), field = el('input');
    field.type = 'search'; field.placeholder = screen?.search || 'Buscar servicios…'; field.value = search; field.setAttribute('aria-label', field.placeholder);
    field.addEventListener('input', () => { search = field.value; const content = $('#screen-content'); if (content) renderContent(content); });
    searchbox.append(el('span', '⌕'), field);
    const content = el('div', null, 'screen-content'); content.id = 'screen-content'; content.setAttribute('aria-busy', String(busy)); renderContent(content);
    const clinicalFlow = (['patients','chart','laboratory'].includes(page) && design)||(role==='doctor'&&['home','patients','laboratory','admissions'].includes(page));
    if(clinicalFlow || page === 'profile' || (role === 'patient' && ['home','chart','laboratory','appointments','request','schedule','health','information'].includes(page))) { portal.className += ' clinical-flow'; portal.append(header,content,bottomBar()); }
    else portal.append(header,searchbox,content,bottomBar());
    if(role==='doctor'&&notificationsOpen)notificationPanel(portal);
    if(role==='patient'&&notificationsOpen&&!design)patientNotificationPanel(portal);
    app.append(portal);
  }
  function closeNotifications(){notificationsOpen=false;render();$('#notifications-bell')?.focus?.();}
  document.addEventListener?.('keydown',event=>{if(event.key==='Escape'&&notificationsOpen){event.preventDefault();closeNotifications();}});
  function patientUnread(){return (patientNotices?.items||[]).filter(item=>item.status==='unread').length;}
  // Avisos propios del paciente (paridad con PatientNotificationBell en ContentView.swift).
  function patientNotificationPanel(portal){
    const backdrop=button(null,closeNotifications,'notification-backdrop');backdrop.setAttribute('aria-label','Cerrar panel de notificaciones');backdrop.tabIndex=-1;
    const panel=el('section',null,'notification-popover');panel.id='doctor-notifications-panel';panel.setAttribute('role','dialog');panel.setAttribute('aria-label','Mis avisos');
    const unread=patientUnread(),head=el('div',null,'notification-popover-head'),heading=el('div');heading.append(el('h2','Mis avisos'),el('p',unread?unread+' sin leer':'Estás al día'));
    const close=button('×',closeNotifications,'notification-close');close.setAttribute('aria-label','Cerrar notificaciones');head.append(heading,close);panel.append(head);
    const list=el('div',null,'notification-popover-list'),items=patientNotices.items||[];
    if(patientNotices.error)list.append(el('p',patientNotices.error,'scope-note'));
    if(!items.length)list.append(el('div','No tienes avisos recientes. Te avisaremos cuando tengas una cita, resultados o una receta lista.','notification-empty'));
    const target=item=>{const t=(item.title+' '+(item.subtitle||'')).toLowerCase();return t.includes('laboratorio')||t.includes('resultado')?['🧪','laboratory']:t.includes('receta')?['💊','prescriptions']:t.includes('cita')?['📅','appointments']:t.includes('solicitud')?['💬','request']:['🔔',null];};
    for(const item of items){
      const [icon,destination]=target(item),card=el('article',null,'notification-item'+(item.status==='unread'?' unread':''));
      card.append(el('span',icon,'notification-icon'),el('h3',item.title),el('p',item.subtitle||''),el('time',new Intl.DateTimeFormat('es-SV',{dateStyle:'medium',timeStyle:'short',timeZone:'America/El_Salvador'}).format(new Date(item.event_at))));
      if(destination)card.append(button('Ver',()=>{notificationsOpen=false;go(destination);},'notification-read'));
      if(item.status==='unread')card.append(button('Marcar como leída',()=>run(async()=>{await api.operation('updateItem',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version});await patientNotices.load('notifications');}),'notification-read'));
      else card.append(el('span','✓ Leída','notification-read-state'));
      list.append(card);
    }
    if(patientNotices.data?.has_more)list.append(button('Cargar más avisos',()=>run(()=>patientNotices.load('notifications',true)),'module-action'));
    panel.append(list,button('Actualizar avisos',()=>run(()=>patientNotices.load('notifications')),'notification-refresh'));portal.append(backdrop,panel);
  }
  function notificationPanel(portal){
    const backdrop=button(null,closeNotifications,'notification-backdrop');backdrop.setAttribute('aria-label','Cerrar panel de notificaciones');backdrop.tabIndex=-1;
    const panel=el('section',null,'notification-popover');panel.id='doctor-notifications-panel';panel.setAttribute('role','dialog');panel.setAttribute('aria-label','Notificaciones');
    const head=el('div',null,'notification-popover-head'),heading=el('div');heading.append(el('h2','Notificaciones'),el('p',(design?0:modules.unreadAlerts)+' sin leer'));
    const close=button('×',closeNotifications,'notification-close');close.setAttribute('aria-label','Cerrar notificaciones');head.append(heading,close);panel.append(head);
    const list=el('div',null,'notification-popover-list');
    if(modules.alertsError&&!design)list.append(el('p',modules.alertsError,'scope-note'));
    const rows=design?[]:modules.alerts;
    if(!rows.length)list.append(el('div',design?'Modo diseño · Sin avisos reales.':'Estás al día. No hay avisos recientes.','notification-empty'));
    for(const item of rows){
      const card=el('article',null,'notification-item'+(item.read_at?'':' unread'));
      card.append(el('h3',item.title),el('p',item.body),el('time',new Intl.DateTimeFormat('es-GT',{dateStyle:'medium',timeStyle:'short'}).format(new Date(item.created_at))));
      if(!item.read_at)card.append(button('Marcar como leída',()=>run(async()=>{await api.operation('updateItem',{p_resource:'notifications',p_id:item.id,p_values:{read_at:new Date().toISOString()},p_expected_version:item.row_version});await modules.loadAlerts();}),'notification-read'));
      else card.append(el('span','✓ Leída','notification-read-state'));
      list.append(card);
    }
    if(!design&&modules.alertsHaveMore)list.append(button('Cargar más avisos',()=>run(()=>modules.loadAlerts(true)),'module-action'));
    panel.append(list);
    if(!design)panel.append(button('Actualizar avisos',()=>run(()=>modules.loadAlerts()),'notification-refresh'));
    portal.append(backdrop,panel);
  }
  function bottomBar() {
    const nav = el('nav', null, role === 'doctor' ? 'bottom-nav doctor-nav' : 'bottom-nav'); nav.setAttribute('aria-label', 'Navegación principal');
    const tabs = role === 'doctor' ? [['home','Inicio'],['patients','Pacientes'],['consultation','Consultas'],['laboratory','Laboratorios'],['more','Más']] : [['home','Inicio'],['appointments','Mis citas'],['health','Salud'],['profile','Perfil'],['more','Más']];
    const active = role==='patient'&&['request','schedule','health'].includes(page) ? 'health' : ['more','rooms','health'].includes(page) ? (page === 'health' ? 'health' : 'more') : page === 'schedule' ? 'home' : definition()?.tab;
    for (const [id, label] of tabs) {
      const node = button(null, () => go(id)); node.append(el('span', glyphs[id], 'nav-icon'), el('span', label));
      node.setAttribute('aria-label', label); if (active === id) node.setAttribute('aria-current', 'page'); nav.append(node);
    }
    return nav;
  }
  function heading(content, text) { content.append(el('h2', text, 'section-title')); }
  function empty(content, text) { content.append(row(text || 'No hay registros que coincidan con esta consulta.')); }
  function dataRows(content, rows, icons = true) {
    for (const values of rows.filter(values => matches(values.join(' ')))) content.append(row(values[0], values[1], values[2], icons));
  }
  function renderContent(content) {
    content.replaceChildren();
    if (busy) content.append(el('p', 'Cargando…', 'loading'));
    if (screenNote) content.append(el('p', screenNote, 'scope-note'));
    const screen = definition();
    if(receptionPreview)return appointmentFlow.renderReception(content);
    if(role==='patient'&&['request','schedule','health'].includes(page))return design ? scheduleView(content) : renderLiveAttention(content);
    if (!design && role==='patient' && !access.patient_id && ['appointments','laboratory','prescriptions','chart','history'].includes(page)) {
      const titles={appointments:'No tienes citas programadas',laboratory:'No tienes resultados de laboratorio',prescriptions:'No tienes recetas disponibles'};
      content.append(row(titles[page] || (['request','schedule','health'].includes(page) ? 'Solicita atención en recepción' : 'Tu información clínica aún no está disponible'),
        'Acércate a recepción o consulta los canales oficiales de contacto del hospital. El personal debe crear o vincular tu expediente y programar tu atención.'));
      content.append(button('Información del hospital',()=>go('information'),'text-button'),button('Actualizar estado',()=>run(()=>load()),'text-button'));
      return;
    }
    if(role==='patient'&&page==='appointments'){
      const demo=design;
      if(!demo)return appointmentFlow.renderLive(content,{items:modules.items,loading:busy,error:!busy&&!modules.data,period:formatConsultationTime,search,go,
        hasMore:!!modules.data?.has_more,loadMore:()=>run(()=>modules.load('appointments',true)),request:(attention.rows||[]).find(r=>['pendiente','en_revision'].includes(r.status))||null,
        cancel:(item,reason)=>run(()=>modules.mutation('cancelAppointment',{p_id:item.id,p_status:'cancelled',p_reason:reason,p_expected_version:item.row_version},'Cita cancelada.'))});
      return appointmentFlow.render(content,{appointments:appointmentFlow.appointments,demonstration:demo,loading:busy,error:false,renderConnected:null});
    }
    if(role === 'patient' && page === 'prescriptions') {
      const useExamples=design;
      return patientPrescriptions.render(content,{records:useExamples?HospitalPatientPrescriptions.examples:HospitalPatientPrescriptions.fromItems(modules.items),demonstration:useExamples,search,loading:busy,
        error:!design&&!busy&&!modules.data?'No pudimos cargar tus recetas. Intenta de nuevo.':null,hasMore:!design&&modules.data?.has_more,retry:()=>run(()=>load()),loadMore:()=>run(()=>modules.load('prescriptions',true))});
    }
    if(role === 'patient' && page === 'history') {
      const useExamples = design;
      return patientHistory.render(content,{records:useExamples?HospitalPatientHistory.examples:HospitalPatientHistory.fromItems(modules.items),demonstration:useExamples,search,loading:busy,
        error:!design&&!busy&&!modules.data?'No pudimos cargar tu historial. Intenta de nuevo.':null,hasMore:!design&&modules.data?.has_more,
        retry:()=>run(()=>load()),loadMore:()=>run(()=>modules.load('history',true))});
    }
    if(!design&&role==='patient'&&['chart','laboratory'].includes(page))return patientClinical.render(content,{page,profile,scope:access?.patient_id});
    if (design && ['patients','chart','laboratory'].includes(page)) return labDesign.render(content,{role,page});
    if (!design && modules.supports(role,page) && page !== 'profile') {
      modules.configure(access,role,access.roles.find(item => item.code === role)?.context_id);
      return modules.render(content,page,search);
    }
    if (page === 'home') return home(content);
    if (design && role === 'doctor' && page === 'consultation') {
      return doctorConsultations.render(content,{day:doctorConsultations.day,appointments:HospitalDoctorConsultations.samples(doctorConsultations.day),demo:true,search,period:formatConsultationTime,
        onDay:day => { doctorConsultations.day = day; renderContent(content); }});
    }
    if (design && role === 'doctor' && page === 'patients') {
      heading(content, 'Mis pacientes');
      return doctorDashboard.renderHistory(content, HospitalDoctorDashboard.demo());
    }
    if (page === 'schedule' && role === 'patient') return scheduleView(content);
    if (page === 'more' || page === 'health') return menu(content);
    if (page === 'rooms') return rooms(content);
    if (page === 'turns') return role === 'doctor' ? schedule(content) : queueView(content);
    if (page === 'profile') return profileView(content);
    if (page === 'information') return information(content);
    if (page === 'chart' && design) {
      const rows = fixtures[role].rows.chart;
      content.append(row(...rows[0])); heading(content, screen.section); dataRows(content,rows.slice(1),false); return;
    }
    heading(content, screen?.section || title());
    if (screen?.layout === 'request' || screen?.layout === 'consultation') return formScaffold(content, screen);
    if (['laboratory','patients'].includes(screen?.layout)) content.append(el('p', screen.layout === 'patients' ? 'Todos　⌄　　Atención actual　⌄' : 'Estado: Todos　⌄' + (role === 'doctor' ? '　　Prioridad: Todas　⌄' : ''), 'filters'));
    if (design) {
      const rows = fixtures[role].rows[page] || [];
      if (role === 'patient' && ['appointments','prescriptions'].includes(page)) {
        const split = page === 'appointments' ? 2 : 3;
        dataRows(content,rows.slice(0,split)); heading(content,screen.sections[0]); dataRows(content,rows.slice(split));
      } else if (page === 'history') {
        for (const values of rows.filter(values => matches(values.join(' ')))) { const card = row(values[0],values[1]); card.append(el('span','Ver detalle','history-detail')); content.append(card); }
      } else dataRows(content, rows, !['chart','history'].includes(page));
      if (!rows.length) empty(content, 'Sin información de ejemplo.');
    } else empty(content);
    if (!design && screen?.layout === 'chart') for (const section of screen.sections || []) content.append(row(section, 'Información protegida'));
    if (screen?.layout === 'prescriptions' && role === 'doctor') {
      content.append(el('p', 'Verificar alergias y contraindicaciones', 'rose-note'));
      const action = button('+ Nueva receta', () => {}, 'primary'); action.disabled = true; content.append(action);
    }
    if (screen?.layout === 'appointments' && role === 'patient') content.append(button('Agendar cita',()=>go('schedule'),'module-action'),button('Solicitar nueva cita', () => go('request'), 'primary'));
  }
  function formatConsultationTime(value) {
    try {
      const bounds = HospitalCore.periodBounds(value), formatter = new Intl.DateTimeFormat('es-GT',{hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
      return formatter.format(new Date(bounds.start)) + '–' + formatter.format(new Date(bounds.end));
    } catch { return 'Horario no disponible'; }
  }
  function home(content) {
    if (role === 'patient') return patientDashboard(content);
    return doctorDashboard.render(content, HospitalDoctorDashboard.demo());
  }

  function patientDashboard(content) {
    const name = design ? displayName() : access.profile.greeting_name || '';
    const greeting = el('article', null, 'dash-greeting');
    const text = el('div', null, 'dash-text');
    text.append(el('h2', name ? '¡Hola, ' + name + '!' : '¡Hola!'), el('p', 'Aquí está el resumen de tu día.'));
    const initials = name.split(/\s+/).map(part => part.charAt(0)).join('').slice(0, 2).toUpperCase();
    greeting.append(text, el('span', initials || 'PA', 'dash-avatar'));
    content.append(greeting);
    const today = new Intl.DateTimeFormat('es-SV', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date());
    const card = el('article', null, 'dash-date');
    const todayRow = el('div', null, 'dash-row');
    const todayText = el('div', null, 'dash-stack');
    todayText.append(el('span', 'HOY', 'dash-label'), el('strong', today));
    todayRow.append(el('span', '▣', 'dash-row-icon'), todayText);
    card.append(todayRow, el('hr'), el('span', 'PRÓXIMA CITA', 'dash-label'));
    if (busy) {
      card.append(el('p','Consultando tus citas…','dash-empty'));
    } else if (dashboardError && !design) {
      card.append(el('strong','No se pudieron cargar tus citas','dash-empty'),el('p',dashboardError,'dash-medico'));
    } else if (design) {
      const sample = fixtures.patient.rows.appointments[0];
      card.append(el('p', '30 de octubre', 'dash-cita-day'), el('strong', '10:00', 'dash-time'), el('p', sample[1], 'dash-medico'));
    } else if (nextAppointment) {
      const date=new Date(nextAppointment.starts_at);
      card.append(el('p',new Intl.DateTimeFormat('es-GT',{weekday:'long',day:'numeric',month:'long'}).format(date),'dash-cita-day'),
        el('strong',new Intl.DateTimeFormat('es-GT',{hour:'numeric',minute:'2-digit'}).format(date),'dash-time'),
        el('p',nextAppointment.doctor_name || 'Nombre del médico no disponible','dash-medico'),
        el('p',HospitalCore.doctorClinical.statusLabel(nextAppointment.status),'dash-medico'));
    } else {
      card.append(el('strong', 'No tienes citas programadas', 'dash-empty'), el('p', 'Cuando recepción programe tu próxima cita, la encontrarás aquí.', 'dash-medico'));
    }
    content.append(card);
    if(dashboardError && !design) content.append(button('Reintentar',()=>run(()=>load()),'text-button'));
    if(!design && !access.patient_id) content.append(el('p','Recepción debe crear o vincular tu expediente. Puedes seguir explorando la app.','scope-note'));
    heading(content, 'Accesos rápidos');
    const grid = el('div', null, 'dash-grid');
    for (const [id, label, icon] of [['appointments', 'Mis citas', '▦'], ['request', 'Solicitar atención', '✚'], ['laboratory', 'Laboratorios', '⚗'], ['prescriptions', 'Recetas', '▤']]) {
      const node = button(null, () => go(id), 'dash-card');
      node.setAttribute('aria-label',label);
      node.append(el('span', icon, 'dash-icon'), el('strong', label));
      grid.append(node);
    }
    content.append(grid);
  }
  // Estado de la pantalla Agendar cita (presentación local, sin escritura en base).
  const symptomList = ['Sangrado', 'Tos', 'Hueso roto', 'Fiebre', 'Dolor de cabeza', 'Náuseas', 'Falta de aire', 'Dolor abdominal', 'Mareo', 'Dolor articular'];
  const noneSymptom = 'Ninguno';
  const specialtyList = [
    { name: 'Médico general', icon: '✚', slots: [{ day: 'Hoy', time: '2:00 pm – 4:00 pm' }, { day: 'Mañana', time: '8:00 am – 10:00 am' }, { day: 'Lunes', time: '10:00 am – 12:00 m' }] },
    { name: 'Cardiólogo', icon: '♥', slots: [{ day: 'Mañana', time: '9:00 am – 11:00 am' }, { day: 'Martes', time: '3:00 pm – 5:00 pm' }] },
    { name: 'Neurólogo', icon: '🧠', slots: [{ day: 'Martes', time: '8:00 am – 10:00 am' }, { day: 'Jueves', time: '1:00 pm – 3:00 pm' }] },
    { name: 'Ortopedista', icon: '🦴', slots: [{ day: 'Hoy', time: '4:30 pm – 6:00 pm' }, { day: 'Miércoles', time: '9:00 am – 11:00 am' }] },
    { name: 'Cirujano', icon: '✛', slots: [{ day: 'Jueves', time: '10:00 am – 12:00 m' }, { day: 'Viernes', time: '8:00 am – 9:30 am' }] },
    { name: 'Pediatra', icon: '👶', slots: [{ day: 'Mañana', time: '11:00 am – 1:00 pm' }, { day: 'Sábado', time: '9:00 am – 11:00 am' }] }
  ];
  // Paciente de prueba precargado: la base de datos aún no devuelve estos datos.
  const scheduleState = {
    fields: { nombres: 'Gaby', apellidos: 'Diaz', dui: '0123-45678', telefono: '7123-4567', correo: 'gaby.diaz@ejemplo.test' },
    symptoms: new Set(), specialty: null, slot: null, reason: '', preference: '', prepared: false
  };
  function resetSchedule() {
    Object.assign(scheduleState, {
      fields: { nombres: 'Gaby', apellidos: 'Diaz', dui: '0123-45678', telefono: '7123-4567', correo: 'gaby.diaz@ejemplo.test' },
      symptoms: new Set(), specialty: null, slot: null, reason: '', preference: '', prepared: false
    });
  }
  function scheduleFormCard(titleText, icon, body) {
    const card = el('article', null, 'sched-card');
    const head = el('div', null, 'sched-head');
    head.append(el('span', icon, 'sched-head-icon'), el('strong', titleText));
    card.append(head, body);
    return card;
  }
  function scheduleField(labelText, id, placeholder, type) {
    const wrap = el('div', null, 'sched-field');
    const label = el('label', labelText); label.htmlFor = 'sched-' + id;
    const input = el('input'); Object.assign(input, { id: 'sched-' + id, type: type || 'text', placeholder, value: scheduleState.fields[id], disabled: busy });
    input.setAttribute('aria-label', labelText);
    input.addEventListener('input', () => { scheduleState.fields[id] = input.value; invalidateSchedule(); updateScheduleButton($('#screen-content')); });
    wrap.append(label, input);
    return wrap;
  }
  // Repinta la pantalla actual tras un cambio de selección (sin tocar el estado de sesión).
  function repaintSchedule() {
    const focused = document.activeElement?.getAttribute('data-choice');
    const node = $('#screen-content'); if (node) renderContent(node);
    if (focused) node?.querySelector('[data-choice="' + focused + '"]')?.focus();
  }
  function invalidateSchedule() {
    scheduleState.prepared = false;
    const feedback = $('#sched-feedback'); if (feedback) feedback.hidden = true;
  }
  function toggleSymptom(value) {
    scheduleState.prepared = false;
    if (value === noneSymptom) scheduleState.symptoms = new Set([noneSymptom]);
    else {
      scheduleState.symptoms.delete(noneSymptom);
      if (scheduleState.symptoms.has(value)) scheduleState.symptoms.delete(value); else scheduleState.symptoms.add(value);
    }
    repaintSchedule();
  }
  function paintSlots(container) {
    const grid = el('div', null, 'sched-grid');
    if (!scheduleState.specialty) { container.append(el('p', 'Selecciona una especialidad para ver los horarios.', 'sched-hint')); return; }
    container.append(el('p', 'Horarios orientativos', 'sched-sub'));
    for (const slot of scheduleState.specialty.slots) {
      const active = scheduleState.slot === slot;
      const node = button(null, () => { scheduleState.slot = slot; scheduleState.prepared = false; repaintSchedule(); }, active ? 'sched-slot is-selected' : 'sched-slot');
      node.setAttribute('aria-pressed', String(active));
      node.setAttribute('data-choice', 'slot-' + scheduleState.specialty.slots.indexOf(slot));
      node.append(el('span', slot.day.toUpperCase(), 'sched-slot-day'), el('strong', slot.time));
      grid.append(node);
    }
    container.append(grid);
  }
  function paintFeedback(content) {
    if (!scheduleState.prepared || !scheduleState.specialty || !scheduleState.slot) return;
    const note = el('article', null, 'sched-success');
    note.id = 'sched-feedback'; note.setAttribute('role', 'status');
    const text = el('div', null, 'sched-success-text');
    text.append(el('strong', 'Solicitud Pendiente'), el('p', scheduleState.specialty.name + ' · ' + scheduleState.slot.day + ' · ' + scheduleState.slot.time),
      el('p', 'Solicitud de ejemplo guardada como Pendiente. Recepción debe asignar una cita; no se envió al hospital.'));
    note.append(el('span', '✓', 'sched-success-icon'), text);
    content.append(note);
  }
  function scheduleView(content) {
    const intro = el('article', null, 'sched-intro');
    intro.append(el('span', 'TU SALUD, A TU TIEMPO', 'sched-eyebrow'), el('h2', 'Preparemos tu próxima cita'),
      el('p', 'Completa tus datos, cuéntanos cómo te sientes y elige tu atención.'),
      el('small', 'Paciente y horarios de prueba · No se envía al hospital'));
    content.append(intro);
    content.append(scheduleFormCard('Datos del paciente', '👤', (() => {
      const wrap = el('div', null, 'sched-fields');
      wrap.append(el('p', 'Datos de prueba. Puedes editarlos para agendar para otra persona.', 'sched-hint'));
      wrap.append(scheduleField('Nombres', 'nombres', 'Nombres'), scheduleField('Apellidos', 'apellidos', 'Apellidos'),
        scheduleField('DUI', 'dui', '0000-00000'), scheduleField('Teléfono', 'telefono', '0000-0000', 'tel'),
        scheduleField('Correo electrónico', 'correo', 'nombre@correo.com', 'email'));
      return wrap;
    })()));
    content.append(scheduleFormCard('Síntomas frecuentes', '♡', (() => {
      const wrap = el('div', null, 'sched-wrap');
      wrap.append(el('p', 'Selecciona lo que te aplica. Puedes elegir varios.', 'sched-hint'));
      const grid = el('div', null, 'sched-grid');
      for (const symptom of [...symptomList, noneSymptom]) {
        const active = scheduleState.symptoms.has(symptom);
        const node = button(symptom, () => toggleSymptom(symptom), active ? 'sched-chip is-selected' : 'sched-chip');
        node.setAttribute('aria-pressed', String(active));
        node.setAttribute('data-choice', 'symptom-' + [...symptomList, noneSymptom].indexOf(symptom));
        grid.append(node);
      }
      wrap.append(grid);
      return wrap;
    })()));
    content.append(scheduleFormCard('Motivo de consulta', '✎', (() => {
      const area = el('textarea', null, 'sched-reason');
      area.placeholder = 'Describe con tus palabras lo que te pasa…';
      area.value = scheduleState.reason;
      area.setAttribute('aria-label', 'Motivo de consulta');
      area.addEventListener('input', () => { scheduleState.reason = area.value; invalidateSchedule(); updateScheduleButton(content); });
      return area;
    })()));
    content.append(scheduleFormCard('Tipo de doctor', '✚', (() => {
      const wrap = el('div', null, 'sched-wrap');
      const grid = el('div', null, 'sched-grid');
      for (const specialty of specialtyList) {
        const active = scheduleState.specialty === specialty;
        const node = button(null, () => {
          scheduleState.prepared = false;
          if (active) { scheduleState.specialty = null; scheduleState.slot = null; }
          else { scheduleState.specialty = specialty; scheduleState.slot = null; }
          repaintSchedule();
        }, active ? 'sched-chip is-selected' : 'sched-chip');
        node.setAttribute('aria-pressed', String(active));
        node.setAttribute('data-choice', 'specialty-' + specialtyList.indexOf(specialty));
        node.append(el('span', specialty.icon), el('span', specialty.name));
        grid.append(node);
      }
      wrap.append(grid);
      const slots = el('div', null, 'sched-slots');
      paintSlots(slots);
      wrap.append(slots);
      return wrap;
    })()));
    content.append(scheduleFormCard('Preferencia de horario','☀',(()=>{
      const wrap=el('div'),options=el('div',null,'sched-preference-options');options.setAttribute('role','group');options.setAttribute('aria-label','Preferencia de horario');
      for(const[value,period,icon,description]of[['Mañana','AM','☀','Antes del mediodía'],['Tarde','PM','☼','Después del mediodía']]){
        const selected=scheduleState.preference===value,node=button(null,()=>{scheduleState.preference=value;invalidateSchedule();repaintSchedule();},'sched-preference-option'+(selected?' is-selected':''));
        node.setAttribute('aria-label',value+' · '+period);node.setAttribute('aria-pressed',String(selected));node.setAttribute('data-choice','preference-'+period.toLowerCase());
        const top=el('span',null,'sched-preference-top'),mark=el('span',selected?'\u2713':'','sched-preference-mark');mark.setAttribute('aria-hidden','true');top.append(el('span',icon),mark);
        node.append(top,el('strong',value),el('small',period+' · '+description));options.append(node);
      }
      wrap.append(options,el('p','Selecciona la opción que te convenga. Recepción confirmará la fecha y hora.','sched-hint'));return wrap;
    })()));
    const summary = el('article', null, 'sched-summary');
    summary.append(el('strong', 'Tu selección'), el('p', scheduleState.specialty && scheduleState.slot
      ? scheduleState.specialty.name + ' · ' + scheduleState.slot.day + ' · ' + scheduleState.slot.time
      : 'Elige una especialidad y un horario para continuar.'),
      el('small', 'Recepción asignará la cita. Completa todos los campos. DUI: 0000-00000; teléfono: 0000-0000; correo válido.'));
    content.append(summary);
    paintFeedback(content);
    const submit = button('Solicitar atención', () => { if (!scheduleCanSubmit() || scheduleState.prepared) return;
      const saved=appointmentFlow.submit({id:crypto.randomUUID(),fields:scheduleState.fields,specialty:scheduleState.specialty.name,reason:scheduleState.reason,symptoms:[...scheduleState.symptoms],preference:scheduleState.preference,preferredSlot:scheduleState.slot.day+' · '+scheduleState.slot.time});
      if(saved){scheduleState.prepared = true; repaintSchedule();} }, 'primary sched-submit');
    submit.id = 'sched-submit';
    submit.disabled = !scheduleCanSubmit() || scheduleState.prepared;
    content.append(submit);appointmentFlow.renderRequests(content);
  }
  function scheduleCanSubmit() {
    const f = scheduleState.fields;
    return ['Mañana','Tarde'].includes(scheduleState.preference) && !!scheduleState.specialty && !!scheduleState.slot && scheduleState.reason.trim().length > 0
      && !!f.nombres.trim() && !!f.apellidos.trim() && /^\d{4}-\d{5}$/.test(f.dui.trim())
      && /^\d{4}-\d{4}$/.test(f.telefono.trim()) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.correo.trim());
  }
  function updateScheduleButton(content) {
    const submit = content.querySelector('#sched-submit');
    if (submit) submit.disabled = !scheduleCanSubmit() || scheduleState.prepared;
  }
  // Menú «Más» del paciente (paridad ContentView.patientMenu). Notificaciones queda solo en la campana superior.
  const patientMenuGroups = [
    {title:'Mi atención', items:[['appointments','\u25A6','Citas activas y solicitudes'],['request','\u271A','Pide una cita o consulta'],['turns','#','Tu turno de atención']]},
    {title:'Mi salud', items:[['chart','\u25A4','Datos clínicos protegidos'],['history','\u21BA','Consultas finalizadas'],['prescriptions','\u211E','Recetas emitidas'],['laboratory','\u2697','Solicitudes y resultados']]},
    {title:'Servicios del hospital', items:[['information','i','Ubicación, servicios y contacto'],['rooms','\u25AD','Tu hospitalización y estancias']]},
    {title:'Mi cuenta', items:[['profile','\u2659','Datos personales y seguridad']]}];
  function patientMenu(content) {
    let shown = 0;
    for (const group of patientMenuGroups) {
      const rows = group.items.map(([id, icon, note]) => ({id, icon, note, title: id === 'rooms' ? 'Habitaciones' : catalog.patient.find(s => s.id === id)?.title})).filter(i => i.title && (matches(i.title) || matches(i.note)));
      if (!rows.length) continue; shown += rows.length;
      const section = el('section', null, 'more-group'); section.append(el('h2', group.title.toUpperCase(), 'more-group-title'));
      const list = el('div', null, 'more-list');
      for (const item of rows) {
        const b = button(null, () => go(item.id), 'more-row'); b.setAttribute('data-screen', item.id); b.setAttribute('aria-label', item.title);
        const text = el('span', null, 'more-row-text'); text.append(el('strong', item.title), el('small', item.note));
        b.append(el('span', item.icon, 'more-row-icon'), text, el('span', '\u203A', 'more-row-chevron')); list.append(b);
      }
      section.append(list); content.append(section);
    }
    if (!shown) empty(content, 'No hay servicios que coincidan con tu búsqueda.');
    const actions = el('div', null, 'more-actions');
    if (roles.length > 1) actions.append(button('Cambiar perfil', () => { role = null; clearData(); render(); }, 'text-button'));
    actions.append(button('Cerrar sesión', logout, 'logout')); content.append(actions);
  }
  function menu(content) {
    if (role === 'patient' && page === 'more') return patientMenu(content);
    heading(content, page === 'health' ? 'Tu información de salud' : 'Servicios');
    for (const screen of catalog[role].filter(item => item.id !== 'home' && (page !== 'health' || item.tab === 'health') && matches(item.title))) content.append(button(screen.title + '　›', () => go(screen.id), 'menu-row'));
    if (page === 'more') {
      content.append(button('Habitaciones　›', () => go('rooms'), 'menu-row'));
      if (roles.length > 1) content.append(button('Cambiar perfil', () => { role = null; clearData(); render(); }, 'text-button'));
      content.append(button('Cerrar sesión', logout, 'logout'));
    }
  }
  function changeWeek(offset){
    if(!offset||!doctorWeek){scheduleWeek=null;}else{const d=new Date(doctorWeek.week_start+'T12:00:00-06:00');d.setUTCDate(d.getUTCDate()+7*offset);scheduleWeek=new Intl.DateTimeFormat('en-CA',{timeZone:'America/El_Salvador'}).format(d);}
    run(()=>load());
  }
  // Paridad con ContentView.schedule (iOS): semana en tarjetas verticales, sin columnas ni desplazamiento horizontal.
  function weekView(content,week){
    const zone='America/El_Salvador',day=k=>new Intl.DateTimeFormat('es-SV',{timeZone:zone,day:'numeric',month:'long'}).format(new Date(k+'T12:00:00-06:00'));
    const hours=m=>m%60?Math.floor(m/60)+' h '+(m%60)+' min':Math.floor(m/60)+' h';
    const hero=el('header',null,'directory-hero schedule-hero');hero.append(el('small','MI HORARIO'),el('h2',day(week.week_start)+' – '+day(week.week_end)),el('p',hours(week.total_minutes)+' de jornada · '+week.days.filter(d=>!d.free).length+' días con actividad'));
    const nav=el('div',null,'schedule-nav');const prev=button('‹',()=>changeWeek(-1),'schedule-step');prev.setAttribute('aria-label','Semana anterior');const next=button('›',()=>changeWeek(1),'schedule-step');next.setAttribute('aria-label','Semana siguiente');
    const now=button('Esta semana',()=>changeWeek(0),'schedule-now');now.disabled=!scheduleWeek;nav.append(prev,now,next);hero.append(nav);content.append(hero);
    for(const d of week.days){
      const card=el('article',null,'schedule-day'+(d.today?' is-today':''));const head=el('div',null,'schedule-day-head');const title=el('div');title.append(el('strong',d.weekday),el('small',day(d.date)));head.append(title);
      if(d.today)head.append(el('span','Hoy','schedule-today'));if(d.minutes)head.append(el('span',hours(d.minutes),'schedule-hours'));card.append(head);
      if(d.free&&!d.absences.length)card.append(el('p','☀ Día libre','schedule-free'));
      const line=(icon,label,value,kind)=>{const r=el('div',null,'schedule-line is-'+kind);r.append(el('span',icon,'schedule-icon'),el('span',label),el('strong',value));card.append(r);};
      for(const b of d.blocks)line(b.shift==='Tarde'?'🌇':'🌅',b.shift||'Jornada',b.start+' – '+b.end,'block');
      for(const b of d.breaks)line(b.kind==='lunch'?'🍽':b.kind==='gap'?'⏸':'☕',b.label||'Descanso',b.start+' – '+b.end,b.kind==='gap'?'gap':'break');
      for(const sh of d.shifts)line('🕒','Jornada asignada · '+sh.type,sh.start+' – '+sh.end,'shift');
      for(const a of d.absences)line('⛔','Ausencia · '+a.reason,a.all_day?'Todo el día':a.start+' – '+a.end,'absence');
      content.append(card);
    }
    content.append(el('p','Almuerzo y descansos según tu jornada registrada por administración. «Entre jornadas» es tiempo sin actividad asignada, no un almuerzo. Los cambios llegan a tus avisos.','scope-note'));
  }
  function schedule(content) {
    if(!design&&role==='doctor'&&doctorWeek){weekView(content,doctorWeek);
      for (const shift of items.filter(item => item.status === 'pending')) content.append(button('Confirmar jornada · ' + formatPeriod(shift.period || `["${shift.starts_at}","${shift.ends_at}")`),() => run(async () => {
        await api.operation('confirmShift',{p_id:shift.id,p_expected_version:shift.row_version}); await load(); message('Jornada confirmada.');}),'module-action'));
      return;}
    heading(content, 'Próxima jornada');
    const demoRows = design ? fixtures.doctor.schedule : null;
    const rows = demoRows || [...items].sort((a,b) => periodTime(a.period,'start') - periodTime(b.period,'start')).map(item => [formatPeriod(item.period), '', statuses[item.status] || item.status]);
    if (design) { const next = row('Viernes 23 de octubre','Mañana · 07:00–15:00','Confirmado'); next.className += ' schedule-next'; content.append(next); }
    else {
      const next = items.filter(item => item.status !== 'cancelled' && periodTime(item.period,'end') > Date.now()).sort((a,b) => periodTime(a.period,'start') - periodTime(b.period,'start'))[0];
      if (next) content.append(row(formatPeriod(next.period), '', statuses[next.status])); else empty(content, 'No tienes próximas jornadas asignadas.');
    }
    heading(content, 'Agenda semanal');
    for (const values of rows.filter(values => matches(values.join(' ')))) { const card = row(values[0],values[1],values[2]); card.className += ' schedule-row'; content.append(card); }
    if (!design) for (const shift of items.filter(item => item.status === 'pending')) content.append(button('Confirmar jornada · ' + formatPeriod(shift.period || `["${shift.starts_at}","${shift.ends_at}")`),() => run(async () => {
      await api.operation('confirmShift',{p_id:shift.id,p_expected_version:shift.row_version}); await load(); message('Jornada confirmada.');
    }),'module-action'));
    if (!rows.length && !busy) empty(content, 'No hay turnos para mostrar.'); loadMore(content);
  }
  function formatPeriod(period) {
    try { const bounds = HospitalCore.periodBounds(period), formatter = new Intl.DateTimeFormat('es-SV', { dateStyle:'medium', timeStyle:'short' }); return formatter.format(new Date(bounds.start)) + ' – ' + formatter.format(new Date(bounds.end)); }
    catch { return 'Horario no disponible'; }
  }
  function periodTime(period,bound) {
    try { return new Date(HospitalCore.periodBounds(period)[bound]).getTime(); }
    catch { return bound === 'end' ? -Infinity : Infinity; }
  }
  // Pantalla original "Mi turno" (ruta turns; paridad con ContentView.swift `queue`). Sin pantallas ni navegación nuevas.
  // El turno es appointments.queue_number, asignado por el servidor al programar la cita; la app solo lo lee y le da formato.
  // Cada cita activa muestra su número dentro de su tarjeta; las finalizadas, canceladas o vencidas pasan a Turnos anteriores.
  function queueView(content) {
    heading(content, 'Turno de atención');
    const zone='America/El_Salvador',P=HospitalCore.patientAppointments,fmt=(value,options)=>{const d=new Date(value);return Number.isFinite(d.getTime())?new Intl.DateTimeFormat('es-SV',{timeZone:zone,...options}).format(d):'No disponible';};
    const field=(item,label)=>{const v=(item.details||[]).find(f=>f.label.toLowerCase()===label.toLowerCase())?.value;return v&&v.trim()&&v!=='Sin registrar'?v.trim():'';};
    const sample=()=>({id:'design',title:'Medicina general',status:'confirmed',event_at:new Date(Date.now()+86400000).toISOString(),ends_at:new Date(Date.now()+88200000).toISOString(),queue_number:fixtures?.patient?.queue?.number||24,details:[{label:'Médico',value:'Médico de ejemplo'},{label:'Especialidad',value:'Medicina general'},{label:'Consultorio',value:'C-3'}]});
    const list=design?[sample()]:(modules.items||[]);
    if(busy&&!list.length){content.append(el('p','Consultando tu turno…','scope-note'));return;}
    const {active,past}=P.split(list,new Date());
    if(!active.length)empty(content,'No tienes un turno activo.');
    for(const item of active){
      const turno=P.turn(item.queue_number),card=el('article',null,'ticket-card turn-card');
      card.setAttribute('aria-label',turno?'Tu turno: '+turno:'Turno pendiente de asignación');
      card.append(el('p','Tu número'),el('strong',turno||'—'),badge(HospitalCore.doctorClinical.statusLabel(item.status)));
      if(!turno)card.append(el('small','El hospital asignará tu turno automáticamente.','turn-pending'));
      const info=el('dl',null,'turn-details'),day=fmt(item.event_at,{weekday:'long',day:'numeric',month:'long'});
      info.append(el('p','Información de la cita','turn-details-title'));
      for(const [label,value] of [['Fecha',day.charAt(0).toUpperCase()+day.slice(1)],['Hora',fmt(item.event_at,{hour:'numeric',minute:'2-digit'})],['Médico',field(item,'Médico')||'Nombre del médico no disponible'],['Especialidad',field(item,'Especialidad')],['Consultorio',field(item,'Consultorio')||'Por asignar']]){
        if(!value)continue;const line=el('div');line.append(el('dt',label),el('dd',value));info.append(line);
      }
      card.append(info);content.append(card);
    }
    if(design)content.append(el('p','Turno de ejemplo · Sin cita real','scope-note'));
    content.append(el('p','El hospital asigna el turno automáticamente al programar tu cita.','scope-note'));
    // Historial: las citas que ya no están activas conservan su turno y su estado (Atendida, Cancelada, No atendida…).
    const history=past.filter(item=>P.turn(item.queue_number));
    if(history.length){
      heading(content,'Turnos anteriores');
      for(const item of history){
        const line=el('article',null,'turn-history'),num=el('span',P.turn(item.queue_number),'turn-history-number'),text=el('div');
        text.append(el('strong',field(item,'Especialidad')||item.title||'Cita médica'),el('small',fmt(item.event_at,{day:'numeric',month:'short',year:'numeric'})+' · '+fmt(item.event_at,{hour:'numeric',minute:'2-digit'})));
        line.append(num,text,el('span',P.active(item)?'':HospitalCore.doctorClinical.statusLabel(item.status),'turn-history-state is-'+item.status));content.append(line);
      }
    }
    content.append(button('Mis citas',()=>go('appointments'),'menu-row'));
  }
  // Ejemplos locales de diseño (solo modo diseño, nunca Supabase): una estancia activa y una finalizada con traslado.
  function stayExamples() {
    return [{id:'ejemplo-activa',status:'hospitalizado',ordered_at:'2026-11-19T14:10:00Z',hospital_name:'Hospital Universitario (ejemplo)',doctor_name:'Dra. Ejemplo Rivas',reason:'Observación posoperatoria (ejemplo)',instructions:'Reposo relativo y control de signos cada 6 h (ejemplo)',
      assignments:[{room:'VIP-302',room_kind:'vip',bed:'A',floor:'Tercer piso',assigned_at:'2026-11-19T14:40:00Z',released_at:null}]},
      {id:'ejemplo-anterior',status:'cerrado',ordered_at:'2026-08-18T15:20:00Z',discharged_at:'2026-08-22T17:15:00Z',hospital_name:'Hospital Universitario (ejemplo)',doctor_name:'Dr. Ejemplo Méndez',discharged_by_name:'Dr. Ejemplo Méndez',reason:'Neumonía adquirida en la comunidad (ejemplo)',discharge_notes:'Control en consulta externa en 7 días (ejemplo)',
      assignments:[{room:'HAB-201',room_kind:'semiprivada',bed:'B',floor:'Segundo piso',assigned_at:'2026-08-18T15:30:00Z',released_at:'2026-08-19T15:00:00Z'},{room:'HAB-204',room_kind:'semiprivada',bed:'A',floor:'Segundo piso',assigned_at:'2026-08-19T15:00:00Z',released_at:'2026-08-22T18:00:00Z'}]}];
  }
  function stayFacts(keys) {
    const grid = el('dl', null, 'stay-facts');
    for (const [label, value] of keys) if (value) { const d = el('div'); d.append(el('dt', label), el('dd', value)); grid.append(d); }
    return grid;
  }
  function stayHeader(node, e) {
    node.append(el('small', e.active ? 'TU HOSPITALIZACIÓN ACTUAL' : 'HOSPITALIZACIÓN FINALIZADA'), el('h2', e.room ? 'Habitación ' + e.room : 'Habitación por confirmar'),
      el('p', [e.room_kind, e.hospital].filter(Boolean).join(' · ')), el('span', e.status_label, 'stay-pill'));
  }
  function stayDetail(content, e) {
    content.append(button('\u2039 Habitaciones', () => { stayOpen = null; renderContent(content); }, 'text-button stay-back'));
    const head = el('header', null, 'stay-hero' + (e.active ? '' : ' is-past')); stayHeader(head, e); content.append(head);
    for (const s of e.sections) { const card = el('section', null, 'stay-section'); card.append(el('h3', s.title), stayFacts(s.rows.map(r => [r.label, r.value]))); content.append(card); }
    if (e.transfers.length) {
      const card = el('section', null, 'stay-section'); card.append(el('h3', 'Traslados de habitación'));
      for (const t of e.transfers) card.append(row([t.room ? 'Habitación ' + t.room : 'Habitación', t.room_kind].filter(Boolean).join(' · '), 'Desde ' + t.from + (t.until ? ' · hasta ' + t.until : ' · actual')));
      content.append(card);
    }
    if (design) content.append(el('p', 'Ejemplo de diseño local: no procede de Supabase.', 'scope-note'));
  }
  function stayEmpty(title, text) { const box = el('div', null, 'stay-empty'); box.append(el('span', '\u2302', 'stay-empty-icon'), el('h3', title), el('p', text)); return box; }
  function patientRooms(content) {
    if (design && !stays) stays = HospitalCore.hospitalizations.present(stayExamples()); // modo diseño no pasa por load()
    const H = stays, open = stayOpen && H && [H.active, ...H.previous].find(e => e && e.id === stayOpen);
    if (open) return stayDetail(content, open);
    if (design) content.append(el('p', 'Modo diseño: hospitalizaciones de ejemplo, no son registros reales.', 'rose-note'));
    if (busy && !H) { content.append(el('p', 'Cargando tu hospitalización…', 'loading')); return; }
    if (stayError) { content.append(row(stayError)); content.append(button('Reintentar', () => run(() => load()), 'menu-row')); return; }
    if (!access?.patient_id && !design) { content.append(stayEmpty('Actualmente no tienes una hospitalización registrada', 'Recepción debe vincular tu expediente para mostrar tus hospitalizaciones.')); return; }
    const e = H?.active, hit = x => !search || [x.room, x.room_kind, x.admitted_date, x.status_label].some(v => v && matches(v));
    if (e && hit(e)) {
      heading(content, 'Tu hospitalización actual');
      const card = button(null, () => { stayOpen = e.id; renderContent(content); }, 'stay-hero stay-hero-button'); card.id = 'stay-active'; stayHeader(card, e);
      card.append(stayFacts([['Ingreso', [e.admitted_date, e.admitted_time].filter(Boolean).join(' · ')], ['Médico', [e.doctor, e.specialty].filter(Boolean).join(' · ')], ['Área', e.area], ['Cama', e.bed]]), el('span', 'Ver detalles \u203A', 'stay-more'));
      content.append(card);
    } else if (!e) content.append(stayEmpty('Actualmente no tienes una hospitalización registrada', 'Cuando el personal autorizado registre un ingreso, aparecerá aquí con tu habitación y médico responsable.'));
    const prev = (H?.previous || []).filter(hit);
    if (prev.length) {
      heading(content, 'Hospitalizaciones anteriores');
      for (const p of prev) {
        const b = button(null, () => { stayOpen = p.id; renderContent(content); }, 'stay-past');
        const t = el('span', null, 'more-row-text');
        t.append(el('strong', [p.room ? 'Habitación ' + p.room : 'Habitación', p.room_kind].filter(Boolean).join(' · ')), el('small', 'Ingreso: ' + (p.admitted_date || 'sin fecha') + (p.discharged_date ? ' · Alta: ' + p.discharged_date : '')));
        b.append(el('span', '\u25AD', 'more-row-icon'), t, el('span', p.status_label, 'badge'), el('span', '\u203A', 'more-row-chevron')); content.append(b);
      }
    }
  }
  function rooms(content) {
    if (role === 'patient') return patientRooms(content);
    heading(content, 'Habitaciones del hospital');
    const records = design ? [...Array.from({length:5}, (_,i) => ({ code:'VIP-' + (301+i), active:true })), ...Array.from({length:6}, (_,i) => ({ code:'HAB-' + (201+i), active:true }))] : items;
    for (const item of records.filter(item => matches(item.code))) content.append(row(item.code, null, item.active ? 'Activa' : 'Inactiva'));
    if (!records.length && !busy) empty(content, 'No hay habitaciones disponibles para consultar.');
    content.append(el('p', 'El estado activo no indica disponibilidad de camas.', 'scope-note')); loadMore(content);
  }
  function loadMore(content) { if (more) content.append(button('Cargar más', () => run(() => load(true)), 'menu-row')); }
  // Tarjeta «Seguridad» del Perfil (paciente y médico; paridad con PasswordChangeCard.swift). Verifica la contraseña actual y
  // actualiza la contraseña en Supabase Auth (api.changePassword). En modo diseño no se llama a Supabase.
  function passwordCard(content) {
    const card=el('section',null,'sched-card password-card'),head=el('header',null,'password-card-head'),text=el('div');
    text.append(el('h2','Seguridad'),el('p','Cambia la contraseña con la que inicias sesión.'));head.append(el('span','🔒','password-card-icon'),text);card.append(head);
    const form=el('form',null,'password-form');form.noValidate=true;
    const problem=()=>HospitalCore.validatePasswordChange(passwordDraft);
    const hint=el('p',null,'password-issue');hint.hidden=true;
    const refreshHint=()=>{const issue=(passwordDraft.current||passwordDraft.next||passwordDraft.confirm)?problem():null;hint.textContent=issue?issue.message:'';hint.hidden=!issue;submit.disabled=busy||!!problem();};
    for(const [key,label,auto] of [['current','Contraseña actual','current-password'],['next','Nueva contraseña','new-password'],['confirm','Confirmar nueva contraseña','new-password']]){
      const wrap=el('label',null,'password-field');wrap.append(el('span',label));
      const input=el('input');input.type=passwordDraft.visible?'text':'password';input.autocomplete=auto;input.value=passwordDraft[key];input.disabled=busy;input.setAttribute('aria-label',label);
      input.addEventListener('input',()=>{passwordDraft[key]=input.value;passwordDraft.error=null;passwordDraft.success=null;refreshHint();});wrap.append(input);form.append(wrap);
    }
    form.append(button(passwordDraft.visible?'Ocultar contraseñas':'Mostrar contraseñas',()=>{passwordDraft.visible=!passwordDraft.visible;render();},'text-button password-toggle'));
    form.append(el('p','Mínimo 8 caracteres y distinta de la actual.','password-rule'),hint);
    if(passwordDraft.error){const e=el('p',passwordDraft.error,'password-error');e.setAttribute('role','alert');form.append(e);}
    if(passwordDraft.success){const ok=el('p',passwordDraft.success,'password-success');ok.setAttribute('role','status');form.append(ok);}
    const submit=el('button',busy?'Actualizando…':'Actualizar contraseña','primary password-submit');submit.type='submit';form.append(submit);refreshHint();
    form.addEventListener('submit',event=>{
      event.preventDefault();if(busy||problem())return;
      if(design){passwordDraft={current:'',next:'',confirm:'',visible:false,error:null,success:'Modo diseño · No se cambió ninguna contraseña real.'};render();return;}
      const current=passwordDraft.current,next=passwordDraft.next;
      run(async()=>{
        try{await api.changePassword(current,next);passwordDraft={current:'',next:'',confirm:'',visible:false,error:null,success:'Contraseña actualizada. Úsala la próxima vez que inicies sesión.'};}
        catch(error){passwordDraft.error=error.message||'No se pudo cambiar la contraseña. Inténtalo de nuevo.';passwordDraft.success=null;}
      });
    });
    card.append(form);content.append(card);
  }
  function profileView(content) {
    const clean = value => typeof value === 'string' && value.trim() ? value.trim() : 'No disponible';
    const given = clean(design ? fixtures[role].givenNames : profile?.person?.given_names);
    const family = clean(design ? fixtures[role].familyNames : profile?.person?.family_names);
    if(role==='patient'){
      const name=[given,family].filter(value=>value!=='No disponible').join(' ')||'No disponible',email=clean(design?'maria.lopez@ejemplo.test':profile?.auth_email),phone=clean(design?'7123-4567':profile?.contacts?.find(item=>item.kind==='phone')?.value);
      const hero=el('article',null,'patient-profile-hero'),avatar=el('span',name==='No disponible'?'?':name.split(' ').slice(0,2).map(value=>value[0]).join(''),'patient-profile-avatar');avatar.setAttribute('aria-hidden','true');hero.append(avatar,el('h2',name),el('p','Paciente · Hospital Universitario'));if(design)hero.append(el('small','Perfil de ejemplo'));content.append(hero);
      const card=el('section',null,'sched-card patient-profile-contact');card.append(el('h2','Información personal','section-title'));
      for(const[label,value,icon]of [['Nombre completo',name,'♙'],['Correo electrónico',email,'@'],['Teléfono',phone,'☎']]){const row=el('div',null,'profile-contact-row'),symbol=el('span',icon,'profile-contact-icon'),text=el('div');symbol.setAttribute('aria-hidden','true');text.append(el('span',label),el('strong',value));row.append(symbol,text);card.append(row);}content.append(card,el('p','Datos de tu registro','clinical-ticket-note'));passwordCard(content);return;
    }
    const intro = el('div',null,'identity-intro');
    const icon = el('span',[given,family].filter(value=>value!=='No disponible').map(value=>value[0]).join('') || '—','identity-icon'); icon.setAttribute('aria-hidden','true');
    intro.append(icon,el('h2','Datos de registro')); content.append(intro);
    for (const [label,value] of [['Nombre',given],['Apellido',family]]) {
      const card = el('article',null,'sched-card identity-field'); card.append(el('span',label),el('strong',value)); content.append(card);
    }
    passwordCard(content);
  }
  function information(content) {
    const link=(label,url,className='info-action')=>{const a=el('a',label,className);a.href=url;if(url.startsWith('https:')){a.target='_blank';a.rel='noopener noreferrer';}return a;};
    const hero=el('article',null,'hospital-info-hero');hero.append(el('span','✚','hospital-info-emblem'),el('h2','Tu hospital, más cerca'),el('p','Ubicación, orientación y servicios en un solo lugar.'),el('small','Santa Ana · El Salvador'));content.append(hero);
    const location=el('section',null,'sched-card hospital-info-card');location.append(el('h2','Encuéntranos','section-title'));
    const address=el('div',null,'hospital-location-heading');address.append(el('span','⌖','hospital-location-pin'),el('strong','Campus UNICAES · Santa Ana'),el('small','Ubicación de referencia'));location.append(address,el('p','By pass carretera a Metapán y carretera antigua hacia San Salvador, Santa Ana, El Salvador','hospital-info-copy'),link('Cómo llegar','https://www.google.com/maps/search/?api=1&query=Universidad+Catolica+de+El+Salvador+Santa+Ana'));content.append(location);
    const contact=el('section',null,'sched-card hospital-info-card');contact.append(el('h2','Orientación y contacto','section-title'),el('h3','¿Necesitas ayuda?'),el('span','Clínica Universitaria · UNICAES','sched-hint'),el('strong','+503 2484-0668','hospital-contact-number'),link('Llamar a la clínica','tel:+50324840668'),el('span','WhatsApp institucional','sched-hint'),el('strong','+503 7742-3033'),link('Abrir WhatsApp institucional','https://wa.me/50377423033','info-text-link'),link('Ver directorio oficial de UNICAES','https://catolica.edu.sv/contactos-facultades-y-unidades-unidaes/','info-source'));content.append(contact);
    const specialties=el('section',null,'sched-card hospital-info-card'),published=!design&&overview?.on_duty?.length>0,names=published?[...new Set(overview.on_duty.map(item=>item.specialty))].sort():specialtyList.map(item=>item.name);
    specialties.append(el('h2','Especialidades','section-title'),el('span',published?'Especialidades de médicos publicados':'Catálogo de demostración','clinical-lab-state'));const grid=el('div',null,'hospital-specialties');for(const name of names){const item=el('article',null,'hospital-specialty');item.append(el('span','✚'),el('strong',name));grid.append(item);}specialties.append(grid,el('p','Confirma la disponibilidad al solicitar atención.','sched-hint'),button('Solicitar atención',()=>go('health'),'primary'));content.append(specialties);
    if(!design&&overview){const notices=el('details',null,'sched-card hospital-info-card');notices.append(el('summary','Avisos y actividad del hospital'),row('Ocupación general',overview.occupied==null||overview.capacity==null?'Sin información publicada':`${overview.occupied} de ${overview.capacity} camas`));for(const person of overview.on_duty)notices.append(row(person.name,person.specialty));for(const note of overview.information)notices.append(row(note.title,note.body));content.append(notices);}
    content.append(button('Consultar habitaciones',()=>go('rooms'),'menu-row'));
  }
  function formScaffold(content, screen) {
    if (screen.layout === 'consultation') {
      if (design) dataRows(content,fixtures.doctor.rows.consultation,false); else empty(content,'Selecciona un paciente autorizado para continuar.');
    }
    for (const label of screen.fields || []) {
      const group = el('div',null,'form-field'); group.append(el('label',label));
      const input = el(label === 'Motivo de consulta' || screen.layout === 'consultation' ? 'textarea' : 'input');
      input.placeholder = label === 'Motivo de consulta' ? 'Describe brevemente tu necesidad' : 'Seleccionar ' + label.toLowerCase() + '　⌄';
      input.disabled = !design; input.setAttribute('aria-label',label); group.append(input); content.append(group);
    }
    content.append(el('p',screen.layout === 'request' ? 'La disponibilidad se confirmará al programar.' : 'Verifica los datos antes de guardar.','rose-note'));
    const action = button(screen.layout === 'request' ? 'Enviar solicitud' : 'Guardar consulta', () => {}, 'primary'); action.disabled = true; content.append(action);
  }
  function setModeLabel() {
    $('#preview-mode').textContent = receptionPreview ? 'MODO DISEÑO · Recepción simulada · Sin permisos ni operaciones reales.' : applicantView.active ? 'MODO DISEÑO · Solicitante de ejemplo. Sin credenciales y sin conexión a Supabase.' : design ? 'MODO DISEÑO · Datos de ejemplo locales. Sin sesión y sin conexión a Supabase.' : 'Conexión real a Supabase. Inicia sesión con una cuenta autorizada.';
    document.body.classList.toggle('design-mode',design || applicantView.active);
  }
  async function enterDesign(candidate) {
    if (busy) return;
    applicantView.close();
    if (!design && access) { message('Cierra tu sesión antes de abrir el modo de diseño.'); return; }
    await run(async () => {
      if (!fixtures) fixtures = await (await fetch('/design-fixtures.json')).json();
      reset(); design = true; role = candidate; roles = [candidate];
      access = { profile:{status:'active'}, roles:[] }; setModeLabel();
    });
  }
  const applicantView = new HospitalApplicantDemo({el, button, header: authHeader, message, rerender: () => render(), exit: () => { applicantView.close(); design = false; reset(); message(null); setModeLabel(); render(); }});
  try {
    const [configResponse, screensResponse] = await Promise.all([fetch('/shared/contract.json',{cache:'no-store'}), fetch('/shared/screens.json',{cache:'no-store'})]);
    if (!configResponse.ok || !screensResponse.ok) throw new Error('No se pudo cargar la configuración.');
    api = new HospitalAPI(await configResponse.json()); catalog = await screensResponse.json();
    appointmentFlow=new HospitalPatientAppointments({el,button,go,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);},exitReception:()=>{receptionPreview=false;page='appointments';setModeLabel();render();}});
    patientPrescriptions = new HospitalPatientPrescriptions({el,button});
    patientHistory = new HospitalPatientHistory({el,button,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);}});
    labDesign = new HospitalClinicalLabsDesign({el,button,go,busy:()=>busy,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);}});
    doctorConsultations = new HospitalDoctorConsultations({el,button,busy:() => busy,repaint:() => { const content = $('#screen-content'); if (content) renderContent(content); }});
    patientClinical=new HospitalPatientClinical({el,button,go,run,busy:()=>busy,model:()=>modules,laboratory:()=>patientLabModules,retry:()=>run(()=>load()),repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);}});
    patientLabModules=new HospitalModules(api,{el,button,row,run,message,go,period:formatPeriod,busy:()=>busy});
    patientNotices=new HospitalModules(api,{el,button,row,run,message,go,period:formatPeriod,busy:()=>busy});
    doctorDashboard = new HospitalDoctorDashboard({el,button,go,run,busy:() => busy});
    modules = new HospitalModules(api,{el,button,row,run,message,go,period:formatPeriod,busy:() => busy,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);},
      doctorConsultations:(parent,module) => {
        const demo = false;
        doctorConsultations.render(parent,{day:module.day,appointments:module.workspace.appointments,stateFilter:module.stateFilter,demo,search,period:formatConsultationTime,
          onFilter:value => { module.stateFilter = value; renderContent($('#screen-content')); },
          onDay:day => { module.day = day; module.select(''); module.workspace = null; run(() => module.load('consultation')); },
          // ABRIR CONSULTA MÉDICA: doctor_native_start es idempotente (misma clave y consulta existente reutilizada).
          onSelect:id => { module.select(id); run(async()=>{await module.loadChart();const a=module.appointment;if(a&&!a.encounter_id&&!HospitalCore.doctorClinical.openingBlocker(a))await module.mutation('startConsultation',{p_appointment:id,p_request_key:module.keys.start},'Consulta abierta. Estado: En consulta.',()=>{module.keys.start=crypto.randomUUID();module.seedDraft=true;});}); }});
      },
      doctorDashboard:(parent,module) => {
        const workspace = module.workspace, clinical = HospitalCore.doctorClinical;
        const agenda = clinical.agenda(workspace.appointments,module.day);
        const dayAppointments = clinical.chronological(workspace.appointments).filter(a=>clinical.dayKey(clinical.start(a)||NaN)===module.day);
        doctorDashboard.render(parent,{name:workspace.doctor_name,facility:workspace.facility_name,
          // Contadores del día elegido (la agenda trae 14 días) y siguiente cita en orden cronológico.
          appointments:dayAppointments,unread:module.unreadAlerts,alerts:module.alerts,next:agenda.day.concat(agenda.upcoming).find(a=>a.status==='in_progress'||(HospitalCore.doctorClinical.start(a)||0)>=new Date())||null,
          count:dayAppointments.filter(item => !['cancelled','rejected','no_show'].includes(item.status)).length});
      },
      doctorPatientHistory:(parent,module) => {
        const patients = [...new Map(module.workspace.appointments.map(item => [item.patient_id,{id:item.patient_id,name:item.patient_name,record:item.record_number}])).values()].sort((a,b) => a.name.localeCompare(b.name,'es'));
        doctorDashboard.renderHistory(parent,{patients,loadHistory:async (patient,from,to) => {
          const chart = await api.operation('patientChart',{p_patient:patient,p_from:from,p_to:to,p_query:''}); return chart.history;
        }});
      }});
  } catch (error) { message(error.message); }
  $('#design-patient').addEventListener('click', () => {if(receptionPreview){receptionPreview=false;page='appointments';setModeLabel();render();}else enterDesign('patient');});
  $('#design-reception').addEventListener('click',async()=>{if(busy)return;if(!design&&access){message('Cierra tu sesión para abrir Recepción de demostración.');return;}if(!design||role!=='patient')await enterDesign('patient');if(!design||busy)return;role='patient';page='appointments';receptionPreview=true;setModeLabel();render();});
  $('#design-doctor').addEventListener('click', () => enterDesign('doctor'));
  $('#design-applicant').addEventListener('click', () => { if (busy) return; if (access && !applicantView.active) { message('Cierra tu sesión antes de abrir el modo de diseño.'); return; } design = false; reset(); applicantView.open(); message(null); setModeLabel(); render(); });
  $('#live-mode').addEventListener('click', () => { if (busy || !(design || applicantView.active)) return; applicantView.close(); design = false; reset(); message(null); setModeLabel(); render(); });
  render();
  if (api && sessionStorage.getItem(api.storageKey)) {
    await run(async () => {
      try { await resolve(); if (role) await load(); }
      catch (error) { if ([400,401,403].includes(error.status)) { api.clear(); reset(); } throw error; }
    });
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden && role && !design && !busy) run(() => load()); });
  setInterval(async()=>{if(!document.hidden&&!design&&!busy&&role==='doctor'&&modules){await modules.loadAlerts();if(notificationsOpen&&!busy)render();else if(page==='notifications')modules.ui.repaint();const badge=document.querySelector('.notification-count');if(badge){badge.textContent=String(modules.unreadAlerts);badge.hidden=!modules.unreadAlerts;}const alert=document.querySelector('#doctor-alert-live');if(alert){const latest=modules.alerts.find(n=>!n.read_at);alert.textContent=latest?latest.title:'';alert.hidden=!latest;}}},30000);
  // Avisos del paciente cada 30 s en primer plano (resultados, citas, recetas, solicitudes).
  setInterval(async()=>{if(document.hidden||design||busy||role!=='patient'||!patientNotices)return;try{await patientNotices.load('notifications');}catch{return;}
    if(notificationsOpen&&!busy)render();else{const badge=document.querySelector('.notification-count');if(badge){const unread=patientUnread();badge.textContent=String(unread);badge.hidden=!unread;}}},30000);
  // Agenda: sin Realtime en la app. Lee planning_revision (una fila) y solo vuelve a pedir la agenda si cambió.
  let planningRevision=null;
  setInterval(async()=>{if(document.hidden||design||busy||role!=='doctor'||page!=='consultation'||!modules||modules.selected)return;
    let revision=null;try{revision=await api.planningRevision();}catch{return;}
    if(revision!==null&&planningRevision!==null&&revision===planningRevision)return;planningRevision=revision;if(!busy&&!modules.selected)run(()=>modules.load('consultation'));},30000);
  setInterval(() => { if (!document.hidden && !design && !busy && ((role === 'patient' && ['turns','notifications'].includes(page)) || (role === 'doctor' && ['home','patients','notifications','turns'].includes(page)))) run(() => load()); },30000);
})();
