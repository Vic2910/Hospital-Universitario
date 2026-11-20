# Análisis del módulo Doctor y su conexión con Supabase — 20 de noviembre de 2026

**Proyecto:** Hospital Móviles, `uvebpsbbwofthucghccc`. **Clientes:** iOS/SwiftUI y la réplica `web-preview/`.

Para cada afirmación se indica de dónde sale:

- **[Supabase]**: consultado en el servidor desplegado mediante el MCP, en modo de solo lectura. Se usaron `pg_proc`, `pg_get_functiondef`, `pg_policies`, `pg_trigger`, `information_schema`, `pg_publication_tables` y los privilegios.
- **[Código]**: leído en este repositorio.
- **[No comprobado]**: no se pudo verificar. No se ejecutó ninguna escritura, migración ni cambio de permisos en Supabase.

## 1. Arquitectura actual

- **[Código] Clientes**:
  - iOS: `DoctorModuleView` y sus vistas, sobre `DoctorViewModel`, `DoctorRepository` y `HospitalAPI.doctorRPC`. `doctorRPC` es una lista cerrada de 15 nombres `doctor_native_*` y envía el JWT del usuario.
  - Web: `web-preview/modules.js` y `doctor-dashboard.js`, sobre `api.js` (`doctorRPC` con la misma lista).
  - Las reglas comunes están en Swift `DoctorClinicalRules` y `DoctorRecordRules`, y en JS `HospitalCore.doctorClinical`.
  - Los clientes nunca envían `doctor_id` ni `user_id`. La identidad sale de `auth.uid()` en el servidor.
- **[Supabase] Autorización**:
  - Las 18 funciones públicas del módulo son `SECURITY DEFINER` con `search_path=''`. Las ejecuta `authenticated` y **no** `anon`: los 16 `doctor_native_*`, `my_consultation_history`, `update_appointment_status` y `cancel_appointment`.
  - `private.native_doctor_id()` exige el rol activo `doctor` y una fila `staff` activa con `profile_id = auth.uid()` y `category = 'doctor'`. Si falta, devuelve el error 42501.
  - `private.treats_patient(p)` es verdadero cuando el médico tiene con ese paciente una cita vigente o completada (`programada`, `confirmada`, `en_atencion` o `completada`), una consulta propia o una asignación activa en `care_team_assignments`.

## 2. Pantallas existentes [Código]

| Pantalla | iOS | Web | RPC |
|---|---|---|---|
| Inicio / panel | `DoctorDashboardView` | `HospitalDoctorDashboard` | `workspace`, `alerts` |
| Consultas (agenda) | `DoctorConsultationAgendaView` (rediseñada) | `HospitalDoctorConsultations.render` (rediseñada) | `workspace` y `planning_revision` (REST) |
| Detalle de cita | `DoctorConsultationTicketView` | ticket en `doctor-dashboard.js` | — |
| Consulta médica | `DoctorModuleView.consultationWorkspace` | `consultationForm` | `start`, `chart`, `save`, `finish` |
| Exámenes / Receta | hojas dentro de la consulta | panel dentro de la consulta | `lab_catalog`, `labs`, `prescribe` |
| Pacientes / Expediente | `DoctorRecordsView` | `recordsView` | `patients`, `chart`, `patient_labs` |
| Laboratorios | `directory(laboratory:)` | `directoryView` | `lab_orders`, `patient_labs`, `lab_catalog` |
| Ingresos | `admissionsView` | `admissionsView` | `admissions`, `admission_request` |
| Avisos | campana / `notifications` | campana | `alerts`, `PATCH notifications` |

## 3. Desde que Recepción agenda hasta que el médico finaliza

1. **[Supabase]** Recepción inserta o actualiza `appointments` (`doctor_id`, `patient_id`, `starts_at`, `ends_at`, `consulting_room_id` y `request_id` opcional) desde su panel externo. Al hacerlo se disparan:
   - `appointment_queue_assignment`, que asigna `queue_number` y `queue_date`;
   - `planning_lock` y `planning_guard`, que impiden solapamientos;
   - `doctor_appointment_notice`, que crea un aviso «Cita asignada» para el médico si su vínculo y su rol están activos;
   - `planning_revision_changed`, que incrementa `planning_revision.revision`.
2. **[Supabase]** El médico pide `doctor_native_workspace(p_from, p_to)`:
   - Rango máximo de 32 días.
   - Filtra `a.doctor_id = native_doctor_id()`, así que **solo recibe sus citas**.
   - Une `patients`, `medical_records` (obligatorio), `clinical_encounters`, `appointment_requests` (motivo y síntomas), `specialties` y `consulting_rooms`.
   - Traduce los estados: programada → `scheduled`, confirmada → `confirmed`, en_atencion → `in_progress`, completada → `completed`, cancelada → `cancelled`, y cualquier otro (`no_asistio`) → `no_show`.
   - **Ordena por el texto de `tstzrange`.** El cliente reordena siempre por fecha y hora reales.
3. **[Código]** La agenda muestra **PENDIENTES** y **FINALIZADAS** (sección 13). Un toque abre el detalle; «ABRIR CONSULTA MÉDICA» llama a `doctor_native_start`.
4. **[Supabase]** `doctor_native_start(p_appointment, p_key)`:
   - Exige que la cita sea propia y la bloquea con `FOR UPDATE`.
   - Si ya existe una consulta, devuelve la misma. Además, `clinical_encounters` tiene `UNIQUE (appointment_id)`. **No puede haber consultas duplicadas.**
   - Exige el estado programada, confirmada o en_atencion, y que falten **como máximo 30 minutos** para la hora de la cita.
   - Exige un expediente vinculado.
   - Inserta la consulta con `id = p_key` y cambia la cita a `en_atencion` con `update_appointment_status`.
5. **[Supabase]** `doctor_native_save(p_encounter, p_version, p_key, p_values)`:
   - Usa `native_doctor_encounter`: consulta propia, cita propia y consulta abierta (en_atencion y `ended_at` nulo).
   - Es idempotente por `last_save_key` y aplica control de versión (40001 si la versión cambió).
   - Las notas admiten 10 000 caracteres; el código de diagnóstico, 50.
   - Valida los rangos de los signos vitales.
   - Sobrescribe `subjective`, `objective`, `assessment` y `plan`, y la **última** fila de `vital_signs` del autor con las 6 medidas.
   - Mantiene **un** diagnóstico en `diagnoses`, con la descripción tomada de `assessment`.
6. **[Supabase]** `doctor_native_finish(p_encounter, p_version)`:
   - Exige la versión guardada (mayor que 0) y las 4 notas.
   - Fija `ended_at = now()` e incrementa la versión.
   - Llama a `update_appointment_status(..., 'completada')`, que solo permite pasar de en_atencion a completada.
   - Registra el cierre en `audit_logs`.
   - El disparador `native_complete_guard` vuelve a exigir, al completar la cita, que la consulta del médico esté cerrada **y las 4 notas, incluido `plan`**.
7. **[Supabase]** Después del cierre, el paciente ve la consulta en `my_consultation_history` y en la RLS `encounters_read` (dueño tras el cierre). El médico la ve en `doctor_native_chart`.

## 4. Tablas utilizadas [Supabase]

- **Citas y planificación**: `appointments` (columnas: `id`, `request_id`, `patient_id`, `doctor_id`, `consulting_room_id`, `starts_at`, `ends_at`, `status`, `created_by`, `cancellation_*`, `queue_number`, `queue_date`), `appointment_status_history`, `appointment_requests`, `appointment_request_symptoms`, `symptom_catalog`, `specialties`, `consulting_rooms`, `planning_revision`.
- **Identidad**: `profiles`, `user_roles`, `staff`, `patients`, `medical_records`, `care_team_assignments`.
- **Clínicas**: `clinical_encounters` (`id`, `record_id`, `appointment_id` único, `doctor_id`, `started_at`, `ended_at`, `subjective`, `objective`, `assessment`, `plan`, `version`, `last_save_key`), `vital_signs`, `diagnoses`, `medical_history`.
- **Laboratorio**: `lab_test_types`, `lab_orders`, `lab_results`.
- **Recetas**: `medications`, `prescriptions`, `prescription_items`.
- **Ingresos**: `hospital_admissions`.
- **Avisos y auditoría**: `notifications`, `audit_logs`.

**Estados de la cita (`appointment_state`)**: programada, confirmada, en_atencion, completada, cancelada y no_asistio.

## 5. RPC utilizadas [Supabase]

`doctor_native_` workspace, start, save, finish, chart, patients, patient_labs, lab_catalog, labs, lab, lab_orders, prescribe, admissions, admission_request y alerts. Además: `my_consultation_history` (paciente), `update_appointment_status` (interna) y `request_admission` (interna).

## 6. Relaciones

```text
profiles ─1:1─ staff (category=doctor) ─< appointments >─ patients ─1:1─ medical_records
appointments ─1:0..1─ clinical_encounters (UNIQUE appointment_id) ─< vital_signs, diagnoses, lab_orders, prescriptions
appointments ─0..1─ appointment_requests ─< appointment_request_symptoms >─ symptom_catalog ; appointment_requests ─ specialties
lab_orders ─0..1─ lab_results ; prescriptions ─< prescription_items >─ medications ; medical_records ─< medical_history
```

## 7. RLS, permisos, disparadores y seguridad [Supabase]

- **Notas y diagnósticos**:
  - `encounters_read` permite leer al médico autor (`owns_clinical_note`) o al paciente propietario cuando la consulta ya está cerrada. `diagnoses_read` sigue la misma regla.
  - `doctor_native_chart` filtra `e.doctor_id = d`.
  - Resultado: **un médico no lee las consultas de otro médico** ni siquiera para un paciente compartido.
- **Paciente**: `my_consultation_history` exige el rol `paciente` y `p.profile_id = auth.uid()`, y solo devuelve consultas cerradas. Sus RPC no reciben identificadores de paciente.
- **Recepción**: no lee notas ni diagnósticos. Sí lee, por diseño operativo o pendiente de decisión:
  - `patients`, `medical_records` y **`medical_history`** (antecedentes: alergias, condiciones), porque `can_read_patient` incluye `recepcionista`;
  - `lab_orders.reason` (`laborder_read`);
  - `appointment_requests` (motivo y síntomas, necesarios para programar);
  - `hospital_admissions` (motivo médico del ingreso, necesario para asignar cama).
- **Médicos tratantes no autores**: `vitals_read` y `prescription_read` permiten leer a cualquier médico que cumpla `treats_patient` y al paciente aunque la consulta siga abierta. Es un hallazgo previo, no modificado.
- **Disparadores**:
  - En `appointments`: cola, identidad, `doctor_appointment_notice`, `native_complete_guard`, `planning_guard` y `planning_lock` (contra solapamientos) y `planning_revision_changed`.
  - En `clinical_encounters`: guarda de identidad.
  - En `vital_signs`: guarda de escritura.
  - En `lab_orders` y `lab_results`: avisos y auditoría.
- **Realtime**: la publicación `supabase_realtime` solo contiene `planning_revision`. Es una sola fila y la pueden leer admin, recepción y doctor, nunca `anon`.

## 8. Laboratorio [Supabase]

- **Solicitud**:
  - `doctor_native_labs(p_encounter, p_tests[], p_reason, p_key)` acepta de 1 a 30 exámenes distintos y activos, con motivo, y exige una consulta propia abierta.
  - Es idempotente por `request_group = p_key`: cada orden recibe `id = md5(encounter:key:test)` y se crea con `doctor_native_lab`.
  - Estado inicial `pendiente`.
- **Resultados**: `lab_results` los publica el personal de laboratorio, que está fuera del módulo Doctor.
- **Qué ve el médico**: `native_mobile_lab_page` solo muestra un resultado si tiene `published_at`, `validated_at` y `validated_by`. El paciente, además, necesita `published_to_patient_at`.
- **Consultas del médico**:
  - `doctor_native_lab_orders`: sus órdenes y las de los pacientes que atiende.
  - `doctor_native_patient_labs`: las de un paciente con `treats_patient`, de 25 en 25 y con `encounter_id`.
  - `doctor_native_lab_catalog`: el catálogo activo.

## 9. Recetas [Supabase]

- `doctor_native_prescribe(p_encounter, p_key, p_lines)`:
  - Exige una consulta propia abierta y es idempotente por `id = p_key`.
  - Acepta de 1 a 30 líneas con medicamento activo, dosis, unidad, frecuencia de 1 a 720 h, vía oral o inyectable, cantidad, días (1 a 365) e indicaciones.
  - Crea la receta en estado `pendiente`.
- La receta pertenece a la consulta (`prescriptions.encounter_id`) y, a través de ella, al expediente.
- **Dónde se ve**:
  - El médico la ve en `doctor_native_chart.prescriptions`, **sin `encounter_id`**.
  - El paciente la ve en su módulo de recetas, por REST con RLS.
  - `my_consultation_history` **no** la incluye.

## 10. Expedientes [Supabase]

- `doctor_native_chart` incluye:
  - los datos del paciente (expediente, DUI, teléfono, correo y ciudad), **sin `patient_code`**;
  - los antecedentes de `medical_history`;
  - el historial de **las consultas del médico** (abiertas y cerradas), con signos vitales y código de diagnóstico;
  - las recetas.
- La relación con el expediente es `clinical_encounters.record_id → medical_records → patients`.
- `doctor_native_patients` busca entre los pacientes con `treats_patient` por nombre, correo, DUI y expediente, de 50 en 50. **No busca por `patient_code`.**

## 11. Ingresos hospitalarios [Supabase]

- `doctor_native_admission_request` exige `treats_patient` y una prioridad normal o urgente, y es idempotente por `(ordered_by, request_key)` con bloqueo transaccional.
- Llama a `request_admission`, que exige categoría y motivo, y una consulta propia del mismo paciente si se indica. Inserta en `hospital_admissions`.
- **[No comprobado]** La autorización y la asignación de cama las hace Recepción en su panel externo. El médico consulta el seguimiento con `doctor_native_admissions`.

## 12. Problemas encontrados

1. **`native_complete_guard` exige `plan`.** El archivo preparado `doctor-consultation-six-fields.sql` solo relajaba `doctor_native_finish`, así que el cierre seguiría fallando. **Corregido en el archivo** (sin aplicar): ahora también ajusta el disparador.
2. **`doctor_native_workspace` no publica `ended_at`.** La agenda no puede saber la hora real de finalización. Se añadió `finished_at` en la migración preparada; hasta entonces, FINALIZADAS usa la hora de la cita y lo indica en cada tarjeta.
3. **El orden por texto de `tstzrange` puede fallar.** El cliente reordena siempre; la migración preparada ordena por `starts_at`.
4. **`doctor_native_start` exige que falten 30 minutos o menos.** Hay un modo de pruebas preparado en `doctor-start-anytime.sql`, sin aplicar.
5. **Falta `patient_code`** en workspace, chart y patients. Falta `encounter_id` en las recetas de chart. Faltan motivo, recetas y exámenes en `my_consultation_history`. Las migraciones están preparadas.
6. **Privacidad pendiente de decisión**:
   - Recepción lee `medical_history` y `lab_orders.reason`.
   - `vital_signs` y `prescriptions` son legibles por cualquier médico tratante y por el paciente antes del cierre.
7. **Zona horaria**: los avisos y la edad usan `America/Guatemala`. Es el mismo desplazamiento UTC−6 que El Salvador y no altera los resultados.
8. **`update_appointment_status`** no tiene definición en los SQL locales; solo existe desplegada.

## 13. Diferencias entre el código local y Supabase

Comparación del cuerpo normalizado (sin espacios) de `pg_proc.prosrc` con cada definición de `supabase/*.sql`:

| Función | Coincide con lo desplegado | Difiere (a propósito o por desfase) |
|---|---|---|
| alerts | doctor-consultation-experience.sql | — |
| chart | doctor-patient-directory.sql | doctor-ios.sql (versión antigua); six-fields y expedientes-historial (propuestas sin aplicar) |
| finish, save, start, lab, prescribe | doctor-ios.sql (y start = doctor-start-restore-30min.sql) | six-fields (finish) y doctor-start-anytime (start), propuestas |
| workspace | **ninguno** | doctor-ios.sql (**desfase**: lo desplegado es más nuevo) y six-fields (propuesta construida sobre lo desplegado) |
| patients | doctor-patient-directory.sql | expedientes-historial (propuesta) |
| patient_labs | doctor-laboratory-multiple.sql | doctor-patient-directory.sql (versión antigua) |
| labs, lab_catalog, lab_orders | doctor-laboratory-multiple.sql | — |
| admissions, admission_request, request_admission | doctor-admissions.sql | — |
| my_consultation_history | patient-consultation-history.sql | expedientes-historial (propuesta) |
| update_appointment_status | — | sin definición local |

Las tres propuestas son `doctor-consultation-six-fields.sql`, `doctor-start-anytime.sql` y `expedientes-historial.sql`. Se redactaron a partir de `pg_get_functiondef` del servidor, no de los SQL antiguos.

## 14. Cambios realizados en esta intervención

**Agenda (iOS y web, con paridad)**:

- Solo dos filtros, **PENDIENTES** y **FINALIZADAS**, que son también los indicadores con su contador. Se retiraron Todos, Programadas, En consulta y Canceladas. Los estados de la base no cambian.
- **PENDIENTES**:
  - Muestra las citas programadas, confirmadas o en espera del día elegido, y las que están en consulta, por hora ascendente.
  - Hoy también muestra las consultas en atención abiertas en días anteriores, con el aviso «Abierta el …».
  - Nunca muestra canceladas, no asistidas ni finalizadas.
- **FINALIZADAS**:
  - Solo las completadas cuya **hora real de finalización** (`finished_at`) cae en la fecha elegida, la última finalizada primero.
  - Sin la migración se usa la hora de la cita y la tarjeta lo indica.
- **Fecha compacta**:
  - Hoy al abrir, con botones para el día anterior y el siguiente, indicador relativo (HOY, AYER…), calendario gráfico en una hoja (iOS) o selector nativo (web) y botón Hoy.
  - Al cambiar la fecha se consulta de nuevo.
- **Búsqueda compacta**: por nombre, apellido, código de paciente o expediente, sin distinguir acentos ni mayúsculas, combinada con el filtro y la fecha.
- **Tarjetas**: la hora destacada, el paciente, el estado, el motivo, el consultorio y el código o expediente.
- **Ventana pedida**: desde 2 días antes del día elegido hasta los 14 siguientes (máximo 32), para retomar consultas en atención y ver las finalizadas tarde.
- **Sincronización sin Realtime en la app**:
  - Cada 30 s, en Consultas y sin una consulta abierta, se lee `planning_revision` (una fila). La agenda solo se vuelve a pedir si el contador cambió.
  - La actualización es silenciosa: no bloquea la pantalla ni borra la agenda si falla.
  - Al finalizar una consulta, la agenda se recarga con la acción existente.
  - La publicación Realtime **no se modificó**.
- **Migración corregida** (sin aplicar): `doctor-consultation-six-fields.sql` ahora también ajusta `native_complete_guard`, publica `finished_at` y ordena el workspace por `starts_at`.

**Archivos modificados**:

- iOS: `Doctor/DoctorConsultationAgendaView.swift`, `Core/DoctorModels.swift`, `Core/DoctorViewModel.swift`, `Core/DoctorRepository.swift`, `Core/HospitalAPI.swift`, `ContentView.swift` y `HospitalUniversitarioTests/DoctorModuleTests.swift`.
- Compartido: `Shared/hospital-core.js`.
- Web: `web-preview/doctor-dashboard.js`, `modules.js`, `api.js`, `app.js` y `style.css`.
- Pruebas: `scripts/test-doctor-agenda.mjs` (nueva), `test-doctor-clinical-rules.mjs` y `test-doctor-preview-live.mjs`.
- SQL: `supabase/doctor-consultation-six-fields.sql`.

## 15. Pruebas ejecutadas

**En Windows**, con DOM y transporte simulados y datos sintéticos. Todas aprobadas:

- test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-applicant y test-patient-record.
- test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions y **test-doctor-agenda**.
- generate-models --check, check-project.py y git diff --check.

`test-clinical-labs` sigue fallando igual que en el commit d828fd6; es un fallo previo.

| N.º | Prueba solicitada | Resultado |
|---|---|---|
| 1, 2 | Citas del médico y pendientes por hora | Simulado ✔ |
| 3, 4 | Finalizadas de hoy y de días anteriores, por hora real | Simulado ✔ |
| 5 | Canceladas y no asistidas fuera de ambos filtros | Simulado ✔ |
| 6 | Consulta en atención (también la de ayer) retomable | Simulado ✔ |
| 7, 8 | Al finalizar sale de Pendientes y aparece en Finalizadas | Simulado ✔ (test-doctor-preview-live) |
| 9, 10 | Fecha (anterior, Hoy, nueva consulta al servidor) y búsqueda (nombre, apellido, código) | Simulado ✔ |
| 11, 12 | Solo citas propias | El cliente no envía identidad ✔. El filtro `a.doctor_id = native_doctor_id()` está verificado en la definición desplegada. **Sin prueba con dos cuentas reales.** |
| 13 | Actualización sin reiniciar | Implementada con `planning_revision`. **El temporizador no se ejecutó en las pruebas** (el entorno simulado no ejecuta `setInterval`). |
| 14 | Sin duplicados | `UNIQUE (appointment_id)` y `start` idempotente verificados en Supabase ✔. Una sola llamada a start en la prueba ✔ |
| 15 | Datos iguales a Supabase | No se comparó con datos reales del médico (el MCP es de solo lectura y no se suplantaron cuentas) |

## 16. Pendiente

- **Compilación y pruebas Swift en Xcode 16.2 o posterior** (⌘B, ⌘R, ⌘U). Hay una prueba nueva de la agenda y las anteriores; no se ejecutaron porque Windows no tiene el SDK de Apple.
- **Revisión visual** en distintos tamaños de iPhone.
- **Aplicar, con autorización**, `doctor-consultation-six-fields.sql` (cierre con seis campos, hora real de finalización y orden por `starts_at`), `expedientes-historial.sql` y, si se quiere el modo de pruebas, `doctor-start-anytime.sql`.
- **Probar con cuentas reales**: dos médicos, recepción y paciente.
- **Decidir** sobre los hallazgos de privacidad de la sección 12.6.
- **Opcional**: suscripción Realtime a `planning_revision` con supabase-swift en lugar del sondeo de una fila.
