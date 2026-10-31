# Citas y solicitudes del Paciente — 2026-10-30

## Comportamiento implementado

- **Paciente → Mis citas:** próxima cita futura, datos del paciente, especialidad, médico, consultorio, edad, teléfono, motivo y síntomas. Ver detalle abre un ticket dentro de la app, con Volver a Mis citas. No ofrece Abrir atención ni acciones clínicas del Doctor.
- SwiftUI reutiliza `DoctorConsultationTicketView` y sus normalizadores. Los parámetros nuevos tienen valores predeterminados y conservan su presentación para Doctor. Web reutiliza las clases `consult-ticket`, `consult-ticket-check`, `consult-ticket-date`, `consult-ticket-fields` y el botón azul existentes.
- Se eliminan las dos implementaciones visuales del formulario antiguo de Solicitar atención. `request` y el alias histórico `schedule` abren ahora el mismo formulario de agendar, cuyo botón dice **Solicitar atención**. Mis citas tiene un único acceso a ese formulario.
- El formulario conserva datos editables, síntomas/Ninguno, motivo, especialidades y horarios de ejemplo. Añade **Preferencia de horario: Mañana/Tarde**, obligatoria. Los horarios son orientativos; escogerlos no reserva una cita.
- Enviar guarda un snapshot local **Pendiente**, muestra confirmación y bloquea el doble envío. No crea una cita asignada ni modifica la próxima cita. Cambiar los campos permite preparar otra solicitud.
- Mis citas muestra también las solicitudes locales y su preferencia, fecha de creación y estado, identificadas como ejemplos.
- Citas reales: se usan los registros autorizados de `mobile_module(appointments)` y `my_profile`. Se selecciona la menor fecha futura de los registros cargados con estado scheduled/confirmed. Se conserva el listado conectado, su paginación y la cancelación con motivo y control de versión.
- Solo una respuesta correcta sin citas activa la próxima cita de ejemplo. Un error no fabrica una cita. Los campos reales ausentes muestran **No hay datos reales**.

## Datos y estados

`PatientAttentionRequest` / `HospitalPatientAppointments.requests` guardan identificador, fecha de creación, nombres, apellidos, DUI, teléfono, correo, especialidad, motivo, síntomas, preferencia y horario orientativo. El estado inicial es `pending` (Pendiente), con `appointmentID` y `resolvedAt` vacíos.

La asignación de ejemplo valida fecha/hora futura y que siga pendiente; crea una cita confirmada, vincula su ID, registra resolución y cambia la solicitud a `scheduled` (Cita asignada). Una segunda asignación del mismo ID no crea otra cita. Los identificadores `pending`, `scheduled`, `rejected` y `cancelled` siguen la convención existente de solicitudes; no se agrega una migración.

Hay una cita para mañana a las 09:00 y una solicitud independiente pendiente, precargadas en ambas plataformas. Los snapshots creados por el usuario permanecen en memoria durante el recorrido local; se reinician al salir/cambiar de sesión o recargar. No se importan fixtures a Supabase, no hay bypass de autenticación y los roles reales siguen siendo doctor/patient.

## Recepción de demostración

- **Web:** botón exterior **Recepción (demo)**. Muestra la cola local dentro del marco de la app, los datos, motivo, síntomas, fecha y preferencia; permite elegir fecha/hora y **Asignar cita de ejemplo**. Volver al portal del paciente conserva los cambios locales.
- **SwiftUI:** `ReceptionAppointmentExampleView(flow:)`, disponible en el Preview **Recepción · solicitudes locales**, consume el mismo tipo de store y comando de asignación. No se añadió una cuenta ni una ruta de recepcionista autenticada a una app cuyo acceso actual solo incluye Doctor/Paciente.
- El receptor web de demostración se abre únicamente en modo diseño; al estar autenticado pide cerrar la sesión antes de cambiar de modo. La asignación es una simulación local, no una autorización real basada en el nombre de un actor.

## Archivos

### iOS

- Nuevo `HospitalUniversitario/HospitalUniversitario/Patient/PatientAppointmentFlow.swift`: modelos, store observable, Mis citas, adaptación de registros autorizados y vista local de recepción.
- Modificados `Patient/PatientAppointmentView.swift` y `Patient/PatientAppointmentComponents.swift`: formulario único, preferencia y confirmación Pendiente.
- Modificado `Doctor/DoctorConsultationTicketView.swift`: soporte embebido, etiqueta Volver y campos contextuales opcionales, sin alterar los valores predeterminados del Doctor.
- Modificados `ContentView.swift`, `Core/HospitalStore.swift` y `Modules/MobileModuleView.swift`: conexión al store compartido, rutas existentes, retirada del formulario anterior y accesos duplicados.
- El nuevo archivo Swift entra mediante el grupo sincronizado existente; no se cambió el target ni se añadió una dependencia.

### Web y pruebas

- Nuevo `web-preview/patient-appointments.js`: store local, adaptador de citas propias, ticket y recepción de demostración.
- Modificados `web-preview/app.js`, `modules.js`, `index.html`, `server.mjs`: integración, formulario único, preferencia, control de demostración y recurso servido sin caché.
- Modificados `scripts/test-preview.mjs`, `scripts/test-modules.mjs`; nuevo `scripts/test-patient-appointments.mjs`.

## Verificaciones de esta intervención

- `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`: recorridos de ambas cuentas y 20 pantallas; formulario, validaciones, síntomas y especialidades.
- `node --preserve-symlinks --preserve-symlinks-main scripts/test-patient-appointments.mjs`: ticket completo, formulario único, preferencia obligatoria, Pendiente, doble envío, recepción local, rechazo de fecha pasada, asignación única, próxima cita actualizada, aislamiento de fixtures y error sin cita inventada.
- `node --preserve-symlinks --preserve-symlinks-main scripts/test-modules.mjs`: siete recorridos, incluida cancelación y consulta/receta/cierre del Doctor.
- `scripts/test-doctor-consultations.mjs` y `scripts/test-doctor-dashboard.mjs`: consultas/ticket y panel del Doctor aprobados con transporte simulado.
- `python scripts/check-project.py`, sintaxis de los JavaScript cambiados y `git diff --check`.
- Se reinició únicamente la sesión del servidor de vista previa que estaba abierta. `/`, `/app.js` y `/patient-appointments.js` responden HTTP 200 con `Cache-Control: no-store` en `http://127.0.0.1:4173`.

Las pruebas de interacción usan DOM y transporte simulados; no son pruebas reales contra Supabase ni revisión visual en navegador. No se compiló Swift/Xcode en Windows.

## Pendientes de conexión real

Compilar y revisar SwiftUI en Mac. Conectar el snapshot/preferencia a persistencia, implementar el acceso autorizado real de Recepción y su operación transaccional de asignación, incluyendo idempotencia y permisos de servidor. El prototipo no pretende cubrir esas operaciones reales. El backend existente y sus RPC no se modificaron.

Esta decisión reemplaza las indicaciones anteriores de mantener dos accesos/formularios separados para Agendar cita y Solicitar atención.
