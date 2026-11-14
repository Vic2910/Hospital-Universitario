# Instrucciones para agentes de IA

Antes de modificar el proyecto lee `README.md`, `docs/TRANSICION_HOSPITAL_MOVILES_2026-11-13.md` y las entradas más recientes de `docs/BITACORA.md`.

## Decisiones vigentes

- El nombre visible es **Hospital Universitario**. El único backend autorizado es **Hospital Móviles**, referencia `uvebpsbbwofthucghccc`.
- Por petición del usuario del 13 de noviembre se retiraron los archivos y contratos del backend anterior. No restaurarlos ni aplicar SQL históricos. Las referencias visuales conservadas no son instrucciones de base de datos.
- iOS/SwiftUI y `web-preview/` avanzan en paralelo. Mantener rutas relativas, recursos compartidos y pertenencia al target. Windows no acredita compilación con SDK Apple.
- Reutilizar tablas, funciones, permisos y RLS del proyecto actual. El rol real `paciente` se presenta como `patient` en la interfaz; `doctor` requiere vínculo activo a personal. No autorizar roles desde user_metadata.
- El módulo Doctor funcional pertenece a iOS y posteriormente Android; el panel web administrativo/recepción es independiente. iOS y su réplica web-preview usan las RPC doctor_native_* y exigen staff.category=doctor además de rol/vínculo activos. No activar ejemplos por ausencia de datos médicos. Contrato común en contracts/doctor-native-v1.json.
- **Preferencia vigente del usuario:** llevar SIEMPRE iOS y web-preview de la mano para que pueda ver los cambios desde Windows. Esto incluye el módulo Doctor. No confundir la réplica local web-preview con el panel administrativo/recepción de otro proyecto. Una petición de no tocar ese panel no excluye la réplica local; solo omitirla si el usuario lo indica expresamente para ese trabajo.
- El rol activo `paciente` permite abrir el Dashboard aunque no exista `patients.profile_id` vinculado. El vínculo se exige para consultas y acciones clínicas, no para entrar al Home. Sin vínculo no consultar tablas clínicas ni mostrar ejemplos como datos reales.
- Solicitar atención iOS usa `my_attention_context`, `submit_my_attention_request` y `my_attention_requests`; admite cuentas sin expediente mediante `appointment_requests.requester_id`. No enviar identidad/patient_id desde el cliente. `patient_id` puede ser nulo hasta la gestión explícita de recepción. La intervención del 13 de noviembre excluye web-preview y el panel web externo por instrucción expresa del usuario.
- Corrección posterior del 13 de noviembre: el usuario aclara que necesita ver el formulario iOS reflejado en web-preview de Windows. Home/Solicitar atención y pestaña Salud deben abrir el formulario conectado incluso sin expediente. El panel externo de recepción sigue excluido; no confundirlo con web-preview ni recrear las RPC desplegadas.
- Por decisión expresa del usuario del 13 de noviembre, el registro solo crea cuenta Auth/perfil, sin paciente, expediente ni cita y sin confirmación de correo. HTTPS confirmó `mailer_autoconfirm=true`. Recepción gestiona el expediente y las citas; `register_patient` no es ejecutable por `anon` ni `authenticated`. No restaurar el alta clínica automática ni cambiar permisos para facilitar pruebas.
- Separar jornadas laborales del médico y atención del paciente. No inventar fila numerada, ocupación, métricas o datos clínicos que el backend no publique.
- Los ejemplos de diseño son locales y deben seguir identificados; no importarlos como registros reales ni habilitar bypass de autenticación.
- No crear cuentas, pacientes ni datos clínicos de prueba en producción por asumir que una conexión los requiere. No introducir claves administrativas o secretos en clientes o documentación.

## Documentación y verificaciones obligatorias

- Registrar cada intervención en `docs/BITACORA.md`: fecha, objetivo, rutas afectadas, cambios, verificaciones realmente ejecutadas y pendientes.
- Para trabajo extenso crear informe en docs y enlazarlo desde bitácora e índice. Actualizar README cuando cambien ejecución, configuración o funcionalidades.
- Distinguir implementación, pruebas con transporte simulado, comprobaciones reales de Supabase y pendientes de Mac. No anunciar compilación Swift ni revisión visual sin ejecutarlas.
- Tras cambios ejecutar `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`, `python scripts/check-project.py` y `git diff --check`. Para Auth/backend ejecutar también test-core y test-patient-registration. Documentar ambas plataformas.
