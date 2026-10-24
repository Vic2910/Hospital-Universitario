(function (root) {
  'use strict';
  class APIError extends Error {
    constructor(status) {
      super(({ 400: 'Credenciales o datos inválidos. Revisa el correo y la contraseña.', 401: 'La sesión no es válida. Inicia sesión de nuevo.', 403: 'Tu cuenta no tiene acceso a esta información o requiere verificación.', 422: 'Datos inválidos.', 429: 'Demasiados intentos. Espera antes de volver a intentarlo.' })[status] || 'No se pudo conectar con el hospital. Inténtalo de nuevo.');
      this.status = status;
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
      if (!response.ok) throw new APIError(response.status);
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
      if (!['my_profile', 'my_activity_summary', 'my_queue_status', 'hospital_overview'].includes(name)) throw new Error('Consulta no disponible.');
      return this.request('/rest/v1/rpc/' + name, parameters, await this.token());
    }
    async factors() {
      const user = await this.request('/auth/v1/user', {}, await this.token(), 'GET');
      return user.factors || [];
    }
    async verifyTOTP(factor, code) {
      if (!/^\d{6}$/.test(code)) throw new Error('Introduce el código de seis dígitos de tu autenticador.');
      if (!/^[0-9a-f-]{36}$/i.test(factor)) throw new Error('Factor inválido.');
      const token = await this.token(), base = '/auth/v1/factors/' + factor;
      const challenge = await this.request(base + '/challenge', {}, token);
      this.accept(await this.request(base + '/verify', { challenge_id: challenge.id, code }, token));
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
