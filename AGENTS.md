# Instrucciones para agentes de IA

Antes de modificar el proyecto lee `README.md`, `docs/TRANSICION_HOSPITAL_MOVILES_2026-11-13.md` y las entradas más recientes de `docs/BITACORA.md`.

## Decisiones vigentes

- El nombre visible es **Hospital Universitario**. El único backend autorizado es **Hospital Móviles**, referencia `uvebpsbbwofthucghccc`.
- Por petición del usuario del 13 de noviembre se retiraron los archivos y contratos del backend anterior. No restaurarlos ni aplicar SQL históricos. Las referencias visuales conservadas no son instrucciones de base de datos.
- iOS/SwiftUI y `web-preview/` avanzan en paralelo. Mantener rutas relativas, recursos compartidos y pertenencia al target. Windows no acredita compilación con SDK Apple.
- Reutilizar tablas, funciones, permisos y RLS del proyecto actual. El rol real `paciente` se presenta como `patient` en la interfaz; `doctor` requiere vínculo activo a personal. No autorizar roles desde user_metadata.
- El rol activo `paciente` permite abrir el Dashboard aunque no exista `patients.profile_id` vinculado. El vínculo se exige para consultas y acciones clínicas, no para entrar al Home. Sin vínculo no consultar tablas clínicas ni mostrar ejemplos como datos reales.
- Por decisión expresa del usuario del 13 de noviembre, el registro solo crea cuenta Auth/perfil, sin paciente, expediente ni cita y sin confirmación de correo. HTTPS confirmó `mailer_autoconfirm=true`. Recepción gestiona el expediente y las citas; `register_patient` no es ejecutable por `anon` ni `authenticated`. No restaurar el alta clínica automática ni cambiar permisos para facilitar pruebas.
- Separar jornadas laborales del médico y atención del paciente. No inventar fila numerada, ocupación, métricas o datos clínicos que el backend no publique.
- Los ejemplos de diseño son locales y deben seguir identificados; no importarlos como registros reales ni habilitar bypass de autenticación.
- No crear cuentas, pacientes ni datos clínicos de prueba en producción por asumir que una conexión los requiere. No introducir claves administrativas o secretos en clientes o documentación.

## Documentación y verificaciones obligatorias

- Registrar cada intervención en `docs/BITACORA.md`: fecha, objetivo, rutas afectadas, cambios, verificaciones realmente ejecutadas y pendientes.
- Para trabajo extenso crear informe en docs y enlazarlo desde bitácora e índice. Actualizar README cuando cambien ejecución, configuración o funcionalidades.
- Distinguir implementación, pruebas con transporte simulado, comprobaciones reales de Supabase y pendientes de Mac. No anunciar compilación Swift ni revisión visual sin ejecutarlas.
- Tras cambios ejecutar `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`, `python scripts/check-project.py` y `git diff --check`. Para Auth/backend ejecutar también test-core y test-patient-registration. Documentar ambas plataformas.
