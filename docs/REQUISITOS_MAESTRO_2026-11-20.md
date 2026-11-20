# Documento maestro: implementación, migraciones y pendientes — 20 de noviembre de 2026

Trabajo hecho sobre el proyecto real, con paridad entre iOS/SwiftUI y `web-preview/`. No se modificaron el ADMIN ni Recepción.

Copia de seguridad: el último commit del repositorio, `4abdab7`, contiene el estado previo; los cambios quedan sin confirmar en el árbol de trabajo.

Para cada punto se indica de dónde sale la información:

- **[Supabase]**: inspección del servidor desplegado mediante el MCP, en modo de solo lectura.
- **[Simulado]**: pruebas web con DOM y transporte simulados.
- **[No ejecutado]**: no se pudo comprobar.

## Errores encontrados

1. **Error «falta el plan de tratamiento» al finalizar.** **[Supabase]** `doctor_native_finish` y el disparador `native_complete_guard` exigen las cuatro notas: `subjective`, `objective`, `assessment` y `plan`. El formulario de seis campos había quitado el plan. **Corrección:** el plan vuelve a tener su propio campo obligatorio y el cierre funciona con lo que ya está desplegado. `doctor-consultation-six-fields.sql` ya no relaja el cierre.
2. **Síntomas del paciente copiados a la nota médica.** Se precargaban en `subjective` y podían editarse. **Corrección:** se muestran aparte, de solo lectura, desde `appointment_requests`. La nota del médico empieza vacía.
3. **Citas vencidas sin cambio de estado.** **[Supabase]** Nada marcaba `no_asistio`; hoy hay 6 citas vencidas sin atender.
4. **Cancelación sin aviso al médico.** **[Supabase]** `cancel_appointment` registra quién cancela, cuándo y el motivo, pero no avisa al médico.
5. **Turno único solo por médico.** **[Supabase]** El 14 de noviembre ya hay un número repetido entre dos médicos.
6. **Jornada sin avisos de cambio ni hora de almuerzo.** **[Supabase]** No hay ninguna columna de almuerzo; la jornada está en `doctor_schedules`, `staff_shifts` y `staff_absences`.
7. **Recordatorios.** No hay APNs (push remoto). Solo hay notificaciones guardadas en la tabla `notifications` y recordatorios locales de iOS.

## Tabla de requisitos

| N.º | Requisito | Archivos | Estado | Evidencia |
|---|---|---|---|---|
| 1 | Formulario y sus campos, iguales que el backend | Swift `DoctorModels` y `DoctorModuleView`; JS `hospital-core` y `modules.js` | Implementado: peso, altura, temperatura y las cuatro notas, con el plan como campo propio | [Simulado] test-doctor-preview-live y test-doctor-clinical-rules |
| 2 | Síntomas originales de solo lectura | `DoctorModuleView`, `DoctorViewModel` y `modules.js` | Implementado | [Simulado] el campo empieza vacío y los síntomas no son editables |
| 3 | Guardar y finalizar; mensaje si falla el guardado | `DoctorViewModel.closeConsultation` y `modules.finishConsultation` | Implementado: «No se ha guardado la consulta. Guarda los cambios antes de finalizar la atención.» | [Simulado] el fallo de guardado no cierra |
| 4 | Citas no atendidas automáticas en el servidor | `supabase/citas-turnos-jornada.sql` (`mark_missed_appointments` y pg_cron cada 5 min); etiqueta «No atendida» en Swift y JS | SQL preparado, **no aplicado**; cliente implementado (sección «Canceladas y no atendidas» en FINALIZADAS) | [Simulado] test-doctor-agenda. [No ejecutado] cron |
| 5 | Cancelación con aviso al médico | `citas-turnos-jornada.sql` (`doctor_cancellation_notice`) | SQL preparado, **no aplicado** | [No ejecutado] |
| 6 | Turno único por hospital y día | `citas-turnos-jornada.sql` (contador diario y `appointments_hospital_day_queue_unique`) | SQL preparado, **no aplicado**. Mi turno (pantalla original) ya muestra el número | [Simulado] test-patient-portal |
| 7 | Mi horario sincronizado con administración | Pantalla existente `ContentView.schedule` / web `schedule`; `HospitalCore.doctorWeek`; `DoctorWeekModels.swift`; `HospitalStore` | Implementado: lectura real, semana en tarjetas, navegación y actualización cada 30 s | [Simulado] test-doctor-schedule |
| 8 | Avisos de cambio de jornada y recordatorio de descanso | `citas-turnos-jornada.sql` (`doctor_schedule_notice`); `DoctorBreakReminders` (iOS) | Avisos: SQL preparado, **no aplicado**. Descanso: recordatorio local de iOS 10 min antes de cada hueco entre bloques; no hay almuerzo en el esquema | [No ejecutado] en el dispositivo |
| 9 | Historial y detalle de consultas anteriores | `DoctorRecordsView`, `modules.recordsView`, `PatientHistoryView`, `patient-history.js` y `hospital-core` | Implementado: paciente, médico, especialidad, inicio, fin y duración, síntomas iniciales y bloques clínicos, de solo lectura. Inicio, fin, especialidad, motivo y síntomas iniciales requieren `expedientes-historial.sql` | [Simulado] test-doctor-directory y test-doctor-alerts-history |
| 10 | Rediseño del formulario de solicitud sin cambiar la lógica | `PatientAttentionLiveView`, `app.js` y `style.css` | Implementado (mismos campos, validaciones y llamadas) | [Simulado] test-attention-navigation |
| 11 | Mostrar solo la solicitud reciente | Ídem | Implementado: las anteriores quedan en una hoja o desplegable aparte y no se borran | [Simulado] test-attention-navigation |
| 12 | Auditoría de validaciones, permisos y RLS | Este informe y `docs/ANALISIS_MODULO_DOCTOR_SUPABASE.md` | Hecha. Ver abajo | [Supabase] |
| — | Solicitud única y avisos del paciente | `paciente-avisos-solicitud-unica.sql` (intervención anterior) | Cliente implementado; SQL **no aplicado** | [Simulado] |

## Auditoría (punto 12) [Supabase]

**Ya garantizado en la base:**

- **Solapes:** las restricciones `EXCLUDE` impiden que un médico, un consultorio o un paciente tengan dos citas activas a la vez.
- **Horas:** `ends_at > starts_at`.
- **Turnos:** el turno debe ser mayor que 0 y no puede escribirse a mano (lo impide el disparador).
- **Transiciones:** `update_appointment_status` no permite reactivar una cita cancelada ni modificar una completada.
- **Consultas:** `UNIQUE (appointment_id)` evita consultas duplicadas.
- **Guardado:** se controla por versión y la clave de guardado lo hace idempotente.
- **Consulta cerrada:** no es editable, porque `native_doctor_encounter` lo rechaza.
- **Autorización:**
  - Las RPC son `SECURITY DEFINER`, solo las ejecuta `authenticated` y nunca `anon`.
  - El médico se identifica por `native_doctor_id`.
  - Solo accede a sus pacientes autorizados (`treats_patient`).

**Pendiente de decisión** (sin cambios):

- Recepción puede leer `medical_history` y `lab_orders.reason`.
- `vital_signs` y `prescriptions` son legibles por cualquier médico tratante.
- **[No comprobado]** Que no se pueda programar fuera de horario o durante una ausencia. Lo hacen `planning_guard` y `planning_lock`, pero no se inspeccionó su lógica completa.

## Cómo aplicar las migraciones (en orden, desde el editor SQL de Supabase)

1. `supabase/citas-turnos-jornada.sql`: requiere permiso para `CREATE EXTENSION pg_cron`. Marcará de inmediato las citas vencidas sin atender.
2. `supabase/paciente-avisos-solicitud-unica.sql`.
3. `supabase/doctor-consultation-six-fields.sql`: solo lecturas del workspace.
4. `supabase/expedientes-historial.sql`: después del 3.
5. Opcional, para pruebas: `supabase/doctor-start-anytime.sql`. Al terminar, `doctor-start-restore-30min.sql`.

Cada archivo incluye un `BEGIN … COMMIT` y comprobaciones de lectura.

## Revisión técnica del 20 de noviembre (resultados reales)

Detalle completo en [REVISION_TECNICA_2026-11-20.md](REVISION_TECNICA_2026-11-20.md).

- **Citas que pasarán a No atendida:** 7 (no 6, porque avanzó la hora), todas sin consulta creada.
- **Turnos:** sin duplicados desde el 15 de noviembre; los números existentes se conservan. pg_cron está disponible pero no instalado.
- **Nuevos SQL preparados:**
  - `doctor-mi-horario.sql`: jornada recurrente propia con descansos registrados;
  - `rls-privacidad-clinica.sql` y su reversión: recepción sin antecedentes ni órdenes de laboratorio, y médicos según su autorización asistencial.
- **Mi horario:** almuerzo y descansos solo si están registrados; los huecos sin registro son «Entre jornadas», sin recordatorio.
- **test-clinical-labs:** fallo previo, desde `65d846e`, por una prueba desactualizada.
- **Swift:** revisión estática sin problemas nuevos. **No se compiló.**

## Pendiente

- **Compilación y pruebas Swift en Xcode:** ⌘B, ⌘U y ⌘R. **La app iOS no se considera terminada hasta que compile.** Windows no tiene el SDK de Apple.
- **Revisión visual** en distintos tamaños de iPhone.
- **Aplicar las migraciones** y probar los escenarios 2 (turnos simultáneos), 5 (no atendida) y 6 (cancelación con aviso) con cuentas reales.
- **APNs (push remoto):** requiere certificado o clave de Apple, la capacidad Push en Xcode y un servicio que envíe los mensajes (por ejemplo, una Edge Function). Hoy los avisos se guardan en `notifications` y se ven en la campana, más recordatorios locales de iOS.
- **Hora de almuerzo propia:** requiere que administración la registre (columna o tabla). Hoy se usan los huecos entre bloques.
- **`test-clinical-labs`:** falla igual que antes de esta intervención.
