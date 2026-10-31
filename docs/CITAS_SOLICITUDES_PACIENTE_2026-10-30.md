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


## Ajuste posterior solicitado — entrada única y referencia 180312

La petición posterior del usuario reemplaza la distribución anterior de Mis citas. Se inspeccionó `docs/design-reference/Captura de pantalla 2026-10-30 180312.png`: icono circular con check, título centrado, fecha/hora en negrita y acción azul al pie.

- **Mis citas ahora muestra una sola tarjeta pulsable: Cita asignada.** Se retiran de esa entrada los datos expandidos, el buscador, el acceso a solicitar y la cola de solicitudes.
- Al pulsar se presenta un ticket dentro del flujo y del marco de la app, sin ventanas externas. Incluye **Volver** en la esquina superior izquierda y **Volver a Mis citas** al pie. Cualquiera regresa a la tarjeta única.
- Se utiliza el check vino y el botón azul ya existentes en la paleta, con fecha/hora destacadas y secciones Datos de la cita, Datos del paciente y Motivo de la atención. Se mantienen especialidad, médico, consultorio, paciente, edad, DUI, teléfono, correo, motivo y síntomas, con los mismos datos autorizados/ejemplos y faltantes explícitos.
- SwiftUI presenta el ticket propio del Paciente dentro de `PatientAppointmentsView`, reutilizando `DoctorConsultationField` y sus normalizadores. La vista del Doctor no cambia en este ajuste.
- Cuando no hay cita asignada, abrir la tarjeta muestra un mensaje explicativo y permite volver. Los ejemplos siguen identificados y un error no activa una cita ficticia.
- La cancelación y registros conectados se conservan dentro de **Gestionar mis citas**, un apartado desplegable del detalle. Así no ocupan la entrada principal.
- **Solicitar atención** continúa accesible desde **Más**. Las solicitudes locales y sus estados se trasladan a un desplegable al final de ese formulario; se conserva Pendiente hasta asignación de Recepción de demostración.
- Se reemplazan el selector segmentado iOS y el desplegable web por dos tarjetas de selección: **Mañana · AM** y **Tarde · PM**, con icono solar, texto explicativo, borde vino y check en la opción elegida. Selección exclusiva, etiquetas accesibles y animación que respeta reducir movimiento. El dato guardado continúa siendo Mañana/Tarde y conserva su validación obligatoria.

**Archivos de este ajuste:** Patient/{PatientAppointmentFlow,PatientAppointmentView,PatientAppointmentComponents}.swift; ContentView.swift; web-preview/{patient-appointments.js,app.js,style.css}; scripts/{test-preview,test-patient-appointments,test-modules}.mjs; README.md y esta documentación/bitácora.

**Verificaciones ejecutadas en este ajuste:** test-preview (20 pantallas), test-patient-appointments (una sola entrada, datos del ticket, Volver superior/inferior, selección exclusiva AM/PM, validación, flujo local de Recepción, datos autorizados y error sin cita inventada), test-modules (siete recorridos incluida cancelación), test-doctor-consultations y test-doctor-dashboard aprobados. También sintaxis de app.js/patient-appointments.js, check-project.py y git diff --check. HTTP 200 y no-store en `/`, `/app.js`, `/patient-appointments.js` y `/style.css`, comprobando que el servidor actual entrega las nuevas clases del ticket/selector, sin abrir otra instancia.

Estas son comprobaciones con DOM/transporte simulado y HTTP local. No se ejecutó revisión visual de la app web en navegador ni compilación Swift/Xcode en esta intervención. Continúan pendientes Mac y la conexión real de Recepción/persistencia, sin cambios en roles, RPC o base de datos.


## Acceso directo desde Salud — 2026-10-30

Por petición posterior del usuario, la pestaña **Salud** del Paciente abre directamente **Solicitar atención**, sin menú intermedio ni buscador. Las rutas `health`, `request` y `schedule` reutilizan el mismo formulario y store; Salud permanece seleccionada. Se conservan los accesos históricos, los datos editables, AM/PM y la validación. El envío sigue como Pendiente en memoria y aparece en Recepción de demostración; no se agregó envío real al backend.

Archivos: ContentView.swift, Core/HospitalStore.swift, web-preview/app.js y scripts/test-preview.mjs. El helper de pruebas ahora entra por Salud, por lo que test-preview, test-patient-appointments y test-modules verifican el nuevo acceso y el recorrido existente hasta la asignación local de recepción. Los tres aprobaron, al igual que check-project.py y git diff --check. Pendiente compilación Swift en Mac; DOM/transporte simulados, sin escrituras reales a Supabase.
