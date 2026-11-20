# Revisión técnica previa a las pruebas del sistema — 20 de noviembre de 2026

No se aplicó ninguna migración ni se modificaron datos. Las consultas a Supabase se hicieron con el MCP en modo de solo lectura.

Etiquetas: **[Supabase]** verificado en el servidor · **[Código]** revisado en el repositorio · **[No ejecutado]** no comprobado.

## 1. Riesgos encontrados

| # | Riesgo | Situación |
|---|---|---|
| R1 | **Al aplicar `citas-turnos-jornada.sql`, 7 citas pasan a No atendida de inmediato.** El recuento subió de 6 a 7 porque avanzó la hora. | [Supabase] Ninguna tiene consulta (`clinical_encounters`); las 7 tienen turno. Se conservan sus datos, su turno y quedan en `appointment_status_history`. |
| R2 | **`pg_cron` está disponible, pero no instalado.** La migración ejecuta `CREATE EXTENSION`. | [Supabase] `pg_available_extensions` lo lista con `installed_version = null`. Requiere un rol con permiso para crear extensiones (por ejemplo `postgres` en el editor SQL). |
| R3 | **Las nuevas políticas de privacidad pueden afectar al panel externo de Recepción** si lee `medical_history` o `lab_orders` directamente. | [Código] La app iOS y web-preview usan RPC `SECURITY DEFINER` y no se ven afectadas. El panel de Recepción no está en este repositorio [No ejecutado]. Existe un archivo de reversión exacta. |
| R4 | **La función auxiliar de las políticas debe poder ejecutarla `authenticated`.** Si se le revoca el permiso, las consultas protegidas fallarían. | Corregido: `doctor_care_access` tiene `GRANT EXECUTE … TO authenticated`, igual que `treats_patient` y `cares_for` [Supabase]. |
| R5 | **La jornada recurrente real (`staff_recurring_journeys`, con `breaks` registrados como «Almuerzo») no era legible por el médico.** | [Supabase] Tiene RLS sin políticas y solo `read_staff_schedule`, exclusiva de administración, la lee. Se preparó `doctor-mi-horario.sql`, con una RPC de lectura propia. |
| R6 | **«Mi horario» presentaba todos los huecos como descanso.** | Corregido: el almuerzo y los descansos solo aparecen si están registrados; un hueco sin registro es «Entre jornadas», sin recordatorio. |
| R7 | **El 14 de noviembre hay un turno repetido entre dos médicos (número 1).** | [Supabase] El índice único hospitalario se aplica desde el 15 de noviembre, y desde esa fecha no hay duplicados. Lo existente no se renumera. |
| R8 | **`planning_guard` ejecuta `assert_staff_planning()` con cada cambio de citas.** | [Supabase] Solo valida solapes de jornadas futuras. No impide el cambio de estado, salvo que la planificación ya fuera inválida, lo que impediría cualquier cambio de citas. |

## 2. Migraciones revisadas (todas preparadas, ninguna aplicada)

| Archivo | Qué hace | Compatibilidad con el esquema [Supabase] | Seguridad y repetición |
|---|---|---|---|
| `citas-turnos-jornada.sql` | Marca citas no atendidas (pg_cron, cada 5 min); avisa al médico de cancelaciones; turno por hospital y día; avisos de cambio de jornada | Usa columnas existentes: `appointments.status, ends_at, cancelled_by, cancellation_reason, queue_*`; el índice único de `notifications (recipient_id, event_key)`; `appointment_status_history (old/new_status, actor_id nulo)`. `kind` es texto libre (no hay CHECK) | Sin DROP de datos. `CREATE … IF NOT EXISTS`, `ON CONFLICT`, `DROP TRIGGER IF EXISTS`, el job de cron se reprograma sin duplicarse y el contador se inicializa con `greatest`. El vencimiento solo toca `programada/confirmada` sin consulta, con `FOR UPDATE SKIP LOCKED`: una segunda pasada no cambia nada |
| `paciente-avisos-solicitud-unica.sql` | Avisos al paciente (cita, receta, solicitud rechazada); solicitud única en el servidor | `prescriptions.status` admite `entregada`; `request_state` tiene pendiente y en_revision; `appointment_requests.closure_reason` existe | `CREATE OR REPLACE` y `DROP TRIGGER IF EXISTS`. Avisos sin duplicar gracias a `event_key` |
| `doctor-consultation-six-fields.sql` | Ahora solo lecturas: workspace con `patient_code`, `finished_at` y orden por `starts_at`; chart con `patient_code`. **Se retiró la relajación del cierre** | Definiciones basadas en `pg_get_functiondef` | `CREATE OR REPLACE`; conserva GRANT |
| `expedientes-historial.sql` | `patient_code` en la búsqueda; especialidad, motivo, horas, síntomas iniciales y recetas por consulta en chart; recetas y exámenes en el historial del paciente | Columnas verificadas: `appointment_request_symptoms`, `symptom_catalog.name`, `lab_results.published_to_patient_at`… | `CREATE OR REPLACE`. Aplicarlo **después** de six-fields |
| `doctor-mi-horario.sql` **(nuevo)** | `doctor_native_schedule`: jornada recurrente propia con `breaks`, `staff_shifts` y `staff_absences` | Reutiliza `private.recurring_work` y `private.recurring_instant`, igual que `read_staff_schedule` | Solo lectura y solo el médico autenticado (`native_doctor_id`); no la ejecuta `anon` |
| `rls-privacidad-clinica.sql` **(nuevo)** + `…-revert.sql` | Recepción sin antecedentes ni órdenes de laboratorio; médicos según su atención; el paciente ve los signos vitales solo tras el cierre | Las políticas reemplazadas se leyeron de `pg_policies`; el archivo de reversión las restaura tal cual | `DROP POLICY IF EXISTS` y `CREATE POLICY` dentro de una transacción |

No se pudo ejecutar el SQL contra el servidor porque el MCP es de solo lectura. La sintaxis y las dependencias se revisaron en el código y contra el catálogo [No ejecutado: ejecución real].

## 3. Citas que pasarían a «No atendida» [Supabase]

Todas en estado `programada`, con solicitud de origen y **0 consultas creadas**:

| Cita | Inicio – fin (America/El_Salvador) | Turno (fecha, n.º) | Médico (staff) |
|---|---|---|---|
| 7fde8889-59e1-43cb-8db4-0a1522edb6f1 | 14/11 09:00 – 09:30 | 2026-11-14 · 1 | 50398547… |
| e793223d-ed78-4110-93b1-9bd61a8ca578 | 14/11 11:30 – 12:00 | 2026-11-14 · 2 | 50398547… |
| ed14ea79-df19-4e0b-9242-8e70afa39e50 | 14/11 13:30 – 14:00 | 2026-11-14 · 1 | 0d4e5b52… |
| 9fcef590-f191-4644-a1b8-eb285e089d7d | 15/11 09:30 – 10:00 | 2026-11-15 · 1 | 50398547… |
| 7f6deed5-00a5-494a-a1ab-eb1a218e1a51 | 19/11 23:30 – 20/11 00:00 | 2026-11-19 · 2 | 0d4e5b52… |
| 37286ddb-83b6-4d63-90df-922393e56b95 | 20/11 09:30 – 10:00 | 2026-11-20 · 4 | bbbe4d82… |
| 661d5267-226d-4cf8-863d-61d6048f577c | 20/11 14:00 – 14:30 | 2026-11-20 · 2 | bbbe4d82… |

El número crecerá con las citas que venzan antes de aplicar la migración. Para revisarlo justo antes:

```sql
SELECT id, status, starts_at, ends_at FROM public.appointments
WHERE status IN ('programada','confirmada') AND ends_at < now()
  AND NOT EXISTS (SELECT 1 FROM public.clinical_encounters e WHERE e.appointment_id = appointments.id);
```

## 4. Turnos hospitalarios [Supabase]

- **Hoy:** el contador es por médico y día (`private.appointment_queue_counters`).
- **Duplicados:** existe un único número repetido, el n.º 1 del 2026-11-14 (dos médicos). Desde el 2026-11-15 no hay duplicados, y no hay citas sin turno.
- **Inicialización del contador por día:**

  | Día | Último turno |
  |---|---|
  | 14/11 | 2 |
  | 15/11 | 1 |
  | 19/11 | 2 |
  | 20/11 | 4 |
  | 27/11 | 1 |

  La siguiente cita de cada día recibe el número que sigue. No se renumera ni se recicla nada.
- **Concurrencia:** la fila del contador se bloquea dentro de la misma transacción que la cita (`INSERT … ON CONFLICT DO UPDATE … RETURNING`). Dos recepcionistas no obtienen el mismo número, y si la cita falla, el número se revierte con ella.

## 5. Tablas y funciones afectadas al aplicar

- **Tablas nuevas:** `private.appointment_queue_day_counters`. No se crean tablas públicas.
- **Índices nuevos:** `appointments_hospital_day_queue_unique` (parcial, desde el 2026-11-15).
- **Funciones nuevas:**
  - `private.mark_missed_appointments`, `private.doctor_cancellation_notice` y `private.doctor_schedule_notice`;
  - `private.patient_appointment_notice`, `private.patient_prescription_notice` y `private.patient_request_notice`;
  - `private.doctor_care_access` y `public.doctor_native_schedule`.
- **Funciones reemplazadas:** `private.assign_appointment_queue`, `public.submit_my_attention_request`, `public.doctor_native_workspace`, `public.doctor_native_chart`, `public.doctor_native_patients` y `public.my_consultation_history`.
- **Disparadores nuevos:**
  - en `appointments`: `doctor_cancellation_notice` y `patient_appointment_notice`;
  - en `prescriptions`: `patient_prescription_notice`;
  - en `appointment_requests`: `patient_request_notice`;
  - en las tablas de jornada (`doctor_schedules`, `staff_shifts` y `staff_absences`): `doctor_schedule_notice`, `doctor_shift_notice` y `doctor_absence_notice`.
- **Tarea programada:** `hospital-mark-missed-appointments` (pg_cron).

## 6. Permisos y políticas RLS

**Situación actual [Supabase]:**

- **`medical_history`:** la lee cualquiera que cumpla `can_read_patient`, que incluye recepcionista y admin.
- **`lab_orders`:** la leen recepcionista y admin.
- **`vital_signs` y `prescriptions`:** las lee cualquier médico con `treats_patient`, que incluye cualquier cita futura. El paciente ve los signos vitales aunque la consulta siga abierta.
- **Notas y diagnósticos:** solo el médico autor, o el paciente tras el cierre. Esto ya era correcto.

**Propuesta (`rls-privacidad-clinica.sql`):**

- **Recepción (punto 7):** ya no lee antecedentes (`medical_history`) ni órdenes de laboratorio. Sigue leyendo `patients` y `medical_records`, que necesita para sus funciones.
- **Médicos (punto 8):** solo con autorización asistencial vigente, según `private.doctor_care_access`. Hay acceso si se cumple alguna de estas condiciones:
  - una asignación activa en el equipo de atención;
  - una consulta propia previa o en curso con el paciente;
  - una cita propia en atención, o programada en una ventana de ±24 h.
  - Además, el médico autor de cada consulta conserva el acceso a ella.
- **Paciente:** ve los signos vitales solo tras el cierre. Sigue viendo sus recetas, sus órdenes y los resultados publicados para él.
- **Administración:** conserva el acceso.

Las RPC `doctor_native_*` mantienen su propia autorización. No se modificaron permisos EXECUTE de RPC existentes.

## 7. Recordatorios (punto 9)

- **Almuerzo:** solo si está registrado (`staff_recurring_journeys.breaks` con motivo «Almuerzo»).
- **Descanso:** cualquier otro descanso registrado, con su motivo.
- **«Entre jornadas»:** los huecos sin registro; nunca se presentan como almuerzo ni generan recordatorio.
- **iOS:** programa avisos locales 10 minutos antes, solo para almuerzo y descansos, con identificador estable (no se duplican).
- **Avisos de cambio de jornada:** llegan por la campana cuando se aplique `citas-turnos-jornada.sql`.

## 8. test-clinical-labs (punto 10)

El fallo es **previo** y ajeno a los cambios. Se ejecutó la prueba en copias de los commits `d828fd6` y `4abdab7` y falla igual: «Missing field DUI o nombre del paciente».

**Causa:** la segunda parte de la prueba entra como médico conectado y espera la vista **de diseño** antigua de Laboratorios. Desde `65d846e` («Connect Doctor/Patient views to Supabase…»), esa pantalla muestra el directorio conectado, y la vista de diseño solo aparece en modo diseño. Hay que actualizar la prueba para que active el modo diseño; no se cambió.

## 9. Revisión estática de Swift (punto 11)

**No se compiló**, porque este equipo no tiene Swift ni el SDK de Apple. Se hizo una revisión con un script y a mano:

- **Funciones repetidas:** las detectadas son la declaración del protocolo junto a su implementación. No hay conflictos.
- **Rutas a tuplas (`\.0`, `\.1`) y `.white.opacity`:** solo aparecen en código anterior que ya compila en Mac. El código nuevo usa índices o `Color.white`.
- **Símbolos nuevos:** todos están definidos en el target, que usa carpetas sincronizadas: `DoctorWeek`, `DoctorBreakReminders`, `AttentionRules`, `PatientNotificationBell`, `DoctorRecordsView`, los componentes `Consultation*`, `choiceChip`, `doctorEmpty`, `rxField`, `pickerTile`, `scheduleDay` y `scheduleRow`.
- **Riesgos que solo Xcode puede confirmar:** la inferencia de tipos en vistas largas (`ContentView.schedule`, `DoctorModuleView`) y los parámetros `[String: Any]` hacia JavaScriptCore.

## 10. Pruebas ejecutadas

**[Simulado], todas aprobadas:**

- test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-applicant, test-patient-record y test-patient-portal.
- test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-doctor-agenda y test-doctor-schedule (incluye almuerzo registrado frente a «Entre jornadas»).
- generate-models --check, check-project.py y git diff --check.

**Con fallo previo:** test-clinical-labs.

**[No ejecutado]:** pruebas Swift (⌘U), SQL contra un servidor y pruebas con cuentas reales.

## 11. Pasos para un entorno de pruebas (no producción)

1. **Crear el entorno:** una rama de Supabase (Branching) o un proyecto de pruebas con el mismo esquema. No usar `uvebpsbbwofthucghccc` hasta aprobar los resultados.
2. **Comprobar antes de aplicar:** ejecutar la consulta de la sección 3 y anotar las citas afectadas.
3. **Aplicar en el editor SQL, en este orden:**
   1. `citas-turnos-jornada.sql`
   2. `paciente-avisos-solicitud-unica.sql`
   3. `doctor-consultation-six-fields.sql`
   4. `expedientes-historial.sql`
   5. `doctor-mi-horario.sql`
   6. `rls-privacidad-clinica.sql`
4. **Comprobar después:**
   - `SELECT jobname FROM cron.job;`
   - La consulta de duplicados de turno (incluida en el archivo) debe dar vacío.
   - `SELECT status, count(*) FROM public.appointments GROUP BY 1;`
   - `SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('medical_history','lab_orders','vital_signs','prescriptions','lab_results');`
5. **Probar con cuentas de prueba** (sin datos reales de pacientes) los escenarios 1 a 8 del documento maestro:
   - dos recepcionistas programando a la vez, para comprobar que los turnos no se repiten;
   - un paciente que cancela, para comprobar el aviso al médico;
   - una cita vencida, para comprobar que pasa a No atendida en 5 minutos como máximo;
   - un cambio de jornada desde administración, para comprobar el aviso y Mi horario;
   - una cuenta de recepción, para comprobar que no lee `medical_history` ni `lab_orders`.
6. **En Mac:** Xcode 16.2 o posterior, ⌘B, ⌘U y ⌘R contra el entorno de pruebas.
7. **Reversión si algo falla:**
   - Permisos: `rls-privacidad-clinica-revert.sql`.
   - Cron: `SELECT cron.unschedule('hospital-mark-missed-appointments');`
   - Las funciones anteriores están en la sección 13 de `docs/ANALISIS_MODULO_DOCTOR_SUPABASE.md` y en `pg_get_functiondef` del entorno original.
