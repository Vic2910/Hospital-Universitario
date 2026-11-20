// Cambio de contraseña desde Perfil (paciente y médico) con Supabase Auth simulado: la contraseña vive en el transporte
// simulado y solo cambia si el cliente verifica la actual y envía PUT /auth/v1/user. Sin Supabase real.
import assert from 'node:assert/strict';
import {createApp} from './test-preview.mjs';

for (const [codes, role] of [[['patient'], 'paciente'], [['doctor'], 'médico']]) {
  let password = 'test-password';
  const ui = createApp(codes, {transport: async (url, params, request) => {
    if (url.includes('/auth/v1/token?grant_type=password'))
      return params.password === password ? {body: {access_token: 'nuevo', refresh_token: 'nuevo-refresh', expires_in: 3600}}
        : {status: 400, body: {code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials'}};
    if (url.endsWith('/auth/v1/user') && request?.method === 'PUT') {
      if (params.password === password) return {status: 422, body: {code: 422, error_code: 'same_password', msg: 'New password should be different from the old password.'}};
      password = params.password; return {body: {id: '00000000-0000-4000-8000-000000000001', email: 'persona@example.test'}};
    }
  }});
  await ui.login();
  const text = () => ui.app.textContent;
  const openProfile = async () => { if (role === 'paciente') await ui.click('Perfil'); else { await ui.click('Más'); await ui.click('Mi perfil　›'); } };
  const fill = async (current, next, confirm) => {
    await ui.input('Contraseña actual', current); await ui.input('Nueva contraseña', next); await ui.input('Confirmar nueva contraseña', confirm);
  };
  const puts = () => ui.calls.filter(c => c.url.endsWith('/auth/v1/user') && c.request?.method === 'PUT');
  await openProfile();
  for (const value of ['Seguridad', 'Contraseña actual', 'Nueva contraseña', 'Confirmar nueva contraseña', 'Actualizar contraseña'])
    assert.ok(text().includes(value), role + ': Perfil muestra ' + value);

  // Validaciones del cliente: no llegan al servidor.
  await fill('test-password', 'NuevaClave2026', 'Distinta2026');
  assert.match(text(), /La confirmación no coincide con la nueva contraseña/);
  await ui.submit('Actualizar contraseña'); assert.equal(puts().length, 0, 'Sin confirmación válida no se envía nada');
  await fill('test-password', 'corta', 'corta'); assert.match(text(), /al menos 8 caracteres/);
  await fill('test-password', 'test-password', 'test-password'); assert.match(text(), /distinta de la actual/);
  await ui.submit('Actualizar contraseña'); assert.equal(puts().length, 0);

  // Contraseña actual incorrecta: Supabase rechaza la verificación y no se cambia nada.
  await fill('incorrecta1', 'NuevaClave2026', 'NuevaClave2026'); await ui.submit('Actualizar contraseña');
  assert.match(text(), /La contraseña actual no es correcta/); assert.equal(puts().length, 0); assert.equal(password, 'test-password');

  // Cambio correcto: verifica la actual con el correo de la cuenta y actualiza en Supabase Auth.
  await fill('test-password', 'NuevaClave2026', 'NuevaClave2026'); await ui.submit('Actualizar contraseña');
  const verify = ui.calls.filter(c => c.url.includes('grant_type=password')).pop();
  assert.equal(verify.params.email, 'persona@example.test'); assert.equal(verify.params.password, 'test-password');
  assert.equal(puts().length, 1); assert.equal(puts()[0].params.password, 'NuevaClave2026'); assert.equal(puts()[0].request.headers.Authorization, 'Bearer nuevo', 'PUT con la sesión recién verificada');
  assert.equal(password, 'NuevaClave2026', 'La contraseña quedó actualizada en Auth');
  assert.match(text(), /Contraseña actualizada/);
  assert.equal(ui.app.all().filter(n => n.attributes['aria-label'] === 'Nueva contraseña').every(n => !n.value), true, 'Los campos se vacían');
  assert.equal([...ui.stored.values()].some(v => String(v).includes('NuevaClave2026') || String(v).includes('test-password')), false, 'Ninguna contraseña se guarda en el navegador');

  // Cerrar sesión: la contraseña anterior ya no entra y la nueva sí.
  await ui.click('Más'); await ui.click('Cerrar sesión');
  const login = async value => { ui.get('email').value = 'persona@example.test'; ui.get('password').value = value; ui.app.all().find(n => n.tagName === 'form').listeners.submit({preventDefault() {}}); await new Promise(r => setTimeout(r, 30)); };
  await login('test-password'); assert.ok(ui.get('password'), 'Con la contraseña anterior sigue en el login');
  await login('NuevaClave2026'); assert.match(text(), role === 'médico' ? /Hola, Persona de prueba/ : /¡Hola, Persona de!/, 'Entra con la nueva contraseña');
  console.log(`OK Perfil (${role}): validaciones, contraseña actual verificada, cambio en Supabase Auth y acceso solo con la nueva`);
}
