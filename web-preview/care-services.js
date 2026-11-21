// Ambulancia del paciente y Habitaciones del médico (paridad con PatientAmbulanceView.swift y DoctorRoomsView.swift).
// RPC: patient_request_ambulance / patient_ambulance_requests / patient_cancel_ambulance y doctor_native_rooms,
// room_candidates, hospitalize, assign_bed, discharge (supabase/paciente-ambulancia-habitaciones-medico.sql).
// La validación de solicitudes simultáneas y de camas ocupadas vive en el servidor (locks + FOR UPDATE); aquí solo se
// evita el doble envío y se muestra el mensaje del servidor.
(function (root) {
  'use strict';
  const uuid = () => (root.crypto?.randomUUID ? root.crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g, () => (Math.random() * 16 | 0).toString(16)));
  const date = v => v ? String(v).slice(0, 16).replace('T', ' ') : '—';
  const category = v => v === 'vip' ? 'VIP' : v === 'semiprivada' ? 'Semiprivada' : v;
  const admissionStatus = v => ({ solicitado: 'Pendiente de cama', asignado: 'Asignado', hospitalizado: 'Hospitalizado', alta_medica: 'Alta médica', cerrado: 'Cerrado' })[v] || v;
  const ambulanceStatus = v => ({ pendiente: 'En espera de autorización', autorizada: 'Autorizada · asignando unidad', despachada: 'Ambulancia en camino',
    finalizada: 'Traslado finalizado', rechazada: 'Rechazada', cancelada: 'Cancelada' })[v] || v;
  const bedState = v => ({ disponible: 'Disponible', ocupada: 'Ocupada', limpieza: 'En limpieza', mantenimiento: 'Mantenimiento' })[v] || v;
  const describe = e => /PGRST202|404/.test(String(e?.code) + e?.status) ? 'El servicio aún no está disponible en el servidor (migración pendiente).' : (e?.detail || e?.message || 'No se pudo completar la operación.');

  class HospitalCareServices {
    constructor({ el, button, api, repaint, confirm }) {
      Object.assign(this, { el, button, api, repaint, confirm: confirm || (text => root.confirm(text)) });
      this.clear();
    }
    clear() {
      this.amb = { board: null, loaded: false, saving: false, error: null, notice: null, key: uuid(),
        form: { contact: '', phone: '', origin: '', destination: 'Hospital Universitario', reason: '', urgent: true } };
      this.rooms = { board: null, loaded: false, saving: false, error: null, notice: null, tab: 0, mode: 'list', roomId: null,
        admission: null, bed: null, candidates: [], candidate: null, query: '', reason: '', instructions: '', notes: '', urgent: false, key: uuid() };
    }
    rpc(name, params = {}) { return this.api.careRPC(name, params); }
    async task(state, work) {
      try { await work(); state.error = null; } catch (e) { state.error = describe(e); }
      this.repaint();
    }
    card(parent, cls = '') { const c = this.el('article', null, 'card care-card ' + cls); parent.append(c); return c; }
    field(parent, label, value, onInput, { multiline = false, type = 'text' } = {}) {
      const wrap = this.el('label', null, 'care-field'); wrap.append(this.el('span', label));
      const input = this.el(multiline ? 'textarea' : 'input'); if (!multiline) input.type = type;
      input.value = value; input.setAttribute('aria-label', label); input.addEventListener('input', () => onInput(input.value));
      wrap.append(input); parent.append(wrap); return input;
    }
    banners(parent, state) {
      if (state.notice) parent.append(this.el('p', state.notice, 'care-notice'));
      if (state.error) { const p = this.el('p', state.error, 'care-error'); p.setAttribute('role', 'alert'); parent.append(p); }
    }

    // ───────────── Ambulancia del paciente ─────────────
    ambulanceProblem() {
      const f = this.amb.form, digits = f.phone.replace(/\D/g, '');
      if (!f.contact.trim()) return 'Indica el nombre de contacto.';
      if (digits.length < 8 || digits.length > 15) return 'Ingresa un teléfono válido (8 dígitos o más).';
      if (f.origin.trim().length < 5) return 'Describe la ubicación de recogida.';
      if (f.reason.trim().length < 5) return 'Describe brevemente el motivo.';
      return null;
    }
    async loadAmbulance() { const s = this.amb; try { s.board = await this.rpc('patient_ambulance_requests'); s.error = null; } catch (e) { s.error = describe(e); } s.loaded = true; }
    async submitAmbulance() {
      const s = this.amb; if (s.saving) return;               // bloqueo local contra doble clic
      const problem = this.ambulanceProblem(); if (problem) { s.error = problem; this.repaint(); return; }
      if (!this.confirm('¿Solicitar ambulancia ahora? Si es una emergencia que pone en riesgo la vida, llama también al 911.')) return;
      s.saving = true; s.notice = null; s.error = null; this.repaint();
      const f = s.form;
      try {
        const r = await this.rpc('patient_request_ambulance', { p_contact: f.contact, p_phone: f.phone, p_origin: f.origin, p_destination: f.destination,
          p_reason: f.reason, p_priority: f.urgent ? 'urgente' : 'normal', p_key: s.key });
        s.key = uuid(); f.reason = '';
        s.notice = r?.waiting ? `Otra solicitud llegó antes que la tuya y ocupó la unidad disponible. Tu solicitud quedó registrada en la posición ${r.queue_position || 1} de la cola.`
          : 'Solicitud enviada. El hospital la autorizará y te asignará una unidad.';
      } catch (e) { s.error = describe(e); if (e?.code === '22023') s.key = uuid(); }
      s.saving = false; await this.loadAmbulance(); this.repaint();
    }
    async cancelAmbulance(id) {
      const s = this.amb; if (s.saving) return; s.saving = true; this.repaint();
      try { await this.rpc('patient_cancel_ambulance', { p_request: id }); s.notice = 'Solicitud cancelada.'; } catch (e) { s.error = describe(e); }
      s.saving = false; await this.loadAmbulance(); this.repaint();
    }
    renderAmbulance(content, { linked, patientName = '' }) {
      const s = this.amb, el = this.el, button = this.button;
      if (!s.form.contact.trim()) s.form.contact = patientName.trim();
      const hero = el('header', null, 'care-hero');
      hero.append(el('small', 'AMBULANCIA'), el('h2', 'Solicitar traslado'));
      if (s.board) hero.append(el('p', s.board.units_available > 0 ? `${s.board.units_available} unidad(es) disponible(s) en este momento` : 'Todas las unidades están en servicio; tu solicitud quedará en cola'));
      content.append(hero);
      if (!linked) { this.card(content).append(el('p', 'Tu cuenta aún no tiene un expediente vinculado. Acércate a recepción o llama al hospital.')); return; }
      if (!s.loaded) { content.append(el('p', 'Cargando…', 'scope-note')); this.loadAmbulance().then(() => this.repaint()); return; }
      this.banners(content, s);
      const requests = s.board?.requests || [], active = requests.find(r => ['pendiente', 'autorizada', 'despachada'].includes(r.status));
      if (active) {
        const c = this.card(content, 'care-active');
        c.append(el('h3', ambulanceStatus(active.status)));
        if (active.queue_position) c.append(el('p', 'Posición en cola: ' + active.queue_position, 'care-strong'));
        if (active.unit) c.append(el('p', 'Unidad asignada: ' + active.unit));
        c.append(el('p', 'Recogida: ' + active.pickup_location, 'care-muted'), el('p', 'Motivo: ' + active.reason, 'care-muted'));
        const row = el('div', null, 'care-actions');
        row.append(button('Actualizar', () => this.task(s, () => this.loadAmbulance()), 'text-button'));
        if (['pendiente', 'autorizada'].includes(active.status)) row.append(button('Cancelar solicitud', () => this.cancelAmbulance(active.id), 'text-button care-danger'));
        c.append(row);
      } else {
        const c = this.card(content); c.append(el('h3', 'Datos del traslado'));
        const f = s.form, refresh = () => { submit.disabled = s.saving || !!this.ambulanceProblem(); hint.textContent = this.ambulanceProblem() || ''; };
        this.field(c, 'Nombre de contacto', f.contact, v => { f.contact = v; refresh(); });
        const phoneInput = this.field(c, 'Teléfono', f.phone, v => { f.phone = root.HospitalCore.formatPhone(v); phoneInput.value = f.phone; refresh(); }, { type: 'tel' });
        this.field(c, 'Ubicación de recogida (dirección y referencias)', f.origin, v => { f.origin = v; refresh(); }, { multiline: true });
        this.field(c, 'Destino', f.destination, v => { f.destination = v; });
        this.field(c, 'Motivo (síntomas, estado del paciente)', f.reason, v => { f.reason = v; refresh(); }, { multiline: true });
        const urgent = el('label', null, 'care-check'), box = el('input'); box.type = 'checkbox'; box.checked = f.urgent;
        box.addEventListener('change', () => { f.urgent = box.checked; }); urgent.append(box, el('span', 'Es urgente')); c.append(urgent);
        const submit = button(s.saving ? 'Enviando…' : 'Solicitar ambulancia', () => this.submitAmbulance(), 'module-action care-primary');
        const hint = el('p', '', 'care-muted'); c.append(submit, hint); refresh();
      }
      const past = requests.filter(r => r !== active);
      if (past.length) {
        content.append(el('h2', 'Solicitudes anteriores', 'section-title'));
        for (const r of past) { const c = this.card(content); c.append(el('h3', ambulanceStatus(r.status)), el('p', date(r.requested_at), 'care-muted')); if (r.decision_reason) c.append(el('p', r.decision_reason, 'care-muted')); }
      }
    }

    // ───────────── Habitaciones del médico ─────────────
    async loadRooms() { const s = this.rooms; try { s.board = await this.rpc('doctor_native_rooms'); s.error = null; } catch (e) { s.error = describe(e); } s.loaded = true; }
    show(mode) { this.rooms.mode = mode; this.repaint(); }
    async mutate(name, params, success, after) {
      const s = this.rooms; if (s.saving) return;
      s.saving = true; s.notice = null; s.error = null; this.repaint();
      try { await this.rpc(name, params); s.notice = success; after?.(); s.mode = 'list'; } catch (e) { s.error = describe(e); }
      s.saving = false; await this.loadRooms(); this.repaint();
    }
    async searchCandidates() {
      const s = this.rooms;
      try { s.candidates = await this.rpc('doctor_native_room_candidates', { p_query: s.query }) || []; } catch (e) { s.candidates = []; s.error = describe(e); }
      this.repaint();
    }
    renderRooms(content, { search = '' } = {}) {
      const s = this.rooms;
      if (!s.loaded) { content.append(this.el('p', 'Cargando habitaciones…', 'scope-note')); this.loadRooms().then(() => this.repaint()); return; }
      this.banners(content, s);
      if (s.mode !== 'list') content.append(this.button('‹ Volver', () => this.show('list'), 'text-button'));
      ({ room: () => this.roomDetail(content), patient: () => this.patientDetail(content), hospitalize: () => this.hospitalizeView(content),
        assign: () => this.assignView(content) }[s.mode] || (() => this.roomList(content, search)))();
    }
    get roomRows() { return this.rooms.board?.rooms || []; }
    get hospitalized() { return this.rooms.board?.hospitalized || []; }
    roomList(content, search) {
      const s = this.rooms, el = this.el, button = this.button, beds = this.roomRows.flatMap(r => r.beds || []);
      const hero = el('header', null, 'care-hero'); hero.append(el('small', 'HABITACIONES'));
      const stats = el('div', null, 'care-stats');
      for (const [v, l] of [[beds.filter(b => b.available).length, 'Camas libres'], [beds.filter(b => b.state === 'ocupada').length, 'Ocupadas'],
        [this.hospitalized.filter(a => a.status === 'hospitalizado').length, 'Mis pacientes']]) { const d = el('div'); d.append(el('strong', String(v)), el('span', l)); stats.append(d); }
      hero.append(stats); content.append(hero);
      const tabs = el('div', null, 'care-tabs');
      ['Habitaciones', 'Mis hospitalizados'].forEach((t, i) => { const b = button(t, () => { s.tab = i; this.repaint(); }, 'care-tab' + (s.tab === i ? ' active' : '')); tabs.append(b); });
      content.append(tabs);
      const q = search.trim().toLocaleLowerCase('es'), has = v => !q || String(v || '').toLocaleLowerCase('es').includes(q);
      if (s.tab === 0) {
        const list = this.roomRows.filter(r => has(r.code) || has(r.floor));
        for (const r of list) {
          const free = (r.beds || []).filter(b => b.available).length, c = this.card(content, 'care-click');
          c.append(el('h3', `${r.code} · ${category(r.kind)}`), el('p', `${r.floor} · ${(r.beds || []).length} cama(s)` + ((r.beds || []).some(b => b.mine) ? ' · tienes pacientes aquí' : ''), 'care-muted'));
          c.append(el('span', !r.active ? 'Inactiva' : free ? `${free} libre(s)` : 'Ocupada', 'badge' + (!r.active || !free ? ' warning' : '')));
          c.tabIndex = 0; c.setAttribute('role', 'button');
          c.addEventListener('click', () => { s.roomId = r.id; this.show('room'); });
        }
        if (!list.length) content.append(el('p', 'No hay habitaciones que coincidan.', 'scope-note'));
      } else {
        const match = a => has(a.patient_name) || has(a.record_number);
        const pending = this.hospitalized.filter(a => a.status === 'solicitado' && match(a));
        if (pending.length) content.append(el('h2', 'Pendientes de cama', 'section-title'));
        for (const a of pending) {
          const c = this.card(content); c.append(el('h3', a.patient_name), el('p', `${category(a.category)} · ${a.reason}`, 'care-muted'));
          c.append(button('Asignar cama', () => { s.admission = a; this.show('assign'); }, 'module-action'));
        }
        content.append(el('h2', 'Hospitalizados por mí', 'section-title'));
        const mine = this.hospitalized.filter(a => a.status !== 'solicitado' && match(a));
        for (const a of mine) {
          const c = this.card(content, 'care-click');
          c.append(el('h3', a.patient_name), el('p', [a.record_number, a.room && `${a.room} · ${a.bed}`, admissionStatus(a.status)].filter(Boolean).join(' · '), 'care-muted'));
          c.tabIndex = 0; c.setAttribute('role', 'button');
          c.addEventListener('click', () => { s.admission = a; s.notes = ''; this.show('patient'); });
        }
        if (!mine.length) content.append(el('p', 'No tienes pacientes hospitalizados.', 'scope-note'));
      }
    }
    roomDetail(content) {
      const s = this.rooms, el = this.el, button = this.button, r = this.roomRows.find(x => x.id === s.roomId);
      if (!r) { s.mode = 'list'; return this.roomList(content, ''); }
      const info = this.card(content); info.append(el('h3', r.code));
      for (const [k, v] of [['Categoría', category(r.kind)], ['Piso', r.floor], ['Estado', r.active ? 'Activa' : 'Inactiva'], ['Camas libres', `${(r.beds || []).filter(b => b.available).length} de ${(r.beds || []).length}`]]) info.append(el('p', `${k}: ${v}`));
      for (const b of r.beds || []) {
        const c = this.card(content); c.append(el('h3', 'Cama ' + b.code), el('span', bedState(b.state), 'badge' + (b.available ? '' : ' warning')));
        if (b.occupant) {
          c.append(el('p', `${b.occupant.patient_name} · desde ${date(b.occupant.since)}`));
          c.append(button('Ver paciente hospitalizado', () => { s.admission = this.hospitalized.find(a => a.admission_id === b.occupant.admission_id); s.notes = ''; if (s.admission) this.show('patient'); }, 'text-button'));
        } else if (b.state === 'ocupada') c.append(el('p', 'Ocupada por un paciente de otro médico.', 'care-muted'));
        if (b.available) c.append(button('Hospitalizar paciente aquí', () => {
          Object.assign(s, { bed: b, candidate: null, reason: '', instructions: '', urgent: false, query: '', candidates: [] }); this.show('hospitalize'); this.searchCandidates();
        }, 'module-action'));
      }
      if (!(r.beds || []).length) content.append(el('p', 'Sin camas registradas.', 'scope-note'));
    }
    patientDetail(content) {
      const s = this.rooms, el = this.el, a = s.admission; if (!a) return;
      const c = this.card(content); c.append(el('h3', a.patient_name));
      for (const line of [`Expediente: ${a.record_number || '—'}`, `Estado: ${admissionStatus(a.status)}`, `Prioridad: ${a.priority}`,
        `Habitación: ${a.room || 'Sin asignar'} · Cama: ${a.bed || '—'} · ${a.floor || ''}`, `Categoría: ${category(a.category)}`,
        `Ingreso: ${date(a.assigned_at || a.ordered_at)}`, `Motivo: ${a.reason}`, a.observations && `Indicaciones: ${a.observations}`].filter(Boolean)) c.append(el('p', line));
      if (a.status === 'hospitalizado') {
        const d = this.card(content); d.append(el('h3', 'Dar de alta'));
        this.field(d, 'Indicaciones de alta (obligatorio)', s.notes, v => { s.notes = v; submit.disabled = s.saving || s.notes.trim().length < 5; }, { multiline: true });
        const submit = this.button(s.saving ? 'Guardando…' : 'Registrar alta médica', () => {
          if (!this.confirm(`¿Dar de alta a ${a.patient_name}? Recepción liberará la cama después del alta.`)) return;
          this.mutate('doctor_native_discharge', { p_admission: a.admission_id, p_notes: s.notes }, `Alta médica registrada para ${a.patient_name}. Recepción liberará la cama.`);
        }, 'module-action care-danger-fill');
        submit.disabled = s.saving || s.notes.trim().length < 5; d.append(submit);
      } else if (a.status === 'alta_medica') {
        const d = this.card(content); d.append(el('h3', 'Alta médica'), el('p', 'Fecha: ' + date(a.discharged_at)));
        if (a.discharge_notes) d.append(el('p', a.discharge_notes)); d.append(el('p', 'Pendiente de que recepción libere la cama.', 'care-muted'));
      }
    }
    hospitalizeView(content) {
      const s = this.rooms, el = this.el, button = this.button, b = s.bed; if (!b) return;
      content.append(el('h2', `Hospitalizar en cama ${b.code}`, 'section-title'));
      const find = this.card(content); find.append(el('h3', 'Paciente (solo quienes ya pasaron consulta contigo)'));
      const input = this.field(find, 'Nombre, expediente o DUI', s.query, v => { s.query = v; });
      input.addEventListener('keydown', e => { if (e.key === 'Enter') this.searchCandidates(); });
      find.append(button('Buscar', () => this.searchCandidates(), 'text-button'));
      for (const c of s.candidates) {
        const blocked = !!c.active_admission, row = this.card(content, blocked ? 'care-disabled' : 'care-click' + (s.candidate?.id === c.id ? ' care-selected' : ''));
        row.append(el('h3', (s.candidate?.id === c.id ? '✓ ' : '') + c.full_name),
          el('p', [c.record_number, c.last_consultation && 'Última consulta ' + date(c.last_consultation)].filter(Boolean).join(' · '), 'care-muted'));
        if (blocked) row.append(el('p', `Ya tiene hospitalización activa (${admissionStatus(c.active_admission)})`, 'care-error'));
        else row.addEventListener('click', () => { s.candidate = c; this.repaint(); });
      }
      if (!s.candidates.length) content.append(el('p', 'Sin pacientes atendidos por ti con ese criterio.', 'scope-note'));
      const form = this.card(content);
      const valid = () => !!s.candidate && s.reason.trim().length >= 5 && !s.saving;
      this.field(form, 'Motivo de hospitalización', s.reason, v => { s.reason = v; submit.disabled = !valid(); }, { multiline: true });
      this.field(form, 'Indicaciones (opcional)', s.instructions, v => { s.instructions = v; }, { multiline: true });
      const urgent = el('label', null, 'care-check'), box = el('input'); box.type = 'checkbox'; box.checked = s.urgent;
      box.addEventListener('change', () => { s.urgent = box.checked; }); urgent.append(box, el('span', 'Urgente')); form.append(urgent);
      const submit = button(s.saving ? 'Guardando…' : 'Hospitalizar', () => {
        const c = s.candidate; if (!valid()) return;
        this.mutate('doctor_native_hospitalize', { p_patient: c.id, p_bed: b.id, p_reason: s.reason, p_instructions: s.instructions,
          p_priority: s.urgent ? 'urgente' : 'normal', p_key: s.key }, `${c.full_name} quedó hospitalizado en la cama ${b.code}.`, () => { s.key = uuid(); });
      }, 'module-action care-primary');
      submit.disabled = !valid(); form.append(submit);
    }
    assignView(content) {
      const s = this.rooms, el = this.el, a = s.admission; if (!a) return;
      content.append(el('h2', `Asignar cama a ${a.patient_name}`, 'section-title'),
        el('p', `Categoría solicitada: ${category(a.category)}. Solo se muestran camas libres.`, 'scope-note'));
      const free = this.roomRows.filter(r => r.active && r.kind === a.category).flatMap(r => (r.beds || []).filter(b => b.available).map(b => [r, b]));
      for (const [r, b] of free) {
        const c = this.card(content, 'care-click'); c.append(el('h3', `${r.code} · Cama ${b.code}`), el('p', r.floor, 'care-muted'));
        c.addEventListener('click', () => this.mutate('doctor_native_assign_bed', { p_admission: a.admission_id, p_bed: b.id }, `Cama ${b.code} asignada a ${a.patient_name}.`));
      }
      if (!free.length) content.append(el('p', 'No hay camas libres de esta categoría.', 'scope-note'));
    }
  }
  root.HospitalCareServices = HospitalCareServices;
})(typeof window !== 'undefined' ? window : globalThis);
