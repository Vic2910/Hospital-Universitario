(async function () {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const app = $('#app'), notice = $('#notice');
  let api, modules, doctorDashboard, doctorConsultations, labDesign, patientHistory, patientPrescriptions, appointmentFlow, catalog, fixtures, access = null, roles = [], role = null, page = 'home', search = '', busy = false, design = false;
  let profile = null, summary = null, overview = null, items = [], queue = [], cursor = null, more = false;
  let homeAppointments = null;
  let screenNote = '';
  let registerOpen = false;
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
  function clearData() { receptionPreview=false; appointmentFlow?.reset(); patientHistory?.clear(); labConnected = false; labDesign?.reset(); doctorConsultations?.clear(); doctorDashboard?.clear(); resetSchedule(); modules?.clear(); profile = summary = overview = null; homeAppointments = null; items = []; queue = []; cursor = null; more = false; screenNote = ''; }
  function reset() { access = null; roles = []; role = null; page = 'home'; registerOpen = false; clearData(); }
  async function run(action) {
    if (busy) return;
    busy = true; message(null); render();
    try { await action(); } catch (error) {
      if (error.status === 401) { api.clear(); reset(); }
      if (error.status === 403) modules?.clear();
      message(error.message || 'No se pudo completar la operación.');
    }
    finally { busy = false; render(); }
  }
  async function resolve() {
    const current = await api.access();
    if (!current.roles.length) throw new Error('Tu cuenta debe estar activa y vinculada a un Médico o Paciente con el rol correspondiente.');
    access = current.access; roles = current.roles;
    role = roles.length === 1 ? roles[0] : null; page = 'home';
  }
  async function load(append = false) {
    if (design || !role) return;
    try {
      const current = await api.access();
      if (!current.roles.includes(role)) { api.clear(); reset(); throw new Error('El acceso cambió. Inicia sesión de nuevo.'); }
      access = current.access; roles = current.roles; screenNote = '';
      if (!profile) profile = await api.rpc('my_profile');
      const facility = access.roles.find(item => item.code === role)?.facility_id;
      if (role==='patient'&&['request','schedule'].includes(page)) { modules.configure(access,role,facility); await modules.load('request'); return; }
      if (page === 'profile') { profile = await api.rpc('my_profile'); modules.configure(access,role,facility); await modules.load('profile'); return; }
      modules.configure(access,role,facility);
      if (role === 'doctor' && ['patients','chart','laboratory'].includes(page) && !labConnected) return;
      if (modules.supports(role,page)) { await modules.load(page,append); return; }
      if (page === 'home') {
        summary = null;
        const from = new Date(); from.setHours(0, 0, 0, 0);
        const to = new Date(from); to.setDate(to.getDate() + (role === 'patient' ? 31 : 1));
        if (facility) {
          try { summary = await api.rpc('my_activity_summary', { p_facility: facility, p_from: from.toISOString(), p_to: to.toISOString(), p_context: role === 'doctor' ? 'staff' : 'patient' }); }
          catch (error) { if (error.status !== 403) throw error; screenNote = 'Se requiere verificación adicional o autorización para consultar el resumen.'; }
        }
        if (role === 'patient' && facility) {
          homeAppointments = await api.rpc('mobile_module', { p_role: 'patient', p_module: 'appointments', p_facility: facility, p_from: null, p_to: null, p_query: '', p_cursor: null, p_limit: 25 });
        }
      } else if (page === 'rooms' || page === 'turns') {
        if (!append) { items = []; queue = []; cursor = null; more = false; }
        const resource = page === 'rooms' ? 'rooms' : HospitalCore.turnResource(role);
        const owner = role === 'doctor' ? access.staff_id : access.patient_id;
        const result = await api.read(resource, append ? cursor : null, owner);
        items = append ? [...items, ...result.data] : result.data; cursor = result.next_cursor; more = result.has_more;
        if (resource === 'queue_tickets') {
          for (const ticket of result.data.filter(item => ['waiting', 'called', 'in_service'].includes(item.status))) queue.push(await api.rpc('my_queue_status', { p_ticket: ticket.id }));
        }
      } else if (page === 'information') overview = facility ? await api.rpc('hospital_overview', { p_facility: facility }) : null;
      else if (page === 'profile') profile = await api.rpc('my_profile');
    } catch (error) {
      clearData();
      if (error.status === 401) { api.clear(); reset(); }
      throw error;
    }
  }
  function go(id) {
    if (busy) return;
    run(async () => { if(receptionPreview){receptionPreview=false;setModeLabel();} if(['request','schedule'].includes(page)&&!['request','schedule'].includes(id))resetSchedule(); if(id==='appointments'&&page!==id)appointmentFlow.selected=false; if(page === 'history' && id !== page)patientHistory?.clear(); if (page === 'patients' && id !== page) { doctorDashboard?.clear(); labDesign.modal=''; } if(id === 'patients' && page !== id)labDesign.modal=''; page = id; search = ''; items = []; queue = []; more = false; cursor = null; await load(); });
  }
  function displayName() {
    if (design) return fixtures[role].name;
    return access?.profile?.preferred_name || (profile?.person ? `${profile.person.given_names} ${profile.person.family_names}` : role === 'doctor' ? 'Doctor' : 'Paciente');
  }
  function title() { return receptionPreview ? 'Recepción de ejemplo' : page === 'home' ? 'Hola, ' + displayName() : definition()?.title || ({ more: 'Más', health: 'Mi salud', rooms: 'Habitaciones', schedule: 'Solicitar atención' })[page] || 'Hospital'; }
  function render() {
    app.replaceChildren();
    document.body.classList.toggle('authenticated', !!role);
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
    switchRow.append(el('span', '¿No tienes cuenta?'), button('Regístrate', () => { registerOpen = true; render(); }, 'link-button'));
    view.append(card, switchRow, el('p', 'Tu perfil y tus permisos son asignados por el hospital.', 'auth-footer'));
    app.append(view);
  }
  // Sede única activa del hospital (hospital.facilities, código CENTRAL).
  const REGISTRATION_FACILITY = '3d101c8a-8974-4e2c-9144-1e777f632589';
  function registrationDraft() {
    return {
      facility: REGISTRATION_FACILITY,
      given: $('#reg-given').value.trim(),
      family: $('#reg-family').value.trim(),
      birthDate: $('#reg-birth').value,
      sex: $('#reg-sex').value,
      dui: $('#reg-dui').value.trim(),
      phone: $('#reg-phone').value.trim()
    };
  }
  function registerProblem() {
    const given = $('#reg-given').value.trim(), family = $('#reg-family').value.trim();
    const duiDigits = $('#reg-dui').value.replace(/\D/g, '');
    const birthValue = $('#reg-birth').value;
    const phoneDigits = $('#reg-phone').value.replace(/\D/g, '');
    const email = $('#reg-email').value.trim();
    if (!given || given.length > 100) return 'Introduce tus nombres (máximo 100 caracteres).';
    if (!family || family.length > 100) return 'Introduce tus apellidos (máximo 100 caracteres).';
    if (duiDigits.length !== 9) return 'El DUI debe contener 9 dígitos, por ejemplo 01234567-8.';
    if (!birthValue) return 'Introduce tu fecha de nacimiento.';
    const birth = new Date(birthValue + 'T00:00:00');
    if (Number.isNaN(birth.getTime())) return 'Introduce una fecha de nacimiento válida.';
    const today = new Date(); today.setHours(0, 0, 0, 0);
    if (birth > today) return 'La fecha de nacimiento no puede ser futura.';
    if (birth < new Date('1900-01-01T00:00:00')) return 'La fecha de nacimiento debe ser igual o posterior a 1900.';
    if (!['female', 'male', 'intersex', 'unknown'].includes($('#reg-sex').value)) return 'Selecciona tu sexo administrativo.';
    if (phoneDigits.length !== 8) return 'El teléfono debe contener 8 dígitos, por ejemplo 7123-4567.';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return 'Introduce un correo electrónico válido.';
    if ($('#reg-password').value.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
    if ($('#reg-confirm').value !== $('#reg-password').value) return 'La confirmación de contraseña no coincide.';
    return null;
  }
  function renderRegister() {
    const view = el('section', null, 'auth-view');
    view.append(authHeader('Crear cuenta', 'Completa tus datos para solicitar tu acceso.'));
    const successText = 'Solicitud enviada. El hospital la revisará y, al aprobarla, activará tu cuenta y quedará vinculada a tu expediente.';

    // --- Formulario ---
    const formCard = el('div', null, 'auth-card');
    const form = el('form');
    for (const [id, label, type, placeholder, autocomplete] of [
      ['reg-given', 'Nombres', 'text', 'Tus nombres', 'given-name'],
      ['reg-family', 'Apellidos', 'text', 'Tus apellidos', 'family-name'],
      ['reg-dui', 'DUI', 'text', '00000000-0', 'off']
    ]) {
      const field = authField(id, label, type, placeholder, autocomplete);
      if (id === 'reg-dui') field.querySelector('input').addEventListener('input', event => {
        const digits = event.target.value.replace(/\D/g, '').slice(0, 9);
        event.target.value = digits.length > 8 ? digits.slice(0, 8) + '-' + digits.slice(8) : digits;
      });
      form.append(field);
    }
    form.append(authField('reg-birth', 'Fecha de nacimiento', 'date', '', 'bday'));
    const sexWrap = el('div', null, 'auth-field');
    const sexLabel = el('label', 'Sexo administrativo'); sexLabel.htmlFor = 'reg-sex';
    const sexSelect = el('select'); sexSelect.id = 'reg-sex'; sexSelect.name = 'reg-sex'; sexSelect.disabled = busy;
    for (const [value, label] of [['female', 'Femenino'], ['male', 'Masculino'], ['intersex', 'Intersex'], ['unknown', 'Desconocido']]) {
      const option = el('option', label); option.value = value; sexSelect.append(option);
    }
    sexWrap.append(sexLabel, sexSelect);
    form.append(sexWrap);
    const phoneField = authField('reg-phone', 'Teléfono', 'tel', '0000-0000', 'tel');
    phoneField.querySelector('input').addEventListener('input', event => {
      const digits = event.target.value.replace(/\D/g, '').slice(0, 8);
      event.target.value = digits.length > 4 ? digits.slice(0, 4) + '-' + digits.slice(4) : digits;
    });
    form.append(phoneField);
    form.append(authField('reg-email', 'Correo electrónico', 'email', 'nombre@correo.com', 'username'));
    form.append(authField('reg-password', 'Contraseña', 'password', 'Contraseña', 'new-password', revealButton('reg-password')));
    form.append(authField('reg-confirm', 'Confirmar contraseña', 'password', 'Repite tu contraseña', 'new-password', revealButton('reg-confirm')));
    const problem = el('p', null, 'auth-error'); problem.hidden = true;
    form.append(el('p', 'El hospital revisa y activa cada cuenta. Al enviar, crearás tu acceso y tu solicitud quedará en espera de aprobación.', 'auth-notice'), problem);
    const submit = el('button', 'Registrarme', 'primary'); submit.type = 'submit';
    form.append(submit);
    const formSwitch = el('div', null, 'auth-link-row');
    formSwitch.append(el('span', '¿Ya tienes cuenta?'), button('Inicia sesión', () => { registerOpen = false; render(); }, 'link-button'));
    formCard.append(form, formSwitch);
    view.append(formCard);
    app.append(view);

    const setBusy = state => { submit.disabled = state; };
    function showSuccess() {
      formCard.hidden = true;
      const doneCard = el('div', null, 'auth-card');
      doneCard.append(el('p', successText, 'auth-notice'),
        button('Volver a iniciar sesión', () => { registerOpen = false; render(); }, 'primary'));
      view.append(doneCard);
    }
    // Registro en un solo paso: signUp y envío de la solicitud. Si el signUp no
    // entrega sesión, se intenta iniciar una vez como respaldo antes de enviar.
    async function doSubmit() {
      const issue = registerProblem();
      if (issue) { problem.textContent = issue; problem.hidden = false; return; }
      problem.hidden = true; setBusy(true);
      try {
        const hasSession = await api.signUp($('#reg-email').value.trim(), $('#reg-password').value);
        if (!hasSession) await api.signIn($('#reg-email').value, $('#reg-password').value);
        await api.submitPatientRegistration(registrationDraft());
        await api.signOut();
        showSuccess();
      } catch (error) {
        problem.textContent = error.message || 'No se pudo crear la cuenta. Inténtalo de nuevo.';
        problem.hidden = false;
      } finally { setBusy(false); }
    }
    form.addEventListener('submit', event => {
      event.preventDefault();
      if (!form.reportValidity() || submit.disabled) return;
      doSubmit();
    });
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
    const bell = button('♧', () => go('notifications'), 'bell'); bell.setAttribute('aria-label', 'Notificaciones');
    line.append(el('span', 'Hospital Universitario'), bell);
    header.append(line, el('h1', title()), el('p', screen?.subtitle || (page === 'schedule' ? 'Elige especialidad y horario' : 'Servicios y consultas del hospital')));
    const searchbox = el('div', null, 'searchbox'), field = el('input');
    field.type = 'search'; field.placeholder = screen?.search || 'Buscar servicios…'; field.value = search; field.setAttribute('aria-label', field.placeholder);
    field.addEventListener('input', () => { search = field.value; const content = $('#screen-content'); if (content) renderContent(content); });
    searchbox.append(el('span', '⌕'), field);
    const content = el('div', null, 'screen-content'); content.id = 'screen-content'; content.setAttribute('aria-busy', String(busy)); renderContent(content);
    const clinicalFlow = ['patients','chart','laboratory'].includes(page) && (design || (role === 'doctor' && !labConnected));
    if(clinicalFlow || page === 'profile' || (role === 'patient' && page === 'chart')) { portal.className += ' clinical-flow'; portal.append(header,content,bottomBar()); }
    else portal.append(header,searchbox,content,bottomBar());
    app.append(portal);
  }
  function bottomBar() {
    const nav = el('nav', null, role === 'doctor' ? 'bottom-nav doctor-nav' : 'bottom-nav'); nav.setAttribute('aria-label', 'Navegación principal');
    const tabs = role === 'doctor' ? [['home','Inicio'],['patients','Pacientes'],['consultation','Consultas'],['laboratory','Laboratorios'],['more','Más']] : [['home','Inicio'],['appointments','Mis citas'],['health','Salud'],['profile','Perfil'],['more','Más']];
    const active = ['more','rooms','health'].includes(page) ? (page === 'health' ? 'health' : 'more') : page === 'schedule' ? 'home' : definition()?.tab;
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
    if(role==='patient'&&['request','schedule'].includes(page))return scheduleView(content);
    if(role==='patient'&&page==='appointments'){
      return appointmentFlow.render(content,{appointments:design?appointmentFlow.appointments:HospitalPatientAppointments.fromItems(modules.items,profile,formatConsultationTime),demonstration:design,
        requests:design?appointmentFlow.requests:null,
        renderConnected:!design&&(modules.items.length||!modules.data)?parent=>modules.render(parent,'appointments',search):null});
    }
    if(role === 'patient' && page === 'prescriptions') {
      return patientPrescriptions.render(content,{records:design?HospitalPatientPrescriptions.examples:HospitalPatientPrescriptions.fromItems(modules.items),demonstration:design,search,loading:busy,
        error:!design&&!busy&&!modules.data?'No pudimos cargar tus recetas. Intenta de nuevo.':null,hasMore:!design&&modules.data?.has_more,retry:()=>run(()=>load()),loadMore:()=>run(()=>modules.load('prescriptions',true))});
    }
    if(role === 'patient' && page === 'history') {
      return patientHistory.render(content,{records:design?HospitalPatientHistory.examples:HospitalPatientHistory.fromItems(modules.items),demonstration:design,search,loading:busy,
        error:!design&&!busy&&!modules.data?'No pudimos cargar tu historial. Intenta de nuevo.':null,hasMore:!design&&modules.data?.has_more,
        retry:()=>run(()=>load()),loadMore:()=>run(()=>modules.load('history',true))});
    }
    if (!design && role === 'doctor' && ['patients','chart','laboratory'].includes(page)) {
      content.append(button(labConnected ? 'Ver diseño de expediente y laboratorios' : 'Ver flujo conectado', () => run(async () => { labConnected = !labConnected; await load(); }), 'text-button'));
      if (!labConnected) {
        labDesign.configureDoctor(modules.workspace?.doctor_name || (profile?.person ? profile.person.given_names+' '+profile.person.family_names : displayName()),access.staff_id || access.profile.id,modules.workspace?.facility_name);
        return labDesign.render(content,{role,page});
      }
    }
    if (design && ['patients','chart','laboratory'].includes(page)) return labDesign.render(content,{role,page});
    if (!design && modules.supports(role,page) && page !== 'profile') {
      modules.configure(access,role,access.roles.find(item => item.code === role)?.facility_id);
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
    if (page === 'profile') {
      profileView(content);
      if (!design && modules.supports(role,'profile')) {
        modules.configure(access,role,access.roles.find(item => item.code === role)?.facility_id);
        modules.render(content,'profile',search);
      }
      return;
    }
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
      content.append(el('p', 'La emisión de recetas requiere iniciar sesión y contar con una consulta abierta.', 'rose-note'));
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
    const name = displayName();
    const greeting = el('article', null, 'dash-greeting');
    const text = el('div', null, 'dash-text');
    text.append(el('h2', 'Hola, ' + name + ' 👋'), el('p', 'Aquí está el resumen de tu día.'));
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
    if (design) {
      const sample = fixtures.patient.rows.appointments[0];
      card.append(el('p', '30 de octubre', 'dash-cita-day'), el('strong', '10:00', 'dash-time'), el('p', sample[1], 'dash-medico'));
    } else {
      const upcoming = (homeAppointments?.items || [])
        .filter(item => ['scheduled','confirmed'].includes(item.status) && Date.parse(item.event_at) >= Date.now())
        .sort((a,b) => Date.parse(a.event_at) - Date.parse(b.event_at))[0];
      if (upcoming) {
        const field = label => upcoming.details?.find(value => value.label.toLocaleLowerCase('es') === label.toLocaleLowerCase('es'))?.value;
        let bounds = null; try { bounds = field('Horario') ? HospitalCore.periodBounds(field('Horario')) : null; } catch { bounds = null; }
        const date = new Date(upcoming.event_at);
        card.append(el('p', new Intl.DateTimeFormat('es-SV', { day: 'numeric', month: 'long' }).format(date), 'dash-cita-day'),
          el('strong', bounds ? new Intl.DateTimeFormat('es-GT', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(bounds.start)) : 'Horario por confirmar', 'dash-time'),
          el('p', field('Medico') || upcoming.title, 'dash-medico'));
      } else {
        card.append(el('strong', 'No tienes citas programadas.', 'dash-empty'), el('p', 'Solicita una atención desde «Solicitar atención».', 'dash-medico'));
      }
    }
    content.append(card);
    heading(content, 'Accesos rápidos');
    const grid = el('div', null, 'dash-grid');
    for (const [id, label, icon] of [['appointments', 'Mis citas', '▦'], ['laboratory', 'Laboratorios', '⚗'], ['chart', 'Expedientes', '▤'], ['prescriptions', 'Recetas', '▤']]) {
      if (!matches(label)) continue;
      const node = button(null, () => go(id), 'dash-card');
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
  // Paciente de prueba precargado: solo se usa en modo diseño; la sesión real usa la cuenta autenticada.
  const dayKey = date => new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
  const tomorrowKey = () => { const date = new Date(); date.setDate(date.getDate() + 1); return dayKey(date); };
  const scheduleState = {
    fields: { nombres: 'Gaby', apellidos: 'Diaz', dui: '0123-45678', telefono: '7123-4567', correo: 'gaby.diaz@ejemplo.test' },
    symptoms: new Set(), specialty: null, slot: null, date: tomorrowKey(), reason: '', preference: '', prepared: false
  };
  function resetSchedule() {
    Object.assign(scheduleState, {
      fields: { nombres: 'Gaby', apellidos: 'Diaz', dui: '0123-45678', telefono: '7123-4567', correo: 'gaby.diaz@ejemplo.test' },
      symptoms: new Set(), specialty: null, slot: null, date: tomorrowKey(), reason: '', preference: '', prepared: false
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
    if (!scheduleState.prepared) return;
    if (!design) {
      if (!scheduleState.specialty || !['Mañana','Tarde'].includes(scheduleState.preference) || !/^\d{4}-\d{2}-\d{2}$/.test(scheduleState.date)) return;
      const note = el('article', null, 'sched-success');
      note.id = 'sched-feedback'; note.setAttribute('role', 'status');
      const text = el('div', null, 'sched-success-text');
      text.append(el('strong', 'Solicitud enviada'), el('p', scheduleState.specialty.name + ' · ' + scheduleState.date + ' · ' + scheduleState.preference),
        el('p', 'Recepción confirmará la fecha y hora de tu atención.'));
      note.append(el('span', '✓', 'sched-success-icon'), text);
      content.append(note);
      return;
    }
    if (!scheduleState.specialty || !scheduleState.slot) return;
    const note = el('article', null, 'sched-success');
    note.id = 'sched-feedback'; note.setAttribute('role', 'status');
    const text = el('div', null, 'sched-success-text');
    text.append(el('strong', 'Solicitud Pendiente'), el('p', scheduleState.specialty.name + ' · ' + scheduleState.slot.day + ' · ' + scheduleState.slot.time),
      el('p', 'Solicitud de ejemplo guardada como Pendiente. Recepción debe asignar una cita; no se envió al hospital.'));
    note.append(el('span', '✓', 'sched-success-icon'), text);
    content.append(note);
  }
  function schedulePatientCard() {
    const wrap = el('div', null, 'sched-fields');
    const person = profile?.person;
    const phone = (profile?.contacts || []).find(item => item.kind === 'phone' && item.is_primary)?.value
      || (profile?.contacts || []).find(item => item.kind === 'phone')?.value || '';
    const name = [person?.given_names, person?.family_names].filter(Boolean).join(' ');
    wrap.append(el('p', 'Datos de tu perfil del hospital. Para actualizarlos usa «Perfil».', 'sched-hint'));
    for (const [label, value] of [['Nombres y apellidos', name], ['Correo electrónico', profile?.auth_email || ''], ['Teléfono', phone]]) {
      const field = el('div', null, 'sched-field');
      field.append(el('span', label), el('strong', value || 'No registrado'));
      wrap.append(field);
    }
    return scheduleFormCard('Datos del paciente', '👤', wrap);
  }
  function scheduleView(content) {
    const real = !design;
    const intro = el('article', null, 'sched-intro');
    intro.append(el('span', 'TU SALUD, A TU TIEMPO', 'sched-eyebrow'), el('h2', 'Preparemos tu próxima cita'),
      el('p', 'Completa tus datos, cuéntanos cómo te sientes y elige tu atención.'),
      el('small', real ? 'La solicitud se envía a la central de citas del hospital.' : 'Paciente y horarios de prueba · No se envía al hospital'));
    content.append(intro);
    content.append(real ? schedulePatientCard() : scheduleFormCard('Datos del paciente', '👤', (() => {
      const wrap = el('div', null, 'sched-fields');
      wrap.append(el('p', 'Datos de prueba. Puedes editarlos para agendar para otra persona.', 'sched-hint'));
      wrap.append(scheduleField('Nombres', 'nombres', 'Nombres'), scheduleField('Apellidos', 'apellidos', 'Apellidos'),
        scheduleField('DUI', 'dui', '0000-00000'), scheduleField('Teléfono', 'telefono', '0000-0000', 'tel'),
        scheduleField('Correo electrónico', 'correo', 'nombre@correo.com', 'email'));
      return wrap;
    })()));
    content.append(scheduleFormCard('Síntomas frecuentes', '♡', (() => {
      const wrap = el('div', null, 'sched-wrap');
      wrap.append(el('p', real ? 'Se añadirán al motivo de la consulta. Puedes elegir varios.' : 'Selecciona lo que te aplica. Puedes elegir varios.', 'sched-hint'));
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
      const list = real ? (modules.data?.options || []).filter(item => item.kind === 'specialty').map(item => ({ id: item.id, name: item.name, icon: '✚', slots: [] })) : specialtyList;
      for (const specialty of list) {
        const active = real ? scheduleState.specialty?.id === specialty.id : scheduleState.specialty === specialty;
        const node = button(null, () => {
          scheduleState.prepared = false;
          if (active) { scheduleState.specialty = null; scheduleState.slot = null; }
          else { scheduleState.specialty = specialty; scheduleState.slot = null; }
          repaintSchedule();
        }, active ? 'sched-chip is-selected' : 'sched-chip');
        node.setAttribute('aria-pressed', String(active));
        node.setAttribute('data-choice', 'specialty-' + list.indexOf(specialty));
        node.append(el('span', specialty.icon), el('span', specialty.name));
        grid.append(node);
      }
      wrap.append(grid);
      if (real && !list.length) wrap.append(el('p', 'No hay especialidades publicadas por el hospital.', 'sched-hint'));
      if (!real) {
        const slots = el('div', null, 'sched-slots');
        paintSlots(slots);
        wrap.append(slots);
      }
      return wrap;
    })()));
    if (real) {
      content.append(scheduleFormCard('Fecha preferida', '📅', (() => {
        const wrap = el('div', null, 'sched-fields');
        const label = el('label', 'Fecha de la atención', 'doctor-field'), input = el('input');
        input.type = 'date'; input.value = scheduleState.date; input.min = tomorrowKey();
        input.setAttribute('aria-label', 'Fecha preferida');
        input.addEventListener('change', () => { scheduleState.date = input.value; invalidateSchedule(); updateScheduleButton($('#screen-content')); });
        label.append(input);
        wrap.append(label, el('p', 'La fecha es una preferencia; recepción confirmará la disponibilidad.', 'sched-hint'));
        return wrap;
      })()));
    }
    const preferenceCard=scheduleFormCard('Preferencia de horario','☀',(()=>{
      const label=el('label','Preferencia de horario','doctor-field'),select=el('select');select.setAttribute('aria-label','Preferencia de horario');
      for(const value of ['', 'Mañana','Tarde']){const option=el('option',value||'Seleccionar');option.value=value;select.append(option);}select.value=scheduleState.preference;
      select.addEventListener('change',()=>{scheduleState.preference=select.value;invalidateSchedule();updateScheduleButton($('#screen-content'));});label.append(select);
      if(real)label.append(el('small','Mañana equivale a 08:00–12:00 y Tarde a 13:00–17:00; la hora exacta la confirma recepción.','sched-hint'));
      return label;
    })());content.append(preferenceCard);
    const summary = el('article', null, 'sched-summary');
    summary.append(el('strong', 'Tu selección'), el('p', real
      ? (scheduleState.specialty ? scheduleState.specialty.name + ' · ' + (scheduleState.date || 'Fecha por definir') + ' · ' + (scheduleState.preference || 'Preferencia por definir') : 'Elige una especialidad, una fecha y una preferencia horaria para continuar.')
      : (scheduleState.specialty && scheduleState.slot
        ? scheduleState.specialty.name + ' · ' + scheduleState.slot.day + ' · ' + scheduleState.slot.time
        : 'Elige una especialidad y un horario para continuar.')),
      el('small', real
        ? 'La solicitud queda pendiente de confirmación por la central de citas.'
        : 'Recepción asignará la cita. Completa todos los campos. DUI: 0000-00000; teléfono: 0000-0000; correo válido.'));
    content.append(summary);
    paintFeedback(content);
    const submit = button('Solicitar atención', () => { if (!scheduleCanSubmit() || scheduleState.prepared) return;
      if (real) {
        run(async () => {
          const facility = access.roles.find(item => item.code === role)?.facility_id;
          const symptoms = [...scheduleState.symptoms].filter(value => value !== noneSymptom);
          const reason = symptoms.length ? scheduleState.reason.trim() + '\nSíntomas: ' + symptoms.join(', ') : scheduleState.reason.trim();
          await api.rpc('request_appointment', {
            p_patient: access.patient_id, p_facility: facility, p_specialty: scheduleState.specialty.id,
            p_reason: reason, p_date: scheduleState.date,
            p_from: scheduleState.preference === 'Tarde' ? '13:00' : '08:00',
            p_to: scheduleState.preference === 'Tarde' ? '17:00' : '12:00',
            p_request_key: crypto.randomUUID()
          });
          scheduleState.prepared = true;
          await modules.load('request');
        });
      } else {
        const saved=appointmentFlow.submit({id:crypto.randomUUID(),fields:scheduleState.fields,specialty:scheduleState.specialty.name,reason:scheduleState.reason,symptoms:[...scheduleState.symptoms],preference:scheduleState.preference,preferredSlot:scheduleState.slot.day+' · '+scheduleState.slot.time});
        if(saved){scheduleState.prepared = true; repaintSchedule();}
      } }, 'primary sched-submit');
    submit.id = 'sched-submit';
    submit.disabled = !scheduleCanSubmit() || scheduleState.prepared;
    content.append(submit);
    if (real) {
      const queue = el('article', null, 'sched-card');
      queue.append(el('h2', 'Mis solicitudes', 'section-title'));
      const requests = modules.items || [];
      if (!requests.length) queue.append(el('p', 'Todavía no tienes solicitudes registradas.', 'sched-hint'));
      for (const item of requests) {
        const state = item.status === 'approved' ? 'Cita asignada' : item.status === 'rejected' ? 'Rechazada' : item.status === 'cancelled' ? 'Cancelada' : 'Pendiente';
        const card = el('article', null, 'doctor-visit');
        card.append(el('strong', item.title), el('span', state, 'clinical-lab-state ' + (item.status === 'pending' ? 'is-pending' : 'is-completed')),
          el('p', item.subtitle || 'Sin motivo registrado'));
        for (const detail of item.details || []) card.append(el('small', detail.label + ': ' + detail.value));
        queue.append(card);
      }
      content.append(queue);
    }
  }
  function scheduleCanSubmit() {
    if (!design) {
      const facility = access?.roles?.find(item => item.code === role)?.facility_id;
      return !busy && !!access?.patient_id && !!facility && !!scheduleState.specialty
        && /^\d{4}-\d{2}-\d{2}$/.test(scheduleState.date || '') && scheduleState.date >= tomorrowKey()
        && ['Mañana','Tarde'].includes(scheduleState.preference) && scheduleState.reason.trim().length > 0;
    }
    const f = scheduleState.fields;
    return ['Mañana','Tarde'].includes(scheduleState.preference) && !!scheduleState.specialty && !!scheduleState.slot && scheduleState.reason.trim().length > 0
      && !!f.nombres.trim() && !!f.apellidos.trim() && /^\d{4}-\d{5}$/.test(f.dui.trim())
      && /^\d{4}-\d{4}$/.test(f.telefono.trim()) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.correo.trim());
  }
  function updateScheduleButton(content) {
    const submit = content.querySelector('#sched-submit');
    if (submit) submit.disabled = !scheduleCanSubmit() || scheduleState.prepared;
  }
  function menu(content) {
    heading(content, page === 'health' ? 'Tu información de salud' : 'Servicios');
    for (const screen of catalog[role].filter(item => item.id !== 'home' && (page !== 'health' || item.tab === 'health') && matches(item.title))) content.append(button(screen.title + '　›', () => go(screen.id), 'menu-row'));
    if (page === 'more') {
      content.append(button('Habitaciones　›', () => go('rooms'), 'menu-row'));
      if (roles.length > 1) content.append(button('Cambiar perfil', () => { role = null; clearData(); render(); }, 'text-button'));
      content.append(button('Cerrar sesión', logout, 'logout'));
    }
  }
  function schedule(content) {
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
    if (!design) for (const shift of items.filter(item => item.status === 'pending')) content.append(button('Confirmar jornada · ' + formatPeriod(shift.period),() => run(async () => {
      await api.rpc('confirm_shift',{p_id:shift.id,p_expected_version:shift.row_version}); await load(); message('Jornada confirmada.');
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
  function queueView(content) {
    heading(content, 'Turno de atención');
    const entries = design ? [fixtures.patient.queue] : queue;
    if (!entries.length && !busy) empty(content, 'No tienes un turno activo.');
    for (const item of entries) {
      const card = el('article', null, 'ticket-card'); card.append(el('p','Tu número'), el('strong', item.display_number || String(item.number)), badge(statuses[item.status] || item.status));
      if (design) card.append(el('p','Medicina interna · Sala de espera 2'));
      content.append(card); heading(content, 'Información de la fila');
      content.append(row('Turno actual en atención', item.serving_number || 'Sin turno en atención'), row('Personas antes de ti', String(item.people_ahead)), row('Consultorio asignado', item.consultation_room?.name || 'Por asignar'));
    }
    loadMore(content);
  }
  function rooms(content) {
    heading(content, 'Habitaciones del hospital');
    const records = design ? [...Array.from({length:5}, (_,i) => ({ code:'VIP-' + (301+i), active:true })), ...Array.from({length:6}, (_,i) => ({ code:'HAB-' + (201+i), active:true }))] : items;
    for (const item of records.filter(item => matches(item.code))) content.append(row(item.code, null, item.active ? 'Activa' : 'Inactiva'));
    if (!records.length && !busy) empty(content, 'No hay habitaciones disponibles para consultar.');
    content.append(el('p', 'El estado activo no indica disponibilidad de camas.', 'scope-note')); loadMore(content);
  }
  function loadMore(content) { if (more) content.append(button('Cargar más', () => run(() => load(true)), 'menu-row')); }
  function profileView(content) {
    const clean = value => typeof value === 'string' && value.trim() ? value.trim() : 'No disponible';
    const given = clean(design ? fixtures[role].givenNames : profile?.person?.given_names);
    const family = clean(design ? fixtures[role].familyNames : profile?.person?.family_names);
    const intro = el('div',null,'identity-intro');
    const icon = el('span',[given,family].filter(value=>value!=='No disponible').map(value=>value[0]).join('') || '—','identity-icon'); icon.setAttribute('aria-hidden','true');
    intro.append(icon,el('h2','Datos de registro')); content.append(intro);
    for (const [label,value] of [['Nombre',given],['Apellido',family]]) {
      const card = el('article',null,'sched-card identity-field'); card.append(el('span',label),el('strong',value)); content.append(card);
    }
  }
  function information(content) {
    heading(content, 'Información del hospital');
    const data = design ? { capacity:17, occupied:10, on_duty:[], information:[] } : overview;
    if (design) for (const [label,detail] of [['Horario de atención','Lunes a viernes · Según servicio'],['Médicos de turno','Consulta las especialidades disponibles'],['Ocupación general','Información agregada de habitaciones'],['Comunicados','Avisos y actualizaciones del hospital']]) content.append(row(label,detail,'Consultar',true));
    else if (data) {
      content.append(row('Ocupación general', `${data.occupied} de ${data.capacity} camas`));
      heading(content,'Médicos de turno'); for (const person of data.on_duty) content.append(row(person.name,person.specialty));
      if (!data.on_duty.length) empty(content,'No hay médicos de turno publicados.');
      heading(content,'Comunicados'); for (const item of data.information) content.append(row(item.title,item.body));
    }
    content.append(button('Consultar habitaciones', () => go('rooms'), 'menu-row'), el('p','La información clínica de otros pacientes no es pública.','rose-note'));
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
    $('#preview-mode').textContent = receptionPreview ? 'MODO DISEÑO · Recepción simulada · Sin permisos ni operaciones reales.' : design ? 'MODO DISEÑO · Datos de ejemplo locales. Sin sesión y sin conexión a Supabase.' : 'Conexión real a Supabase. Inicia sesión con una cuenta autorizada.';
    document.body.classList.toggle('design-mode',design);
  }
  async function enterDesign(candidate) {
    if (busy) return;
    if (!design && access) { message('Cierra tu sesión antes de abrir el modo de diseño.'); return; }
    await run(async () => {
      if (!fixtures) fixtures = await (await fetch('/design-fixtures.json')).json();
      reset(); design = true; role = candidate; roles = [candidate];
      access = { profile:{status:'active'}, roles:[] }; setModeLabel();
    });
  }
  try {
    const [configResponse, screensResponse] = await Promise.all([fetch('/shared/contract.json',{cache:'no-store'}), fetch('/shared/screens.json',{cache:'no-store'})]);
    if (!configResponse.ok || !screensResponse.ok) throw new Error('No se pudo cargar la configuración.');
    api = new HospitalAPI(await configResponse.json()); catalog = await screensResponse.json();
    appointmentFlow=new HospitalPatientAppointments({el,button,go,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);},exitReception:()=>{receptionPreview=false;page='appointments';setModeLabel();render();}});
    patientPrescriptions = new HospitalPatientPrescriptions({el,button});
    patientHistory = new HospitalPatientHistory({el,button,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);}});
    labDesign = new HospitalClinicalLabsDesign({el,button,go,busy:()=>busy,repaint:()=>{const content=$('#screen-content');if(content)renderContent(content);}});
    doctorConsultations = new HospitalDoctorConsultations({el,button,busy:() => busy,repaint:() => { const content = $('#screen-content'); if (content) renderContent(content); }});
    doctorDashboard = new HospitalDoctorDashboard({el,button,go,run,busy:() => busy});
    modules = new HospitalModules(api,{el,button,row,run,message,go,period:formatPeriod,busy:() => busy,
      doctorConsultations:(parent,module) => {
        doctorConsultations.render(parent,{day:module.day,appointments:module.workspace.appointments,demo:false,search,period:formatConsultationTime,
          onDay:day => { module.day = day; module.select(''); module.workspace = null; run(() => module.load('consultation')); },
          onSelect:id => { module.select(id); run(() => module.loadChart()); }});
      },
      doctorDashboard:(parent,module) => {
        const workspace = module.workspace;
        doctorDashboard.render(parent,{name:workspace.doctor_name,facility:workspace.facility_name,
          count:workspace.appointments.filter(item => !['cancelled','rejected','no_show'].includes(item.status)).length});
      },
      doctorPatientHistory:(parent,module) => {
        const patients = [...new Map(module.workspace.appointments.map(item => [item.patient_id,{id:item.patient_id,name:item.patient_name,record:item.record_number}])).values()].sort((a,b) => a.name.localeCompare(b.name,'es'));
        doctorDashboard.renderHistory(parent,{patients,loadHistory:async (patient,from,to) => {
          const chart = await api.rpc('doctor_chart',{p_patient:patient,p_from:from,p_to:to,p_query:''}); return chart.history;
        }});
      }});
  } catch (error) { message(error.message); }
  $('#design-patient').addEventListener('click', () => {if(receptionPreview){receptionPreview=false;page='appointments';setModeLabel();render();}else enterDesign('patient');});
  $('#design-reception').addEventListener('click',async()=>{if(busy)return;if(!design&&access){message('Cierra tu sesión para abrir Recepción de demostración.');return;}if(!design||role!=='patient')await enterDesign('patient');if(!design||busy)return;role='patient';page='appointments';receptionPreview=true;setModeLabel();render();});
  $('#design-doctor').addEventListener('click', () => enterDesign('doctor'));
  $('#live-mode').addEventListener('click', () => { if (!design || busy) return; design = false; reset(); message(null); setModeLabel(); render(); });
  render();
  document.addEventListener('visibilitychange', () => { if (!document.hidden && role && !design && !busy) run(() => load()); });
  setInterval(() => { if (!document.hidden && !design && !busy && ((role === 'patient' && ['turns','notifications'].includes(page)) || (role === 'doctor' && ['home','patients','notifications'].includes(page)))) run(() => load()); },30000);
})();
