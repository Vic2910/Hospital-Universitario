# Conexión de Doctor/Paciente a Supabase y datos de ejemplo en la base (2026-10-31)

## Objetivo

Conectar las vistas de Doctor y Paciente (iOS/SwiftUI y su réplica web) al proyecto Supabase «Hospital Universitario» (`kgulityewtcyvjnxeskd`) respetando el flujo diseñado de cada pantalla, eliminar los ejemplos locales de las listas conectadas y crear los ejemplos dentro de la base de datos, que antes solo tenía registrado «Paciente de prueba».

## Trabajo de aplicación (iOS y web, por duplicado)

Convención vigente del repositorio: todo cambio visible se implementa en la app iOS/SwiftUI (fuente de verdad, compilable en Xcode) y en la vista previa web `web-preview/`, conservando en ambas la lógica existente (autenticación, validaciones, API, sesión y rutas).

- **iOS (`HospitalUniversitario/HospitalUniversitario/`)**
  - `Core/HospitalStore.swift`: `refreshScreen` carga datos reales por pantalla; `request`/`schedule` traen `my_profile()` y `modules.load("request")`, `home` del Paciente carga `modules.load("appointments")` y `profile` carga `my_profile()` y `modules.load("profile")`.
  - `ContentView.swift`: rama real `PatientAppointmentRealView` para solicitar/agendar; `PatientAppointmentsView` sin `useExamples`; recetas/historial sin ejemplos en modo real; «próxima cita» real en el inicio del Paciente (próxima cita `scheduled`/`confirmed` desde hoy, con «Médico» y título desde el módulo); perfil del Paciente renderizado con `MobileModuleView(module: "profile")`; fallback del flujo sin ejemplos; se eliminó el `@StateObject appointmentFlow` local.
  - `Patient/PatientAppointmentView.swift`: `PatientAppointmentRealView` conectado — especialidades del catálogo real (`options` con `kind: specialty`), datos del Paciente en solo lectura desde el perfil, «Fecha preferida» con `DatePicker`, preferencia Mañana/Tarde (08:00–12:00 / 13:00–17:00), validación con `puedeAgendar`, envío con `model.requestAppointment()` e «Mis solicitudes» desde `model.items`. Se conserva `PatientAppointmentView` local solo para previews.
  - `Patient/PatientAppointmentFlow.swift`: `PatientAppointmentsView` sin «Mis solicitudes de ejemplo» ni ejemplos en el ticket; `ReceptionAppointmentExampleView` solo para previews.
  - `Core/MobileModuleViewModel.swift`: nueva propiedad `@Published var symptoms: [String]`; `requestAppointment()` concatena los síntomas a `p_reason` (la RPC no tiene parámetro de síntomas) y se limpian en `clear()` y tras envío exitoso.
  - `Doctor/DoctorModuleView.swift`: consulta del Doctor sin fallback `DoctorConsultationDemo.appointments` (agenda con lista vacía en modo real).
- **Web (`web-preview/`)**
  - `app.js`: `scheduleView` real con especialidades del módulo, `scheduleCanSubmit`, `homeAppointments`/próxima cita en el dashboard, módulos sin ejemplos en modo real, «+ Nueva receta» como nota informativa y perfil con `modules.render('profile')`.
  - `patient-appointments.js`: parámetro `requests` para las solicitudes.
- **Scripts (`scripts/`):** seis suites actualizadas en esta sesión para el modo real (`test-preview`, `test-modules`, `test-profile`, `test-patient-history`, `test-patient-prescriptions`, `test-doctor-consultations`); el resto de suites (`test-patient-appointments`, `test-patient-chart`, `test-doctor-dashboard`, `test-doctor-patients`, `test-clinical-labs`, `test-account-tools`) ya estaban adaptadas.

## Datos de ejemplo creados en Supabase

Los datos se crearon con SQL por el MCP de Supabase, sobre las cuentas existentes («Médico DE PRUEBA» / «Paciente de prueba», expediente `DEMO-EXP-001`, personal `DEMO-MED-001`), sin crear cuentas nuevas y sin tocar esquema, RPC ni políticas. Todo se insertó respetando los triggers `private.touch_and_audit()` y `private.validate_record()` (autores coherentes, catálogos válidos, receta en `draft` antes de emitir, resultados en `draft` antes de validar/liberar).

Se creó o completó:

- **Infraestructura:** 2 consultorios en Medicina interna (`CONS-101`, `CONS-102`), jornada del médico hoy 08:00–16:00 (`staff_shifts`, `confirmed`), 1 aviso público («Vacunación de influenza»), cola del día con 1 turno `waiting` para el Paciente.
- **Citas:** 3 citas del Paciente con el médico de prueba en Medicina interna — pasada `completed` (ayer 09:00), próxima `confirmed` (hoy, a ~3 horas de la ejecución, para que siempre aparezca como «próxima») y futura `scheduled` (+7 días). La solicitud `pending` preexistente (2026-00-29, Pediatría) se conserva.
- **Atención clínica:** 1 encuentro `outpatient` cerrado de la cita pasada, 1 nota clínica firmada (faringitis aguda, SOAP completo) y su diagnóstico principal (`J06.9`).
- **Receta:** 1 receta `issued` con 2 ítems (Amoxicilina 500 mg y Paracetamol 500 mg, vía oral, cada 8 horas, con fechas y cantidad).
- **Laboratorio:** 1 orden `completed` (`ORD-DEMO-0001`) con Hemograma de control y Glucosa en ayunas, resultados `released` con valores (Hb 13.5 g/dL; Glucosa 92 mg/dL, `normal`).
- **Perfil clínico del Paciente:** alergia (Penicilina, moderada), condición resuelta (J06.9), antecedente familiar, teléfono y correo de la persona, contacto de emergencia (tutora) y vínculo `care_assignments` entre el médico y el Paciente.
- **Catálogos:** medicamentos (Amoxicilina/Paracetamol 500 mg), analitos (HGB, GLU, WBC), pruebas de laboratorio y sus analitos (`test_analytes`), códigos de diagnóstico (J06.9, A09, J21.9) y alérgenos (Penicilina, Polen). Las vías de administración y alérgenos preexistentes se conservaron; se eliminó una vía duplicada creada durante la siembra.

## Hallazgos técnicos relevantes

- El esquema real está en `hospital.*`; `public.*` solo contiene vistas de catálogo. Las RPC de móvil son `public.mobile_module` (envoltorio) y `private.mobile_module`.
- `private.mobile_module` es `SECURITY DEFINER` con owner `hospital_api` y las tablas tienen `ROW LEVEL SECURITY` + `FORCE`, de modo que dentro del RPC sí aplican las policies de `hospital_api`. Para que el Doctor vea recetas, la política exige `private.can_encounter(encounter, 'clinical.read')`, que a su vez exige el permiso `clinical.read` en la sede **y** un `care_assignments` vigente Paciente–Personal; sin ese vínculo el módulo del Doctor devuelve vacío aunque la receta exista.
- `validate_record()` impide modificar una receta `issued` (incluidos sus ítems) y exige que los ítems se agreguen en `draft`; los resultados de laboratorio se cargan en `draft`, se validan y luego se liberan. La transición de estados de citas también está restringida.
- `request_appointment(p_patient, p_facility, p_specialty, p_reason, p_date, p_from, p_to, p_request_key)` no tiene parámetro de síntomas ni de preferencia: la app los traduce a motivo y franja horaria.

## Verificaciones ejecutadas

- **Supabase (reales, con claims simulados y `ROLLBACK`**, siguiendo `docs/sql/test-mobile-flows.sql`): sesión `aal2` para ambas identidades demo; como Paciente: `my_access`, módulos `appointments` (3 citas), `request` (catálogo de especialidades y solicitudes), `chart` (alergias/condiciones/antecedentes), `history` (encuentro con nota firmada), `prescriptions` (receta con Amoxicilina), `laboratory` (2 estudios liberados con glucosa), `notifications` y `profile`; `request_appointment` con idempotencia por `p_request_key`; suplantación de rol rechazada y cuenta sin vínculo rechazada. Como Doctor: `my_access`, `prescriptions` (receta `issued` propia) y `profile`; acceso a módulos de Paciente rechazado. La verificación completa terminó sin excepciones.
- **Locales:** `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs` (8 recorridos y 20 pantallas aprobados, más agendar cita en diseño y sesión), `python scripts/check-project.py` (referencias, recursos, esquema y pantallas) y `git diff --check` (sin observaciones). `scripts/test-account-codes.mjs` sigue requiriendo `.local/test-accounts.json` (condición conocida, no relacionada).

## Qué no se verificó

- Compilación y pruebas Swift: requieren Xcode en Mac; no se anuncia ninguna compilación.
- Login real con las credenciales de `.local/`: las credenciales no están disponibles en esta copia; la verificación contra Supabase se hizo con claims simulados en transacciones revertidas.
- Revisión visual en navegador o dispositivo.

## Supuestos

- «Solicitar atención» en modo real usa el catálogo real de especialidades, reemplaza la rejilla de horarios por «Fecha preferida» + preferencia Mañana/Tarde y muestra los datos del Paciente en solo lectura desde el perfil; los síntomas se añaden al motivo porque la RPC no los admite. Web e iOS se mantienen coherentes.
- Los ejemplos de la base son ficticios, están ligados a las cuentas demo existentes y no deben interpretarse como registros clínicos reales.
- La cita «próxima» sembrada se sitúa a ~3 horas de la fecha de ejecución para que el inicio del Paciente siempre la muestre como próxima; si el proyecto se usa días después, la cita pasará a histórico y convendrá sembrar una nueva.
