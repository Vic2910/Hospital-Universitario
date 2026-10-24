# Hospital Universitario: inventario, modelo de datos y backend Supabase

**Entrega verificada al 23 de octubre de 2026.** Con la confirmación expresa del usuario se aplicaron 12 migraciones en Hospital Universitario / AppMoviles (`kgulityewtcyvjnxeskd`): 90 tablas hospitalarias y una técnica, 162 FK, 268 políticas RLS, 49 RPC y cinco vistas internas. document-access está desplegada con JWT obligatorio. Se aprobaron 90 comprobaciones SQL locales y 16 adicionales en Supabase PostgreSQL 17.11. El proyecto no contiene pacientes ni cuentas de demostración. La configuración del entorno y los servicios externos pendientes se detallan al final; el despliegue del esquema no equivale por sí solo a una puesta en producción clínica.

**Evidencia:** se inventariaron 53 frames en Figma: 12 web y 41 móviles. Los 12 web tienen extracción completa de textos, contenedores y reacciones. Los dos adjuntos del usuario completan los elementos textuales de los 41 móviles; se conserva cada fuente y su correspondencia con los IDs. No se inventan modales, opciones desplegadas ni pantallas de detalle ausentes. Lucidchart contiene la página Modelo normalizado · Supabase actualizada con 92 entidades y 162 relaciones, incluidas las solicitudes de atención y los contactos de emergencia.

Diseño: https://www.figma.com/design/bGo6nI4CD4KoNdtDn0mO4v/Hospital-Universitario?node-id=10-8761

Diagrama solicitado: https://lucid.app/lucidchart/dcb708c3-7110-4803-935d-c6465c1c8b0f/edit

## 1. Inventario de pantallas y datos

### Web: evidencia textual completa

Los 12 frames web no contienen nodos ocultos ni reacciones de prototipo registradas. No aparecen frames separados para modales, menús desplegados, validaciones, carga, error o vacío. Esto describe únicamente la web inspeccionada; no significa que esos flujos no deban existir. Los botones + y menús indican una intención, pero no permiten conocer sus formularios internos.

La navegación compartida enlaza los 12 módulos. Incluye búsqueda global, notificaciones, ayuda y perfil. Notificaciones y perfil apuntan a datos del mismo usuario Auth. No se crea una tabla por pestaña, tarjeta, gráfico o canal.

#### Tablero general — 42:168

- **Muestra/captura:** Ocupación y capacidad; VIP y semiprivadas; ambulancia; citas del día; órdenes de laboratorio por estado y urgencia; médicos de turno; ingresos recientes; agenda horaria.
- **Controles y filtros:** Búsqueda global; selector Hoy / vista operativa; enlaces a módulos.
- **Estados visibles:** Disponible, ocupada, ingresado, observación, triage, completada, en curso, pendiente; personal en turno / próximo.
- **Tablas/proyecciones:** `bed_statuses, fleet_statuses, appointments, diagnostic_orders, staff_shifts, admissions`.
- **Servicios:** operational_dashboard; read_resource; list_admissions
- **Evidencia:** 146 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Expediente clínico — 42:418

- **Muestra/captura:** Identidad y número de expediente; edad, sangre, alergias y médico; diagnóstico CIE-10 y fecha; PA, pulso, respiración, temperatura, SpO₂ y peso; alertas; antecedentes; recetas activas, próxima cita, notas y estudios recientes.
- **Controles y filtros:** Pestañas Resumen, Historia clínica, Diagnósticos, Recetas, Órdenes, Laboratorio y Evolución; botón Acciones. Sólo el contenido de Resumen está desarrollado en este frame.
- **Estados visibles:** Diagnóstico en tratamiento y evolución favorable; alergias críticas y antecedentes importantes; estudios completados; cita programada.
- **Tablas/proyecciones:** `patients, patient_allergies, patient_conditions, medical_history_entries, encounters, clinical_notes, vital_sign_sets, prescriptions, diagnostic_orders, lab_results`.
- **Servicios:** patient_chart; read_resource; create_record; update_record; finalize_clinical_record
- **Evidencia:** 133 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Citas y turnos — 42:607

- **Muestra/captura:** Hora, paciente, especialidad, médico y estado; contadores, flujo por hora y resumen de atención.
- **Controles y filtros:** Fecha, especialidad, médico y estado; Agendar cita; Hoy/Semana/Mes; semana completa; Ver y menú.
- **Estados visibles:** Programada, en espera, en curso, atendida, cancelada. La cola y la cita son recursos diferentes.
- **Tablas/proyecciones:** `appointments, appointment_events, care_queues, queue_tickets, encounters`.
- **Servicios:** book_appointment; transition_appointment; check_in; call_next_ticket; start_consultation
- **Evidencia:** 112 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Usuarios y roles — 42:761

- **Muestra/captura:** Usuario, correo de cuenta, varios roles, área, establecimiento, estado; totales de cuentas, personal y doctores; catálogo de roles y texto de permisos.
- **Controles y filtros:** Buscar nombre/correo/cargo; rol, estado, área y establecimiento; Nuevo usuario; menú por fila; paginación.
- **Estados visibles:** Activo, inactivo; Administradora + Doctora en una misma fila.
- **Tablas/proyecciones:** `profiles, persons, user_role_assignments, role_permissions, staff_assignments`.
- **Servicios:** list_users; set_user_roles; set_account_status; Auth Admin para invitaciones (pendiente de integración)
- **Evidencia:** 127 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Pacientes e ingresos — 42:932

- **Muestra/captura:** Expediente, nombre, edad, sexo, tipo y hora de ingreso, médico, habitación y cama, estado; distribución, prioridades y capacidad.
- **Controles y filtros:** Buscar nombre/expediente/habitación; estado, tipo de ingreso, planta/habitación, médico y fecha; Registrar ingreso; Ver; menú; paginación.
- **Estados visibles:** Ingresado, observación, triage, alta prevista; habitación sin asignar.
- **Tablas/proyecciones:** `patients, persons, encounters, admissions, triage_levels, bed_allocations`.
- **Servicios:** register_patient; register_admission; list_admissions; discharge_admission
- **Evidencia:** 134 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Habitaciones y camas — 42:1116

- **Muestra/captura:** Planta, código, tipo de habitación, camas y ocupantes; total 17; VIP-301…305; HAB-201…206 con camas A/B.
- **Controles y filtros:** Planta, estado y tipo; Asignar cama; Ver habitación; Asignar paciente.
- **Estados visibles:** Disponible, ocupada, reservada, limpieza; habitaciones parciales 0/2, 1/2, 2/2; sin paciente y en preparación.
- **Tablas/proyecciones:** `floors, room_types, rooms, beds, bed_allocations, admissions`.
- **Servicios:** read_resource(bed_statuses); allocate_bed; block_bed; complete_bed_block; discharge_admission
- **Evidencia:** 129 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Turnos del personal — 42:1318

- **Muestra/captura:** Semana, colaborador, área, guardias por día; Mañana 06–14, Tarde 14–22, Noche 22–06; cobertura por área; cambios, descansos y próximas guardias.
- **Controles y filtros:** Semana, área, cargo y turno; Asignar turno; calendario semanal.
- **Estados visibles:** Mañana, tarde, noche, libre; confirmado, por confirmar; cambios solicitados y descansos aprobados.
- **Tablas/proyecciones:** `staff_members, staff_assignments, staff_shifts, shift_templates, shift_requests, coverage_requirements`.
- **Servicios:** read_resource; create_record; update_record. confirm_shift; review_shift_request.
- **Evidencia:** 151 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Laboratorio — 42:1553

- **Muestra/captura:** Número de orden, paciente, examen, prioridad, estado; situación de muestras; resultados recientes; procesados por día y tiempo medio.
- **Controles y filtros:** Buscar orden/paciente/examen; estado, prioridad, fecha y especialidad; Nueva orden; Ver; menú; paginación.
- **Estados visibles:** Pendiente, en proceso, completado; normal y urgente; resultado disponible.
- **Tablas/proyecciones:** `diagnostic_orders, diagnostic_order_items, test_definitions, specimens, specimen_items, lab_results, lab_result_values`.
- **Servicios:** laboratory_worklist; read_resource; create_record; finalize_clinical_record. collect_specimen; process_lab_item.
- **Evidencia:** 131 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Inventario y recursos — 42:1743

- **Muestra/captura:** Código, producto, categoría, existencias, estado; alertas de caducidad; distribución por categoría; movimientos con fecha, cantidad y responsable; equipos disponibles.
- **Controles y filtros:** Buscar código/producto/categoría; categoría, estado, ubicación, orden de existencias y lote/vencimiento; Nuevo producto; Ver; menú; paginación.
- **Estados visibles:** Disponible, stock bajo, crítico, por vencer; entrada/salida; cantidades positivas/negativas.
- **Tablas/proyecciones:** `products, product_categories, stock_lots, stock_locations, stock_thresholds, stock_movements, equipment_assets`.
- **Servicios:** read_resource(inventory_balances); create_record; record_stock_movement
- **Evidencia:** 140 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Ambulancia — 42:1931

- **Muestra/captura:** AMB-001, tipo, dotación, estado; servicios del mes y mantenimiento; bitácora con ID, fecha/hora, servicio, destino y estado.
- **Controles y filtros:** Registrar despacho; historial de unidad; fecha, tipo y estado; exportar bitácora; Ver; menú; paginación.
- **Estados visibles:** Disponible, en servicio, mantenimiento; despachos completados; prohibición de servicios activos simultáneos.
- **Tablas/proyecciones:** `ambulances, ambulance_activities, ambulance_dispatches, dispatch_patients, dispatch_crew`.
- **Servicios:** read_resource(fleet_statuses); dispatch_ambulance; maintain_ambulance; finish_ambulance_activity; report_jobs
- **Evidencia:** 113 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Reportes y analítica — 43:2083

- **Muestra/captura:** Atenciones, ocupación promedio, citas atendidas y estudios procesados; tendencia diaria; camas libres/ocupadas; porcentajes por servicio; cuatro reportes.
- **Controles y filtros:** Período, área y tipo; Exportar reporte; ocupación PDF, consultas Excel, laboratorio PDF e inventario Excel.
- **Estados visibles:** No hay estado vacío/error/exportación en curso dibujado. Los denominadores de cobertura e indicadores no están definidos.
- **Tablas/proyecciones:** `report_definitions, report_jobs, report_schedules, bed_allocations, encounters, appointments, lab_results, stock_movements`.
- **Servicios:** operational_dashboard; create_record(report_jobs). Worker PDF/XLSX pendiente de implementación.
- **Evidencia:** 106 nodos de texto; ruta enlazada por ID en `evidence/`.

#### Configuración — 43:2248

- **Muestra/captura:** Formulario con nombre, correo, teléfono, dirección, zona horaria e idioma; apariencia; preferencias de nuevos ingresos, resultados, turnos, inventario y reportes; capacidades e indicador de una ambulancia.
- **Controles y filtros:** General / Notificaciones; Guardar cambios; tema Claro/Oscuro/Alto contraste; ajustes de accesibilidad; Administrar roles y permisos.
- **Estados visibles:** Tres opciones de tema; controles de notificación sin flujo de guardado detallado; capacidades informativas.
- **Tablas/proyecciones:** `organizations, profiles, notification_preferences, notification_topics, room_types, rooms, beds, ambulances`.
- **Servicios:** read_resource; update_record; set_user_roles
- **Evidencia:** 78 nodos de texto; ruta enlazada por ID en `evidence/`.

### Móviles: 41 pantallas con elementos textuales contrastados

Los dos adjuntos del usuario completan los textos de los frames inventariados en Figma. El orden del volcado intercala columnas de pantallas; se vincularon por títulos, rol y contenido al ID de cada frame. No se afirman coordenadas, conexiones de prototipo ni contenido de modales/desplegables que no están en esos textos. Los campos y acciones ausentes se marcan como supuestos.

#### Inicio de sesión — 48:2

- **Frame Figma:** ANDROID · 01 · Iniciar sesión
- **Muestra/captura:** Correo institucional, contraseña oculta; marca Hospital Universitario / San Gabriel.
- **Controles y filtros:** Iniciar sesión; mostrar contraseña; ¿Olvidaste tu contraseña?
- **Estados visibles y traducción:** Acceso exclusivo para personal autorizado; una app con acceso según rol. No se adjuntó pantalla de recuperación ni error.
- **Tablas/proyecciones:** auth.users, profiles, user_role_assignments
- **Servicios:** Supabase Auth signInWithPassword, resetPasswordForEmail; my_access
- **Evidencia:** `evidence/mobile_android_elements.md líneas 27–185`.

#### Recepción · Inicio — 48:31

- **Frame Figma:** Recepcionista
- **Muestra/captura:** Saludo y fecha; citas programadas, personas en espera, ingresos de hoy y camas libres.
- **Controles y filtros:** Buscar servicios y pacientes; Registrar paciente, Agendar cita, Registrar ingreso, Ver habitaciones; navegación Inicio/Pacientes/Citas/Turnos/Más.
- **Estados visibles y traducción:** Conteos de muestra 42/8/6/7; son consultas, no atributos.
- **Tablas/proyecciones:** appointments, queue_tickets, admissions, bed_allocations
- **Servicios:** operational_dashboard; register_patient; book_appointment; register_admission
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Recepción · Pacientes — 48:80

- **Frame Figma:** ANDROID · RECEPCIÓN · 02 
- **Muestra/captura:** Nombre, expediente y situación asistencial por paciente.
- **Controles y filtros:** Buscar pacientes; selector Todos; selector Activos; Ver expediente; + Nuevo paciente.
- **Estados visibles y traducción:** Activo, hospitalizada, en triage, seguimiento, hospitalizado. Se deriva de registros/atenciones; no un enum global del paciente.
- **Tablas/proyecciones:** patients, persons, admissions, encounters, care_assignments
- **Servicios:** search_patients; read_resource; register_patient. Ver expediente sólo abre la proyección demográfica autorizada para recepción.
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Recepción · Citas — 48:142

- **Frame Figma:** ANDROID · RECEPCIÓN · 03 
- **Muestra/captura:** Hora, paciente, especialidad, profesional y estado.
- **Controles y filtros:** Buscar citas; día anterior/Hoy/siguiente; Todos; + Agendar cita.
- **Estados visibles y traducción:** Confirmada, en espera, en curso, pendiente. En espera se obtiene del turno, sin duplicarla en appointments.
- **Tablas/proyecciones:** appointments, appointment_directory, queue_tickets
- **Servicios:** read_resource(appointment_directory); book_appointment; transition_appointment; reschedule_appointment
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Recepción · Turnos — 48:204

- **Frame Figma:** ANDROID · RECEPCIÓN · 04 
- **Muestra/captura:** Totales en espera y atención; número, paciente, especialidad y hora de turno.
- **Controles y filtros:** Buscar turnos; navegación compartida. No se adjuntó formulario para llamar o finalizar.
- **Estados visibles y traducción:** En espera, llamado, en atención.
- **Tablas/proyecciones:** care_queues, queue_tickets, appointment_queue_tickets
- **Servicios:** read_resource; check_in; call_next_ticket; start_consultation/close_consultation actualizan el turno
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Recepción · Ingresos — 48:256

- **Frame Figma:** ANDROID · RECEPCIÓN · 05 
- **Muestra/captura:** Paciente, tipo/área, habitación/cama y estado; sin asignar.
- **Controles y filtros:** Buscar ingresos; Estado Todos; Fecha Hoy; + Nuevo ingreso.
- **Estados visibles y traducción:** Ingresado/a, observación, en triage; sin asignar.
- **Tablas/proyecciones:** admissions, encounters, bed_allocations
- **Servicios:** list_admissions; register_admission; allocate_bed; discharge_admission
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Recepción · Habitaciones — 48:318

- **Frame Figma:** ANDROID · RECEPCIÓN · 06 
- **Muestra/captura:** Capacidad total y disponible; VIP-301 a 305 en tercera planta; HAB-201 a 206 semiprivadas de dos camas en segunda.
- **Controles y filtros:** Buscar disponibilidad; Consultar disponibilidad completa.
- **Estados visibles y traducción:** Ocupada, disponible. Bloqueos de limpieza/mantenimiento proceden de la web.
- **Tablas/proyecciones:** floors, rooms, beds, bed_allocations
- **Servicios:** read_resource(bed_statuses); allocate_bed; block_bed; complete_bed_block
- **Evidencia:** `evidence/mobile_android_elements.md líneas 28–245`.

#### Enfermería · Inicio — 50:373

- **Frame Figma:** ANDROID · ENFERMERÍA · 01 · Inicio
- **Muestra/captura:** Nombre, turno y fecha; pacientes asignados, preconsultas, indicaciones pendientes y cambio de turno.
- **Controles y filtros:** Buscar tareas y pacientes; Preconsulta, Mis pacientes, Habitaciones, Indicaciones; navegación Inicio/Pacientes/Preconsulta/Habitaciones/Más.
- **Estados visibles y traducción:** Resumen de mi turno.
- **Tablas/proyecciones:** care_assignments, vital_sign_sets, care_orders, shift_requests
- **Servicios:** read_resource con asignación/estado/período; my_access
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Enfermería · Pacientes asignados — 50:422

- **Frame Figma:** Asistentes
- **Muestra/captura:** Paciente, habitación y tarea de seguimiento/preconsulta/medicación/evolución.
- **Controles y filtros:** Buscar pacientes asignados.
- **Estados visibles y traducción:** En seguimiento, pendiente, estable. Estable es valoración de nota de enfermería, no ocupación ni estado administrativo.
- **Tablas/proyecciones:** care_assignments, encounters, care_orders, clinical_notes, bed_allocations
- **Servicios:** search_patients; read_resource; patient_chart para vínculo asistencial vigente
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Enfermería · Preconsulta — 50:482

- **Frame Figma:** ANDROID · ENFERMERÍA · 03 · Preconsulta
- **Muestra/captura:** Paciente seleccionado, expediente, edad, cama; PA, frecuencia cardíaca, temperatura, SpO₂, frecuencia respiratoria y peso.
- **Controles y filtros:** Buscar preconsulta; Registrar signos vitales; Guardar preconsulta.
- **Estados visibles y traducción:** Pendiente; valores de muestra 120/80,78,36.7,98,18,68. Ninguno es default clínico.
- **Tablas/proyecciones:** encounters, vital_sign_sets, patients, persons
- **Servicios:** create_record(vital_sign_sets); read_resource; paciente y atención autorizados, CHECK fisiológicos
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Enfermería · Habitaciones — 50:532

- **Frame Figma:** ANDROID · ENFERMERÍA · 04 · Habitaciones
- **Muestra/captura:** Capacidad/ocupadas; habitación VIP con paciente asignado o sin paciente; resumen 12 camas semiprivadas.
- **Controles y filtros:** Buscar habitaciones.
- **Estados visibles y traducción:** Ocupada, disponible; paciente asignado/sin paciente.
- **Tablas/proyecciones:** beds, bed_allocations, admissions, care_assignments
- **Servicios:** read_resource(bed_statuses); list_admissions con demografía autorizada; patient_chart sólo para asignados
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Enfermería · Turnos laborales — 50:589

- **Frame Figma:** ANDROID · ENFERMERÍA · 05 · Turnos laborales
- **Muestra/captura:** Próxima guardia, día, franja mañana/tarde y horas; semana laboral con descanso.
- **Controles y filtros:** Buscar turnos laborales. No aparecen formularios de cambio o aprobación.
- **Estados visibles y traducción:** Confirmado, pendiente, descanso/libre. Descanso se deriva de ausencia de guardia o solicitud de descanso aprobada; no se graba una guardia vacía.
- **Tablas/proyecciones:** staff_shifts, shift_requests, shift_templates
- **Servicios:** read_resource; confirm_shift; create_record(shift_requests); review_shift_request
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Enfermería · Indicaciones autorizadas — 50:644

- **Frame Figma:** ANDROID · ENFERMERÍA · 06 · Indicaciones autorizadas
- **Muestra/captura:** Paciente, instrucción y hora; lista de indicaciones del turno.
- **Controles y filtros:** Buscar indicaciones; Pendientes; Paciente Todos.
- **Estados visibles y traducción:** Pendiente, en curso, completada; sólo ejecutar indicaciones registradas y autorizadas.
- **Tablas/proyecciones:** care_orders, care_order_executions
- **Servicios:** read_resource(care_orders); execute_care_order; finalize_clinical_record(authorize) sólo médico
- **Evidencia:** `evidence/mobile_android_elements.md líneas 270–470`.

#### Android Médico · Inicio — 52:706

- **Frame Figma:** ANDROID · DOCTOR · 01 · Inicio
- **Muestra/captura:** Saludo, jornada, citas asignadas/programadas, pacientes en espera, resultados nuevos y recetas pendientes.
- **Controles y filtros:** Buscar servicios/citas/pacientes; Consulta/Iniciar consulta, Expedientes/Mis pacientes, Laboratorio, Recetas; navegación de rol.
- **Estados visibles y traducción:** Contadores calculados; no se importan los valores 12/4/3/2.
- **Tablas/proyecciones:** appointments, queue_tickets, lab_results, prescriptions
- **Servicios:** read_resource; my_access; start_consultation
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Mis citas (frame Doctores) — 52:755

- **Frame Figma:** Doctores
- **Muestra/captura:** Hora, paciente, motivo/especialidad, sala/consultorio y estado; agenda diaria.
- **Controles y filtros:** Buscar mis citas; día anterior/Hoy/siguiente; Estado Todas/Todos.
- **Estados visibles y traducción:** Confirmada, en espera, en curso, pendiente, completado; los estados de fila combinan cita y turno.
- **Tablas/proyecciones:** appointment_directory, appointments, queue_tickets
- **Servicios:** read_resource(appointment_directory); reschedule_appointment; start_consultation
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Consulta general — 52:815

- **Frame Figma:** ANDROID · DOCTOR · 03 · Consulta general
- **Muestra/captura:** Paciente seleccionado, expediente, edad, consultorio/hora; motivo/síntomas, exploración física, diagnóstico CIE-10 y plan.
- **Controles y filtros:** Buscar consultas/consulta general; selección de paciente; Buscar CIE-10/Diagnóstico clínico; Guardar consulta.
- **Estados visibles y traducción:** Borrador mientras se registra; el adjunto no muestra confirmación ni error de guardado.
- **Tablas/proyecciones:** encounters, clinical_notes, diagnosis_codes, patient_conditions, encounter_diagnoses
- **Servicios:** save_consultation; create_record/update_record para borradores; close_consultation para firma y cierre
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Expediente clínico — 52:853

- **Frame Figma:** ANDROID · DOCTOR · 04 · Expediente clínico
- **Muestra/captura:** Paciente, expediente, edad y sangre; diagnósticos, alergias, tratamiento/medicamentos activos, antecedentes y evolución reciente.
- **Controles y filtros:** Buscar expedientes/expediente clínico; resumen autorizado.
- **Estados visibles y traducción:** Confidencial; hipertensión en seguimiento, penicilina/precaución, receta prescrita.
- **Tablas/proyecciones:** patients, persons, patient_conditions, patient_allergies, prescriptions, medical_history_entries, clinical_notes
- **Servicios:** patient_chart; read_resource por FK; MFA y vínculo asistencial
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Laboratorio — 52:897

- **Frame Figma:** ANDROID · DOCTOR · 05 · Laboratorio
- **Muestra/captura:** Orden LAB, paciente, examen, prioridad y estado: biometría, química, perfil lipídico, uroanálisis y PCR.
- **Controles y filtros:** Buscar laboratorio; Todas/Estado Todos en Android; Estado Todos/Prioridad Todas en iOS.
- **Estados visibles y traducción:** Pendiente, en proceso, completado; alta/urgente se normaliza a urgent, sin importar los ejemplos.
- **Tablas/proyecciones:** diagnostic_orders, diagnostic_order_items, test_definitions, lab_results
- **Servicios:** read_resource(laboratory_directory); create_record; finalize_clinical_record; document-access
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Recetas — 52:957

- **Frame Figma:** ANDROID · DOCTOR · 06 · Recetas
- **Muestra/captura:** Paciente, medicamento, concentración y vía; prescripciones recientes.
- **Controles y filtros:** Buscar recetas; Paciente Todos y Estado Todos en Android; + Nueva receta; verificar alergias y contraindicaciones. No se adjuntó el formulario de alta.
- **Estados visibles y traducción:** Activa/vigente; pendiente/borrador/tratamiento por confirmar.
- **Tablas/proyecciones:** prescriptions, prescription_items, medications, administration_routes
- **Servicios:** read_resource; create_record cabecera y renglones; finalize_clinical_record(issue)
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### Android Médico · Mi horario — 52:1014

- **Frame Figma:** ANDROID · DOCTOR · 07 · Mi horario
- **Muestra/captura:** Próxima jornada y agenda semanal; mañana/tarde/guardia con horas y descanso.
- **Controles y filtros:** Buscar mi horario.
- **Estados visibles y traducción:** Confirmada/confirmado, pendiente/en espera, descanso/libre. Las horas de médicos y enfermería son específicas por guardia.
- **Tablas/proyecciones:** staff_shifts, shift_requests
- **Servicios:** read_resource; confirm_shift; create_record(shift_requests); review_shift_request
- **Evidencia:** `evidence/mobile_android_elements.md líneas 499–715`.

#### iOS Paciente · Inicio — 61:2

- **Frame Figma:** iOS · PACIENTE · 01 · Inicio
- **Muestra/captura:** Saludo; próximas citas, resultado nuevo, recetas activas y turno actual.
- **Controles y filtros:** Buscar servicios; Solicitar atención, Mis citas, Mi expediente, Laboratorio; navegación Inicio/Mis citas/Salud/Perfil/Más.
- **Estados visibles y traducción:** Tarjetas 2/1/3/A-014 son consultas.
- **Tablas/proyecciones:** appointments, lab_results, prescriptions, queue_tickets
- **Servicios:** my_access; read_resource con propietario; my_queue_status
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Mis citas — 61:51

- **Frame Figma:** iOS · PACIENTE · 02 · Mis citas
- **Muestra/captura:** Próximas citas e historial: día/hora, especialidad y médico o atención finalizada.
- **Controles y filtros:** Buscar mis citas; Solicitar nueva cita.
- **Estados visibles y traducción:** Confirmada, programada, completada.
- **Tablas/proyecciones:** appointment_directory, appointments
- **Servicios:** read_resource(appointment_directory); request_appointment; transition_appointment(cancelled) como capacidad propuesta no botón confirmado
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Solicitar atención — 61:106

- **Frame Figma:** iOS · PACIENTE · 03 · Solicitar atención
- **Muestra/captura:** Especialidad, motivo de consulta, fecha preferida y horario preferido.
- **Controles y filtros:** Buscar solicitar atención; seleccionar especialidad/fecha/horario; Enviar solicitud; “La disponibilidad se confirmará al programar”.
- **Estados visibles y traducción:** Solicitud pendiente de disponibilidad; no se muestran doctor, cama ni reserva confirmada.
- **Tablas/proyecciones:** appointment_requests, specialties, appointments
- **Servicios:** request_appointment; read_resource(appointment_requests); schedule_appointment_request por recepción
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Mi turno — 61:146

- **Frame Figma:** iOS · PACIENTE · 04 · Mi turno
- **Muestra/captura:** Tu número, estado, especialidad/sala de espera; número atendido, personas antes y consultorio asignado.
- **Controles y filtros:** Buscar mi turno.
- **Estados visibles y traducción:** En espera; número propio A-014 y atendido A-011; no se muestran identidades de terceros.
- **Tablas/proyecciones:** queue_tickets, care_queues, consultation_rooms, appointment_queue_tickets
- **Servicios:** my_queue_status; proyección con número atendido y consultorio, sin nombres ajenos
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Mi expediente — 61:186

- **Frame Figma:** iOS · PACIENTE · 05 · Expediente
- **Muestra/captura:** Nombre, expediente, sangre, edad; condiciones registradas, alergias, tratamientos, última consulta y documentos de salud.
- **Controles y filtros:** Buscar mi expediente.
- **Estados visibles y traducción:** Privado; seguimiento activo, precaución médica, documentos disponibles.
- **Tablas/proyecciones:** patients, persons, patient_conditions, patient_allergies, prescriptions, patient_documents
- **Servicios:** patient_chart; read_resource; document-access sólo documentos liberados
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Historial médico — 61:230

- **Frame Figma:** iOS · PACIENTE · 06 · Historial médico
- **Muestra/captura:** Línea de tiempo con fecha y tipo/servicio de atenciones, control, pruebas, seguimiento y revisión de tratamiento.
- **Controles y filtros:** Buscar historial médico; Ver detalle por evento.
- **Estados visibles y traducción:** Eventos pasados. No se adjunta pantalla de detalle.
- **Tablas/proyecciones:** encounters, clinical_notes, diagnostic_orders, patient_conditions
- **Servicios:** read_resource(encounters) orden started_at descendente con cursor; patient_chart; FK de cada evento
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Mis recetas — 61:274

- **Frame Figma:** iOS · PACIENTE · 07 · Mis recetas
- **Muestra/captura:** Tratamientos vigentes: fármaco/concentración, dosis y frecuencia textual; recetas anteriores por fecha.
- **Controles y filtros:** Buscar mis recetas; Consultar en receta anterior.
- **Estados visibles y traducción:** Activa; prescripción clínica registrada.
- **Tablas/proyecciones:** prescriptions, prescription_items, medications, administration_routes
- **Servicios:** read_resource por propietario y estado/fechas; no exponer borradores
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Laboratorio — 61:327

- **Frame Figma:** iOS · PACIENTE · 08 · Laboratorio
- **Muestra/captura:** Mis estudios con examen, orden y fecha.
- **Controles y filtros:** Buscar laboratorio.
- **Estados visibles y traducción:** Completado, en proceso, pendiente. Resultado publicado separado del estado interno validado.
- **Tablas/proyecciones:** diagnostic_orders, diagnostic_order_items, lab_results, documents
- **Servicios:** read_resource(laboratory_directory); read_resource(lab_results released); document-access
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Información pública — 61:380

- **Frame Figma:** iOS · PACIENTE · 09 · Información pública
- **Muestra/captura:** Horario de atención; médicos de turno/especialidades; ocupación general agregada; comunicados.
- **Controles y filtros:** Buscar información pública; Consultar por sección.
- **Estados visibles y traducción:** No publica clínica de otros pacientes.
- **Tablas/proyecciones:** public_information, staff_shifts, staff_specialties, bed_allocations
- **Servicios:** GET information; hospital_overview; physician_directory
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Notificaciones — 61:434

- **Frame Figma:** iOS · PACIENTE · 10 · Notificaciones
- **Muestra/captura:** Cita confirmada, resultado disponible, recordatorio, receta disponible y aviso institucional.
- **Controles y filtros:** Buscar notificaciones; Estado Todos.
- **Estados visibles y traducción:** El selector confirma filtrado; opciones leído/no leído se proponen, no se ven desplegadas.
- **Tablas/proyecciones:** notifications, notification_preferences, notification_topics
- **Servicios:** read_resource por recipient; filtro read_at isnull; update_record(read_at)
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Paciente · Mi perfil — 61:483

- **Frame Figma:** iOS · PACIENTE · 11 · Perfil
- **Muestra/captura:** Iniciales, nombre, expediente, cuenta activa; correo, teléfono y contacto de emergencia.
- **Controles y filtros:** Buscar mi perfil; Contraseña y seguridad/Administrar acceso; Preferencias y privacidad/Gestionar notificaciones; Cerrar sesión.
- **Estados visibles y traducción:** Teléfono por configurar; emergencia por actualizar. No se adjunta modal de edición.
- **Tablas/proyecciones:** profiles, persons, person_contacts, emergency_contacts, patient_accounts, auth.users
- **Servicios:** my_profile; update_my_phone; set_my_emergency_contact; Auth/MFA; notification_preferences
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 45–363`.

#### iOS Médico · Inicio — 63:531

- **Frame Figma:** iOS · DOCTOR · 01 · Inicio
- **Muestra/captura:** Saludo, jornada, citas asignadas/programadas, pacientes en espera, resultados nuevos y recetas pendientes.
- **Controles y filtros:** Buscar servicios/citas/pacientes; Consulta/Iniciar consulta, Expedientes/Mis pacientes, Laboratorio, Recetas; navegación de rol.
- **Estados visibles y traducción:** Contadores calculados; no se importan los valores 12/4/3/2.
- **Tablas/proyecciones:** appointments, queue_tickets, lab_results, prescriptions
- **Servicios:** read_resource; my_access; start_consultation
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Mis pacientes — 63:580

- **Frame Figma:** iOS · DOCTOR · 02 · Mis pacientes
- **Muestra/captura:** Paciente, expediente, consulta programada/control/seguimiento/revisión; consultorio, hora y edad en consulta.
- **Controles y filtros:** Buscar mis pacientes; Todos y Atención actual.
- **Estados visibles y traducción:** En espera, activo, en consulta, pendiente.
- **Tablas/proyecciones:** patients, persons, care_assignments, encounters, appointments
- **Servicios:** search_patients; read_resource con care_assignments; patient_chart
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Mis citas — 63:640

- **Frame Figma:** iOS · DOCTOR · 03 · Mis citas
- **Muestra/captura:** Hora, paciente, motivo/especialidad, sala/consultorio y estado; agenda diaria.
- **Controles y filtros:** Buscar mis citas; día anterior/Hoy/siguiente; Estado Todas/Todos.
- **Estados visibles y traducción:** Confirmada, en espera, en curso, pendiente, completado; los estados de fila combinan cita y turno.
- **Tablas/proyecciones:** appointment_directory, appointments, queue_tickets
- **Servicios:** read_resource(appointment_directory); reschedule_appointment; start_consultation
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Consultas — 63:700

- **Frame Figma:** iOS · DOCTOR · 04 · Consultas
- **Muestra/captura:** Paciente seleccionado, expediente, edad, consultorio/hora; motivo/síntomas, exploración física, diagnóstico CIE-10 y plan.
- **Controles y filtros:** Buscar consultas/consulta general; selección de paciente; Buscar CIE-10/Diagnóstico clínico; Guardar consulta.
- **Estados visibles y traducción:** Borrador mientras se registra; el adjunto no muestra confirmación ni error de guardado.
- **Tablas/proyecciones:** encounters, clinical_notes, diagnosis_codes, patient_conditions, encounter_diagnoses
- **Servicios:** save_consultation; create_record/update_record para borradores; close_consultation para firma y cierre
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Expedientes — 63:738

- **Frame Figma:** iOS · DOCTOR · 05 · Expedientes
- **Muestra/captura:** Paciente, expediente, edad y sangre; diagnósticos, alergias, tratamiento/medicamentos activos, antecedentes y evolución reciente.
- **Controles y filtros:** Buscar expedientes/expediente clínico; resumen autorizado.
- **Estados visibles y traducción:** Confidencial; hipertensión en seguimiento, penicilina/precaución, receta prescrita.
- **Tablas/proyecciones:** patients, persons, patient_conditions, patient_allergies, prescriptions, medical_history_entries, clinical_notes
- **Servicios:** patient_chart; read_resource por FK; MFA y vínculo asistencial
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Recetas — 63:782

- **Frame Figma:** iOS · DOCTOR · 06 · Recetas
- **Muestra/captura:** Paciente, medicamento, concentración y vía; prescripciones recientes.
- **Controles y filtros:** Buscar recetas; Paciente Todos y Estado Todos en Android; + Nueva receta; verificar alergias y contraindicaciones. No se adjuntó el formulario de alta.
- **Estados visibles y traducción:** Activa/vigente; pendiente/borrador/tratamiento por confirmar.
- **Tablas/proyecciones:** prescriptions, prescription_items, medications, administration_routes
- **Servicios:** read_resource; create_record cabecera y renglones; finalize_clinical_record(issue)
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Laboratorio — 63:838

- **Frame Figma:** iOS · DOCTOR · 07 · Laboratorio
- **Muestra/captura:** Orden LAB, paciente, examen, prioridad y estado: biometría, química, perfil lipídico, uroanálisis y PCR.
- **Controles y filtros:** Buscar laboratorio; Todas/Estado Todos en Android; Estado Todos/Prioridad Todas en iOS.
- **Estados visibles y traducción:** Pendiente, en proceso, completado; alta/urgente se normaliza a urgent, sin importar los ejemplos.
- **Tablas/proyecciones:** diagnostic_orders, diagnostic_order_items, test_definitions, lab_results
- **Servicios:** read_resource(laboratory_directory); create_record; finalize_clinical_record; document-access
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Mi horario — 63:898

- **Frame Figma:** iOS · DOCTOR · 08 · Mi horario
- **Muestra/captura:** Próxima jornada y agenda semanal; mañana/tarde/guardia con horas y descanso.
- **Controles y filtros:** Buscar mi horario.
- **Estados visibles y traducción:** Confirmada/confirmado, pendiente/en espera, descanso/libre. Las horas de médicos y enfermería son específicas por guardia.
- **Tablas/proyecciones:** staff_shifts, shift_requests
- **Servicios:** read_resource; confirm_shift; create_record(shift_requests); review_shift_request
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Notificaciones — 63:953

- **Frame Figma:** iOS · DOCTOR · 09 · Notificaciones
- **Muestra/captura:** Resultado nuevo, cita reprogramada, paciente asignado, recordatorio de guardia y comunicado institucional.
- **Controles y filtros:** Buscar notificaciones.
- **Estados visibles y traducción:** Avisos recientes; no se adjunta estado leído/no leído ni detalle.
- **Tablas/proyecciones:** notifications, notification_topics, notification_preferences
- **Servicios:** read_resource(notifications); update_record(read_at)
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.

#### iOS Médico · Mi perfil — 63:1002

- **Frame Figma:** iOS · DOCTOR · 10 · Perfil
- **Muestra/captura:** Nombre, iniciales, especialidad, médico activo, correo institucional, identificación profesional/verificación institucional.
- **Controles y filtros:** Buscar mi perfil; Seguridad y privacidad, Credenciales y autenticación; Notificaciones/preferencias; Cerrar sesión.
- **Estados visibles y traducción:** Médico activo; identificación pendiente de verificación institucional según texto, sin inventar documentos.
- **Tablas/proyecciones:** profiles, persons, staff_members, staff_specialties, auth.users
- **Servicios:** my_profile; my_access; update_record(profiles); Auth updateUser/MFA/signOut
- **Evidencia:** `evidence/mobile_patient_ios_doctor_elements.md líneas 404–712`.


### Ambigüedades y supuestos controlados

| ID | Evidencia / ausencia | Decisión propuesta |
|---|---|---|
| S01 | Aparecen Santa Ana y San Gabriel en diferentes encabezados | Se inicializa únicamente Hospital Universitario / Sede Central; el nombre legal, dirección, teléfono y correo se confirman antes de usar datos reales |
| S02 | Una misma persona aparece con datos de muestra incompatibles y fechas 2024/2026 | No se importa ninguna persona, correo, edad, diagnóstico o conteo de las maquetas como dato real |
| S03 | Tablero muestra 10/17 y otras vistas muestran cifras/pacientes que no concuerdan | Todos los conteos son consultas; no se guardan números de tarjetas. Los 28 ingresados no se convierten en 28 camas ocupadas |
| S04 | Hay edades, no un formulario de nacimiento visible | Se propone birth_date para calcular edad según fecha de atención; no se almacena edad |
| S05 | PA y alergias aparecen como textos compactos | Se separan sistólica/diastólica y una fila por alergia; el texto con comas es una presentación |
| S06 | Se muestran roles combinados, áreas y establecimientos | Roles N:M por usuario y sede; staff_assignments para áreas; una sola persona puede ser profesional y paciente |
| S07 | Laboratorio requiere procesar/validar, pero el catálogo visible sólo enumera roles principales | Se proponen técnico y validador con permisos mínimos; se exige un segundo profesional para validar resultados. Es una decisión de seguridad adicional, no una pantalla confirmada |
| S08 | No se define la duración del vínculo asistencial | Una consulta crea acceso de 24 h; un ingreso lo mantiene hasta el alta. Esta regla requiere aprobación clínica antes de liberar |
| S09 | Se ve radiografía de tórax entre los estudios | test_definitions soporta laboratory e imaging; no se simula un PACS/DICOM ni integración con equipos |
| S10 | Porcentajes de cobertura/servicio sin fórmula | Se devuelve null y nota explicativa hasta definir metas, denominadores, licencias y cobertura por intervalo |
| S11 | Los adjuntos móviles muestran preferencias de atención, contacto de emergencia, turno atendido, privacidad y guardias con franjas diferentes por rol | appointment_requests separa solicitud de reserva; emergency_contacts enlaza personas/contactos; los datos compartidos se proyectan según rol. Los IDs se vinculan por contenido, sin afirmar una revisión geométrica de los adjuntos |
| S14 | Horario preferido no tiene opciones desplegadas | Se propone una ventana local preferred_start/preferred_end en la fecha y zona de la sede; la reserva definitiva usa timestamptz y no está obligada a reproducir una preferencia |
| S15 | Perfil muestra contacto de emergencia, pero no su formulario | Se proponen persona, relación y teléfono; el paciente edita únicamente su relación y contactos propios, con MFA. Identidades compartidas requieren verificación administrativa |
| S16 | Se alternan Alta/Urgente, Vigente/Activa y En espera en distintas listas | Se define un contrato: alta/urgente → urgent; activa/vigente → receta issued con renglón vigente; en espera → queue_tickets.waiting, sin añadir estados duplicados a citas |
| S17 | No se ven menús de alta de usuarios, editar perfil, nueva receta, detalle ni recuperación | Se documentan servicios y validaciones propuestos; los campos de esos formularios no se presentan como observados |
| S12 | No se especifican jurisdicción, conservación ni explotación sanitaria real | Este paquete no equivale a certificación clínica/legal. Retención, alojamiento, procedimientos de acceso excepcional y recuperación deben aprobarse para el entorno concreto |
| S13 | El dashboard pide ocupación promedio y las capacidades visibles son fijas | El cálculo pondera tiempo de ocupación y asume capacidad habilitada constante en el período; si se permiten cambios históricos de capacidad debe incorporarse su historial antes de dar ese indicador por exacto |

## 2. Modelo entidad-relación, restricciones y RLS

Una única base PostgreSQL compartida sirve a web, Android e iOS. `hospital` contiene el dominio; `private` contiene auxiliares e idempotencia; `public` contiene RPC y proyecciones publicables. Los esquemas internos se excluyen de la API REST. No existen tablas ios_*, android_* o web_*.

El modelo separa la persona de la cuenta Auth, de su condición de paciente y de su actividad laboral. Cita, turno de atención, consulta e ingreso son hechos distintos. Una consulta puede enlazarse a una cita sin copiar sus datos mediante appointment_encounters. Los documentos, diagnósticos y tratamientos cuelgan de entidades clínicas con FK.

| Dominio | Tablas |
|---|---|
| Identidad y acceso | organizations, facilities, departments, persons, person_contacts, person_identifiers, profiles, roles, permissions, role_permissions, user_role_assignments, staff_members, specialties, staff_specialties, staff_assignments, patient_accounts |
| Pacientes y atención | patients, emergency_contacts, appointment_requests, patient_facility_registrations, care_assignments, appointments, appointment_events, triage_levels, care_queues, queue_tickets, appointment_queue_tickets, encounters, appointment_encounters, admissions |
| Infraestructura | floors, room_types, rooms, beds, consultation_rooms, bed_allocations |
| Expediente y tratamientos | diagnosis_codes, patient_conditions, encounter_diagnoses, allergens, patient_allergies, medical_history_entries, vital_sign_sets, clinical_notes, note_addenda, units, medications, administration_routes, prescriptions, prescription_items, care_orders, care_order_executions |
| Diagnóstico y documentos | test_definitions, analytes, test_analytes, lab_reference_ranges, diagnostic_orders, diagnostic_order_items, specimens, specimen_items, documents, patient_documents, lab_results, lab_result_values |
| Personal y recursos | shift_templates, staff_shifts, shift_requests, coverage_requirements, product_categories, products, stock_locations, stock_thresholds, stock_lots, stock_movements, equipment_assets, equipment_maintenance |
| Ambulancia y servicios | ambulances, ambulance_activities, ambulance_dispatches, dispatch_patients, dispatch_crew, notification_topics, notification_preferences, notifications, device_tokens, public_information, report_definitions, report_jobs, report_schedules, audit_events |
| Soporte técnico | idempotency_keys |

Las FK impiden referencias huérfanas. Las claves de negocio tienen UNIQUE. Las cantidades, signos vitales, fechas, rangos temporales, dosis y estados tienen CHECK; las reglas entre filas se validan en triggers o RPC. Las reservas usan intervalos [inicio, fin), de modo que dos intervalos contiguos no colisionan. EXCLUDE impide dobles asignaciones incluso si dos peticiones concurren.

Se comprueba el límite de camas por habitación y de habitaciones por institución: cinco VIP individuales y seis semiprivadas dobles. Una única ambulancia por organización se valida bloqueando la institución, además de la exclusión temporal común para servicio y mantenimiento. La ocupación y los bloqueos de camas comparten bed_allocations, por lo que limpieza y mantenimiento también compiten con una asignación.

### Aplicación del acceso sanitario

| Actor | Alcance permitido | Restricción aplicada |
|---|---|---|
| Paciente | Su identidad, citas, turno y datos clínicos publicados | patient_accounts verificado; UUID ajeno no concede acceso; MFA para clínica |
| Doctor | Pacientes con asignación clínica vigente y sede autorizada | care_assignments + rol + permiso; no acceso por sólo conocer el expediente |
| Enfermería/asistente | Paciente asignado, signos y ejecución de indicaciones | Puede registrar signos; no emitir recetas ni diagnósticos de médico |
| Recepción | Demografía, citas, colas, ingresos y camas de la sede | Sin SELECT a notas, antecedentes, signos ni resultados clínicos |
| Administración | Personal, infraestructura, configuración y agregados | Ser administrador no habilita lectura clínica; rol clínico y vínculo asistencial se evalúan aparte |
| Laboratorio | Órdenes y resultados de su sede | Sin expediente completo; borradores no disponibles para pacientes |
| Inventario / ambulancia | Operación de sus recursos y sede | Permisos distintos del rol clínico |
| Auditor | Metadatos de acceso y reportes autorizados | No se guardan cuerpos clínicos ni contraseñas en auditoría |

Las cuentas desactivadas pierden acceso por comprobación en DB aunque un JWT anterior siga vigente. Los roles se consultan en tablas, evitando depender de claims de permisos desactualizados. La clave service_role se reserva al servidor y no aparece en frontend. Los catálogos son REST auto generado; la lectura clínica se audita con RPC POST. El acceso a archivos usa autorización DB y URL privada temporal, no buckets públicos.

`hospital_api` es NOLOGIN/NOBYPASSRLS y no es dueño de tablas. read_resource/create_record/update_record/patient_chart se implementan en private con ese dueño y siguen RLS. Todas las entradas REST son SECURITY INVOKER; las implementaciones privilegiadas se encuentran en private, fuera del esquema expuesto, con EXECUTE restringido. Las que usan el dueño de migración comprueban identidad, permiso, sede, relación y versión expresamente; las de hospital_api aplican RLS. No se concedió a hospital_api membresía de authenticated: el puente privado de identidad resuelve el acceso al esquema Auth administrado sin heredar sus permisos.

### Lucidchart

El diagrama compartido fue actualizado en una página nueva llamada Modelo normalizado · Supabase, conservando la página original. Se verificaron 92 entidades y 254 objetos totales (92 tablas y 162 relaciones). Las autorreferencias lab_results.supersedes_id y stock_movements.reversal_of se añadieron manualmente con cardinalidad 0..1 en ambos extremos. El archivo `erd/ERD_Hospital_Universitario.drawio` contiene una página completa y páginas por dominio, con tablas, columnas, tipos, PK, FK y conectores. Las referencias entre dominios están rotuladas. `Relaciones.csv` añade nulabilidad/cardinalidad exacta; en el gráfico la notación genérica de conector debe cotejarse con ese CSV.

Para la biblioteca ERD nativa de Lucidchart se entrega `Lucidchart_metadata.csv` con metadatos PostgreSQL y referencias PK/FK, más un diccionario completo. Su importación fue aceptada por Lucidchart y las 92 entidades se colocaron en el lienzo. Las cardinalidades y la nulabilidad de las relaciones importadas deben cotejarse con Relaciones.csv: el importador no reemplaza la revisión de UNIQUE/CHECK del diccionario. La distribución global requiere zoom y se entrega además la versión organizada por dominios en el archivo drawio. En la opción Import from SQL database, seleccionar PostgreSQL y usar los metadatos; si el editor exige su consulta propia, ejecutarla tras desplegar el esquema y utilizar ese resultado. La documentación oficial de Lucid describe este flujo y las relaciones automáticas al arrastrar las tablas.

### Diccionario completo de tablas

Fuente: catálogo real de PostgreSQL después de ejecutar las migraciones; recuentos cotejados con Supabase PostgreSQL 17.11. Incluye 90 tablas de negocio/seguridad en `hospital`, una tabla técnica en `private` y cinco vistas calculadas. `auth.users` pertenece a Supabase Auth; no se recrea en producción.

Todos los identificadores internos son UUID. Las tablas puente tienen PK UUID y restricciones UNIQUE sobre sus claves de negocio. `created_at`, `updated_at` y `row_version` se añaden a todas las tablas hospitalarias. Ningún cliente tiene DELETE; la historia clínica se corrige mediante adendas/versiones.

R = política de SELECT; I = INSERT/WITH CHECK; U = UPDATE/USING y WITH CHECK. El rol SQL `hospital_api` es NOLOGIN y NOBYPASSRLS; las tablas son propiedad del rol de migración y fuerzan RLS. Las funciones auxiliares de `private` consultan el JWT verificado, el estado activo de cuenta, las membresías y la asignación clínica; no confían en `user_metadata`. Véase `20261023175751_hospital_security.sql` para sus definiciones completas.

## Identidad y acceso

### hospital.organizations

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| name | text | NO |  | — |
| institutional_email | text | YES |  | — |
| phone | text | YES |  | — |
| administrative_address | text | YES |  | — |
| timezone | text | NO |  | 'America/El_Salvador'::text |
| locale | text | NO |  | 'es-SV'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `organizations_institutional_email_check`: `CHECK (((institutional_email IS NULL) OR (institutional_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text)))`.
- `organizations_name_check`: `CHECK (((length(TRIM(BOTH FROM name)) >= 2) AND (length(TRIM(BOTH FROM name)) <= 160)))`.
- `organizations_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'settings.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'settings.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'settings.write'::text)`.

### hospital.facilities

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| organization_id | uuid | NO |  FK → hospital.organizations.id | — |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| address | text | YES |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `facilities_code_key`: `UNIQUE (code)`.
- `facilities_organization_id_fkey`: `FOREIGN KEY (organization_id) REFERENCES hospital.organizations(id)`.
- `facilities_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(id, 'settings.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(id, 'settings.write'::text)`; `WITH CHECK private.has_permission(id, 'settings.write'::text)`.

### hospital.departments

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| code | text | NO |  | — |
| name | text | NO |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `departments_facility_id_code_key`: `UNIQUE (facility_id, code)`.
- `departments_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `departments_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(facility_id, 'settings.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(facility_id, 'settings.write'::text)`; `WITH CHECK private.has_permission(facility_id, 'settings.write'::text)`.

### hospital.persons

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| given_names | text | NO |  | — |
| family_names | text | NO |  | — |
| birth_date | date | YES |  | — |
| administrative_sex | text | YES |  | — |
| archived_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `persons_administrative_sex_check`: `CHECK ((administrative_sex = ANY (ARRAY['female'::text, 'male'::text, 'intersex'::text, 'unknown'::text])))`.
- `persons_family_names_check`: `CHECK (((length(TRIM(BOTH FROM family_names)) >= 1) AND (length(TRIM(BOTH FROM family_names)) <= 100)))`.
- `persons_given_names_check`: `CHECK (((length(TRIM(BOTH FROM given_names)) >= 1) AND (length(TRIM(BOTH FROM given_names)) <= 100)))`.
- `persons_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) OR private.has_permission(NULL::uuid, 'users.write'::text))`.
- **SELECT** → ['hospital_api']; `USING private.can_person(id)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (private.has_permission(NULL::uuid, 'patients.write'::text) OR private.has_permission(NULL::uuid, 'users.write'::text))`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) OR private.has_permission(NULL::uuid, 'users.write'::text))`.

### hospital.person_contacts

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| person_id | uuid | NO |  FK → hospital.persons.id | — |
| kind | text | NO |  | — |
| value | text | NO |  | — |
| is_primary | boolean | NO |  | false |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `person_contacts_check`: `CHECK (((kind <> 'email'::text) OR (value ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text)))`.
- `person_contacts_kind_check`: `CHECK ((kind = ANY (ARRAY['phone'::text, 'email'::text, 'address'::text])))`.
- `person_contacts_person_id_fkey`: `FOREIGN KEY (person_id) REFERENCES hospital.persons(id)`.
- `person_contacts_person_id_kind_value_key`: `UNIQUE (person_id, kind, value)`.
- `person_contacts_pkey`: `PRIMARY KEY (id)`.
- `person_contacts_value_check`: `CHECK (((length(TRIM(BOTH FROM value)) >= 1) AND (length(TRIM(BOTH FROM value)) <= 500)))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`.
- **SELECT** → ['hospital_api']; `USING private.can_person(person_id)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`.

### hospital.person_identifiers

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| person_id | uuid | NO |  FK → hospital.persons.id | — |
| issuer_country | character(2) | NO |  | — |
| kind | text | NO |  | — |
| value | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `person_identifiers_issuer_country_kind_value_key`: `UNIQUE (issuer_country, kind, value)`.
- `person_identifiers_person_id_fkey`: `FOREIGN KEY (person_id) REFERENCES hospital.persons(id)`.
- `person_identifiers_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`.
- **SELECT** → ['hospital_api']; `USING private.can_person(person_id)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`; `WITH CHECK (private.has_permission(NULL::uuid, 'patients.write'::text) AND private.can_person(person_id))`.

### hospital.profiles

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK FK → auth.users.id UNIQUE | — |
| person_id | uuid | YES |  FK → hospital.persons.id UNIQUE | — |
| status | text | NO |  | 'pending'::text |
| preferred_name | text | YES |  | — |
| theme | text | NO |  | 'system'::text |
| locale | text | NO |  | 'es-SV'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `profiles_id_fkey`: `FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT`.
- `profiles_person_id_fkey`: `FOREIGN KEY (person_id) REFERENCES hospital.persons(id)`.
- `profiles_person_id_key`: `UNIQUE (person_id)`.
- `profiles_pkey`: `PRIMARY KEY (id)`.
- `profiles_status_check`: `CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'disabled'::text])))`.
- `profiles_theme_check`: `CHECK ((theme = ANY (ARRAY['system'::text, 'light'::text, 'dark'::text, 'high_contrast'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.
- **SELECT** → ['hospital_api']; `USING private.can_profile(id)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK ((id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.

### hospital.roles

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `roles_code_key`: `UNIQUE (code)`.
- `roles_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.permissions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| description | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `permissions_code_key`: `UNIQUE (code)`.
- `permissions_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.role_permissions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| role_id | uuid | NO |  FK → hospital.roles.id | — |
| permission_id | uuid | NO |  FK → hospital.permissions.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `role_permissions_permission_id_fkey`: `FOREIGN KEY (permission_id) REFERENCES hospital.permissions(id)`.
- `role_permissions_pkey`: `PRIMARY KEY (id)`.
- `role_permissions_role_id_fkey`: `FOREIGN KEY (role_id) REFERENCES hospital.roles(id)`.
- `role_permissions_role_id_permission_id_key`: `UNIQUE (role_id, permission_id)`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.user_role_assignments

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| profile_id | uuid | NO |  FK → hospital.profiles.id | — |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| role_id | uuid | NO |  FK → hospital.roles.id | — |
| granted_by | uuid | YES |  FK → hospital.profiles.id | — |
| granted_at | timestamp with time zone | NO |  | now() |
| revoked_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `user_role_assignments_check`: `CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at)))`.
- `user_role_assignments_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `user_role_assignments_granted_by_fkey`: `FOREIGN KEY (granted_by) REFERENCES hospital.profiles(id)`.
- `user_role_assignments_pkey`: `PRIMARY KEY (id)`.
- `user_role_assignments_profile_id_facility_id_role_id_key`: `UNIQUE (profile_id, facility_id, role_id)`.
- `user_role_assignments_profile_id_fkey`: `FOREIGN KEY (profile_id) REFERENCES hospital.profiles(id)`.
- `user_role_assignments_role_id_fkey`: `FOREIGN KEY (role_id) REFERENCES hospital.roles(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (private.has_permission(facility_id, 'users.write'::text) AND (profile_id <> ( SELECT auth.uid() AS uid)))`.
- **SELECT** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) OR private.has_permission(facility_id, 'users.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (private.has_permission(facility_id, 'users.write'::text) AND (profile_id <> ( SELECT auth.uid() AS uid)))`; `WITH CHECK (private.has_permission(facility_id, 'users.write'::text) AND (profile_id <> ( SELECT auth.uid() AS uid)))`.

### hospital.staff_members

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| person_id | uuid | NO |  FK → hospital.persons.id UNIQUE | — |
| employee_code | text | NO |  UNIQUE | — |
| license_number | text | YES |  UNIQUE | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `staff_members_employee_code_key`: `UNIQUE (employee_code)`.
- `staff_members_license_number_key`: `UNIQUE (license_number)`.
- `staff_members_person_id_fkey`: `FOREIGN KEY (person_id) REFERENCES hospital.persons(id)`.
- `staff_members_person_id_key`: `UNIQUE (person_id)`.
- `staff_members_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'users.write'::text)`.
- **SELECT** → ['hospital_api']; `USING ((id = private.staff_id()) OR private.has_permission(NULL::uuid, 'users.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'users.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'users.write'::text)`.

### hospital.specialties

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `specialties_code_key`: `UNIQUE (code)`.
- `specialties_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.staff_specialties

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| specialty_id | uuid | NO |  FK → hospital.specialties.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `staff_specialties_pkey`: `PRIMARY KEY (id)`.
- `staff_specialties_specialty_id_fkey`: `FOREIGN KEY (specialty_id) REFERENCES hospital.specialties(id)`.
- `staff_specialties_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.
- `staff_specialties_staff_id_specialty_id_key`: `UNIQUE (staff_id, specialty_id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'users.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'users.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'users.write'::text)`.

### hospital.staff_assignments

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| job_title | text | NO |  | — |
| valid_during | tstzrange | NO |  | tstzrange(now(), NULL::timestamp with time zone, '[)'::text) |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `staff_assignments_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `staff_assignments_pkey`: `PRIMARY KEY (id)`.
- `staff_assignments_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.
- `staff_assignments_valid_during_check`: `CHECK (((NOT isempty(valid_during)) AND (lower(valid_during) IS NOT NULL)))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'users.write'::text)`.
- **SELECT** → ['hospital_api']; `USING ((staff_id = private.staff_id()) OR private.has_permission(private.department_facility(department_id), 'users.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'users.write'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'users.write'::text)`.

### hospital.patient_accounts

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id UNIQUE | — |
| profile_id | uuid | NO |  FK → hospital.profiles.id UNIQUE | — |
| verified_by | uuid | NO |  FK → hospital.profiles.id | — |
| verified_at | timestamp with time zone | NO |  | now() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patient_accounts_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `patient_accounts_patient_id_key`: `UNIQUE (patient_id)`.
- `patient_accounts_pkey`: `PRIMARY KEY (id)`.
- `patient_accounts_profile_id_fkey`: `FOREIGN KEY (profile_id) REFERENCES hospital.profiles(id)`.
- `patient_accounts_profile_id_key`: `UNIQUE (profile_id)`.
- `patient_accounts_verified_by_fkey`: `FOREIGN KEY (verified_by) REFERENCES hospital.profiles(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'patients.write'::text)`.
- **SELECT** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) OR private.can_patient(patient_id, 'patients.write'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'patients.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'patients.write'::text)`.

## Pacientes y atención

### hospital.patients

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| person_id | uuid | NO |  FK → hospital.persons.id UNIQUE | — |
| medical_record_number | text | NO |  UNIQUE | — |
| blood_group | text | YES |  | — |
| archived_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patients_blood_group_check`: `CHECK ((blood_group = ANY (ARRAY['O+'::text, 'O-'::text, 'A+'::text, 'A-'::text, 'B+'::text, 'B-'::text, 'AB+'::text, 'AB-'::text, 'unknown'::text])))`.
- `patients_medical_record_number_key`: `UNIQUE (medical_record_number)`.
- `patients_person_id_fkey`: `FOREIGN KEY (person_id) REFERENCES hospital.persons(id)`.
- `patients_person_id_key`: `UNIQUE (person_id)`.
- `patients_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'patients.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_patient(id, 'patients.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'patients.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'patients.write'::text)`.

### hospital.emergency_contacts

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| contact_person_id | uuid | NO |  FK → hospital.persons.id | — |
| relationship | text | NO |  | — |
| is_primary | boolean | NO |  | false |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `emergency_contacts_contact_person_id_fkey`: `FOREIGN KEY (contact_person_id) REFERENCES hospital.persons(id)`.
- `emergency_contacts_patient_id_contact_person_id_key`: `UNIQUE (patient_id, contact_person_id)`.
- `emergency_contacts_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `emergency_contacts_pkey`: `PRIMARY KEY (id)`.
- `emergency_contacts_relationship_check`: `CHECK (((length(TRIM(BOTH FROM relationship)) >= 1) AND (length(TRIM(BOTH FROM relationship)) <= 100)))`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING (private.own_patient(patient_id) OR private.can_patient(patient_id, 'patients.read'::text))`; `WITH CHECK None`.

### hospital.appointment_requests

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| specialty_id | uuid | NO |  FK → hospital.specialties.id | — |
| reason | text | NO |  | — |
| preferred_date | date | NO |  | — |
| preferred_start | time without time zone | NO |  | — |
| preferred_end | time without time zone | NO |  | — |
| status | text | NO |  | 'pending'::text |
| appointment_id | uuid | YES |  FK → hospital.appointments.id UNIQUE | — |
| requested_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| resolved_by | uuid | YES |  FK → hospital.profiles.id | — |
| resolved_at | timestamp with time zone | YES |  | — |
| decision_reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `appointment_requests_appointment_id_fkey`: `FOREIGN KEY (appointment_id) REFERENCES hospital.appointments(id)`.
- `appointment_requests_appointment_id_key`: `UNIQUE (appointment_id)`.
- `appointment_requests_check`: `CHECK ((preferred_end > preferred_start))`.
- `appointment_requests_check1`: `CHECK (((status = 'scheduled'::text) = (appointment_id IS NOT NULL)))`.
- `appointment_requests_check2`: `CHECK ((((status = 'pending'::text) AND (resolved_by IS NULL) AND (resolved_at IS NULL)) OR ((status <> 'pending'::text) AND (resolved_by IS NOT NULL) AND (resolved_at IS NOT NULL))))`.
- `appointment_requests_check3`: `CHECK (((status <> ALL (ARRAY['rejected'::text, 'cancelled'::text])) OR ((decision_reason IS NOT NULL) AND (length(TRIM(BOTH FROM decision_reason)) > 0))))`.
- `appointment_requests_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `appointment_requests_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `appointment_requests_pkey`: `PRIMARY KEY (id)`.
- `appointment_requests_reason_check`: `CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 2000)))`.
- `appointment_requests_requested_by_fkey`: `FOREIGN KEY (requested_by) REFERENCES hospital.profiles(id)`.
- `appointment_requests_resolved_by_fkey`: `FOREIGN KEY (resolved_by) REFERENCES hospital.profiles(id)`.
- `appointment_requests_specialty_id_fkey`: `FOREIGN KEY (specialty_id) REFERENCES hospital.specialties(id)`.
- `appointment_requests_status_check`: `CHECK ((status = ANY (ARRAY['pending'::text, 'scheduled'::text, 'rejected'::text, 'cancelled'::text])))`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING (private.own_patient(patient_id) OR private.has_permission(facility_id, 'appointments.all'::text))`; `WITH CHECK None`.

### hospital.patient_facility_registrations

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| registered_at | timestamp with time zone | NO |  | now() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patient_facility_registrations_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `patient_facility_registrations_patient_id_facility_id_key`: `UNIQUE (patient_id, facility_id)`.
- `patient_facility_registrations_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `patient_facility_registrations_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(facility_id, 'patients.write'::text)`.
- **SELECT** → ['hospital_api']; `USING (private.own_patient(patient_id) OR private.has_permission(facility_id, 'patients.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(facility_id, 'patients.write'::text)`; `WITH CHECK private.has_permission(facility_id, 'patients.write'::text)`.

### hospital.care_assignments

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| valid_during | tstzrange | NO |  | — |
| authorized_by | uuid | NO |  FK → hospital.profiles.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `care_assignments_authorized_by_fkey`: `FOREIGN KEY (authorized_by) REFERENCES hospital.profiles(id)`.
- `care_assignments_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `care_assignments_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `care_assignments_pkey`: `PRIMARY KEY (id)`.
- `care_assignments_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.
- `care_assignments_valid_during_check`: `CHECK (((NOT isempty(valid_during)) AND (lower(valid_during) IS NOT NULL)))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'care.assign'::text)`.
- **SELECT** → ['hospital_api']; `USING ((staff_id = private.staff_id()) OR private.can_patient(patient_id, 'clinical.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'care.assign'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'care.assign'::text)`.

### hospital.appointments

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| physician_id | uuid | NO |  FK → hospital.staff_members.id | — |
| specialty_id | uuid | NO |  FK → hospital.specialties.id | — |
| consultation_room_id | uuid | YES |  FK → hospital.consultation_rooms.id | — |
| period | tstzrange | NO |  | — |
| reason | text | NO |  | — |
| status | text | NO |  | 'scheduled'::text |
| requested_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| cancellation_reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `appointments_check`: `CHECK (((status <> 'cancelled'::text) OR ((cancellation_reason IS NOT NULL) AND (length(TRIM(BOTH FROM cancellation_reason)) > 0))))`.
- `appointments_consultation_room_id_fkey`: `FOREIGN KEY (consultation_room_id) REFERENCES hospital.consultation_rooms(id)`.
- `appointments_consultation_room_id_period_excl`: `EXCLUDE USING gist (consultation_room_id WITH =, period WITH &&) WHERE ((status <> ALL (ARRAY['cancelled'::text, 'no_show'::text])))`.
- `appointments_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `appointments_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `appointments_patient_id_period_excl`: `EXCLUDE USING gist (patient_id WITH =, period WITH &&) WHERE ((status <> ALL (ARRAY['cancelled'::text, 'no_show'::text])))`.
- `appointments_period_check`: `CHECK (((NOT isempty(period)) AND (lower(period) IS NOT NULL) AND (upper(period) IS NOT NULL) AND lower_inc(period) AND (NOT upper_inc(period))))`.
- `appointments_physician_id_fkey`: `FOREIGN KEY (physician_id) REFERENCES hospital.staff_members(id)`.
- `appointments_physician_id_period_excl`: `EXCLUDE USING gist (physician_id WITH =, period WITH &&) WHERE ((status <> ALL (ARRAY['cancelled'::text, 'no_show'::text])))`.
- `appointments_pkey`: `PRIMARY KEY (id)`.
- `appointments_reason_check`: `CHECK (((length(TRIM(BOTH FROM reason)) >= 1) AND (length(TRIM(BOTH FROM reason)) <= 2000)))`.
- `appointments_requested_by_fkey`: `FOREIGN KEY (requested_by) REFERENCES hospital.profiles(id)`.
- `appointments_specialty_id_fkey`: `FOREIGN KEY (specialty_id) REFERENCES hospital.specialties(id)`.
- `appointments_status_check`: `CHECK ((status = ANY (ARRAY['scheduled'::text, 'confirmed'::text, 'checked_in'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text, 'no_show'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'appointments.write'::text)`.
- **SELECT** → ['hospital_api']; `USING (private.own_patient(patient_id) OR private.has_permission(private.department_facility(department_id), 'appointments.all'::text) OR ((physician_id = private.staff_id()) AND private.has_permission(private.department_facility(department_id), 'appointments.read'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'appointments.write'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'appointments.write'::text)`.

### hospital.appointment_events

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| appointment_id | uuid | NO |  FK → hospital.appointments.id | — |
| from_status | text | YES |  | — |
| to_status | text | NO |  | — |
| actor_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| occurred_at | timestamp with time zone | NO |  | now() |
| event_kind | text | NO |  | 'status_changed'::text |
| previous_period | tstzrange | YES |  | — |
| new_period | tstzrange | YES |  | — |
| reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `appointment_events_actor_id_fkey`: `FOREIGN KEY (actor_id) REFERENCES hospital.profiles(id)`.
- `appointment_events_appointment_id_fkey`: `FOREIGN KEY (appointment_id) REFERENCES hospital.appointments(id)`.
- `appointment_events_check`: `CHECK (((event_kind <> 'rescheduled'::text) OR ((previous_period IS NOT NULL) AND (new_period IS NOT NULL) AND (reason IS NOT NULL) AND (length(TRIM(BOTH FROM reason)) > 0))))`.
- `appointment_events_event_kind_check`: `CHECK ((event_kind = ANY (ARRAY['status_changed'::text, 'rescheduled'::text])))`.
- `appointment_events_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.appointments a
  WHERE ((a.id = appointment_events.appointment_id) AND private.has_permission(private.department_facility(a.department_id), 'appointments.write'::text))))`.
- **SELECT** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.appointments a
  WHERE (a.id = appointment_events.appointment_id)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.appointments a
  WHERE ((a.id = appointment_events.appointment_id) AND private.has_permission(private.department_facility(a.department_id), 'appointments.write'::text))))`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.appointments a
  WHERE ((a.id = appointment_events.appointment_id) AND private.has_permission(private.department_facility(a.department_id), 'appointments.write'::text))))`.

### hospital.triage_levels

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| priority | smallint | NO |  UNIQUE | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `triage_levels_code_key`: `UNIQUE (code)`.
- `triage_levels_pkey`: `PRIMARY KEY (id)`.
- `triage_levels_priority_check`: `CHECK (((priority >= 1) AND (priority <= 5)))`.
- `triage_levels_priority_key`: `UNIQUE (priority)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.care_queues

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| service_date | date | NO |  | — |
| code | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `care_queues_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `care_queues_department_id_service_date_code_key`: `UNIQUE (department_id, service_date, code)`.
- `care_queues_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'queue.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'queue.manage'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'queue.manage'::text)`.

### hospital.queue_tickets

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| queue_id | uuid | NO |  FK → hospital.care_queues.id | — |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| triage_level_id | uuid | YES |  FK → hospital.triage_levels.id | — |
| number | integer | NO |  | — |
| status | text | NO |  | 'waiting'::text |
| arrived_at | timestamp with time zone | NO |  | now() |
| called_at | timestamp with time zone | YES |  | — |
| started_at | timestamp with time zone | YES |  | — |
| finished_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `queue_tickets_check`: `CHECK (((called_at IS NULL) OR (called_at >= arrived_at)))`.
- `queue_tickets_check1`: `CHECK (((started_at IS NULL) OR (started_at >= arrived_at)))`.
- `queue_tickets_check2`: `CHECK (((finished_at IS NULL) OR (finished_at >= COALESCE(started_at, arrived_at))))`.
- `queue_tickets_number_check`: `CHECK ((number > 0))`.
- `queue_tickets_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `queue_tickets_pkey`: `PRIMARY KEY (id)`.
- `queue_tickets_queue_id_fkey`: `FOREIGN KEY (queue_id) REFERENCES hospital.care_queues(id)`.
- `queue_tickets_queue_id_number_key`: `UNIQUE (queue_id, number)`.
- `queue_tickets_status_check`: `CHECK ((status = ANY (ARRAY['waiting'::text, 'called'::text, 'in_service'::text, 'completed'::text, 'cancelled'::text])))`.
- `queue_tickets_triage_level_id_fkey`: `FOREIGN KEY (triage_level_id) REFERENCES hospital.triage_levels(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.care_queues q
  WHERE ((q.id = queue_tickets.queue_id) AND private.has_permission(private.department_facility(q.department_id), 'queue.manage'::text))))`.
- **SELECT** → ['hospital_api']; `USING (private.own_patient(patient_id) OR (EXISTS ( SELECT 1
   FROM hospital.care_queues q
  WHERE ((q.id = queue_tickets.queue_id) AND private.has_permission(private.department_facility(q.department_id), 'queue.read'::text)))))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.care_queues q
  WHERE ((q.id = queue_tickets.queue_id) AND private.has_permission(private.department_facility(q.department_id), 'queue.manage'::text))))`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.care_queues q
  WHERE ((q.id = queue_tickets.queue_id) AND private.has_permission(private.department_facility(q.department_id), 'queue.manage'::text))))`.

### hospital.appointment_queue_tickets

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| appointment_id | uuid | NO |  FK → hospital.appointments.id UNIQUE | — |
| ticket_id | uuid | NO |  FK → hospital.queue_tickets.id UNIQUE | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `appointment_queue_tickets_appointment_id_fkey`: `FOREIGN KEY (appointment_id) REFERENCES hospital.appointments(id)`.
- `appointment_queue_tickets_appointment_id_key`: `UNIQUE (appointment_id)`.
- `appointment_queue_tickets_pkey`: `PRIMARY KEY (id)`.
- `appointment_queue_tickets_ticket_id_fkey`: `FOREIGN KEY (ticket_id) REFERENCES hospital.queue_tickets(id)`.
- `appointment_queue_tickets_ticket_id_key`: `UNIQUE (ticket_id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (EXISTS ( SELECT 1
   FROM (hospital.queue_tickets q
     JOIN hospital.care_queues c ON ((c.id = q.queue_id)))
  WHERE ((q.id = appointment_queue_tickets.ticket_id) AND private.has_permission(private.department_facility(c.department_id), 'queue.manage'::text))))`.
- **SELECT** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.queue_tickets q
  WHERE (q.id = appointment_queue_tickets.ticket_id)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM (hospital.queue_tickets q
     JOIN hospital.care_queues c ON ((c.id = q.queue_id)))
  WHERE ((q.id = appointment_queue_tickets.ticket_id) AND private.has_permission(private.department_facility(c.department_id), 'queue.manage'::text))))`; `WITH CHECK (EXISTS ( SELECT 1
   FROM (hospital.queue_tickets q
     JOIN hospital.care_queues c ON ((c.id = q.queue_id)))
  WHERE ((q.id = appointment_queue_tickets.ticket_id) AND private.has_permission(private.department_facility(c.department_id), 'queue.manage'::text))))`.

### hospital.encounters

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| attending_physician_id | uuid | YES |  FK → hospital.staff_members.id | — |
| kind | text | NO |  | — |
| status | text | NO |  | 'open'::text |
| started_at | timestamp with time zone | NO |  | now() |
| ended_at | timestamp with time zone | YES |  | — |
| chief_complaint | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `encounters_attending_physician_id_fkey`: `FOREIGN KEY (attending_physician_id) REFERENCES hospital.staff_members(id)`.
- `encounters_check`: `CHECK (((ended_at IS NULL) OR (ended_at >= started_at)))`.
- `encounters_check1`: `CHECK (((status <> 'closed'::text) OR (ended_at IS NOT NULL)))`.
- `encounters_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `encounters_kind_check`: `CHECK ((kind = ANY (ARRAY['outpatient'::text, 'emergency'::text, 'inpatient'::text, 'follow_up'::text])))`.
- `encounters_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `encounters_pkey`: `PRIMARY KEY (id)`.
- `encounters_status_check`: `CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_encounter(id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_encounter(id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_encounter(id, 'clinical.write'::text)`; `WITH CHECK private.can_encounter(id, 'clinical.write'::text)`.

### hospital.appointment_encounters

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| appointment_id | uuid | NO |  FK → hospital.appointments.id UNIQUE | — |
| encounter_id | uuid | NO |  FK → hospital.encounters.id UNIQUE | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `appointment_encounters_appointment_id_fkey`: `FOREIGN KEY (appointment_id) REFERENCES hospital.appointments(id)`.
- `appointment_encounters_appointment_id_key`: `UNIQUE (appointment_id)`.
- `appointment_encounters_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `appointment_encounters_encounter_id_key`: `UNIQUE (encounter_id)`.
- `appointment_encounters_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_encounter(encounter_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'clinical.write'::text)`; `WITH CHECK private.can_encounter(encounter_id, 'clinical.write'::text)`.

### hospital.admissions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id UNIQUE | — |
| admission_type | text | NO |  | — |
| triage_level_id | uuid | YES |  FK → hospital.triage_levels.id | — |
| status | text | NO |  | 'triage'::text |
| admitted_at | timestamp with time zone | NO |  | now() |
| planned_discharge_at | timestamp with time zone | YES |  | — |
| discharged_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `admissions_admission_type_check`: `CHECK ((admission_type = ANY (ARRAY['emergency'::text, 'scheduled'::text, 'observation'::text])))`.
- `admissions_check`: `CHECK (((discharged_at IS NULL) OR (discharged_at >= admitted_at)))`.
- `admissions_check1`: `CHECK (((status <> 'discharged'::text) OR (discharged_at IS NOT NULL)))`.
- `admissions_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `admissions_encounter_id_key`: `UNIQUE (encounter_id)`.
- `admissions_pkey`: `PRIMARY KEY (id)`.
- `admissions_status_check`: `CHECK ((status = ANY (ARRAY['triage'::text, 'observation'::text, 'admitted'::text, 'discharge_planned'::text, 'discharged'::text, 'cancelled'::text])))`.
- `admissions_triage_level_id_fkey`: `FOREIGN KEY (triage_level_id) REFERENCES hospital.triage_levels(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.encounter_facility(encounter_id), 'admissions.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_patient(private.encounter_patient(encounter_id), 'patients.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.encounter_facility(encounter_id), 'admissions.write'::text)`; `WITH CHECK private.has_permission(private.encounter_facility(encounter_id), 'admissions.write'::text)`.

## Infraestructura

### hospital.floors

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| number | smallint | NO |  | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `floors_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `floors_facility_id_number_key`: `UNIQUE (facility_id, number)`.
- `floors_number_check`: `CHECK (((number >= '-5'::integer) AND (number <= 200)))`.
- `floors_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(facility_id, 'beds.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(facility_id, 'beds.manage'::text)`; `WITH CHECK private.has_permission(facility_id, 'beds.manage'::text)`.

### hospital.room_types

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| max_beds | smallint | NO |  | — |
| max_rooms_per_organization | smallint | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `room_types_code_key`: `UNIQUE (code)`.
- `room_types_max_beds_check`: `CHECK (((max_beds >= 1) AND (max_beds <= 12)))`.
- `room_types_max_rooms_per_organization_check`: `CHECK ((max_rooms_per_organization > 0))`.
- `room_types_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.rooms

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| floor_id | uuid | NO |  FK → hospital.floors.id | — |
| room_type_id | uuid | NO |  FK → hospital.room_types.id | — |
| code | text | NO |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `rooms_floor_id_code_key`: `UNIQUE (floor_id, code)`.
- `rooms_floor_id_fkey`: `FOREIGN KEY (floor_id) REFERENCES hospital.floors(id)`.
- `rooms_pkey`: `PRIMARY KEY (id)`.
- `rooms_room_type_id_fkey`: `FOREIGN KEY (room_type_id) REFERENCES hospital.room_types(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.floors f
  WHERE ((f.id = rooms.floor_id) AND private.has_permission(f.facility_id, 'beds.manage'::text))))`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.floors f
  WHERE ((f.id = rooms.floor_id) AND private.has_permission(f.facility_id, 'beds.manage'::text))))`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.floors f
  WHERE ((f.id = rooms.floor_id) AND private.has_permission(f.facility_id, 'beds.manage'::text))))`.

### hospital.beds

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| room_id | uuid | NO |  FK → hospital.rooms.id | — |
| code | text | NO |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `beds_pkey`: `PRIMARY KEY (id)`.
- `beds_room_id_code_key`: `UNIQUE (room_id, code)`.
- `beds_room_id_fkey`: `FOREIGN KEY (room_id) REFERENCES hospital.rooms(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.room_facility(room_id), 'beds.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.room_facility(room_id), 'beds.manage'::text)`; `WITH CHECK private.has_permission(private.room_facility(room_id), 'beds.manage'::text)`.

### hospital.consultation_rooms

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| code | text | NO |  | — |
| name | text | NO |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `consultation_rooms_department_id_code_key`: `UNIQUE (department_id, code)`.
- `consultation_rooms_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `consultation_rooms_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'settings.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'settings.write'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'settings.write'::text)`.

### hospital.bed_allocations

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| bed_id | uuid | NO |  FK → hospital.beds.id | — |
| admission_id | uuid | YES |  FK → hospital.admissions.id | — |
| kind | text | NO |  | — |
| period | tstzrange | NO |  | — |
| cancelled_at | timestamp with time zone | YES |  | — |
| reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `bed_allocations_admission_id_fkey`: `FOREIGN KEY (admission_id) REFERENCES hospital.admissions(id)`.
- `bed_allocations_admission_id_period_excl`: `EXCLUDE USING gist (admission_id WITH =, period WITH &&) WHERE (((cancelled_at IS NULL) AND (admission_id IS NOT NULL)))`.
- `bed_allocations_bed_id_fkey`: `FOREIGN KEY (bed_id) REFERENCES hospital.beds(id)`.
- `bed_allocations_bed_id_period_excl`: `EXCLUDE USING gist (bed_id WITH =, period WITH &&) WHERE ((cancelled_at IS NULL))`.
- `bed_allocations_check`: `CHECK (((kind = ANY (ARRAY['occupancy'::text, 'reservation'::text])) = (admission_id IS NOT NULL)))`.
- `bed_allocations_kind_check`: `CHECK ((kind = ANY (ARRAY['occupancy'::text, 'reservation'::text, 'cleaning'::text, 'maintenance'::text])))`.
- `bed_allocations_period_check`: `CHECK (((NOT isempty(period)) AND (lower(period) IS NOT NULL) AND lower_inc(period) AND (NOT upper_inc(period))))`.
- `bed_allocations_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.bed_facility(bed_id), 'beds.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.bed_facility(bed_id), 'beds.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.bed_facility(bed_id), 'beds.manage'::text)`; `WITH CHECK private.has_permission(private.bed_facility(bed_id), 'beds.manage'::text)`.

## Expediente y tratamientos

### hospital.diagnosis_codes

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| system | text | NO |  | 'ICD-10'::text |
| code | text | NO |  | — |
| description | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `diagnosis_codes_pkey`: `PRIMARY KEY (id)`.
- `diagnosis_codes_system_code_key`: `UNIQUE (system, code)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.patient_conditions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| diagnosis_code_id | uuid | NO |  FK → hospital.diagnosis_codes.id | — |
| onset_date | date | YES |  | — |
| resolved_date | date | YES |  | — |
| status | text | NO |  | 'active'::text |
| severity | text | YES |  | — |
| recorded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patient_conditions_check`: `CHECK (((resolved_date IS NULL) OR (onset_date IS NULL) OR (resolved_date >= onset_date)))`.
- `patient_conditions_diagnosis_code_id_fkey`: `FOREIGN KEY (diagnosis_code_id) REFERENCES hospital.diagnosis_codes(id)`.
- `patient_conditions_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `patient_conditions_pkey`: `PRIMARY KEY (id)`.
- `patient_conditions_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES hospital.profiles(id)`.
- `patient_conditions_severity_check`: `CHECK ((severity = ANY (ARRAY['mild'::text, 'moderate'::text, 'severe'::text])))`.
- `patient_conditions_status_check`: `CHECK ((status = ANY (ARRAY['active'::text, 'resolved'::text, 'inactive'::text, 'entered_in_error'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.write'::text)`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.

### hospital.encounter_diagnoses

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| condition_id | uuid | NO |  FK → hospital.patient_conditions.id | — |
| is_principal | boolean | NO |  | false |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `encounter_diagnoses_condition_id_fkey`: `FOREIGN KEY (condition_id) REFERENCES hospital.patient_conditions(id)`.
- `encounter_diagnoses_encounter_id_condition_id_key`: `UNIQUE (encounter_id, condition_id)`.
- `encounter_diagnoses_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `encounter_diagnoses_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_encounter(encounter_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'clinical.write'::text)`; `WITH CHECK private.can_encounter(encounter_id, 'clinical.write'::text)`.

### hospital.allergens

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| kind | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `allergens_code_key`: `UNIQUE (code)`.
- `allergens_kind_check`: `CHECK ((kind = ANY (ARRAY['medication'::text, 'food'::text, 'environment'::text, 'other'::text])))`.
- `allergens_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.patient_allergies

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| allergen_id | uuid | NO |  FK → hospital.allergens.id | — |
| reaction | text | YES |  | — |
| severity | text | NO |  | — |
| status | text | NO |  | 'active'::text |
| recorded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patient_allergies_allergen_id_fkey`: `FOREIGN KEY (allergen_id) REFERENCES hospital.allergens(id)`.
- `patient_allergies_patient_id_allergen_id_key`: `UNIQUE (patient_id, allergen_id)`.
- `patient_allergies_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `patient_allergies_pkey`: `PRIMARY KEY (id)`.
- `patient_allergies_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES hospital.profiles(id)`.
- `patient_allergies_severity_check`: `CHECK ((severity = ANY (ARRAY['mild'::text, 'moderate'::text, 'severe'::text, 'life_threatening'::text, 'unknown'::text])))`.
- `patient_allergies_status_check`: `CHECK ((status = ANY (ARRAY['active'::text, 'resolved'::text, 'entered_in_error'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.write'::text)`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.

### hospital.medical_history_entries

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| kind | text | NO |  | — |
| description | text | NO |  | — |
| occurred_on | date | YES |  | — |
| recorded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| entered_in_error_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `medical_history_entries_kind_check`: `CHECK ((kind = ANY (ARRAY['pathological'::text, 'surgical'::text, 'family'::text, 'social'::text, 'other'::text])))`.
- `medical_history_entries_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `medical_history_entries_pkey`: `PRIMARY KEY (id)`.
- `medical_history_entries_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES hospital.profiles(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.write'::text)`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.

### hospital.vital_sign_sets

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| recorded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| measured_at | timestamp with time zone | NO |  | now() |
| systolic_mmhg | smallint | YES |  | — |
| diastolic_mmhg | smallint | YES |  | — |
| pulse_bpm | smallint | YES |  | — |
| respiratory_rate | smallint | YES |  | — |
| temperature_c | numeric(4,1) | YES |  | — |
| spo2_percent | numeric(5,2) | YES |  | — |
| weight_kg | numeric(6,2) | YES |  | — |
| height_cm | numeric(5,1) | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `vital_sign_sets_check`: `CHECK (((systolic_mmhg IS NULL) = (diastolic_mmhg IS NULL)))`.
- `vital_sign_sets_check1`: `CHECK (((systolic_mmhg IS NULL) OR (systolic_mmhg > diastolic_mmhg)))`.
- `vital_sign_sets_check2`: `CHECK ((num_nonnulls(systolic_mmhg, pulse_bpm, respiratory_rate, temperature_c, spo2_percent, weight_kg, height_cm) > 0))`.
- `vital_sign_sets_diastolic_mmhg_check`: `CHECK (((diastolic_mmhg >= 10) AND (diastolic_mmhg <= 250)))`.
- `vital_sign_sets_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `vital_sign_sets_height_cm_check`: `CHECK (((height_cm >= (10)::numeric) AND (height_cm <= (280)::numeric)))`.
- `vital_sign_sets_pkey`: `PRIMARY KEY (id)`.
- `vital_sign_sets_pulse_bpm_check`: `CHECK (((pulse_bpm >= 10) AND (pulse_bpm <= 300)))`.
- `vital_sign_sets_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES hospital.profiles(id)`.
- `vital_sign_sets_respiratory_rate_check`: `CHECK (((respiratory_rate >= 1) AND (respiratory_rate <= 100)))`.
- `vital_sign_sets_spo2_percent_check`: `CHECK (((spo2_percent >= (0)::numeric) AND (spo2_percent <= (100)::numeric)))`.
- `vital_sign_sets_systolic_mmhg_check`: `CHECK (((systolic_mmhg >= 20) AND (systolic_mmhg <= 350)))`.
- `vital_sign_sets_temperature_c_check`: `CHECK (((temperature_c >= (20)::numeric) AND (temperature_c <= (50)::numeric)))`.
- `vital_sign_sets_weight_kg_check`: `CHECK (((weight_kg >= 0.1) AND (weight_kg <= (700)::numeric)))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_encounter(encounter_id, 'vitals.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'clinical.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_encounter(encounter_id, 'vitals.write'::text)`; `WITH CHECK private.can_encounter(encounter_id, 'vitals.write'::text)`.

### hospital.clinical_notes

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| author_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| kind | text | NO |  | — |
| subjective | text | YES |  | — |
| objective | text | YES |  | — |
| assessment | text | YES |  | — |
| plan | text | YES |  | — |
| status | text | NO |  | 'draft'::text |
| signed_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `clinical_notes_author_id_fkey`: `FOREIGN KEY (author_id) REFERENCES hospital.profiles(id)`.
- `clinical_notes_check`: `CHECK (((status <> 'signed'::text) OR (signed_at IS NOT NULL)))`.
- `clinical_notes_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `clinical_notes_kind_check`: `CHECK ((kind = ANY (ARRAY['admission'::text, 'consultation'::text, 'progress'::text, 'discharge'::text, 'nursing'::text])))`.
- `clinical_notes_pkey`: `PRIMARY KEY (id)`.
- `clinical_notes_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'signed'::text, 'entered_in_error'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND (((kind = 'nursing'::text) AND private.can_encounter(encounter_id, 'vitals.write'::text)) OR ((kind <> 'nursing'::text) AND private.can_encounter(encounter_id, 'clinical.write'::text))))`.
- **SELECT** → ['hospital_api']; `USING (private.can_encounter(encounter_id, 'clinical.read'::text) AND ((NOT private.own_patient(private.encounter_patient(encounter_id))) OR (status = 'signed'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((author_id = ( SELECT auth.uid() AS uid)) AND (((kind = 'nursing'::text) AND private.can_encounter(encounter_id, 'vitals.write'::text)) OR ((kind <> 'nursing'::text) AND private.can_encounter(encounter_id, 'clinical.write'::text))))`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND (((kind = 'nursing'::text) AND private.can_encounter(encounter_id, 'vitals.write'::text)) OR ((kind <> 'nursing'::text) AND private.can_encounter(encounter_id, 'clinical.write'::text))))`.

### hospital.note_addenda

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| note_id | uuid | NO |  FK → hospital.clinical_notes.id | — |
| author_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| body | text | NO |  | — |
| signed_at | timestamp with time zone | NO |  | now() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `note_addenda_author_id_fkey`: `FOREIGN KEY (author_id) REFERENCES hospital.profiles(id)`.
- `note_addenda_body_check`: `CHECK ((length(TRIM(BOTH FROM body)) > 0))`.
- `note_addenda_note_id_fkey`: `FOREIGN KEY (note_id) REFERENCES hospital.clinical_notes(id)`.
- `note_addenda_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.clinical_notes n
  WHERE ((n.id = note_addenda.note_id) AND (n.author_id = ( SELECT auth.uid() AS uid)) AND (n.status = 'signed'::text)))))`.
- **SELECT** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.clinical_notes n
  WHERE (n.id = note_addenda.note_id)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((author_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.clinical_notes n
  WHERE ((n.id = note_addenda.note_id) AND (n.author_id = ( SELECT auth.uid() AS uid)) AND (n.status = 'signed'::text)))))`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.clinical_notes n
  WHERE ((n.id = note_addenda.note_id) AND (n.author_id = ( SELECT auth.uid() AS uid)) AND (n.status = 'signed'::text)))))`.

### hospital.units

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `units_code_key`: `UNIQUE (code)`.
- `units_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.medications

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| generic_name | text | NO |  | — |
| strength | numeric(12,4) | NO |  | — |
| strength_unit_id | uuid | NO |  FK → hospital.units.id | — |
| dosage_form | text | NO |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `medications_code_key`: `UNIQUE (code)`.
- `medications_generic_name_strength_strength_unit_id_dosage_f_key`: `UNIQUE (generic_name, strength, strength_unit_id, dosage_form)`.
- `medications_pkey`: `PRIMARY KEY (id)`.
- `medications_strength_check`: `CHECK ((strength > (0)::numeric))`.
- `medications_strength_unit_id_fkey`: `FOREIGN KEY (strength_unit_id) REFERENCES hospital.units(id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.administration_routes

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `administration_routes_code_key`: `UNIQUE (code)`.
- `administration_routes_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.prescriptions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| prescriber_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| status | text | NO |  | 'draft'::text |
| issued_at | timestamp with time zone | YES |  | — |
| cancelled_at | timestamp with time zone | YES |  | — |
| cancellation_reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `prescriptions_check`: `CHECK (((status <> 'issued'::text) OR (issued_at IS NOT NULL)))`.
- `prescriptions_check1`: `CHECK (((status <> 'cancelled'::text) OR ((cancelled_at IS NOT NULL) AND (length(TRIM(BOTH FROM cancellation_reason)) > 0))))`.
- `prescriptions_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `prescriptions_pkey`: `PRIMARY KEY (id)`.
- `prescriptions_prescriber_id_fkey`: `FOREIGN KEY (prescriber_id) REFERENCES hospital.profiles(id)`.
- `prescriptions_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'issued'::text, 'cancelled'::text, 'completed'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((prescriber_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.
- **SELECT** → ['hospital_api']; `USING (private.can_encounter(encounter_id, 'clinical.read'::text) AND ((NOT private.own_patient(private.encounter_patient(encounter_id))) OR (status <> 'draft'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((prescriber_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`; `WITH CHECK ((prescriber_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.

### hospital.prescription_items

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| prescription_id | uuid | NO |  FK → hospital.prescriptions.id | — |
| medication_id | uuid | NO |  FK → hospital.medications.id | — |
| dose | numeric(12,4) | NO |  | — |
| dose_unit_id | uuid | NO |  FK → hospital.units.id | — |
| route_id | uuid | NO |  FK → hospital.administration_routes.id | — |
| interval_hours | numeric(7,2) | YES |  | — |
| instructions | text | NO |  | — |
| starts_on | date | NO |  | — |
| ends_on | date | YES |  | — |
| quantity | numeric(12,3) | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `prescription_items_check`: `CHECK (((ends_on IS NULL) OR (ends_on >= starts_on)))`.
- `prescription_items_dose_check`: `CHECK ((dose > (0)::numeric))`.
- `prescription_items_dose_unit_id_fkey`: `FOREIGN KEY (dose_unit_id) REFERENCES hospital.units(id)`.
- `prescription_items_interval_hours_check`: `CHECK ((interval_hours > (0)::numeric))`.
- `prescription_items_medication_id_fkey`: `FOREIGN KEY (medication_id) REFERENCES hospital.medications(id)`.
- `prescription_items_pkey`: `PRIMARY KEY (id)`.
- `prescription_items_prescription_id_fkey`: `FOREIGN KEY (prescription_id) REFERENCES hospital.prescriptions(id)`.
- `prescription_items_quantity_check`: `CHECK ((quantity > (0)::numeric))`.
- `prescription_items_route_id_fkey`: `FOREIGN KEY (route_id) REFERENCES hospital.administration_routes(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_prescription(prescription_id, true)`.
- **SELECT** → ['hospital_api']; `USING private.can_prescription(prescription_id, false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_prescription(prescription_id, true)`; `WITH CHECK private.can_prescription(prescription_id, true)`.

### hospital.care_orders

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| author_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| instruction | text | NO |  | — |
| kind | text | NO |  | — |
| due_at | timestamp with time zone | YES |  | — |
| status | text | NO |  | 'draft'::text |
| authorized_at | timestamp with time zone | YES |  | — |
| started_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `care_orders_author_id_fkey`: `FOREIGN KEY (author_id) REFERENCES hospital.profiles(id)`.
- `care_orders_check`: `CHECK (((status <> ALL (ARRAY['authorized'::text, 'in_progress'::text, 'completed'::text])) OR (authorized_at IS NOT NULL)))`.
- `care_orders_check1`: `CHECK (((status <> 'in_progress'::text) OR (started_at IS NOT NULL)))`.
- `care_orders_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `care_orders_instruction_check`: `CHECK ((length(TRIM(BOTH FROM instruction)) > 0))`.
- `care_orders_kind_check`: `CHECK ((kind = ANY (ARRAY['nursing'::text, 'procedure'::text, 'monitoring'::text])))`.
- `care_orders_pkey`: `PRIMARY KEY (id)`.
- `care_orders_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'authorized'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.
- **SELECT** → ['hospital_api']; `USING (private.can_encounter(encounter_id, 'clinical.read'::text) AND ((NOT private.own_patient(private.encounter_patient(encounter_id))) OR (status <> 'draft'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((author_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`; `WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.

### hospital.care_order_executions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| care_order_id | uuid | NO |  FK → hospital.care_orders.id | — |
| performed_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| performed_at | timestamp with time zone | NO |  | now() |
| outcome | text | NO |  | — |
| note | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `care_order_executions_care_order_id_fkey`: `FOREIGN KEY (care_order_id) REFERENCES hospital.care_orders(id)`.
- `care_order_executions_outcome_check`: `CHECK ((outcome = ANY (ARRAY['done'::text, 'not_done'::text, 'refused'::text])))`.
- `care_order_executions_performed_by_fkey`: `FOREIGN KEY (performed_by) REFERENCES hospital.profiles(id)`.
- `care_order_executions_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((performed_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.care_orders o
  WHERE ((o.id = care_order_executions.care_order_id) AND (o.status = ANY (ARRAY['authorized'::text, 'in_progress'::text])) AND private.can_encounter(o.encounter_id, 'vitals.write'::text)))))`.
- **SELECT** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.care_orders o
  WHERE (o.id = care_order_executions.care_order_id)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((performed_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.care_orders o
  WHERE ((o.id = care_order_executions.care_order_id) AND (o.status = ANY (ARRAY['authorized'::text, 'in_progress'::text])) AND private.can_encounter(o.encounter_id, 'vitals.write'::text)))))`; `WITH CHECK ((performed_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM hospital.care_orders o
  WHERE ((o.id = care_order_executions.care_order_id) AND (o.status = ANY (ARRAY['authorized'::text, 'in_progress'::text])) AND private.can_encounter(o.encounter_id, 'vitals.write'::text)))))`.

## Diagnóstico y documentos

### hospital.test_definitions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| kind | text | NO |  | — |
| specialty_id | uuid | YES |  FK → hospital.specialties.id | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `test_definitions_code_key`: `UNIQUE (code)`.
- `test_definitions_kind_check`: `CHECK ((kind = ANY (ARRAY['laboratory'::text, 'imaging'::text])))`.
- `test_definitions_pkey`: `PRIMARY KEY (id)`.
- `test_definitions_specialty_id_fkey`: `FOREIGN KEY (specialty_id) REFERENCES hospital.specialties(id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.analytes

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `analytes_code_key`: `UNIQUE (code)`.
- `analytes_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.test_analytes

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| test_id | uuid | NO |  FK → hospital.test_definitions.id | — |
| analyte_id | uuid | NO |  FK → hospital.analytes.id | — |
| display_order | smallint | NO |  | 1 |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `test_analytes_analyte_id_fkey`: `FOREIGN KEY (analyte_id) REFERENCES hospital.analytes(id)`.
- `test_analytes_pkey`: `PRIMARY KEY (id)`.
- `test_analytes_test_id_analyte_id_key`: `UNIQUE (test_id, analyte_id)`.
- `test_analytes_test_id_fkey`: `FOREIGN KEY (test_id) REFERENCES hospital.test_definitions(id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.lab_reference_ranges

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| analyte_id | uuid | NO |  FK → hospital.analytes.id | — |
| unit_id | uuid | NO |  FK → hospital.units.id | — |
| sex | text | YES |  | — |
| age_min_days | integer | NO |  | 0 |
| age_max_days | integer | YES |  | — |
| lower_value | numeric(18,6) | YES |  | — |
| upper_value | numeric(18,6) | YES |  | — |
| interpretation | text | YES |  | — |
| valid_from | date | NO |  | — |
| valid_to | date | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `lab_reference_ranges_age_min_days_check`: `CHECK ((age_min_days >= 0))`.
- `lab_reference_ranges_analyte_id_fkey`: `FOREIGN KEY (analyte_id) REFERENCES hospital.analytes(id)`.
- `lab_reference_ranges_check`: `CHECK ((age_max_days >= age_min_days))`.
- `lab_reference_ranges_check1`: `CHECK (((lower_value IS NULL) OR (upper_value IS NULL) OR (lower_value <= upper_value)))`.
- `lab_reference_ranges_check2`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`.
- `lab_reference_ranges_pkey`: `PRIMARY KEY (id)`.
- `lab_reference_ranges_sex_check`: `CHECK ((sex = ANY (ARRAY['female'::text, 'male'::text, 'intersex'::text, 'unknown'::text])))`.
- `lab_reference_ranges_unit_id_fkey`: `FOREIGN KEY (unit_id) REFERENCES hospital.units(id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.diagnostic_orders

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| encounter_id | uuid | NO |  FK → hospital.encounters.id | — |
| order_number | text | NO |  UNIQUE | — |
| ordered_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| priority | text | NO |  | 'normal'::text |
| clinical_question | text | YES |  | — |
| status | text | NO |  | 'draft'::text |
| ordered_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `diagnostic_orders_encounter_id_fkey`: `FOREIGN KEY (encounter_id) REFERENCES hospital.encounters(id)`.
- `diagnostic_orders_order_number_key`: `UNIQUE (order_number)`.
- `diagnostic_orders_ordered_by_fkey`: `FOREIGN KEY (ordered_by) REFERENCES hospital.profiles(id)`.
- `diagnostic_orders_pkey`: `PRIMARY KEY (id)`.
- `diagnostic_orders_priority_check`: `CHECK ((priority = ANY (ARRAY['normal'::text, 'urgent'::text, 'stat'::text])))`.
- `diagnostic_orders_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'ordered'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((ordered_by = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.
- **SELECT** → ['hospital_api']; `USING ((private.can_encounter(encounter_id, 'clinical.read'::text) OR private.has_permission(private.encounter_facility(encounter_id), 'lab.process'::text)) AND ((NOT private.own_patient(private.encounter_patient(encounter_id))) OR (status <> 'draft'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((ordered_by = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`; `WITH CHECK ((ordered_by = ( SELECT auth.uid() AS uid)) AND private.can_encounter(encounter_id, 'clinical.write'::text))`.

### hospital.diagnostic_order_items

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| order_id | uuid | NO |  FK → hospital.diagnostic_orders.id | — |
| test_id | uuid | NO |  FK → hospital.test_definitions.id | — |
| status | text | NO |  | 'pending'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `diagnostic_order_items_order_id_fkey`: `FOREIGN KEY (order_id) REFERENCES hospital.diagnostic_orders(id)`.
- `diagnostic_order_items_order_id_test_id_key`: `UNIQUE (order_id, test_id)`.
- `diagnostic_order_items_pkey`: `PRIMARY KEY (id)`.
- `diagnostic_order_items_status_check`: `CHECK ((status = ANY (ARRAY['pending'::text, 'collected'::text, 'processing'::text, 'validated'::text, 'cancelled'::text])))`.
- `diagnostic_order_items_test_id_fkey`: `FOREIGN KEY (test_id) REFERENCES hospital.test_definitions(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_lab_order(order_id, true)`.
- **SELECT** → ['hospital_api']; `USING private.can_lab_order(order_id, false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_lab_order(order_id, true)`; `WITH CHECK private.can_lab_order(order_id, true)`.

### hospital.specimens

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| barcode | text | NO |  UNIQUE | — |
| specimen_type | text | NO |  | — |
| collected_at | timestamp with time zone | YES |  | — |
| collected_by | uuid | YES |  FK → hospital.profiles.id | — |
| received_at | timestamp with time zone | YES |  | — |
| rejection_reason | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `specimens_barcode_key`: `UNIQUE (barcode)`.
- `specimens_check`: `CHECK (((received_at IS NULL) OR ((collected_at IS NOT NULL) AND (received_at >= collected_at))))`.
- `specimens_collected_by_fkey`: `FOREIGN KEY (collected_by) REFERENCES hospital.profiles(id)`.
- `specimens_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'lab.process'::text)`.
- **SELECT** → ['hospital_api']; `USING (private.can_specimen(id) OR (collected_by = ( SELECT auth.uid() AS uid)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'lab.process'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'lab.process'::text)`.

### hospital.specimen_items

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| specimen_id | uuid | NO |  FK → hospital.specimens.id | — |
| order_item_id | uuid | NO |  FK → hospital.diagnostic_order_items.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `specimen_items_order_item_id_fkey`: `FOREIGN KEY (order_item_id) REFERENCES hospital.diagnostic_order_items(id)`.
- `specimen_items_pkey`: `PRIMARY KEY (id)`.
- `specimen_items_specimen_id_fkey`: `FOREIGN KEY (specimen_id) REFERENCES hospital.specimens(id)`.
- `specimen_items_specimen_id_order_item_id_key`: `UNIQUE (specimen_id, order_item_id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_lab_order(private.item_order(order_item_id), true)`.
- **SELECT** → ['hospital_api']; `USING private.can_lab_order(private.item_order(order_item_id), false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_lab_order(private.item_order(order_item_id), true)`; `WITH CHECK private.can_lab_order(private.item_order(order_item_id), true)`.

### hospital.documents

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| object_path | text | NO |  UNIQUE | — |
| mime_type | text | NO |  | — |
| byte_size | bigint | NO |  | — |
| sha256 | text | NO |  | — |
| state | text | NO |  | 'quarantined'::text |
| uploaded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `documents_byte_size_check`: `CHECK (((byte_size > 0) AND (byte_size <= 26214400)))`.
- `documents_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `documents_mime_type_check`: `CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'::text])))`.
- `documents_object_path_key`: `UNIQUE (object_path)`.
- `documents_pkey`: `PRIMARY KEY (id)`.
- `documents_sha256_check`: `CHECK ((sha256 ~ '^[a-f0-9]{64}$'::text))`.
- `documents_state_check`: `CHECK ((state = ANY (ARRAY['quarantined'::text, 'available'::text, 'rejected'::text])))`.
- `documents_uploaded_by_fkey`: `FOREIGN KEY (uploaded_by) REFERENCES hospital.profiles(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((uploaded_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'documents.write'::text))`.
- **SELECT** → ['hospital_api']; `USING private.can_document(id)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((uploaded_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'documents.write'::text))`; `WITH CHECK ((uploaded_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'documents.write'::text))`.

### hospital.patient_documents

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| document_id | uuid | NO |  FK → hospital.documents.id UNIQUE | — |
| title | text | NO |  | — |
| released_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `patient_documents_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES hospital.documents(id)`.
- `patient_documents_document_id_key`: `UNIQUE (document_id)`.
- `patient_documents_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `patient_documents_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.
- **SELECT** → ['hospital_api']; `USING (private.can_patient(patient_id, 'clinical.read'::text) AND ((NOT private.own_patient(patient_id)) OR (released_at IS NOT NULL)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_patient(patient_id, 'clinical.write'::text)`; `WITH CHECK private.can_patient(patient_id, 'clinical.write'::text)`.

### hospital.lab_results

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| order_item_id | uuid | NO |  FK → hospital.diagnostic_order_items.id | — |
| version | integer | NO |  | 1 |
| supersedes_id | uuid | YES |  FK → hospital.lab_results.id UNIQUE | — |
| status | text | NO |  | 'draft'::text |
| narrative | text | YES |  | — |
| document_id | uuid | YES |  FK → hospital.documents.id | — |
| recorded_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| validated_by | uuid | YES |  FK → hospital.profiles.id | — |
| validated_at | timestamp with time zone | YES |  | — |
| released_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `lab_results_check`: `CHECK (((status <> ALL (ARRAY['validated'::text, 'released'::text])) OR ((validated_by IS NOT NULL) AND (validated_at IS NOT NULL))))`.
- `lab_results_check1`: `CHECK (((status <> 'released'::text) OR (released_at IS NOT NULL)))`.
- `lab_results_check2`: `CHECK (((released_at IS NULL) OR (released_at >= validated_at)))`.
- `lab_results_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES hospital.documents(id)`.
- `lab_results_order_item_id_fkey`: `FOREIGN KEY (order_item_id) REFERENCES hospital.diagnostic_order_items(id)`.
- `lab_results_order_item_id_version_key`: `UNIQUE (order_item_id, version)`.
- `lab_results_pkey`: `PRIMARY KEY (id)`.
- `lab_results_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES hospital.profiles(id)`.
- `lab_results_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'validated'::text, 'released'::text, 'entered_in_error'::text])))`.
- `lab_results_supersedes_id_fkey`: `FOREIGN KEY (supersedes_id) REFERENCES hospital.lab_results(id)`.
- `lab_results_supersedes_id_key`: `UNIQUE (supersedes_id)`.
- `lab_results_validated_by_fkey`: `FOREIGN KEY (validated_by) REFERENCES hospital.profiles(id)`.
- `lab_results_version_check`: `CHECK ((version > 0))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.encounter_facility(private.order_encounter(private.item_order(order_item_id))), 'lab.process'::text)`.
- **SELECT** → ['hospital_api']; `USING (private.can_lab_order(private.item_order(order_item_id), false) AND ((NOT private.own_patient(private.encounter_patient(private.order_encounter(private.item_order(order_item_id))))) OR (status = 'released'::text)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.encounter_facility(private.order_encounter(private.item_order(order_item_id))), 'lab.process'::text)`; `WITH CHECK private.has_permission(private.encounter_facility(private.order_encounter(private.item_order(order_item_id))), 'lab.process'::text)`.

### hospital.lab_result_values

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| result_id | uuid | NO |  FK → hospital.lab_results.id | — |
| analyte_id | uuid | NO |  FK → hospital.analytes.id | — |
| value_numeric | numeric(18,6) | YES |  | — |
| value_text | text | YES |  | — |
| unit_id | uuid | YES |  FK → hospital.units.id | — |
| reference_range_id | uuid | YES |  FK → hospital.lab_reference_ranges.id | — |
| flag | text | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `lab_result_values_analyte_id_fkey`: `FOREIGN KEY (analyte_id) REFERENCES hospital.analytes(id)`.
- `lab_result_values_check`: `CHECK ((num_nonnulls(value_numeric, value_text) = 1))`.
- `lab_result_values_check1`: `CHECK (((value_numeric IS NULL) OR (unit_id IS NOT NULL)))`.
- `lab_result_values_flag_check`: `CHECK ((flag = ANY (ARRAY['normal'::text, 'low'::text, 'high'::text, 'critical'::text, 'indeterminate'::text])))`.
- `lab_result_values_pkey`: `PRIMARY KEY (id)`.
- `lab_result_values_reference_range_id_fkey`: `FOREIGN KEY (reference_range_id) REFERENCES hospital.lab_reference_ranges(id)`.
- `lab_result_values_result_id_analyte_id_key`: `UNIQUE (result_id, analyte_id)`.
- `lab_result_values_result_id_fkey`: `FOREIGN KEY (result_id) REFERENCES hospital.lab_results(id)`.
- `lab_result_values_unit_id_fkey`: `FOREIGN KEY (unit_id) REFERENCES hospital.units(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.can_lab_result(result_id, true)`.
- **SELECT** → ['hospital_api']; `USING private.can_lab_result(result_id, false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.can_lab_result(result_id, true)`; `WITH CHECK private.can_lab_result(result_id, true)`.

## Personal y recursos

### hospital.shift_templates

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| starts_at | time without time zone | NO |  | — |
| ends_at | time without time zone | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `shift_templates_check`: `CHECK ((starts_at <> ends_at))`.
- `shift_templates_code_key`: `UNIQUE (code)`.
- `shift_templates_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.staff_shifts

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| period | tstzrange | NO |  | — |
| status | text | NO |  | 'pending'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `staff_shifts_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `staff_shifts_period_check`: `CHECK (((NOT isempty(period)) AND (lower(period) IS NOT NULL) AND (upper(period) IS NOT NULL) AND lower_inc(period) AND (NOT upper_inc(period))))`.
- `staff_shifts_pkey`: `PRIMARY KEY (id)`.
- `staff_shifts_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.
- `staff_shifts_staff_id_period_excl`: `EXCLUDE USING gist (staff_id WITH =, period WITH &&) WHERE ((status <> 'cancelled'::text))`.
- `staff_shifts_status_check`: `CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING ((staff_id = private.staff_id()) OR private.has_permission(private.department_facility(department_id), 'shifts.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`.

### hospital.shift_requests

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| shift_id | uuid | YES |  FK → hospital.staff_shifts.id | — |
| kind | text | NO |  | — |
| requested_period | tstzrange | NO |  | — |
| reason | text | NO |  | — |
| status | text | NO |  | 'pending'::text |
| decided_by | uuid | YES |  FK → hospital.profiles.id | — |
| decided_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `shift_requests_check`: `CHECK (((status <> ALL (ARRAY['approved'::text, 'rejected'::text])) OR ((decided_by IS NOT NULL) AND (decided_at IS NOT NULL))))`.
- `shift_requests_decided_by_fkey`: `FOREIGN KEY (decided_by) REFERENCES hospital.profiles(id)`.
- `shift_requests_kind_check`: `CHECK ((kind = ANY (ARRAY['change'::text, 'time_off'::text])))`.
- `shift_requests_pkey`: `PRIMARY KEY (id)`.
- `shift_requests_requested_period_check`: `CHECK (((NOT isempty(requested_period)) AND (lower(requested_period) IS NOT NULL) AND (upper(requested_period) IS NOT NULL)))`.
- `shift_requests_shift_id_fkey`: `FOREIGN KEY (shift_id) REFERENCES hospital.staff_shifts(id)`.
- `shift_requests_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.
- `shift_requests_status_check`: `CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((staff_id = private.staff_id()) AND private.session_active(true))`.
- **SELECT** → ['hospital_api']; `USING ((staff_id = private.staff_id()) OR private.has_permission(NULL::uuid, 'shifts.manage'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((staff_id = private.staff_id()) AND private.session_active(true))`; `WITH CHECK ((staff_id = private.staff_id()) AND private.session_active(true))`.

### hospital.coverage_requirements

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| role_id | uuid | NO |  FK → hospital.roles.id | — |
| weekday | smallint | NO |  | — |
| starts_at | time without time zone | NO |  | — |
| ends_at | time without time zone | NO |  | — |
| required_staff | smallint | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `coverage_requirements_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `coverage_requirements_department_id_role_id_weekday_starts__key`: `UNIQUE (department_id, role_id, weekday, starts_at)`.
- `coverage_requirements_pkey`: `PRIMARY KEY (id)`.
- `coverage_requirements_required_staff_check`: `CHECK ((required_staff > 0))`.
- `coverage_requirements_role_id_fkey`: `FOREIGN KEY (role_id) REFERENCES hospital.roles(id)`.
- `coverage_requirements_weekday_check`: `CHECK (((weekday >= 1) AND (weekday <= 7)))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'shifts.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'shifts.manage'::text)`.

### hospital.product_categories

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `product_categories_code_key`: `UNIQUE (code)`.
- `product_categories_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.products

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| sku | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| category_id | uuid | NO |  FK → hospital.product_categories.id | — |
| stock_unit_id | uuid | NO |  FK → hospital.units.id | — |
| medication_id | uuid | YES |  FK → hospital.medications.id UNIQUE | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `products_category_id_fkey`: `FOREIGN KEY (category_id) REFERENCES hospital.product_categories(id)`.
- `products_medication_id_fkey`: `FOREIGN KEY (medication_id) REFERENCES hospital.medications(id)`.
- `products_medication_id_key`: `UNIQUE (medication_id)`.
- `products_pkey`: `PRIMARY KEY (id)`.
- `products_sku_key`: `UNIQUE (sku)`.
- `products_stock_unit_id_fkey`: `FOREIGN KEY (stock_unit_id) REFERENCES hospital.units(id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'catalogs.write'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'catalogs.write'::text)`.

### hospital.stock_locations

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| department_id | uuid | NO |  FK → hospital.departments.id | — |
| code | text | NO |  | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `stock_locations_department_id_code_key`: `UNIQUE (department_id, code)`.
- `stock_locations_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `stock_locations_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'stock.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'stock.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.department_facility(department_id), 'stock.manage'::text)`; `WITH CHECK private.has_permission(private.department_facility(department_id), 'stock.manage'::text)`.

### hospital.stock_thresholds

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| product_id | uuid | NO |  FK → hospital.products.id | — |
| location_id | uuid | NO |  FK → hospital.stock_locations.id | — |
| minimum_quantity | numeric(14,3) | NO |  | — |
| critical_quantity | numeric(14,3) | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `stock_thresholds_check`: `CHECK (((critical_quantity >= (0)::numeric) AND (critical_quantity <= minimum_quantity)))`.
- `stock_thresholds_location_id_fkey`: `FOREIGN KEY (location_id) REFERENCES hospital.stock_locations(id)`.
- `stock_thresholds_minimum_quantity_check`: `CHECK ((minimum_quantity >= (0)::numeric))`.
- `stock_thresholds_pkey`: `PRIMARY KEY (id)`.
- `stock_thresholds_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES hospital.products(id)`.
- `stock_thresholds_product_id_location_id_key`: `UNIQUE (product_id, location_id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.location_facility(location_id), 'stock.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`; `WITH CHECK private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`.

### hospital.stock_lots

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| product_id | uuid | NO |  FK → hospital.products.id | — |
| lot_number | text | NO |  | — |
| expires_on | date | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `stock_lots_pkey`: `PRIMARY KEY (id)`.
- `stock_lots_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES hospital.products(id)`.
- `stock_lots_product_id_lot_number_key`: `UNIQUE (product_id, lot_number)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(NULL::uuid, 'stock.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'stock.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(NULL::uuid, 'stock.manage'::text)`; `WITH CHECK private.has_permission(NULL::uuid, 'stock.manage'::text)`.

### hospital.stock_movements

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| lot_id | uuid | NO |  FK → hospital.stock_lots.id | — |
| location_id | uuid | NO |  FK → hospital.stock_locations.id | — |
| quantity_delta | numeric(14,3) | NO |  | — |
| kind | text | NO |  | — |
| reason | text | NO |  | — |
| occurred_at | timestamp with time zone | NO |  | now() |
| actor_id | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| reversal_of | uuid | YES |  FK → hospital.stock_movements.id UNIQUE | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `stock_movements_actor_id_fkey`: `FOREIGN KEY (actor_id) REFERENCES hospital.profiles(id)`.
- `stock_movements_check`: `CHECK (((kind <> ALL (ARRAY['receipt'::text, 'transfer_in'::text])) OR (quantity_delta > (0)::numeric)))`.
- `stock_movements_check1`: `CHECK (((kind <> ALL (ARRAY['issue'::text, 'transfer_out'::text])) OR (quantity_delta < (0)::numeric)))`.
- `stock_movements_kind_check`: `CHECK ((kind = ANY (ARRAY['receipt'::text, 'issue'::text, 'adjustment'::text, 'transfer_in'::text, 'transfer_out'::text])))`.
- `stock_movements_location_id_fkey`: `FOREIGN KEY (location_id) REFERENCES hospital.stock_locations(id)`.
- `stock_movements_lot_id_fkey`: `FOREIGN KEY (lot_id) REFERENCES hospital.stock_lots(id)`.
- `stock_movements_pkey`: `PRIMARY KEY (id)`.
- `stock_movements_quantity_delta_check`: `CHECK ((quantity_delta <> (0)::numeric))`.
- `stock_movements_reversal_of_fkey`: `FOREIGN KEY (reversal_of) REFERENCES hospital.stock_movements(id)`.
- `stock_movements_reversal_of_key`: `UNIQUE (reversal_of)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (private.has_permission(private.location_facility(location_id), 'stock.manage'::text) AND (actor_id = ( SELECT auth.uid() AS uid)))`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.location_facility(location_id), 'stock.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (private.has_permission(private.location_facility(location_id), 'stock.manage'::text) AND (actor_id = ( SELECT auth.uid() AS uid)))`; `WITH CHECK (private.has_permission(private.location_facility(location_id), 'stock.manage'::text) AND (actor_id = ( SELECT auth.uid() AS uid)))`.

### hospital.equipment_assets

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| product_id | uuid | NO |  FK → hospital.products.id | — |
| serial_number | text | NO |  UNIQUE | — |
| location_id | uuid | NO |  FK → hospital.stock_locations.id | — |
| status | text | NO |  | 'available'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `equipment_assets_location_id_fkey`: `FOREIGN KEY (location_id) REFERENCES hospital.stock_locations(id)`.
- `equipment_assets_pkey`: `PRIMARY KEY (id)`.
- `equipment_assets_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES hospital.products(id)`.
- `equipment_assets_serial_number_key`: `UNIQUE (serial_number)`.
- `equipment_assets_status_check`: `CHECK ((status = ANY (ARRAY['available'::text, 'in_use'::text, 'maintenance'::text, 'retired'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.location_facility(location_id), 'stock.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`; `WITH CHECK private.has_permission(private.location_facility(location_id), 'stock.manage'::text)`.

### hospital.equipment_maintenance

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| asset_id | uuid | NO |  FK → hospital.equipment_assets.id | — |
| started_at | timestamp with time zone | NO |  | — |
| ended_at | timestamp with time zone | YES |  | — |
| description | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `equipment_maintenance_asset_id_fkey`: `FOREIGN KEY (asset_id) REFERENCES hospital.equipment_assets(id)`.
- `equipment_maintenance_check`: `CHECK (((ended_at IS NULL) OR (ended_at >= started_at)))`.
- `equipment_maintenance_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.equipment_assets a
  WHERE ((a.id = equipment_maintenance.asset_id) AND private.has_permission(private.location_facility(a.location_id), 'stock.manage'::text))))`.
- **SELECT** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.equipment_assets a
  WHERE (a.id = equipment_maintenance.asset_id)))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING (EXISTS ( SELECT 1
   FROM hospital.equipment_assets a
  WHERE ((a.id = equipment_maintenance.asset_id) AND private.has_permission(private.location_facility(a.location_id), 'stock.manage'::text))))`; `WITH CHECK (EXISTS ( SELECT 1
   FROM hospital.equipment_assets a
  WHERE ((a.id = equipment_maintenance.asset_id) AND private.has_permission(private.location_facility(a.location_id), 'stock.manage'::text))))`.

## Ambulancia y servicios

### hospital.ambulances

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| facility_id | uuid | NO |  FK → hospital.facilities.id UNIQUE | — |
| code | text | NO |  UNIQUE | — |
| license_plate | text | YES |  UNIQUE | — |
| ambulance_type | text | NO |  | — |
| equipment_description | text | YES |  | — |
| active | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `ambulances_code_key`: `UNIQUE (code)`.
- `ambulances_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `ambulances_facility_id_key`: `UNIQUE (facility_id)`.
- `ambulances_license_plate_key`: `UNIQUE (license_plate)`.
- `ambulances_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(facility_id, 'fleet.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(facility_id, 'fleet.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(facility_id, 'fleet.manage'::text)`; `WITH CHECK private.has_permission(facility_id, 'fleet.manage'::text)`.

### hospital.ambulance_activities

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| ambulance_id | uuid | NO |  FK → hospital.ambulances.id | — |
| kind | text | NO |  | — |
| period | tstzrange | NO |  | — |
| status | text | NO |  | 'active'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `ambulance_activities_ambulance_id_fkey`: `FOREIGN KEY (ambulance_id) REFERENCES hospital.ambulances(id)`.
- `ambulance_activities_ambulance_id_period_excl`: `EXCLUDE USING gist (ambulance_id WITH =, period WITH &&) WHERE ((status <> 'cancelled'::text))`.
- `ambulance_activities_check`: `CHECK (((status <> 'completed'::text) OR (upper(period) IS NOT NULL)))`.
- `ambulance_activities_kind_check`: `CHECK ((kind = ANY (ARRAY['dispatch'::text, 'maintenance'::text])))`.
- `ambulance_activities_period_check`: `CHECK (((NOT isempty(period)) AND (lower(period) IS NOT NULL) AND lower_inc(period) AND (NOT upper_inc(period))))`.
- `ambulance_activities_pkey`: `PRIMARY KEY (id)`.
- `ambulance_activities_status_check`: `CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'completed'::text, 'cancelled'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.ambulance_facility(ambulance_id), 'fleet.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.ambulance_facility(ambulance_id), 'fleet.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.ambulance_facility(ambulance_id), 'fleet.manage'::text)`; `WITH CHECK private.has_permission(private.ambulance_facility(ambulance_id), 'fleet.manage'::text)`.

### hospital.ambulance_dispatches

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| activity_id | uuid | NO |  FK → hospital.ambulance_activities.id UNIQUE | — |
| dispatch_number | text | NO |  UNIQUE | — |
| service_type | text | NO |  | — |
| origin | text | NO |  | — |
| destination | text | NO |  | — |
| requested_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `ambulance_dispatches_activity_id_fkey`: `FOREIGN KEY (activity_id) REFERENCES hospital.ambulance_activities(id)`.
- `ambulance_dispatches_activity_id_key`: `UNIQUE (activity_id)`.
- `ambulance_dispatches_dispatch_number_key`: `UNIQUE (dispatch_number)`.
- `ambulance_dispatches_pkey`: `PRIMARY KEY (id)`.
- `ambulance_dispatches_requested_by_fkey`: `FOREIGN KEY (requested_by) REFERENCES hospital.profiles(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.activity_facility(activity_id), 'fleet.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.activity_facility(activity_id), 'fleet.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.activity_facility(activity_id), 'fleet.manage'::text)`; `WITH CHECK private.has_permission(private.activity_facility(activity_id), 'fleet.manage'::text)`.

### hospital.dispatch_patients

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| dispatch_id | uuid | NO |  FK → hospital.ambulance_dispatches.id | — |
| patient_id | uuid | NO |  FK → hospital.patients.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `dispatch_patients_dispatch_id_fkey`: `FOREIGN KEY (dispatch_id) REFERENCES hospital.ambulance_dispatches(id)`.
- `dispatch_patients_dispatch_id_patient_id_key`: `UNIQUE (dispatch_id, patient_id)`.
- `dispatch_patients_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES hospital.patients(id)`.
- `dispatch_patients_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`; `WITH CHECK private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`.

### hospital.dispatch_crew

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| dispatch_id | uuid | NO |  FK → hospital.ambulance_dispatches.id | — |
| staff_id | uuid | NO |  FK → hospital.staff_members.id | — |
| duty | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `dispatch_crew_dispatch_id_fkey`: `FOREIGN KEY (dispatch_id) REFERENCES hospital.ambulance_dispatches(id)`.
- `dispatch_crew_dispatch_id_staff_id_key`: `UNIQUE (dispatch_id, staff_id)`.
- `dispatch_crew_pkey`: `PRIMARY KEY (id)`.
- `dispatch_crew_staff_id_fkey`: `FOREIGN KEY (staff_id) REFERENCES hospital.staff_members(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`.
- **SELECT** → ['hospital_api']; `USING private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.read'::text)`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`; `WITH CHECK private.has_permission(private.dispatch_facility(dispatch_id), 'fleet.manage'::text)`.

### hospital.notification_topics

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `notification_topics_code_key`: `UNIQUE (code)`.
- `notification_topics_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['authenticated']; `USING private.session_active(false)`; `WITH CHECK None`.
- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.notification_preferences

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| profile_id | uuid | NO |  FK → hospital.profiles.id | — |
| topic_id | uuid | NO |  FK → hospital.notification_topics.id | — |
| channel | text | NO |  | — |
| enabled | boolean | NO |  | true |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `notification_preferences_channel_check`: `CHECK ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'push'::text])))`.
- `notification_preferences_pkey`: `PRIMARY KEY (id)`.
- `notification_preferences_profile_id_fkey`: `FOREIGN KEY (profile_id) REFERENCES hospital.profiles(id)`.
- `notification_preferences_profile_id_topic_id_channel_key`: `UNIQUE (profile_id, topic_id, channel)`.
- `notification_preferences_topic_id_fkey`: `FOREIGN KEY (topic_id) REFERENCES hospital.notification_topics(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.
- **SELECT** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.

### hospital.notifications

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| recipient_id | uuid | NO |  FK → hospital.profiles.id | — |
| topic_id | uuid | NO |  FK → hospital.notification_topics.id | — |
| title | text | NO |  | — |
| body | text | NO |  | — |
| read_at | timestamp with time zone | YES |  | — |
| expires_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `notifications_pkey`: `PRIMARY KEY (id)`.
- `notifications_recipient_id_fkey`: `FOREIGN KEY (recipient_id) REFERENCES hospital.profiles(id)`.
- `notifications_topic_id_fkey`: `FOREIGN KEY (topic_id) REFERENCES hospital.notification_topics(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((recipient_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.
- **SELECT** → ['hospital_api']; `USING ((recipient_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((recipient_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK ((recipient_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.

### hospital.device_tokens

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| profile_id | uuid | NO |  FK → hospital.profiles.id | — |
| provider | text | NO |  | — |
| token | text | NO |  UNIQUE | — |
| revoked_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `device_tokens_pkey`: `PRIMARY KEY (id)`.
- `device_tokens_profile_id_fkey`: `FOREIGN KEY (profile_id) REFERENCES hospital.profiles(id)`.
- `device_tokens_provider_check`: `CHECK ((provider = ANY (ARRAY['apns'::text, 'fcm'::text])))`.
- `device_tokens_token_key`: `UNIQUE (token)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.
- **SELECT** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`; `WITH CHECK ((profile_id = ( SELECT auth.uid() AS uid)) AND private.session_active(false))`.

### hospital.public_information

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| category | text | NO |  | — |
| title | text | NO |  | — |
| body | text | NO |  | — |
| published_at | timestamp with time zone | YES |  | — |
| expires_at | timestamp with time zone | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `public_information_category_check`: `CHECK ((category = ANY (ARRAY['service'::text, 'schedule'::text, 'contact'::text, 'notice'::text])))`.
- `public_information_check`: `CHECK (((expires_at IS NULL) OR (published_at IS NULL) OR (expires_at > published_at)))`.
- `public_information_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `public_information_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['anon', 'authenticated']; `USING ((published_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now())))`; `WITH CHECK None`.
- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK private.has_permission(facility_id, 'settings.write'::text)`.
- **SELECT** → ['hospital_api']; `USING (((published_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now()))) OR private.has_permission(facility_id, 'settings.write'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING private.has_permission(facility_id, 'settings.write'::text)`; `WITH CHECK private.has_permission(facility_id, 'settings.write'::text)`.

### hospital.report_definitions

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| code | text | NO |  UNIQUE | — |
| name | text | NO |  | — |
| required_permission | text | NO |  FK → hospital.permissions.code | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `report_definitions_code_key`: `UNIQUE (code)`.
- `report_definitions_pkey`: `PRIMARY KEY (id)`.
- `report_definitions_required_permission_fkey`: `FOREIGN KEY (required_permission) REFERENCES hospital.permissions(code)`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING private.session_active(false)`; `WITH CHECK None`.

### hospital.report_jobs

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| report_id | uuid | NO |  FK → hospital.report_definitions.id | — |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| department_id | uuid | YES |  FK → hospital.departments.id | — |
| requested_by | uuid | NO |  FK → hospital.profiles.id | auth.uid() |
| from_at | timestamp with time zone | NO |  | — |
| to_at | timestamp with time zone | NO |  | — |
| format | text | NO |  | — |
| status | text | NO |  | 'queued'::text |
| document_id | uuid | YES |  FK → hospital.documents.id | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `report_jobs_check`: `CHECK (((to_at > from_at) AND ((to_at - from_at) <= '366 days'::interval)))`.
- `report_jobs_department_id_fkey`: `FOREIGN KEY (department_id) REFERENCES hospital.departments(id)`.
- `report_jobs_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES hospital.documents(id)`.
- `report_jobs_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `report_jobs_format_check`: `CHECK ((format = ANY (ARRAY['pdf'::text, 'xlsx'::text])))`.
- `report_jobs_pkey`: `PRIMARY KEY (id)`.
- `report_jobs_report_id_fkey`: `FOREIGN KEY (report_id) REFERENCES hospital.report_definitions(id)`.
- `report_jobs_requested_by_fkey`: `FOREIGN KEY (requested_by) REFERENCES hospital.profiles(id)`.
- `report_jobs_status_check`: `CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'ready'::text, 'failed'::text, 'expired'::text])))`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((requested_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`.
- **SELECT** → ['hospital_api']; `USING ((requested_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((requested_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`; `WITH CHECK ((requested_by = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`.

### hospital.report_schedules

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| report_id | uuid | NO |  FK → hospital.report_definitions.id | — |
| facility_id | uuid | NO |  FK → hospital.facilities.id | — |
| owner_id | uuid | NO |  FK → hospital.profiles.id | — |
| cron_expression | text | NO |  | — |
| timezone | text | NO |  | 'America/El_Salvador'::text |
| enabled | boolean | NO |  | true |
| format | text | NO |  | — |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `report_schedules_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `report_schedules_format_check`: `CHECK ((format = ANY (ARRAY['pdf'::text, 'xlsx'::text])))`.
- `report_schedules_owner_id_fkey`: `FOREIGN KEY (owner_id) REFERENCES hospital.profiles(id)`.
- `report_schedules_pkey`: `PRIMARY KEY (id)`.
- `report_schedules_report_id_fkey`: `FOREIGN KEY (report_id) REFERENCES hospital.report_definitions(id)`.

Políticas RLS:

- **INSERT** → ['hospital_api']; `USING None`; `WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`.
- **SELECT** → ['hospital_api']; `USING ((owner_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`; `WITH CHECK None`.
- **UPDATE** → ['hospital_api']; `USING ((owner_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`; `WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(facility_id, 'reports.read'::text))`.

### hospital.audit_events

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| actor_id | uuid | YES |  FK → hospital.profiles.id | — |
| facility_id | uuid | YES |  FK → hospital.facilities.id | — |
| resource | text | NO |  | — |
| record_id | uuid | YES |  | — |
| operation | text | NO |  | — |
| occurred_at | timestamp with time zone | NO |  | now() |
| correlation_id | text | YES |  | — |
| outcome | text | NO |  | 'success'::text |
| created_at | timestamp with time zone | NO |  | now() |
| updated_at | timestamp with time zone | NO |  | now() |
| row_version | bigint | NO |  | 1 |

Restricciones:

- `audit_events_actor_id_fkey`: `FOREIGN KEY (actor_id) REFERENCES hospital.profiles(id)`.
- `audit_events_facility_id_fkey`: `FOREIGN KEY (facility_id) REFERENCES hospital.facilities(id)`.
- `audit_events_operation_check`: `CHECK ((operation = ANY (ARRAY['SELECT'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text, 'AUTH'::text, 'EXPORT'::text])))`.
- `audit_events_outcome_check`: `CHECK ((outcome = ANY (ARRAY['success'::text, 'denied'::text])))`.
- `audit_events_pkey`: `PRIMARY KEY (id)`.

Políticas RLS:

- **SELECT** → ['hospital_api']; `USING private.has_permission(facility_id, 'audit.read'::text)`; `WITH CHECK None`.

## Soporte técnico

### private.idempotency_keys

| Columna | Tipo PostgreSQL | Nulo | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | NO | PK | gen_random_uuid() |
| profile_id | uuid | NO |  FK → hospital.profiles.id | — |
| request_key | uuid | NO |  | — |
| operation | text | NO |  | — |
| resource_id | uuid | YES |  | — |
| created_at | timestamp with time zone | NO |  | now() |

Restricciones:

- `idempotency_keys_pkey`: `PRIMARY KEY (id)`.
- `idempotency_keys_profile_id_fkey`: `FOREIGN KEY (profile_id) REFERENCES hospital.profiles(id)`.
- `idempotency_keys_profile_id_request_key_key`: `UNIQUE (profile_id, request_key)`.

Políticas RLS:

- **ALL** → ['hospital_api']; `USING (profile_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid))`; `WITH CHECK (profile_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid))`.

## Vistas calculadas

`bed_statuses`, `inventory_balances`, `fleet_statuses`, `appointment_directory` y `laboratory_directory` son proyecciones `security_invoker`, sin almacenamiento duplicado. Sólo `hospital_api` puede consultarlas. Los catálogos publicados usan vistas del mismo tipo con SELECT expresamente concedido a `authenticated` y sus propias políticas de lectura. `information` publica únicamente avisos vigentes.

Una FK histórica se mantiene con RESTRICT por defecto. No se eliminan usuarios Auth que sigan referenciados. `audit_events.record_id` e `idempotency_keys.resource_id` son referencias técnicas polimórficas; no sustituyen FK en el dominio asistencial. Se conservan aunque cambie la disponibilidad de la entidad, por lo que no se dibujan como FK inexistentes.

## 3. Justificación de la normalización

**1FN.** Cada fila representa una entidad o relación identificada por PK. Alergias, medicamentos de una receta, analitos, especialidades, roles, contactos, sedes y miembros de tripulación se almacenan como filas relacionadas. No se guardan listas con comas ni columnas alergia_1/alergia_2, lunes/martes o rol_1/rol_2. Los JSON de respuesta sólo componen la presentación; las entidades del negocio no se guardan como bloques JSON.

**2FN.** Las tablas puente tienen PK sustituta y UNIQUE sobre la combinación natural. Los atributos de la relación pertenecen a esa relación: vigencia de una asignación, permiso de un rol, dosis en un renglón de receta, umbral de un producto en una ubicación. El nombre del rol depende de roles, no de la asignación del usuario; el nombre de medicamento depende del catálogo, no de cada renglón.

**3FN.** Los nombres del paciente viven en persons; la cuenta y sus preferencias en profiles; el expediente y sangre en patients. La edad se calcula. La cama apunta a la habitación, la habitación a la planta y ésta a la sede; no se copian todos esos nombres en cada ingreso. El ingreso apunta a un encounter y no repite paciente/sede. Una orden apunta a la atención y sus estudios a la orden. Una muestra se vincula a los estudios mediante specimen_items. Las dosis/unidades, categorías, especialidades y CIE-10 son catálogos con FK.

La solicitud de atención conserva las preferencias de un hecho distinto de la cita: preferred_date y franja horaria no son copias del horario reservado. appointment_id UNIQUE enlaza el resultado sin copiar médico, consultorio ni nombres. El contacto de emergencia es una relación paciente-persona; el teléfono vive en person_contacts y no se repite en patients ni en la relación.

La misma alergia aparece en resumen, alertas, consulta y perfil clínico mediante una consulta al mismo patient_allergies. No se crea un campo patient.allergies_text. El diagnóstico principal es un índice único parcial por encounter en encounter_diagnoses. La PA se recompone desde dos números; no se almacena además el texto 128/76. Las recetas se muestran en web y móvil leyendo las mismas cabeceras y renglones.

La ocupación, plazas libres, número de recetas, porcentajes, stock y alertas de vencimiento no son atributos repetidos de pacientes/habitaciones. Se obtienen de bed_allocations y del libro stock_movements, agrupados en vistas o RPC. El libro de inventario es inmutable; una corrección es un movimiento de reversión. El catálogo products puede tener un nombre comercial distinto del nombre genérico de medications; ambos conceptos se documentan separados, sin duplicar una etiqueta calculada del medicamento.

Los estados de ciclo de vida, fechas de firma, vigencias y versiones son hechos persistentes necesarios para reconstruir quién autorizó qué. Las notas firmadas y resultados validados no se reescriben: se añade adenda o versión correctiva. Los metadatos de auditoría y de idempotencia son soporte técnico, no un sustituto de las FK del dominio.

## 4. Endpoints y servicios agrupados por recurso

Base: `https://kgulityewtcyvjnxeskd.supabase.co`. Los RPC están publicados en Supabase y document-access está desplegada; la disponibilidad de archivos depende del bucket privado y del flujo de carga/escaneo pendiente. Las firmas exactas están en `openapi.yaml`.

La API REST auto generada de Supabase sirve catálogos públicos/controlados. La lectura de datos clínicos se realiza por POST RPC para escribir auditoría dentro de la misma transacción. No se habilitan hospital/private como schemas expuestos. Las operaciones de varios registros utilizan RPC transaccionales; Edge se reserva para Auth Admin, archivos y proveedores externos.

| Recurso | Consultas concretas | Mutaciones / servicio | Implementación |
|---|---|---|---|
| Ambulancia | ambulances, ambulance_activities, ambulance_dispatches, dispatch_patients, dispatch_crew | read_resource(fleet_statuses); dispatch_ambulance; maintain_ambulance; finish_ambulance_activity; report_jobs | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Citas y turnos | appointments, appointment_events, care_queues, queue_tickets, encounters | book_appointment; transition_appointment; check_in; call_next_ticket; start_consultation | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Configuración | organizations, profiles, notification_preferences, notification_topics, room_types, rooms, beds, ambulances | read_resource; update_record; set_user_roles | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Expediente clínico | patients, patient_allergies, patient_conditions, medical_history_entries, encounters, clinical_notes, vital_sign_sets, prescriptions, diagnostic_orders, lab_results | patient_chart; read_resource; create_record; update_record; finalize_clinical_record | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Habitaciones y camas | floors, room_types, rooms, beds, bed_allocations, admissions | read_resource(bed_statuses); allocate_bed; block_bed; complete_bed_block; discharge_admission | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Inventario y recursos | products, product_categories, stock_lots, stock_locations, stock_thresholds, stock_movements, equipment_assets | read_resource(inventory_balances); create_record; record_stock_movement | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Laboratorio | diagnostic_orders, diagnostic_order_items, test_definitions, specimens, specimen_items, lab_results, lab_result_values | laboratory_worklist; read_resource; create_record; finalize_clinical_record. collect_specimen; process_lab_item. | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Pacientes e ingresos | patients, persons, encounters, admissions, triage_levels, bed_allocations | register_patient; register_admission; list_admissions; discharge_admission | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Reportes y analítica | report_definitions, report_jobs, report_schedules, bed_allocations, encounters, appointments, lab_results, stock_movements | operational_dashboard; create_record(report_jobs). Worker PDF/XLSX pendiente de implementación. | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Tablero general | bed_statuses, fleet_statuses, appointments, diagnostic_orders, staff_shifts, admissions | operational_dashboard; read_resource; list_admissions | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Turnos del personal | staff_members, staff_assignments, staff_shifts, shift_templates, shift_requests, coverage_requirements | read_resource; create_record; update_record. confirm_shift; review_shift_request. | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |
| Usuarios y roles | profiles, persons, user_role_assignments, role_permissions, staff_assignments | list_users; set_user_roles; set_account_status; Auth Admin para invitaciones (pendiente de integración) | RPC/REST implementados; las salvedades de proveedores se indican en esta sección |

## Flujos móviles añadidos

| Recurso | Servicios implementados |
|---|---|
| Solicitud de atención | request_appointment captura especialidad, motivo y preferencia; schedule_appointment_request reserva y resuelve en una transacción; resolve_appointment_request rechaza/cancela |
| Consulta y preconsulta | save_consultation guarda nota y diagnóstico principal; close_consultation firma, cierra atención y completa cita/turno; create_record(vital_sign_sets) registra una medición inmutable |
| Indicaciones | start_care_order y execute_care_order exigen autorización, paciente asignado, versión y atención abierta; ejecución idempotente |
| Perfil y privacidad | my_profile, update_my_phone, set_my_emergency_contact; preferencias propias, Auth y MFA del mismo usuario en todos los clientes |
| Inicio e información | my_activity_summary por contexto patient/staff y período; hospital_overview agrega capacidad, médicos de turno y publicaciones sin identidades de terceros |
| Laboratorio y personal | collect_specimen / process_lab_item; confirm_shift / review_shift_request |

## Firmas SQL implementadas

- `POST /rest/v1/rpc/allocate_bed`: `(p_admission uuid, p_bed uuid, p_at timestamp with time zone, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.allocate_bed`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/authorize_document_download`: `(p_document uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.authorize_document_download`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/block_bed`: `(p_bed uuid, p_kind text, p_from timestamp with time zone, p_to timestamp with time zone, p_reason text, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.block_bed`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/book_appointment`: `(p_patient uuid, p_department uuid, p_physician uuid, p_specialty uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_reason text, p_room uuid, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.book_appointment`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/call_next_ticket`: `(p_queue uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.call_next_ticket`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/check_in`: `(p_appointment uuid, p_queue uuid, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.check_in`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/close_consultation`: `(p_encounter uuid, p_note uuid, p_note_version bigint, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.close_consultation`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/collect_specimen`: `(p_item uuid, p_barcode text, p_type text, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.collect_specimen`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/complete_bed_block`: `(p_id uuid, p_at timestamp with time zone, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.complete_bed_block`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/confirm_shift`: `(p_id uuid, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.confirm_shift`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/create_record`: `(p_resource text, p_values jsonb, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.create_record`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/discharge_admission`: `(p_id uuid, p_at timestamp with time zone, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.discharge_admission`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/dispatch_ambulance`: `(p_ambulance uuid, p_service_type text, p_origin text, p_destination text, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.dispatch_ambulance`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/execute_care_order`: `(p_order uuid, p_outcome text, p_note text, p_expected_version bigint, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.execute_care_order`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/finalize_clinical_record`: `(p_resource text, p_id uuid, p_action text, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.finalize_clinical_record`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/finish_ambulance_activity`: `(p_id uuid, p_at timestamp with time zone, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.finish_ambulance_activity`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/hospital_overview`: `(p_facility uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.hospital_overview`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/laboratory_worklist`: `(p_facility uuid, p_limit integer DEFAULT 25, p_after uuid DEFAULT NULL::uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.laboratory_worklist`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/link_patient_account`: `(p_profile uuid, p_patient uuid) → void`; entrada pública SECURITY INVOKER; implementación `private.link_patient_account`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/list_admissions`: `(p_facility uuid, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 25, p_after uuid DEFAULT NULL::uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.list_admissions`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/list_users`: `(p_facility uuid, p_limit integer DEFAULT 25, p_after uuid DEFAULT NULL::uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.list_users`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/maintain_ambulance`: `(p_ambulance uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.maintain_ambulance`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/my_access`: `() → jsonb`; entrada pública SECURITY INVOKER; implementación `private.my_access`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/my_activity_summary`: `(p_facility uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_context text) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.my_activity_summary`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/my_profile`: `() → jsonb`; entrada pública SECURITY INVOKER; implementación `private.my_profile`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/my_queue_status`: `(p_ticket uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.my_queue_status`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/operational_dashboard`: `(p_facility uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_department uuid DEFAULT NULL::uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.operational_dashboard`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/patient_chart`: `(p_patient uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.patient_chart`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/physician_directory`: `(p_facility uuid, p_specialty uuid DEFAULT NULL::uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.physician_directory`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/process_lab_item`: `(p_item uuid, p_specimen uuid, p_action text, p_reason text, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.process_lab_item`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/read_resource`: `(p_resource text, p_filters jsonb DEFAULT '[]'::jsonb, p_limit integer DEFAULT 25, p_sort text DEFAULT 'id'::text, p_direction text DEFAULT 'asc'::text, p_cursor jsonb DEFAULT NULL::jsonb) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.read_resource`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/record_stock_movement`: `(p_lot uuid, p_location uuid, p_quantity numeric, p_kind text, p_reason text, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.record_stock_movement`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/register_admission`: `(p_patient uuid, p_department uuid, p_physician uuid, p_type text, p_priority uuid, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.register_admission`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/register_patient`: `(p_facility uuid, p_given_names text, p_family_names text, p_birth_date date, p_sex text, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.register_patient`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/request_appointment`: `(p_patient uuid, p_facility uuid, p_specialty uuid, p_reason text, p_date date, p_from time without time zone, p_to time without time zone, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.request_appointment`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/reschedule_appointment`: `(p_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_room uuid, p_reason text, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.reschedule_appointment`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/resolve_appointment_request`: `(p_id uuid, p_status text, p_appointment uuid, p_reason text, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.resolve_appointment_request`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/review_shift_request`: `(p_id uuid, p_approve boolean, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.review_shift_request`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/save_consultation`: `(p_encounter uuid, p_note uuid, p_values jsonb, p_diagnosis uuid, p_expected_version bigint, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.save_consultation`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/schedule_appointment_request`: `(p_id uuid, p_department uuid, p_physician uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_room uuid, p_expected_version bigint, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.schedule_appointment_request`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/search_patients`: `(p_query text, p_facility uuid, p_limit integer DEFAULT 25) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.search_patients`, dueño `hospital_api`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/set_account_status`: `(p_profile uuid, p_facility uuid, p_status text, p_expected_version bigint) → void`; entrada pública SECURITY INVOKER; implementación `private.set_account_status`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/set_my_emergency_contact`: `(p_id uuid, p_given_names text, p_family_names text, p_phone text, p_relationship text, p_expected_version bigint, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.set_my_emergency_contact`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/set_user_roles`: `(p_profile uuid, p_facility uuid, p_roles uuid[]) → void`; entrada pública SECURITY INVOKER; implementación `private.set_user_roles`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/start_care_order`: `(p_id uuid, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.start_care_order`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/start_consultation`: `(p_appointment uuid, p_request_key uuid) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.start_consultation`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/transition_appointment`: `(p_id uuid, p_status text, p_reason text, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.transition_appointment`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/update_my_phone`: `(p_value text) → void`; entrada pública SECURITY INVOKER; implementación `private.update_my_phone`, dueño `postgres`, SECURITY DEFINER=True.
- `POST /rest/v1/rpc/update_record`: `(p_resource text, p_id uuid, p_values jsonb, p_expected_version bigint) → jsonb`; entrada pública SECURITY INVOKER; implementación `private.update_record`, dueño `hospital_api`, SECURITY DEFINER=True.

## Lectura, filtros y paginación

`read_resource` acepta un recurso de la lista fija, hasta 12 filtros acumulables, límite 1–100, columna de orden, dirección y cursor compuesto por valor e ID. Operadores: eq, ne, gt, gte, lt, lte, ilike, isnull e in, y overlaps (&&) para intervalos PostgreSQL. El filtro de citas por fecha se aplica a period con un tstzrange [inicio, fin).

```json
{"p_resource":"appointment_directory","p_filters":[{"column":"status","op":"eq","value":"scheduled"}],"p_limit":25,"p_sort":"id","p_direction":"asc"}
```

Respuesta: `{data: [...], has_more: boolean, next_cursor: {id,value}|null}`. El cursor se usa con los mismos filtros y el mismo orden. Las búsquedas generales con nombres se resuelven con `search_patients`, que devuelve sólo demografía autorizada. Las pestañas clínicas consultan recursos normalizados mediante sus FK.

## Campos editables

`create_record` recibe p_resource, p_values y p_request_key UUID. `update_record` recibe p_resource, p_id, p_values y p_expected_version. Se rechazan columnas adicionales, PK, autores y metadatos de permisos. Las claves idempotentes son por usuario; reutilizarlas con otro cuerpo falla. Las funciones de negocio mantienen sus propias transacciones e idempotencia. Las entradas públicas convierten 40001, 23503, 23505 y 23P01 a PT409 (HTTP 409), y los errores de datos/CHECK a PT422 (HTTP 422). El campo details conserva únicamente el SQLSTATE original, sin la fila clínica. Una edición en conflicto requiere volver a leer su versión; no se reintenta silenciosamente. La publicación de un resultado actualiza el estudio y completa su orden cuando todos sus estudios están validados/cancelados.

| Recurso | Campos de creación | Campos de actualización |
|---|---|---|
| administration_routes | code, name |  |
| allergens | code, name, kind |  |
| ambulances | facility_id, code, license_plate, ambulance_type, equipment_description | license_plate, ambulance_type, equipment_description, active |
| analytes | code, name |  |
| beds | room_id, code | code, active |
| care_assignments | patient_id, staff_id, department_id, valid_during, authorized_by | valid_during |
| care_order_executions |  |  |
| care_orders | encounter_id, instruction, kind, due_at | instruction, due_at |
| care_queues | department_id, service_date, code |  |
| clinical_notes | encounter_id, kind, subjective, objective, assessment, plan | subjective, objective, assessment, plan |
| consultation_rooms | department_id, code, name | name, active |
| coverage_requirements | department_id, role_id, weekday, starts_at, ends_at, required_staff | required_staff |
| departments | facility_id, code, name | name, active |
| device_tokens | profile_id, provider, token | revoked_at |
| diagnosis_codes | system, code, description |  |
| diagnostic_order_items | order_id, test_id |  |
| diagnostic_orders | encounter_id, order_number, priority, clinical_question | priority, clinical_question |
| dispatch_crew | dispatch_id, staff_id, duty | duty |
| dispatch_patients | dispatch_id, patient_id |  |
| encounter_diagnoses | encounter_id, condition_id, is_principal | is_principal |
| equipment_assets | product_id, serial_number, location_id | location_id, status |
| equipment_maintenance | asset_id, started_at, description | ended_at, description |
| facilities | organization_id, code, name, address | name, address, active |
| floors | facility_id, number, name | name |
| lab_reference_ranges | analyte_id, unit_id, sex, age_min_days, age_max_days, lower_value, upper_value, interpretation, valid_from, valid_to |  |
| lab_result_values | result_id, analyte_id, value_numeric, value_text, unit_id, reference_range_id, flag | value_numeric, value_text, unit_id, reference_range_id, flag |
| lab_results | order_item_id, version, supersedes_id, narrative, document_id | narrative, document_id |
| medical_history_entries | patient_id, kind, description, occurred_on | entered_in_error_at |
| medications | code, generic_name, strength, strength_unit_id, dosage_form, active | active |
| note_addenda | note_id, body |  |
| notification_preferences | profile_id, topic_id, channel, enabled | enabled |
| notifications |  | read_at |
| organizations | name, institutional_email, phone, administrative_address, timezone, locale | name, institutional_email, phone, administrative_address, timezone, locale |
| patient_allergies | patient_id, allergen_id, reaction, severity | reaction, severity, status |
| patient_conditions | patient_id, diagnosis_code_id, onset_date, severity | status, resolved_date, severity |
| patient_documents | patient_id, document_id, title | title |
| person_contacts | person_id, kind, value, is_primary | value, is_primary |
| person_identifiers | person_id, issuer_country, kind, value | value |
| prescription_items | prescription_id, medication_id, dose, dose_unit_id, route_id, interval_hours, instructions, starts_on, ends_on, quantity | medication_id, dose, dose_unit_id, route_id, interval_hours, instructions, starts_on, ends_on, quantity |
| prescriptions | encounter_id |  |
| product_categories | code, name |  |
| products | sku, name, category_id, stock_unit_id, medication_id, active | active |
| profiles |  | preferred_name, theme, locale |
| public_information | facility_id, category, title, body, published_at, expires_at | title, body, published_at, expires_at |
| report_jobs | report_id, facility_id, department_id, from_at, to_at, format |  |
| report_schedules | report_id, facility_id, owner_id, cron_expression, timezone, format | cron_expression, timezone, enabled, format |
| rooms | floor_id, room_type_id, code | code, active |
| shift_requests | staff_id, shift_id, kind, requested_period, reason | reason, requested_period |
| specialties | code, name |  |
| staff_assignments | staff_id, department_id, job_title, valid_during | job_title, valid_during |
| staff_members | person_id, employee_code, license_number | active |
| staff_shifts | staff_id, department_id, period | period |
| staff_specialties | staff_id, specialty_id |  |
| stock_locations | department_id, code, name | name |
| stock_lots | product_id, lot_number, expires_on |  |
| stock_thresholds | product_id, location_id, minimum_quantity, critical_quantity | minimum_quantity, critical_quantity |
| test_analytes | test_id, analyte_id, display_order |  |
| test_definitions | code, name, kind, specialty_id, active | active |
| units | code, name |  |
| vital_sign_sets | encounter_id, measured_at, systolic_mmhg, diastolic_mmhg, pulse_bpm, respiratory_rate, temperature_c, spo2_percent, weight_kg, height_cm |  |

## Servicios especificados que deben completarse antes de liberar

| Servicio propuesto | Contrato / regla | Motivo |
|---|---|---|
| Auth Admin / invite-user | POST email, persona, sede, roles; comprobar users.write; invitación pendiente y activación explícita; compensar fallos entre Auth y DB | No se ha implementado el orquestador de invitaciones ni enviado correo a nadie |
| report-worker / exports | Validar permiso del tipo de reporte; acotar sede/fechas; PDF/XLSX privados; antifórmulas en celdas de Excel | Existen report_jobs y report_schedules; no hay renderer/worker desplegado |
| upload-document / scan-document | Ruta UUID del servidor, vínculo inmutable al paciente, SHA-256, cuarentena, antivirus y liberación | document-access está desplegada para archivos ya autorizados; la carga y el escaneo siguen pendientes |
| notification-worker | Preferencias por tema/canal, cola de salida, reintentos/idempotencia y mensajes sin diagnóstico en push | No se han configurado APNs/FCM ni proveedores de correo |
| period/area report queries | Filtros temporales y de área equivalentes en todas las métricas, tendencia diaria y tiempos de proceso | operational_dashboard cubre el agregado básico; no reemplaza todos los gráficos del diseño |

Estas filas son pendientes explícitos de implementación; no son endpoints operativos ni pruebas aprobadas. Las acciones de menús de tres puntos sin contenido visible no se inventan como requerimientos confirmados.

## 5. Autenticación y pruebas

### Estrategia Auth

1. Una cuenta Supabase Auth sirve en las tres plataformas. Inicio de sesión, refresh, cierre de sesión, recuperación y MFA usan las API oficiales; no se implementa una tabla de contraseñas.
2. El trigger crea profiles en estado pending y no lee roles de user_metadata. La invitación/activación de personal y la verificación de pacientes deben completar el enlace a persons. patient_accounts exige que cuenta y paciente correspondan a la misma persona.
3. Los permisos vienen de roles → role_permissions y user_role_assignments por sede. my_access devuelve el contexto para mostrar navegación; la interfaz no decide la autorización.
4. El personal necesita aal2 en cada operación privilegiada. La clínica propia del paciente también necesita aal2. La configuración local propone JWT de 10 minutos, TOTP, registro público deshabilitado y redirecciones explícitas.
5. Web debe proteger sus sesiones contra XSS/CSRF según su arquitectura; móvil debe utilizar Keychain/almacenamiento seguro del sistema. No guardar PHI, refresh tokens ni service_role en logs, analytics o repositorios. El cierre de sesión revoca refresh; el acceso inmediato se bloquea desactivando profiles. La base comprueba también session_id, usuario y not_after contra auth.sessions: una sesión borrada o vencida bloquea incluso un JWT todavía vigente. Esta conducta se probó en el proyecto real.
6. Archivos en bucket privado hospital-files, cuarentena y validación de contenido. La Edge Function document-access está desplegada y sólo firma una ruta previamente autorizada por DB, durante 60 segundos. Se verificó HTTP 401 sin JWT. El bucket, scanner, cargas y proveedores siguen pendientes; sin ellos no existen documentos descargables. La lista de orígenes web permitidos está cerrada hasta conocer los dominios definitivos.
7. Las lecturas clínicas por RPC escriben auditoría de actor, recurso, registro y correlación; las mutaciones se auditan con trigger. No se registran los cuerpos clínicos. Los intentos fallidos que aborten una transacción requieren bitácora en el gateway/infraestructura: el rollback también revierte una auditoría SQL de ese intento. El acceso directo de administradores DB requiere auditoría de infraestructura adicional.

### Validación realizada

Las doce migraciones se ejecutaron desde cero en PostgreSQL 18.6 mediante PGlite 0.5.11, con btree_gist real, roles y políticas RLS. Las doce migraciones se aplicaron también al proyecto remoto PostgreSQL 17.11. Allí se aprobaron 16 comprobaciones transaccionales de solicitudes, perfil, contactos, demografía autorizada, denegación clínica a administración, bloqueo anónimo y revocación de sesión; se revirtieron todas las personas y cuentas de prueba. Los archivos SQL locales están alineados con las versiones remotas y sus SHA-256 se conservan en remote_verification.json. El bootstrap de tests simula auth.uid/auth.jwt; no verifica criptografía de JWT ni sustituye Auth/HTTP de Supabase.

Se aprobaron **90 comprobaciones SQL**. document-access se compiló y desplegó en el runtime Edge de Supabase; su gateway rechaza peticiones sin JWT. No se ha comprobado una descarga clínica real porque no hay bucket, documentos ni identidades clínicas reales configuradas.

| Comprobación ejecutada | Resultado |
|---|---|
| Administrador sin acceso clínico implícito | Aprobada |
| Administrador sí obtiene agregado | Aprobada |
| Alta libera cama y crea limpieza | Aprobada |
| Ambulancia sin despachos simultáneos | Aprobada |
| Asignación de cama transaccional | Aprobada |
| Auditoría de lectura existe | Aprobada |
| Autor no se puede suplantar | Aprobada |
| Bitácora sin cuerpos clínicos | Aprobada |
| Cama no admite limpieza solapada | Aprobada |
| Capacidad observada 17 camas | Aprobada |
| Check-in no admite cita de otra fecha | Aprobada |
| Cierre firma nota, completa cita y turno | Aprobada |
| Cierre repetido con versión antigua falla | Aprobada |
| Cierre también completa turno | Aprobada |
| Cita conserva idempotencia | Aprobada |
| Clave idempotente con otro cuerpo se rechaza | Aprobada |
| Consulta conecta cita, paciente y atención | Aprobada |
| Contacto de emergencia se lee sin duplicar al paciente | Aprobada |
| Contactos ajenos ocultos por RLS | Aprobada |
| Cuenta desactivada pierde acceso con JWT vigente | Aprobada |
| Despacho inicial funciona | Aprobada |
| Enfermería asignada registra signos | Aprobada |
| Enfermería confirma su guardia | Aprobada |
| Enfermería no receta | Aprobada |
| Entrada aumenta existencias | Aprobada |
| Evento de reprogramación contiene períodos | Aprobada |
| Expediente requiere MFA | Aprobada |
| FK de paciente obligatoria | Aprobada |
| Fecha nacimiento futura | Aprobada |
| Idempotencia no duplica movimiento | Aprobada |
| Información pública devuelve sólo capacidad agregada | Aprobada |
| Ingreso activo no se duplica | Aprobada |
| Jefatura resuelve cambio con control de sede | Aprobada |
| Limpieza posterior preservada | Aprobada |
| Mantenimiento respeta el mismo bloqueo | Aprobada |
| Médico asignado lee expediente | Aprobada |
| Médico no puede tener citas solapadas | Aprobada |
| Médico sin asignación no lee expediente | Aprobada |
| No cabe otra cama VIP | Aprobada |
| No hay DELETE concedido a clientes | Aprobada |
| No hay datos clínicos de otra sede | Aprobada |
| No se permite sexta habitación VIP | Aprobada |
| No se puede aprobar el propio cambio | Aprobada |
| Nota firmada inmutable | Aprobada |
| Orden SQL inyectado se rechaza | Aprobada |
| Paciente consulta posición sin identidad ajena | Aprobada |
| Paciente no agenda directamente | Aprobada |
| Paciente no lee otro expediente | Aprobada |
| Paciente no ve resultado en borrador | Aprobada |
| Paciente puede leer su expediente | Aprobada |
| Paciente sólo ve una nota publicada | Aprobada |
| Paciente ve resultado publicado | Aprobada |
| Perfil móvil conserva teléfono normalizado | Aprobada |
| Preferencia horaria invertida rechazada | Aprobada |
| Programación desde solicitud es idempotente | Aprobada |
| Publicar resultado completa el estudio y la orden | Aprobada |
| RLS de encuentros sólo paciente asignado | Aprobada |
| RLS habilitado y forzado en todas las tablas | Aprobada |
| Recepción agenda y resuelve solicitud en una transacción | Aprobada |
| Recepción de muestra inicia procesamiento | Aprobada |
| Recepción no ve notas | Aprobada |
| Recepción no ve signos vitales | Aprobada |
| Recepción ve demografía | Aprobada |
| Recolección conserva idempotencia | Aprobada |
| Recurso SQL inyectado se rechaza | Aprobada |
| Registro de cita en cola | Aprobada |
| Reprogramación con versión antigua falla | Aprobada |
| Reprogramación registra historia de fechas | Aprobada |
| Resumen de médico respeta asignaciones | Aprobada |
| Resumen de paciente usa el mismo modelo | Aprobada |
| Rol de API sin BYPASSRLS | Aprobada |
| Saturación fuera de rango | Aprobada |
| Se registra resultado en borrador | Aprobada |
| Segundo profesional valida resultado | Aprobada |
| Sesión revocada bloquea JWT vigente | Aprobada |
| Siguiente turno se llama | Aprobada |
| Sin autoasignación de roles | Aprobada |
| Sin campos de privilegio en perfil | Aprobada |
| Sin lectura directa de notas | Aprobada |
| Solicitud de otro paciente oculta por RLS | Aprobada |
| Solicitud móvil guarda preferencia sin reservar cita | Aprobada |
| Solicitud sobre paciente ajeno denegada | Aprobada |
| Stock nunca negativo | Aprobada |
| Todas las tablas tienen PK | Aprobada |
| Técnico no confirma guardias ajenas | Aprobada |
| Técnico no ve expediente general | Aprobada |
| Técnico ve lista mínima de laboratorio | Aprobada |
| Una ambulancia inicial | Aprobada |
| Una sola ambulancia entre sedes | Aprobada |
| Validador publica resultado | Aprobada |

### Pruebas adicionales propuestas

| Recurso / capa | Casos necesarios antes de liberar |
|---|---|
| Modelo | Aplicar todas las migraciones en PG17; PK/FK/UNIQUE/CHECK; rollback; invariantes de sede/paciente; fechas de nacimiento, dosis y mediciones; cambio de tipo de habitación con ocupación |
| RLS por tabla | Matriz de cada tabla con paciente A/B, doctor asignado/no asignado, enfermero, recepción, técnico/validador, administración/auditor; sede ajena, vínculo expirado, MFA ausente y cuenta desactivada; INSERT/UPDATE además de SELECT |
| Auth | Contraseñas inválidas, recuperación, refresh/revocación, TOTP, invitación incompleta, cambio de correo, bloqueo, enlace de persona correcto e intento de autoasignación de rol |
| Pacientes e ingresos | Identidad duplicada, registro idempotente, ingreso activo duplicado, asignación y traslado, alta con cama ocupada, limpieza y reapertura de capacidad |
| Citas y atención | Dos conexiones reservando médico/paciente/consultorio al mismo tiempo; cancelación, reprogramación, no-show; check-in de otra fecha; consulta y cierre integral |
| Colas | Dos conexiones llamando siguiente turno; prioridad frente a orden de llegada; números únicos por fecha/cola; posición propia sin exponer otros pacientes |
| Expediente | Paciente ajeno, campos no permitidos, notas firmadas, adendas, signos fuera de rango, principal único, alergias múltiples y corrección de antecedentes |
| Recetas e indicaciones | Emisión con renglones, unidad/dosis/ruta, paciente y autor correctos, edición tras firma, cancelación, repetición de indicación y registro de ejecución |
| Laboratorio | Muestra con paciente equivocado, código repetido, recepción/rechazo, analito ajeno, rango/unidad incompatibles, doble validación, publicación y corrección sin reescritura |
| Personal | Cruce de medianoche y zona horaria, solapamientos en conexiones distintas, cobertura parcial, confirmación y aprobación de cambios/descansos |
| Inventario | Dos salidas concurrentes, lote vencido, ajustes y reversión, traslado entre almacenes, caducidad parcial y activos con mantenimiento |
| Ambulancia | Despacho/mantenimiento simultáneos desde conexiones distintas, cierre/cancelación, una sola unidad entre sedes, historial y reporte |
| Archivos | Objeto ajeno, vínculo cruzado entre pacientes/sedes, MIME falso, antivirus, archivo grande, URL vencida, cuota, falta de secret y ausencia de PHI en logs |
| Reportes/notificaciones | Permiso por tipo, filtrado de sede/área/fechas, PDF/XLSX real, fórmulas de Excel, denominadores aprobados, schedules idempotentes, preferencias y reintentos de APNs/FCM |
| Rendimiento y recuperación | EXPLAIN ANALYZE con datos representativos y RLS, índices FK, keyset en cambios concurrentes, p95 de listados, restauración real de backup, objetivos RPO/RTO y concurrencia clínica |

PGlite usa una conexión de ejecución; las pruebas de colisión realizadas verifican las restricciones secuencialmente. No se anuncian pruebas de carreras entre conexiones, de carga, de restore ni una auditoría de seguridad exhaustiva como ya aprobadas.

### Pendientes concretos de esta entrega

1. Configurar las URLs web y deep links definitivos, SMTP, política de registro, TOTP y primer administrador real en Auth. config.toml no cambia automáticamente los ajustes del proyecto. No se han enviado invitaciones ni creado credenciales ficticias.
2. Conectar el bucket privado hospital-files, carga/antivirus/liberación y proveedores APNs/FCM/correo; completar el orquestador Auth Admin y los workers de reportes/notificaciones indicados en la sección 4.
3. Lucidchart contiene las 92 entidades y 162 relaciones. Las columnas nuevas de appointment_events y care_orders se actualizaron mediante el importador. Completar la revisión individual de extremos nativos y nulabilidad contra Relaciones.csv; la validación visual fue por muestreo y recuento. El archivo drawio aporta nueve páginas organizadas por dominios.
4. Ejecutar la matriz completa de RLS por tabla y las pruebas HTTP, concurrencia entre conexiones, generación PDF/XLSX, rendimiento y restauración. Las 90 pruebas locales y 16 remotas acreditan los casos descritos, sin sustituir esas verificaciones.

La revisión automática rechazó una propuesta de herencia del rol authenticated. Esa propuesta se descartó; la migración hospital_api_auth_bridge utiliza auxiliares privados de identidad sin ampliar membresías ni eliminar políticas. Los asesores remotos de seguridad y rendimiento no presentan avisos WARN/ERROR; sólo señalan índices sin uso en una base todavía sin datos operativos. Se conservan los índices de FK para evaluar su uso con carga representativa. Referencia: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index.

### Fuentes técnicas primarias consultadas

- Supabase, RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase, seguridad de Data API: https://supabase.com/docs/guides/api/securing-your-api
- Supabase, funciones de base de datos: https://supabase.com/docs/guides/database/functions
- Supabase, MFA: https://supabase.com/docs/guides/auth/auth-mfa
- PostgreSQL, constraints: https://www.postgresql.org/docs/current/ddl-constraints.html
- Lucid, importar ERD: https://help.lucid.co/hc/en-us/articles/16471565238292-Create-an-Entity-Relationship-Diagram-in-Lucidchart
- Lucid, formatos de diagramas: https://help.lucid.co/hc/en-us/articles/16389149809428-Import-files-into-Lucidchart
- PostgREST, errores y códigos PT: https://docs.postgrest.org/en/v16/references/errors.html
- Supabase changelog revisado: https://supabase.com/changelog.md. Cambio relevante de TLS de noviembre: https://supabase.com/changelog/cbc-tls-ciphers-deprecated; comprobar clientes antiguos antes de liberar móviles.