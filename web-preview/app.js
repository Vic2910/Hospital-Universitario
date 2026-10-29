(async function () {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const app = $('#app'), notice = $('#notice');
  let api, modules, catalog, fixtures, access = null, roles = [], role = null, page = 'home', search = '', busy = false, design = false;
  let profile = null, summary = null, overview = null, items = [], queue = [], cursor = null, more = false;
  let screenNote = '';
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
  function clearData() { modules?.clear(); profile = summary = overview = null; items = []; queue = []; cursor = null; more = false; screenNote = ''; }
  function reset() { access = null; roles = []; role = null; page = 'home'; clearData(); }
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
      modules.configure(access,role,facility);
      if (modules.supports(role,page)) { await modules.load(page,append); return; }
      if (page === 'home') {
        summary = null;
        const from = new Date(); from.setHours(0, 0, 0, 0);
        const to = new Date(from); to.setDate(to.getDate() + (role === 'patient' ? 31 : 1));
        if (facility) {
          try { summary = await api.rpc('my_activity_summary', { p_facility: facility, p_from: from.toISOString(), p_to: to.toISOString(), p_context: role === 'doctor' ? 'staff' : 'patient' }); }
          catch (error) { if (error.status !== 403) throw error; screenNote = 'Se requiere verificación adicional o autorización para consultar el resumen.'; }
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
    run(async () => { page = id; search = ''; items = []; queue = []; more = false; cursor = null; await load(); });
  }
  function displayName() {
    if (design) return fixtures[role].name;
    return access?.profile?.preferred_name || (profile?.person ? `${profile.person.given_names} ${profile.person.family_names}` : role === 'doctor' ? 'Doctor' : 'Paciente');
  }
  function title() { return page === 'home' ? 'Hola, ' + displayName() : definition()?.title || ({ more: 'Más', health: 'Mi salud', rooms: 'Habitaciones' })[page] || 'Hospital'; }
  function render() {
    app.replaceChildren();
    document.body.classList.toggle('authenticated', !!role);
    if (!access) return renderLogin();
    if (!role) return renderRoles();
    renderPortal();
  }
  function renderLogin() {
    const view = el('section', null, 'login');
    view.append(el('div', '✚', 'mark'), el('p', 'HOSPITAL UNIVERSITARIO', 'eyebrow'), el('h1', 'Tu salud,\nen buenas manos.'), el('h2', 'Iniciar sesión'), el('p', 'Accede a tu espacio de Médico o Paciente.', 'muted'));
    const form = el('form');
    for (const [id, label, type, placeholder] of [['email', 'Correo electrónico', 'email', 'nombre@correo.com'], ['password', 'Contraseña', 'password', 'Introduce tu contraseña']]) {
      const fieldLabel = el('label', label); fieldLabel.htmlFor = id;
      const field = el('input'); Object.assign(field, { id, name: id, type, placeholder, required: true, disabled: busy, autocomplete: id === 'email' ? 'username' : 'current-password' });
      form.append(fieldLabel, field);
    }
    const reveal = button('Mostrar contraseña', () => {
      const field = $('#password'); field.type = field.type === 'password' ? 'text' : 'password'; reveal.textContent = field.type === 'password' ? 'Mostrar contraseña' : 'Ocultar contraseña';
    }, 'text-button reveal');
    const submit = el('button', busy ? 'Conectando…' : 'Iniciar sesión', 'primary'); submit.type = 'submit'; submit.disabled = busy || !api;
    form.append(reveal, submit);
    form.addEventListener('submit', event => {
      event.preventDefault(); if (!form.reportValidity() || busy) return;
      const email = $('#email').value, password = $('#password').value; $('#password').value = '';
      run(async () => {
        try { await api.signIn(email, password); await resolve(); }
        catch (error) { await api.signOut(); reset(); throw error; }
        if (role) await load();
      });
    });
    view.append(form, el('p', 'Tu perfil y tus permisos son asignados por el hospital.', 'login-footer')); app.append(view);
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
    header.append(line, el('h1', title()), el('p', screen?.subtitle || 'Servicios y consultas del hospital'));
    const searchbox = el('div', null, 'searchbox'), field = el('input');
    field.type = 'search'; field.placeholder = screen?.search || 'Buscar servicios…'; field.value = search; field.setAttribute('aria-label', field.placeholder);
    field.addEventListener('input', () => { search = field.value; const content = $('#screen-content'); if (content) renderContent(content); });
    searchbox.append(el('span', '⌕'), field);
    const content = el('div', null, 'screen-content'); content.id = 'screen-content'; content.setAttribute('aria-busy', String(busy)); renderContent(content);
    portal.append(header, searchbox, content, bottomBar()); app.append(portal);
  }
  function bottomBar() {
    const nav = el('nav', null, 'bottom-nav'); nav.setAttribute('aria-label', 'Navegación principal');
    const tabs = role === 'doctor' ? [['home','Inicio'],['patients','Pacientes'],['appointments','Mis citas'],['consultation','Consultas'],['more','Más']] : [['home','Inicio'],['appointments','Mis citas'],['health','Salud'],['profile','Perfil'],['more','Más']];
    const active = ['more','rooms','health'].includes(page) ? (page === 'health' ? 'health' : 'more') : definition()?.tab;
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
    if (!design && modules.supports(role,page) && page !== 'profile') {
      modules.configure(access,role,access.roles.find(item => item.code === role)?.facility_id);
      return modules.render(content,page,search);
    }
    if (page === 'home') return home(content);
    if (page === 'more' || page === 'health') return menu(content);
    if (page === 'rooms') return rooms(content);
    if (page === 'turns') return role === 'doctor' ? schedule(content) : queueView(content);
    if (page === 'profile') return profileView(content);
    if (page === 'information') return information(content);
    if (page === 'chart' && design) {
      const rows = fixtures[role].rows.chart;
      content.append(row(...rows[0])); heading(content, screen.section); dataRows(content,rows.slice(1),false); return;
    }
    heading(content, page === 'appointments' && role === 'doctor' ? (design ? 'Viernes 23 de octubre' : new Intl.DateTimeFormat('es-SV',{weekday:'long',day:'numeric',month:'long'}).format(new Date())) : screen?.section || title());
    if (screen?.layout === 'request' || screen?.layout === 'consultation') return formScaffold(content, screen);
    if (['laboratory','patients'].includes(screen?.layout)) content.append(el('p', screen.layout === 'patients' ? 'Todos　⌄　　Atención actual　⌄' : 'Estado: Todos　⌄' + (role === 'doctor' ? '　　Prioridad: Todas　⌄' : ''), 'filters'));
    if (page === 'appointments' && role === 'doctor') content.append(el('p','‹　Hoy　›　　Estado: Todas　⌄','filters'));
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
    if (screen?.layout === 'appointments' && role === 'patient') content.append(button('Solicitar nueva cita', () => go('request'), 'primary'));
  }
  function home(content) {
    heading(content, definition().section);
    const patient = role === 'patient';
    const metrics = design ? fixtures[role].metrics : patient ? [[summary?.upcoming_appointments,'Próximas citas','appointments'],[summary?.new_results,'Resultado nuevo','laboratory'],[summary?.active_prescriptions,'Recetas activas','prescriptions'],[summary?.tickets?.[0]?.number,'Turno actual','turns']] : [[summary?.scheduled_appointments,'Citas programadas','appointments'],[summary?.waiting_patients,'Pacientes en espera','patients'],[summary?.new_results,'Resultados nuevos','laboratory'],[summary?.pending_prescriptions,'Recetas pendientes','prescriptions']];
    const grid = el('div', null, 'metric-grid');
    for (const [value,label,id] of metrics) { const node = button(null, () => go(id), 'metric'); node.append(el('strong', value == null ? '—' : String(value)), el('span', label)); grid.append(node); }
    content.append(grid); heading(content, patient ? 'Accesos rápidos' : 'Accesos clínicos');
    const shortcuts = patient ? [['request','Solicitar atención'],['appointments','Mis citas'],['chart','Mi expediente'],['laboratory','Laboratorio']] : [['patients','Mis pacientes'],['consultation','Iniciar consulta'],['laboratory','Laboratorio'],['prescriptions','Recetas']];
    const actions = el('div', null, 'shortcut-grid');
    for (const [id,label] of shortcuts.filter(([,label]) => matches(label))) { const node = button(null, () => go(id), 'shortcut'); node.append(el('span', glyphs[id] || '✚'), el('strong', label)); actions.append(node); }
    content.append(actions);
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
    const person = design ? fixtures[role].fullName : displayName(), email = design ? fixtures[role].email : profile?.auth_email || 'No disponible';
    const card = el('article', null, 'profile-card'), initials = design ? fixtures[role].initials : person.split(' ').slice(0,2).map(word => word[0]).join('');
    const details = el('div'); details.append(el('h3', person), el('p', design ? (role === 'doctor' ? 'Medicina interna' : 'Paciente · EXP-001285') : HospitalCore.labels[role]), badge(role === 'doctor' ? 'Médico activo' : 'Cuenta activa'));
    card.append(el('div', initials, 'avatar'), details); content.append(card); heading(content, definition().section);
    content.append(row(role === 'doctor' ? 'Correo institucional' : 'Correo electrónico', email));
    if (role === 'doctor') content.append(row('Especialidad', design ? 'Medicina interna' : 'Verificación institucional'), row('Identificación profesional', profile?.professional?.license_number || 'Verificación institucional'));
    else if (design) content.append(row('Teléfono', 'Número por configurar'), row('Contacto de emergencia', 'Información por actualizar'));
    if (!design) {
      modules.configure(access,role,access.roles.find(item => item.code === role)?.facility_id);
      modules.render(content,'profile',search);
    }
    content.append(button('Notificaciones　›', () => go('notifications'), 'menu-row'), button('Cerrar sesión', logout, 'logout'));
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
    $('#preview-mode').textContent = design ? 'MODO DISEÑO · Datos de ejemplo locales. Sin sesión y sin conexión a Supabase.' : 'Conexión real a Supabase. Inicia sesión con una cuenta autorizada.';
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
    modules = new HospitalModules(api,{el,button,row,run,message,go,period:formatPeriod,busy:() => busy});
    if (sessionStorage.getItem(api.storageKey)) {
      busy = true;
      try { await resolve(); if (role) await load(); } catch (error) { api.clear(); reset(); message(error.message); }
      finally { busy = false; }
    }
  } catch (error) { message(error.message); }
  $('#design-patient').addEventListener('click', () => enterDesign('patient'));
  $('#design-doctor').addEventListener('click', () => enterDesign('doctor'));
  $('#live-mode').addEventListener('click', () => { if (!design || busy) return; design = false; reset(); message(null); setModeLabel(); render(); });
  render();
  document.addEventListener('visibilitychange', () => { if (!document.hidden && role && !design && !busy) run(() => load()); });
  setInterval(() => { if (!document.hidden && !design && !busy && ((role === 'patient' && ['turns','notifications'].includes(page)) || (role === 'doctor' && ['home','patients','notifications'].includes(page)))) run(() => load()); },30000);
})();
