(function (root) {
  'use strict';
  class APIError extends Error {
    constructor(status, code) {
      super(({ 400: 'Credenciales o datos inválidos. Revisa el correo y la contraseña.', 401: 'La sesión no es válida. Inicia sesión de nuevo.', 403: 'Tu cuenta no tiene acceso a esta información o requiere verificación.', 422: 'Datos inválidos.', 429: 'Demasiados intentos. Espera antes de volver a intentarlo.' })[status] || 'No se pudo conectar con el hospital. Inténtalo de nuevo.');
      this.status = status;
      this.code = code;
      if (code === 'PGRST202') this.message = 'No se pudo encontrar el servicio de este módulo. Actualiza la conexión.';
      if (status === 409 || ['40001','23505','PT409'].includes(code)) this.message = 'El registro cambió o ya existe. Actualiza antes de continuar.';
      if (['22023','23514','PT400','PT422'].includes(code)) this.message = 'Revisa los datos y el estado de la atención antes de continuar.';
      if (status === 403) this.message = 'Tu cuenta no tiene acceso a esta operación. Revisa tu rol, permisos y vínculo con el registro solicitado.';
    }
  }
  class HospitalAPI {
    constructor(contract, options = {}) {
      this.contract = contract;
      this.fetch = options.fetch || root.fetch.bind(root);
      this.storage = options.storage || root.sessionStorage;
      this.session = null;
      this.expiry = 0;
      this.refreshing = null;
      this.storageKey = 'hospital.refresh-token.v1';
    }
    async request(path, body, token, method = 'POST') {
      const headers = { apikey: this.contract.publishableKey, 'Content-Type': 'application/json' };
      if (token) headers.Authorization = `Bearer ${token}`;
      let response;
      try { response = await this.fetch(this.contract.url + path, { method, headers, body: method === 'GET' ? undefined : JSON.stringify(body), cache: 'no-store', signal: AbortSignal.timeout(25000) }); }
      catch { throw new Error('No se pudo conectar con el hospital. Revisa la conexión e inténtalo de nuevo.'); }
      if (!response.ok) {
        let detail; try { detail = await response.json(); } catch { /* No clinical response bodies are surfaced. */ }
        throw new APIError(response.status, detail?.code);
      }
      if (response.status === 204) return null;
      const text = await response.text();
      return text ? JSON.parse(text) : null;
    }
    accept(session) {
      if (!session || typeof session.access_token !== 'string' || typeof session.refresh_token !== 'string' || !Number.isFinite(session.expires_in)) throw new Error('Respuesta de autenticación inválida.');
      this.storage.setItem(this.storageKey, session.refresh_token);
      this.session = session;
      this.expiry = Date.now() + (session.expires_in - 60) * 1000;
    }
    async signIn(email, password) {
      const session = await this.request('/auth/v1/token?grant_type=password', { email: email.trim(), password });
      try { this.accept(session); }
      catch (error) { await this.request('/auth/v1/logout?scope=local', {}, session.access_token).catch(() => {}); throw error; }
    }
    async token() {
      if (this.session && this.expiry > Date.now()) return this.session.access_token;
      if (this.refreshing) return this.refreshing;
      const refresh = this.storage.getItem(this.storageKey);
      if (!refresh) throw new APIError(401);
      this.refreshing = (async () => {
        let session;
        try { session = await this.request('/auth/v1/token?grant_type=refresh_token', { refresh_token: refresh }); }
        catch (error) { if ([400, 401, 403].includes(error.status)) throw new APIError(401); throw error; }
        this.accept(session);
        return session.access_token;
      })();
      try { return await this.refreshing; } finally { this.refreshing = null; }
    }
    async access() {
      const access = await this.request('/rest/v1/rpc/my_access', {}, await this.token());
      return { access, roles: root.HospitalCore.routes(access) };
    }
    async rpc(name, parameters = {}) {
      if (!['my_profile', 'my_activity_summary', 'my_queue_status', 'hospital_overview', 'mobile_module',
        'doctor_workspace', 'doctor_chart', 'doctor_issue_lab_order', 'mobile_issue_prescription',
        'request_appointment', 'transition_appointment', 'start_consultation', 'save_consultation', 'close_consultation',
        'update_record', 'create_record', 'update_my_phone', 'set_my_emergency_contact', 'confirm_shift', 'read_resource'].includes(name)) throw new Error('Consulta no disponible.');
      return this.request('/rest/v1/rpc/' + name, parameters, await this.token());
    }
    async changePassword(password) {
      return this.request('/auth/v1/user', {password}, await this.token(), 'PUT');
    }
    async documentURL(id) {
      if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)) throw new Error('Documento inválido.');
      const response = await this.fetch('/document-access', {method:'POST', headers:{Authorization:'Bearer ' + await this.token(),'Content-Type':'application/json'}, body:JSON.stringify({document_id:id}), cache:'no-store', signal:AbortSignal.timeout(25000)});
      if (!response.ok) throw new APIError(response.status);
      const result = await response.json(), url = new URL(result.url);
      if (url.protocol !== 'https:' || url.origin !== new URL(this.contract.url).origin || !url.pathname.startsWith('/storage/v1/object/sign/hospital-files/')) throw new Error('El documento no devolvió un enlace seguro.');
      return url.href;
    }
    async read(resource, cursor, owner) {
      if (resource === 'staff_shifts' && (!cursor || !this.shiftWindow)) this.shiftWindow = root.HospitalCore.weekWindow();
      const page = await this.request('/rest/v1/rpc/read_resource', root.HospitalCore.readRequest(resource, cursor, owner, resource === 'staff_shifts' ? this.shiftWindow : null), await this.token());
      if (!page || !Array.isArray(page.data) || typeof page.has_more !== 'boolean' || (page.has_more && !page.next_cursor)) throw new Error('Respuesta de datos inválida.');
      const model = this.contract.models[({ rooms: 'Room', staff_shifts: 'StaffShift', queue_tickets: 'QueueTicket' })[resource]];
      for (const item of page.data) {
        for (const [field, declaredType] of Object.entries(model)) {
          if (declaredType.endsWith('?') && item[field] == null) continue;
          const type = declaredType.replace('?', '');
          const valid = type === 'Bool' ? typeof item[field] === 'boolean' : ['Int', 'Int64'].includes(type) ? Number.isSafeInteger(item[field]) : type === 'UUID' ? typeof item[field] === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(item[field]) : typeof item[field] === 'string';
          if (!valid) throw new Error('El servidor devolvió datos incompatibles con el contrato.');
        }
      }
      return page;
    }
    clear() { this.session = null; this.expiry = 0; this.shiftWindow = null; this.storage.removeItem(this.storageKey); }
    async signOut() {
      let warning = null;
      try { await this.request('/auth/v1/logout?scope=local', {}, await this.token()); }
      catch { warning = 'Se cerró la sesión en este navegador. No se pudo confirmar el cierre remoto.'; }
      finally { this.clear(); }
      return warning;
    }
  }
  root.HospitalAPI = HospitalAPI;
})(typeof globalThis !== 'undefined' ? globalThis : this);
