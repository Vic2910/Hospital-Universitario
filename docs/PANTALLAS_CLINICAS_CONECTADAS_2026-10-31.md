# Pantallas clínicas conectadas — 31 de octubre de 2026

## Alcance y decisión del usuario

Se pidió hacer funcionales las pantallas que mostraban «Prototipo local · Solicitudes y expediente de ejemplo · Sin escritura en Supabase». El usuario confirmó conservar la regla de consulta abierta para registrar observaciones y emitir recetas u órdenes. Se implementa en iOS/SwiftUI y web; no se amplían los roles a Recepción ni Laboratorio.

## Implementación

- La sesión del Doctor abre Pacientes, Expedientes y Laboratorios conectados. Se retiran el interruptor iOS y el enlace web que mostraban ejemplos dentro de una sesión autenticada. Los botones exteriores de diseño web conservan su entorno local, explícitamente identificado y sin llamadas clínicas.
- Búsqueda por nombre, DUI y expediente dentro de la agenda autorizada de la fecha elegida. Los vacíos no se rellenan con personas ficticias. Se conserva el paciente/cita seleccionado al ir a consulta, laboratorio o receta.
- Ficha interna con tarjeta compartida de identidad, historial de consultas propias, antecedentes, alergias, medicamentos y signos vitales registrados. Laboratorios cronológicos y detalle interno con paciente, solicitud, estado y valores/unidades/referencias publicados.
- Laboratorio utiliza el catálogo real y `doctor_issue_lab_order`, con la consulta seleccionada y clave de idempotencia. Una consulta no abierta ofrece acceso a Consultas; el inicio sigue sujeto al check-in y estados existentes. No se publican resultados desde el Doctor.
- Añadir observación lleva a la nota de consulta existente (`save_consultation`); Añadir receta usa el formulario conectado (`mobile_issue_prescription`) cuando hay consulta abierta, o dirige a Consultas. No se guardan textos o medicamentos libres como si fueran registros reales del prototipo. Las observaciones y recetas pertenecen al encuentro clínico; no se crea una relación ficticia con el examen abierto.
- Los datos demográficos y los signos vitales se leen del expediente. El formulario conectado solicita estudio e indicaciones: no conserva los campos locales de peso/altura como entradas que aparenten guardar sin persistencia. La captura de nuevas mediciones no se añadió en esta intervención.
- Ante error de carga de agenda o expediente se descartan los datos anteriores. Un rechazo no muestra ejemplos ni conserva notas del paciente previamente cargado. Los reintentos de emisión conservan su clave; tras éxito se renueva y se recarga el contexto.

## Supabase

Se usó el complemento Supabase contra el proyecto existente `kgulityewtcyvjnxeskd`, inspeccionando funciones, columnas y políticas antes de modificar.

Se aplicaron `clinical_connected_chart_projection` y `clinical_chart_first_appointment`. El SQL final reproducible está en [sql/clinical-connected.sql](sql/clinical-connected.sql): amplía las proyecciones existentes `private.doctor_chart` y `private.doctor_workspace`, sin tablas nuevas ni cambios a RLS, Auth o MFA.

El expediente devuelve nombres separados, DUI, teléfono y laboratorios por paciente, con resultados exclusivamente `released`. Conserva `require_doctor`, `patient_chart`, auditoría y comprobaciones de acceso. Para un paciente sin encuentros previos, permite resolver la sede desde una cita del mismo médico únicamente si `can_patient(..., 'clinical.read')` lo autoriza. La agenda incorpora DUI para la búsqueda.

Las funciones conservan propietario `hospital_api`, sin BYPASSRLS. El permiso CREATE temporal sobre `private` se revoca dentro de la misma transacción. La primera ejecución de migración fue rechazada por propietario de función y no aplicó cambios; se corrigió siguiendo el patrón de despliegue existente del repositorio.

Asesores: permanecen seis INFO de RLS sin políticas en `hospital_recovery_3fn` y la advertencia preexistente de protección de contraseñas filtradas deshabilitada. No se alteraron esas configuraciones. Referencias: [RLS sin políticas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) y [protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Archivos

- `HospitalUniversitario/HospitalUniversitario/ContentView.swift`: enrutamiento real sin ejemplos en sesión.
- `Core/DoctorModels.swift`: identidad y contrato de resultados publicados.
- `Doctor/DoctorClinicalView.swift`: presentación conectada; `Doctor/DoctorModuleView.swift`: integración.
- `web-preview/app.js` y `web-preview/modules.js`: navegación, presentación y operaciones conectadas.
- `scripts/test-clinical-connected.mjs`: pruebas nuevas de los flujos conectados. Las pruebas de diseño conservan sus comprobaciones locales y dejan de esperar ejemplos dentro de sesiones.
- `docs/sql/test-mobile-flows.sql`: ampliación de comprobaciones de laboratorio y consulta cerrada.

## Verificación y límites

Pruebas DOM/transporte simulado: búsquedas, ficha y detalle, tres estados, resultado publicado, ocultación de borradores, regla de consulta abierta, emisión, error/reintento idempotente, bloqueo de doble envío y rechazo sin datos residuales. Se ejecutaron también las suites existentes y comprobaciones portables indicadas en la bitácora.

Pruebas reales PostgreSQL mediante el complemento: `test-mobile-flows.sql` pasó con claims/sesiones transitorios y rollback. Incluye inicio/nota, orden y receta idempotentes, proyección de laboratorio pendiente, exclusión de un borrador insertado dentro de la transacción, identidad estructurada, permisos, sesión vencida y rechazo de orden/receta en consulta cerrada. No acredita login HTTPS de usuario ni uso visual de la app. No quedaron registros clínicos de estas pruebas.

Pendiente: compilación y ejecución SwiftUI en Mac/Xcode, revisión visual de ambas plataformas y recorrido HTTPS con cuentas reales. Esta copia no dispone de `.local/` con credenciales. La comprobación portable de Xcode verifica estructura/recursos, no compilación.
