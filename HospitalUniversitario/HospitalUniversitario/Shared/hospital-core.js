/* Shared by JavaScriptCore (iOS) and the Windows browser preview. No credentials. */
(function (root) {
  'use strict';
  var labels = { doctor: 'Médico', patient: 'Paciente' };
  function routes(access) {
    if (!access || !access.profile || access.profile.status !== 'active') return [];
    return ['doctor', 'patient'].filter(function (code) {
      var linked = code === 'doctor' ? access.staff_id : access.patient_id;
      return !!linked && (access.roles || []).some(function (role) { return role.code === code; });
    });
  }
  function turnResource(role) {
    if (role === 'doctor') return 'staff_shifts';
    if (role === 'patient') return 'queue_tickets';
    throw new Error('Rol no permitido');
  }
  function weekWindow(now) {
    var first = now ? new Date(now) : new Date();
    if (!isFinite(first.getTime())) throw new Error('Fecha inválida');
    first.setDate(first.getDate() - (first.getDay() + 6) % 7);
    first.setHours(0, 0, 0, 0);
    var last = new Date(first); last.setDate(last.getDate() + 7);
    return '["' + first.toISOString() + '","' + last.toISOString() + '")';
  }
  function readRequest(resource, cursor, owner, window) {
    if (['rooms', 'staff_shifts', 'queue_tickets'].indexOf(resource) < 0) throw new Error('Recurso no permitido');
    var filters = [];
    if (resource !== 'rooms') {
      if (typeof owner !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(owner)) throw new Error('Vínculo de cuenta inválido');
      filters.push({ column: resource === 'queue_tickets' ? 'patient_id' : 'staff_id', op: 'eq', value: owner });
      if (resource === 'staff_shifts') filters.push({ column: 'period', op: 'overlaps', value: window || weekWindow() });
    }
    return { p_resource: resource, p_filters: filters, p_limit: 25, p_sort: resource === 'staff_shifts' ? 'period' : 'id', p_direction: 'asc', p_cursor: cursor || null };
  }
  function periodBounds(value) {
    // PostgreSQL tstzrange: ["2026-10-23 07:00:00-06","2026-10-23 15:00:00-06")
    if (typeof value !== 'string' || value[0] !== '[' || value.slice(-1) !== ')') throw new Error('Intervalo inválido');
    var match = /^\["?([^",]+)"?,"?([^",]+)"?\)$/.exec(value);
    if (!match) throw new Error('Intervalo inválido');
    function normalize(s) { return s.replace(' ', 'T').replace(/([+-]\d{2})$/, '$1:00'); }
    var start = new Date(normalize(match[1])), end = new Date(normalize(match[2]));
    if (!isFinite(start.getTime()) || !isFinite(end.getTime()) || start >= end) throw new Error('Intervalo inválido');
    return { start: start.toISOString(), end: end.toISOString() };
  }
  root.HospitalCore = { labels: labels, routes: routes, turnResource: turnResource, weekWindow: weekWindow, readRequest: readRequest, periodBounds: periodBounds };
})(typeof globalThis !== 'undefined' ? globalThis : this);
