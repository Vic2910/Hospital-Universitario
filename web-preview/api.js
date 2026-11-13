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
      if (contract.url !== 'https://uvebpsbbwofthucghccc.supabase.co' || !contract.publishableKey?.startsWith('sb_publishable_')) {
        throw new Error('La configuración debe corresponder al proyecto Hospital Móviles y usar una clave pública publicable.');
      }
      this.contract = contract;
      this.fetch = options.fetch || root.fetch.bind(root);
      this.storage = options.storage || root.sessionStorage;
      this.session = null;
      this.expiry = 0;
      this.refreshing = null;
      this.storageKey = 'hospital.moviles.uvebpsbbwofthucghccc.refresh.v1';
      this.storage.removeItem('hospital.refresh-token.v1');
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
    async signUp(email, password, data) {
      const result = await this.request('/auth/v1/signup', { email: email.trim(), password, data });
      if (!result?.access_token) return false;
      try { this.accept(result); }
      catch (error) { await this.request('/auth/v1/logout?scope=local', {}, result.access_token).catch(() => {}); throw error; }
      return true;
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
      const token = await this.token();
      const user = await this.request('/auth/v1/user', null, token, 'GET');
      if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(user.id || '')) throw new Error('Identidad inválida.');
      const get = (table, fields, key, extra = '') => this.request('/rest/v1/' + table + '?select=' + fields + '&' + key + '=eq.' + user.id + extra, null, token, 'GET');
      const [profiles, roles, patients, staff] = await Promise.all([
        get('profiles','id,first_name,last_name,phone,birth_date,city','id'),
        get('user_roles','user_id,role,active','user_id'),
        get('patients','id,profile_id','profile_id'),get('staff','id,profile_id,active','profile_id')]);
      this.context = root.HospitalCore.backendAccess(user,profiles[0],roles,patients,staff);
      return {access:this.context,roles:root.HospitalCore.routes(this.context)};
    }
    async operation(kind, parameters = {}) {
      if (!this.context) await this.access();
      const plan = root.HospitalCore.backendPlan(kind,parameters,this.context);
      const results = [];
      for (const step of plan) results.push(await this.request(step.path,step.body,await this.token(),step.method));
      return root.HospitalCore.backendPresent(kind,parameters,this.context,results);
    }
    async changePassword(password) {
      return this.request('/auth/v1/user', {password}, await this.token(), 'PUT');
    }
    async documentURL() { throw new Error('Los documentos todavía no están habilitados en Hospital Móviles.'); }
    async read(resource, cursor) {
      if (resource === 'appointments') throw new Error('Hospital Móviles no publica una fila numerada. Consulta Mis citas.');
      return this.operation(resource === 'rooms' ? 'rooms' : 'shifts', {cursor,window:root.HospitalCore.weekWindow()});
    }
    clear() { this.context = null; this.session = null; this.expiry = 0; this.shiftWindow = null; this.storage.removeItem(this.storageKey); }
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
