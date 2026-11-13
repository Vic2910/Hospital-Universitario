(function (root) {
  'use strict';
  // Solicitante sin expediente. Vista de diseño con datos de ejemplo locales:
  // no llama a Supabase, no guarda nada fuera de la memoria de la página y no crea citas.
  const core = () => root.HospitalCore;
  const PERIODS = { morning: 'Mañana · AM', afternoon: 'Tarde · PM' };
  const TITLES = { complete: 'Completa tus datos', home: 'Inicio', request: 'Solicitar atención', requests: 'Mis solicitudes' };
  const STATE_CLASS = { pending: 'is-pending', review: 'is-processing', accepted: 'is-completed', scheduled: 'is-completed', rejected: 'is-rejected', cancelled: 'is-rejected' };
  const NEXT_EXAMPLE = { pending: 'identity_verified', identity_verified: 'converted' };

  class HospitalApplicantDemo {
    constructor(deps) { this.deps = deps; this.reset(); }

    reset() {
      this.active = false; this.view = 'complete'; this.person = null; this.requests = [];
      this.draft = { specialty: '', reason: '', date: '', period: '' }; this.sequence = 0; this.busy = false;
    }
    open() { this.active = true; this.view = this.person ? 'home' : 'complete'; }
    close() { this.reset(); }
    go(view) { this.view = view; this.deps.rerender(); }

    render(app) {
      const { el } = this.deps;
      app.replaceChildren();
      const section = el('section', null, 'auth-view');
      section.append(this.deps.header(TITLES[this.view], 'Vista de diseño con datos de ejemplo locales.'));
      const card = el('div', null, 'auth-card');
      section.append(card);
      section.append(el('p', 'Vista de diseño: nada se envía al hospital ni a Supabase. Una solicitud no es una cita.', 'auth-notice'));
      if (this.view === 'complete') this.completeForm(card);
      if (this.view === 'home') this.home(card);
      if (this.view === 'request') this.requestForm(card);
      if (this.view === 'requests') this.requestList(card);
      if (this.person) section.append(this.nav());
      else section.append(this.deps.button('Salir de la demostración', () => this.deps.exit(), 'text-button'));
      app.append(section);
    }

    nav() {
      const { el, button } = this.deps;
      const bar = el('nav', null, 'applicant-nav');
      const tab = (label, view) => {
        const node = button(label, () => this.go(view), 'applicant-tab' + (this.view === view ? ' is-active' : ''));
        node.setAttribute('aria-current', String(this.view === view));
        return node;
      };
      bar.append(tab('Inicio', 'home'), tab('Solicitar', 'request'), tab('Mis solicitudes', 'requests'));
      bar.append(button('Salir de la demostración', () => this.deps.exit(), 'text-button'));
      return bar;
    }

    formatDay(iso) {
      const date = new Date(iso + 'T12:00:00');
      return isNaN(date.getTime()) ? iso : new Intl.DateTimeFormat('es-SV', { day: 'numeric', month: 'short', year: 'numeric' }).format(date);
    }

    field(id, label, type, placeholder, value) {
      const { el } = this.deps;
      const wrap = el('div', null, 'auth-field');
      const fieldLabel = el('label', label); fieldLabel.htmlFor = id;
      const input = el('input');
      Object.assign(input, { id, name: id, type, placeholder, value: value || '', required: true });
      wrap.append(fieldLabel, input);
      return { wrap, input };
    }

    completeForm(card) {
      const { el, button } = this.deps;
      const form = el('form');
      const given = this.field('ap-given', 'Nombres', 'text', 'Tus nombres');
      const family = this.field('ap-family', 'Apellidos', 'text', 'Tus apellidos');
      const dui = this.field('ap-dui', 'DUI', 'text', '0000-00000');
      const birth = this.field('ap-birth', 'Fecha de nacimiento', 'date', '');
      const phone = this.field('ap-phone', 'Teléfono', 'tel', '0000-0000');
      dui.input.addEventListener('input', () => { dui.input.value = core().formatDui(dui.input.value); });
      const problem = el('p', null, 'auth-error'); problem.hidden = true;
      form.append(given.wrap, family.wrap, dui.wrap, birth.wrap, phone.wrap, problem);
      const submit = el('button', 'Guardar datos', 'primary'); submit.type = 'submit';
      form.append(submit);
      form.addEventListener('submit', event => {
        event.preventDefault(); problem.hidden = true;
        const values = { given: given.input.value, family: family.input.value, birthDate: birth.input.value, dui: dui.input.value, phone: phone.input.value };
        const issue = core().validatePersonalData(values, core().localIsoDay(new Date()));
        if (issue) { problem.textContent = issue.message; problem.hidden = false; return; }
        this.person = { given: values.given.trim(), family: values.family.trim(), dui: core().formatDui(values.dui), birthDate: values.birthDate, phone: values.phone.trim() };
        this.view = 'home';
        this.deps.message('Datos de ejemplo guardados solo en esta vista.');
        this.deps.rerender();
      });
      card.append(el('h2', 'Completa tus datos', 'section-title'), el('p', 'Tu cuenta no tiene expediente clínico. Estos datos sirven para verificar tu identidad en recepción.', 'auth-notice'), form);
    }

    home(card) {
      const { el, button } = this.deps;
      const first = this.person ? this.person.given.split(' ')[0] : 'Solicitante';
      card.append(el('h2', 'Hola, ' + first, 'section-title'));
      card.append(el('p', 'Todavía no tienes expediente. Puedes solicitar atención y recepción la revisará.', 'sched-hint'));
      card.append(el('p', 'Solicitudes registradas en esta vista: ' + this.requests.length, 'sched-hint'));
      card.append(button('Solicitar atención', () => this.go('request'), 'primary'));
      card.append(button('Ver mis solicitudes', () => this.go('requests'), 'menu-row'));
    }

    requestForm(card) {
      const { el, button } = this.deps;
      const form = el('form');
      const select = el('select'); select.id = 'ap-specialty';
      const placeholder = el('option', 'Elige una especialidad'); placeholder.value = ''; select.append(placeholder);
      for (const name of core().applicantDemoSpecialties) { const option = el('option', name); option.value = name; select.append(option); }
      select.value = this.draft.specialty;
      select.addEventListener('change', () => { this.draft.specialty = select.value; });
      const reason = el('textarea'); reason.id = 'ap-reason'; reason.value = this.draft.reason;
      reason.addEventListener('input', () => { this.draft.reason = reason.value; });
      const date = this.field('ap-date', 'Fecha preferida', 'date', '', this.draft.date);
      date.input.min = core().localIsoDay(new Date());
      date.input.addEventListener('change', () => { this.draft.date = date.input.value; });
      const problem = el('p', null, 'auth-error'); problem.hidden = true;
      const periods = el('div', null, 'applicant-periods');
      const periodButtons = {};
      for (const key of ['morning', 'afternoon']) {
        const option = button(PERIODS[key], () => {
          this.draft.period = key;
          for (const other of Object.keys(periodButtons)) periodButtons[other].setAttribute('aria-pressed', String(other === key));
        }, 'period-choice');
        option.setAttribute('aria-pressed', String(this.draft.period === key));
        periodButtons[key] = option; periods.append(option);
      }
      const specialtyLabel = el('label', 'Especialidad'); specialtyLabel.htmlFor = select.id;
      const reasonLabel = el('label', 'Motivo de la consulta'); reasonLabel.htmlFor = reason.id;
      form.append(specialtyLabel, select, reasonLabel, reason, date.wrap, el('p', 'Preferencia de horario', 'sched-hint'), periods, problem);
      const submit = el('button', 'Enviar solicitud', 'primary'); submit.type = 'submit';
      form.append(submit);
      form.addEventListener('submit', event => {
        event.preventDefault(); problem.hidden = true;
        if (this.busy) return;
        const issue = core().validateAttentionRequest(this.draft, core().localIsoDay(new Date()));
        if (issue) { problem.textContent = issue.message; problem.hidden = false; return; }
        this.busy = true;
        this.sequence += 1;
        this.requests.unshift({ id: 'ejemplo-' + this.sequence, specialty: this.draft.specialty, reason: this.draft.reason.trim(), date: this.draft.date, period: this.draft.period, status: 'pending', appointmentStatus: null, decisionReason: null, example: true, createdAt: new Date().toISOString() });
        this.draft = { specialty: '', reason: '', date: '', period: '' };
        this.busy = false;
        this.view = 'requests';
        this.deps.message('Solicitud registrada como Pendiente. No es una cita.');
        this.deps.rerender();
      });
      card.append(el('h2', 'Solicitar atención', 'section-title'), el('p', 'Recepción confirmará disponibilidad. Esta solicitud no reserva ninguna cita.', 'sched-hint'), form);
    }

    addStateExamples() {
      if (this.requests.some(item => item.id === 'ejemplo-rechazada')) return;
      this.requests.push(
        { id: 'ejemplo-rechazada', specialty: 'Pediatría', reason: 'Consulta de control (ejemplo de diseño)', date: '2026-11-20', period: 'morning', status: 'rejected', appointmentStatus: null, decisionReason: 'Ejemplo: la especialidad no tiene agenda en esa fecha.', example: true, createdAt: '2026-11-10T15:00:00.000Z' },
        { id: 'ejemplo-cancelada', specialty: 'Ginecología', reason: 'Valoración general (ejemplo de diseño)', date: '2026-11-22', period: 'afternoon', status: 'cancelled', appointmentStatus: null, decisionReason: 'Ejemplo: el solicitante canceló la solicitud.', example: true, createdAt: '2026-11-09T14:00:00.000Z' }
      );
      this.deps.message('Ejemplos de diseño añadidos: rechazada y cancelada. No son citas ni solicitudes reales.');
      this.deps.rerender();
    }

    requestList(card) {
      const { el, button } = this.deps;
      card.append(el('h2', 'Mis solicitudes', 'section-title'));
      card.append(el('p', 'Registros de ejemplo locales. Ninguno es una cita ni se envía al hospital.', 'sched-hint'));
      if (!this.requests.length) card.append(el('p', 'Aún no tienes solicitudes en esta vista.', 'sched-hint'));
      for (const request of this.requests) {
        const view = core().applicantStateView(request.status, request.appointmentStatus);
        const article = el('article', null, 'doctor-visit');
        article.append(el('strong', request.specialty), el('span', view.label, 'clinical-lab-state ' + (STATE_CLASS[view.key] || 'is-pending')));
        article.append(el('p', request.reason), el('small', 'Preferencia: ' + this.formatDay(request.date) + ' · ' + PERIODS[request.period]));
        if (request.decisionReason) article.append(el('p', 'Motivo: ' + request.decisionReason, 'sched-hint'));
        if (view.key === 'scheduled') article.append(el('small', 'Cita de ejemplo: la programa recepción en el sistema real.'));
        article.append(el('small', 'Solicitud de ejemplo · no es una cita'));
        if (NEXT_EXAMPLE[request.status] || (request.status === 'converted' && !request.appointmentStatus)) {
          article.append(button('Simular avance de recepción (ejemplo)', () => this.advance(request.id), 'text-button'));
        }
        card.append(article);
      }
      card.append(button('Mostrar ejemplos de rechazada y cancelada', () => this.addStateExamples(), 'text-button'));
    }

    advance(id) {
      const request = this.requests.find(item => item.id === id);
      if (!request) return;
      if (NEXT_EXAMPLE[request.status]) request.status = NEXT_EXAMPLE[request.status];
      else if (request.status === 'converted' && !request.appointmentStatus) request.appointmentStatus = 'scheduled';
      this.deps.message('Avance de ejemplo local. No se modificó ningún dato del hospital.');
      this.deps.rerender();
    }
  }

  root.HospitalApplicantDemo = HospitalApplicantDemo;
})(typeof globalThis !== 'undefined' ? globalThis : this);
