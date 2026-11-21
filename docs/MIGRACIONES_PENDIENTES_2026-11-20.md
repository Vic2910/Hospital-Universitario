# Migraciones pendientes: inventario definitivo — 20 de noviembre de 2026

Este inventario sustituye a los recuentos de informes anteriores, que hablaban de «cuatro» o «seis» archivos según el momento.

**Método:** para cada archivo de `supabase/` se buscaron en Hospital Móviles (MCP, solo lectura), con `pg_proc`, `pg_trigger`, `pg_class` y `pg_get_functiondef`, sus objetos o el texto que lo distingue. **No se aplicó nada.**

## A. Pendientes de aplicar (7), en este orden

| Orden | Archivo | Evidencia de que falta [Supabase] | Qué cambia |
|---|---|---|---|
| 1 | `citas-turnos-jornada.sql` | No existen `mark_missed_appointments`, `appointment_queue_day_counters`, el índice `appointments_hospital_day_queue_unique` ni `doctor_schedule_notice`; pg_cron no está instalado | Citas vencidas → no_asistio cada 5 min; aviso de cancelación al médico; turno por hospital y día; avisos de jornada en **4 tablas** |
| 2 | `paciente-avisos-solicitud-unica.sql` | No existen `patient_*_notice`; `submit_my_attention_request` no incluye «Ya tienes una cita programada» | Avisos al paciente; una sola solicitud activa en el servidor |
| 3 | `doctor-consultation-six-fields.sql` (el nombre es histórico: solo lecturas) | `doctor_native_workspace` sin `finished_at` | Agenda con `patient_code` y `finished_at`, orden por hora |
| 4 | `expedientes-historial.sql` (después del 3; conserva su `patient_code`) | `doctor_native_chart` sin `reported_symptoms`; `my_consultation_history` sin `lab_orders` | Historial completo para médico y paciente |
| 5 | `doctor-mi-horario.sql` | No existe `doctor_native_schedule` | El médico lee su jornada recurrente con almuerzo y descansos |
| 6 | `notificaciones-idempotentes.sql` | `laboratory_notifications` todavía incluye la revisión en `event_key` | Un aviso por orden y destinatario; republicar no duplica. Opcional después: `notificaciones-duplicadas-limpieza.sql` (revisar su consulta; termina en ROLLBACK) |
| 7 | `rls-privacidad-clinica.sql` | No existe `doctor_care_access`; las políticas siguen siendo las antiguas | Recepción sin antecedentes ni órdenes de laboratorio; médicos según su autorización asistencial |
| 8 | `hospitalizaciones-paciente.sql` | **APLICADO el 20 de noviembre** (antes no existían `my_hospitalizations`, `doctor_native_patient_hospitalizations` ni `transfer_bed`) | Habitaciones del paciente, hospitalización en el expediente médico y traslados con trazabilidad |

**Opcional (modo de pruebas):** `doctor-start-anytime.sql`. **[Supabase]** `doctor_native_start` todavía exige 30 minutos de antelación. Los clientes ya permiten abrir la consulta a cualquier hora (`openingLeadMinutes = nil`), pero el servidor la rechaza si falta más de media hora. Al terminar las pruebas: `doctor-start-restore-30min.sql`.

## B. No aplicar

- `rls-privacidad-clinica-revert.sql`: solo para revertir el punto 6.
- `doctor-start-restore-30min.sql`: coincide con lo que está desplegado hoy.
- `test-*-rollback.sql`: scripts de verificación que terminan en ROLLBACK.

## C. Ya aplicados (sus objetos existen) [Supabase]

| Archivo | Objetos que lo confirman |
|---|---|
| `attention-account.sql` | `attention_request_owner`, `my_attention_context` |
| `attention-validation.sql` | sus redefiniciones; contenido exacto no comparado línea a línea |
| `clinical-write-integrity.sql` | `clinical_vitals_write_guard` y `clinical_appointment_identity_guard` |
| `doctor-admissions.sql` | `doctor_native_admissions` y `reception_admissions` |
| `doctor-consultation-experience.sql` | `doctor_native_alerts` y `doctor_appointment_notice` |
| `doctor-ios.sql` | `doctor_native_*` y `native_complete_guard` |
| `doctor-laboratory-multiple.sql` | `doctor_native_labs` |
| `doctor-patient-directory.sql` | `doctor_native_patients` |
| `patient-consultation-history.sql` | `my_consultation_history` |

## D. Dependencias y permisos [Supabase]

**Funciones que se reutilizan**

- Todas existen: `private.recurring_work(p_from, p_until, p_staff)` devuelve `journey_id, staff_id, work_day, starts_at, ends_at`, igual que lo usa el punto 5; `private.recurring_instant(date, time, time)`, `native_doctor_id`, `has_role`, `my_staff_id`, `cares_for` y `lab_permission`.
- `recurring_work` es SECURITY DEFINER y `authenticated` no la ejecuta directamente. Se llama desde dentro de `doctor_native_schedule`, que también es DEFINER, así que funciona.

**Columnas que se usan**

Todas existen:
- `doctor_schedules.doctor_id`;
- `staff_shifts.staff_id`, `staff_absences.staff_id` y `staff_recurring_journeys.staff_id`;
- `clinical_encounters`: `record_id`, `doctor_id`, `appointment_id` y `ended_at`;
- `care_team_assignments`: `patient_id`, `staff_id`, `starts_at` y `ends_at`.

**Permisos**

- Funciones nuevas: `REVOKE … FROM PUBLIC, anon`.
- Las de disparadores y cron no las ejecuta `authenticated`.
- `doctor_native_schedule` y `doctor_care_access` son ejecutables por `authenticated`, como las demás auxiliares de RLS.

**Orden**

- El 4 debe ir después del 3, porque ambos redefinen `doctor_native_chart`.
- El resto es independiente.
- El 7 (permisos) se recomienda al final, para poder revertirlo aislado.

## E. Efectos sobre otros proyectos

| Área | Efecto |
|---|---|
| **Recepción** | (1) Los turnos pasan a numerarse por hospital y día. Lo asigna el disparador y no se escribe a mano, así que el flujo de programar no cambia. Las citas vencidas aparecen como no_asistio. (2) Al rechazar una solicitud se avisa al paciente. (6) **Deja de leer `medical_history` y `lab_orders`**: si el panel externo las consulta directamente, esas vistas quedarán vacías. Revisar ese panel antes de aplicar el 6; reversión disponible. |
| **Administración** | (1) Al guardar horarios, jornadas, ausencias o jornadas recurrentes se inserta un aviso dentro de la misma transacción. Usa `ON CONFLICT DO NOTHING` y no cambia `save_staff_planning_set` ni la sincronización (`planning_revision_changed` sigue en las cuatro tablas). (6) Conserva todo su acceso. |
| **Laboratorios** | (6) `laborder_laboratory_read` y `lab_permission` en `lab_results` no se tocan, así que laboratorio no pierde acceso. Las RPC `doctor_native_lab*` no dependen de las políticas. (2) Entregar una receta avisa al paciente. |
| **Farmacia** | (2) Cambiar una receta a `entregada` genera el aviso al paciente; no cambia el flujo. |

## F. Avisos de cambio de jornada (en el archivo 1)

| Fuente que modifica administración | Disparador | Texto |
|---|---|---|
| `doctor_schedules` (semanal) | `doctor_schedule_notice` | «Administración actualizó tu horario laboral.» |
| `staff_shifts` (por fecha) | `doctor_shift_notice` | Ídem |
| `staff_absences` | `doctor_absence_notice` | «Se registró o modificó una ausencia en tu jornada.» |
| `staff_recurring_journeys` | `doctor_recurring_journey_notice` (**nuevo**) | «Administración actualizó tu jornada recurrente (horario, almuerzo o descansos).» |

**Sin duplicados.** El `event_key` es `schedule:<staff>:<AAAAMMDDHHMI>` y el índice único `notification_event_once` lo respalda, así que un cambio masivo, o el reemplazo de filas de `save_staff_planning_set`, produce un solo aviso por minuto. Un guardado que cruce el cambio de minuto puede producir dos.

**[No ejecutado]:** no se probó contra un servidor; requiere el entorno de pruebas.
