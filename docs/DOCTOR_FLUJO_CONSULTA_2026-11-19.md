# Doctor: flujo completo de consulta médica — 19 de noviembre de 2026

> **Actualización posterior del mismo día:** el formulario se redujo a seis campos (bloques A Datos físicos, B Evaluación médica y C Servicios adicionales). Las secciones B y C descritas abajo quedan sustituidas por [el formulario de seis campos](DOCTOR_FORMULARIO_SEIS_CAMPOS_2026-11-19.md).

iOS/SwiftUI y la réplica `web-preview/` implementan el mismo flujo, con las mismas reglas (Swift `DoctorClinicalRules` ↔ JS `HospitalCore.doctorClinical`). No se modificó el backend, ni Recepción, ni el panel administrativo externo.

## Recorrido del médico

1. **Agenda** (`doctor_native_workspace`). Muestra el día elegido y los 13 días siguientes, en hora de `America/El_Salvador`. Las secciones son Citas de hoy, Próximas, Finalizadas y Canceladas, con contadores, búsqueda por nombre o expediente, filtro de estado y selector de fecha. El orden se calcula en el cliente con la fecha y hora reales de inicio. El servidor ordena por el texto de `tstzrange`; ese orden coincide solo mientras PostgREST trabaje en UTC, y el cliente garantiza el orden de todos modos. Las tarjetas muestran hora, paciente, expediente, motivo, especialidad, consultorio y estado. Las citas que llegan son solo las del médico autenticado: el servidor filtra `a.doctor_id = native_doctor_id()`.
2. **Detalle de la cita**. Muestra fecha, hora, paciente, expediente, edad, teléfono, especialidad, consultorio, motivo y síntomas. Botón **ABRIR CONSULTA MÉDICA** (`doctor_native_start`). Si la consulta ya existe, el botón cambia a **CONTINUAR CONSULTA** o **VER CONSULTA FINALIZADA**, porque la RPC reutiliza la consulta existente. El botón se desactiva y explica el motivo en dos casos: falta más de 30 minutos (regla del servidor) o la cita está cancelada.
3. **Formulario por secciones**:
   - A. Información de la consulta, en solo lectura: paciente, expediente, edad, fecha de nacimiento (del expediente), teléfono, DUI solo si el expediente autorizado lo devuelve, médico responsable, especialidad, consultorio, fecha de atención y hora de apertura, motivo y síntomas.
   - B. Signos vitales: peso, altura, presión sistólica y diastólica, frecuencia cardíaca y temperatura. Muestran unidades, no admiten texto y validan con los mismos rangos que `doctor_native_save`. El IMC se calcula y se indica que no se guarda.
   - C. Las cuatro notas que exige `doctor_native_finish`: motivo y síntomas (`subjective`, que se precarga con lo enviado por el paciente), exploración y observaciones (`objective`), evaluación y diagnóstico principal (`assessment`, con código opcional en `diagnoses`), y plan de tratamiento y recomendaciones (`plan`).
   - D/E. **SOLICITAR EXÁMENES** y **RECETAR MEDICAMENTO** abren los formularios existentes sin salir de la consulta: hoja en iOS, panel en la web. Laboratorio: `doctor_native_lab_catalog` y `doctor_native_labs`, con selección múltiple, revisión y clave estable. Receta: búsqueda en el catálogo, varias líneas, revisión y confirmación con `doctor_native_prescribe` y clave estable. Ambos son opcionales.
4. **Guardado** (`doctor_native_save`, con control de versión). Estados visibles: Guardando…, Guardado correctamente, Error al guardar y Cambios pendientes. Un error no borra lo escrito. Ante un conflicto (`40001`) se recupera y se muestra la versión real, y el médico elige «Usar la versión guardada» o «Conservar lo que escribí y guardar». Salir con cambios sin guardar pide confirmación.
5. **FINALIZAR CONSULTA**. Si faltan secciones obligatorias, hay signos vitales inválidos, hay una receta sin emitir o hay un conflicto pendiente, se muestra lo que falta. Después aparece la confirmación «¿Estás seguro de que deseas finalizar esta consulta?», con los botones «Volver a la consulta» (no modifica nada ni cancela la cita) y «Confirmar y finalizar». Al confirmar se guarda, se ejecuta `doctor_native_finish` con la versión recién guardada (la cita pasa a `completada` en la misma transacción), se informa y se regresa a la agenda.

**Estados** para médico y paciente: Programada (`programada`/`confirmada`, hasta abrir), En consulta (`en_atencion`, al abrir) y Finalizada (`completada`, al cerrar). Se aplican en la agenda, el detalle, el panel, Mis citas, la tarjeta del Home y el historial del paciente.

## Backend real inspeccionado (MCP de solo lectura)

Se leyeron las firmas, las definiciones, `SECURITY DEFINER` y los permisos de las 15 RPC `doctor_native_*`, además de `my_consultation_history`, `cancel_appointment` y `update_appointment_status`. Todas son ejecutables por `authenticated` y no por `anon`. También se revisaron las columnas de las tablas clínicas, RLS y las funciones auxiliares (`owns_clinical_note`, `treats_patient`, `cares_for`, `native_complete_guard`). Las RPC y columnas que usa el cliente existen tal como se invocan. No se ejecutaron escrituras, migraciones ni cambios de permisos.

## Limitaciones del esquema actual (requieren migración; no aplicadas)

| Pedido | Situación real | Propuesta |
|---|---|---|
| Frecuencia respiratoria y saturación de O₂ | `vital_signs` no tiene esas columnas, y `doctor_native_save` y `my_consultation_history` no las procesan | Añadir `respiratory_rate smallint` y `oxygen_saturation smallint` con CHECK, y extender save/chart/historial. Hasta entonces la interfaz no muestra esos campos, para no aparentar que se guardan. |
| Diagnósticos adicionales | `diagnoses` admite varias filas, pero `doctor_native_save` mantiene una sola | Aceptar `p_values.diagnoses[]`. Mientras tanto se escriben en la evaluación clínica. |
| Código de paciente, sexo, DUI en la agenda | `workspace` devuelve `record_code` como expediente, sin `patient_code` ni `birth_date`. `patients` no tiene sexo. `chart.identification` es `NULL` | Añadir `patient_code` y `birth_date` a `doctor_native_workspace`. No existe columna de sexo. |
| Catálogo de diagnósticos | No está publicado (`DoctorRepository.diagnoses` lo rechaza) | Publicar un catálogo y una RPC de búsqueda. |
| Recetas y exámenes por consulta en el historial del paciente | `my_consultation_history` devuelve notas, diagnósticos y signos vitales, pero no recetas ni órdenes | Extender la RPC por `encounter_id`. Las recetas y los laboratorios del paciente siguen disponibles en sus módulos. |
| Actualización en tiempo real | Realtime tiene 0 tablas publicadas | Se mantiene la sincronización existente: refresco cada 30 s en primer plano y al volver a la app. |

## Privacidad: verificado y pendiente de decisión

- Correcto en el servidor: `encounters_read` y `diagnoses_read` permiten la lectura solo al médico autor activo, o al paciente propietario cuando la consulta ya está cerrada. `doctor_native_chart` filtra `e.doctor_id = d`. `doctor_native_finish` y `native_complete_guard` impiden cerrar consultas ajenas o incompletas. Recepción no lee notas, diagnósticos, signos vitales ni recetas.
- **Pendiente (no modificado):**
  1. `laborder_read` concede lectura a `recepcionista` y `admin`. `lab_orders.reason` puede contener texto clínico.
  2. `vitals_read` y `prescription_read` permiten leer a cualquier médico que `treats_patient`, no solo al autor, y al paciente aunque la consulta siga abierta.

  Cambiarlos afecta otros módulos (Recepción, enfermería y laboratorio), así que requiere una decisión explícita.

## Archivos

- iOS: `Core/{DoctorModels,DoctorViewModel,HospitalAPI,SharedCore,MobileModuleModels}.swift`, `Doctor/{DoctorModuleView,DoctorConsultationAgendaView,DoctorConsultationTicketView,DoctorDashboardView,DoctorPatientHistoryView}.swift`, `Patient/{PatientAppointmentFlow,PatientDashboardComponents}.swift`, `HospitalUniversitarioTests/DoctorModuleTests.swift`.
- Compartido: `Shared/hospital-core.js` (`HospitalCore.doctorClinical`).
- Web: `web-preview/{modules,doctor-dashboard,app,patient-appointments,style}.js|css`.
- Pruebas: `scripts/test-doctor-clinical-rules.mjs` (nueva), `scripts/test-doctor-preview-live.mjs`, `scripts/test-patient-dashboard.mjs`.

## Verificaciones

- Ejecutadas en Windows (DOM y transporte simulados, datos sintéticos): test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, generate-models --check, check-project.py y git diff --check, todas aprobadas. `test-clinical-labs` falla igual que en el commit d828fd6: es un fallo previo y ajeno.
- La réplica web cubre:
  - Orden cronológico, detalle y apertura única.
  - Precarga de lo enviado por el paciente.
  - Signos vitales sin texto, con rangos e IMC.
  - Guardado y conflicto de versión sin sobrescritura.
  - Exámenes de laboratorio.
  - Receta de dos medicamentos con revisión.
  - Bloqueo del cierre si la consulta está incompleta.
  - Confirmación que no modifica nada.
  - Fallo de guardado sin cierre ni pérdida de datos.
  - Finalización y lectura de la consulta finalizada.
  - Ninguna RPC envía la identidad del médico.
- Pruebas Swift nuevas en `DoctorModuleTests` (agenda, estados, signos vitales e IMC, cierre incompleto, cierre correcto, conflicto, precarga) **preparadas, no ejecutadas**: Windows no tiene el SDK de Apple. Revisión estática de símbolos y firmas hecha. Falta ⌘B, ⌘R y ⌘U en Xcode 16.2+.
- Supabase: solo lectura mediante MCP. No se repitieron pruebas de escritura porque el MCP está configurado `read_only=true`. La prueba reversible previa `supabase/test-doctor-experience-rollback.sql` cubre start, save, finish, recetas, laboratorio, historial y aislamiento con el mismo backend, que no cambió.
- Revisión visual: no realizada. En Windows: `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs`, luego http://127.0.0.1:4173/ y Ctrl+F5.
