# Menú «Más» y Habitaciones con hospitalización — 20 de noviembre de 2026

## Análisis previo [Supabase, solo lectura]

Ya existe la estructura hospitalaria; no se crean tablas:

| Pieza | Uso |
|---|---|
| `hospital_admissions` | Episodio: `status` (`solicitado, asignado, hospitalizado, alta_medica, cerrado, cancelado`), `ordered_by` (médico), `ordered_at`, `medical_reason`, `clinical_instructions`, `medically_discharged_at/_by`, `discharge_notes`, `closed_at`. |
| `bed_assignments` | Cama por episodio con `assigned_at` / `released_at` (trazabilidad de traslados). |
| `beds`, `rooms` (`kind`: `vip`, `semiprivada`), `hospital_floors` | Habitación, clase y área. No existe «privada»: no se muestra. |
| Operaciones existentes | `request_admission` / `doctor_native_admission_request` (médico), `assign_bed` (recepción/admin), `medical_discharge` (médico que ordenó), `release_bed` (recepción/admin; cierra el episodio y pasa la cama a limpieza). |
| Validaciones existentes | `one_active_admission_per_patient`, `one_active_patient_bed`, `one_active_bed_patient`, `released_at >= assigned_at`, alta solo desde `hospitalizado` (no se finaliza dos veces), RLS `admission_read` (propio paciente, médico tratante, recepción, admin, equipo de cuidado). |

Faltaba: una lectura con nombre del médico y habitación accesible al paciente y al médico, y una operación de **traslado** (`assign_bed` rechaza otra cama si el ingreso ya está hospitalizado).

## SQL (aplicado el 20 de noviembre con autorización del usuario): `supabase/hospitalizaciones-paciente.sql`

- `my_hospitalizations()` — paciente; identidad por `auth.uid()`, sin `patient_id` del cliente.
- `doctor_native_patient_hospitalizations(p_patient)` — exige `native_doctor_id()` y `treats_patient()`.
- `transfer_bed(p_admission, p_bed)` — recepción/admin; cierra la asignación actual y abre otra en el mismo episodio, registra `bed_status_history`.
- Reversión al final del archivo. Sin borrados ni tablas nuevas.

Si la RPC fallara, iOS y web muestran «La consulta de hospitalizaciones aún no está disponible en el servidor (migración pendiente)», nunca datos inventados.

## Implementación (iOS ↔ web-preview)

- **Regla común:** `HospitalCore.hospitalizations` (`hospital-core.js`, cargado también por iOS). Activa = `asignado`/`hospitalizado`; `alta_medica` y `cerrado` → «Hospitalizaciones anteriores» con «Alta médica». Ingreso = primera asignación de cama; secciones sin campos vacíos.
- **Menú «Más» del paciente:** `ContentView.patientMenu` ↔ `patientMenu` (app.js). Grupos Mi atención, Mi salud, Servicios del hospital, Mi cuenta. Notificaciones sale solo de esta lista: la campana, el panel, `notifications`, servicios y RPC no cambian. El menú del médico y la pestaña Salud siguen igual. Se mantienen Mis citas, Solicitar atención y Mi turno para no dejar sin acceso la ruta `turns`.
- **Habitaciones (pantalla original `rooms`, sin rutas nuevas):** paciente → `PatientHospitalizationView` (contenido) ↔ `patientRooms`; médico → catálogo de habitaciones como antes. Estado vacío, tarjeta «Tu hospitalización actual», detalle (ingreso, habitación, información médica, alta, traslados) y anteriores.
- **Expediente del médico:** sección «Hospitalización» en `DoctorRecordsView` ↔ `recordsView` (modules.js).
- **Ejemplos de diseño:** solo en modo diseño web (`stayExamples`, marcados «(ejemplo)»); iOS no usa ejemplos.
- No hay campo de diagnóstico ni especialidad del médico asociados al ingreso en el esquema actual: no se muestran (el motivo médico sí).

## Pruebas

| Prueba | Tipo | Resultado |
|---|---|---|
| `scripts/test-hospitalizations.mjs` (escenarios A–D y E estático) | Núcleo con transporte simulado | Aprobada |
| `scripts/test-preview.mjs` (menú agrupado, sin Notificaciones, campana presente, Habitaciones sin ficticios) | Simulado | Aprobada |
| Revisión visual web modo diseño (menú, Habitaciones, detalle) | Navegador integrado | Realizada |
| Escenarios B–E contra Supabase real | — | **No ejecutados**: requieren aplicar el SQL y registrar ingresos reales |
| Compilación Swift / revisión visual iOS | — | **Pendiente de Mac** |
