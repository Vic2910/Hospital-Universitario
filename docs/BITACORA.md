# Bitácora de trabajo

## 2026-11-20 — Paciente: citas a la vista, campana de avisos y solicitud única

- **Objetivo:** ver todos los detalles de las citas sin pantallas intermedias, que el paciente tenga avisos propios como el médico y que no pueda enviar otra solicitud con una pendiente o una cita programada.
- **Supabase (solo lectura):** submit_my_attention_request (sin bloqueo de duplicados), laboratory_notifications (único aviso al paciente), disparadores, estados de request_state, RLS de notifications, staff, profiles, specialties y consulting_rooms, y check de prescriptions.status.
- **Cambios:** iOS PatientAppointmentsView (reescrita), PatientNotificationBell y temporizador en ContentView, HospitalStore (patientNotifications; cita vigente para la solicitud), PatientAttentionModel (AttentionRules, submissionBlocker), PatientAttentionLiveView (cabecera y aviso de bloqueo) y PatientAttentionTests; Shared/hospital-core.js (citas con médico, especialidad y motivo; attentionBlocker); web patient-appointments.js (renderLive), app.js (campana, bloqueo y citas) y style.css; pruebas test-patient-portal (nueva) y test-attention-navigation. [Informe](PACIENTE_CITAS_AVISOS_SOLICITUD_2026-11-20.md).
- **SQL preparado, no aplicado:** supabase/paciente-avisos-solicitud-unica.sql.
- **Verificaciones ejecutadas:** las 15 pruebas web, generate-models --check, check-project.py y git diff --check aprobados (simulados).
- **Pendiente:** compilación Swift, revisión visual y aplicación del SQL (avisos de cita, receta y solicitud, y bloqueo en el servidor).

## 2026-11-20 — Doctor: interfaz de ingresos, laboratorio y recetas

- **Objetivo:** mejorar la interfaz sin cambiar la lógica. En ingresos, buscar al paciente por nombre, apellido o DUI sin mostrar el listado completo.
- **Cambios:** iOS DoctorModuleView (ingresos en 3 pasos con buscador de al menos 2 letras y espera breve, categorías en etiquetas, prioridad segmentada, tarjetas de solicitudes; selección de exámenes con búsqueda, categorías en etiquetas, tarjetas y resumen; tarjetas de órdenes con resultados; receta en 3 pasos con campos con unidades y revisión; selector de paciente y recetas emitidas en tarjetas). Web modules.js (mismos pasos y buscador; selects conservados) y style.css. Prueba test-doctor-admissions ajustada: sin listado al abrir y una letra no consulta.
- **Verificaciones ejecutadas:** las 14 pruebas web, generate-models --check, check-project.py y git diff --check aprobados (simulados).
- **Pendiente:** compilación Swift y revisión visual.

## 2026-11-20 — Doctor: agenda de dos filtros y auditoría del módulo con Supabase

- **Objetivo:** agenda con solo PENDIENTES y FINALIZADAS (fecha inicial hoy, fecha compacta, búsqueda, tarjetas con hora destacada) y auditoría completa del módulo Doctor contra Supabase desplegado.
- **Supabase (solo lectura):** inventario y permisos de las 18 RPC, definiciones de start/save/finish/labs/lab/prescribe/admission_request/request_admission/update_appointment_status, disparadores de appointments y tablas clínicas, RLS, estados `appointment_state` y publicación Realtime (solo `planning_revision`). Comparación por hash de cada función desplegada con los SQL locales.
- **Hallazgo crítico:** el disparador `native_complete_guard` también exige `plan` al completar la cita; `doctor-consultation-six-fields.sql` (sin aplicar) se corrigió para ajustarlo. Esa migración ahora también publica `finished_at` (ended_at) y ordena el workspace por `starts_at`.
- **Cambios:** iOS DoctorConsultationAgendaView (reescrita), DoctorModels (pending, finished, matches y finished_at; DoctorDate con microsegundos), DoctorViewModel (ventana desde 2 días antes, filtro pending, refresh silencioso, syncAgendaIfChanged), DoctorRepository y HospitalAPI (planningRevision), ContentView (sondeo de 30 s en Consultas) y DoctorModuleTests; Shared/hospital-core.js (mismas reglas); web doctor-dashboard.js (agenda), modules.js, api.js, app.js y style.css; pruebas test-doctor-agenda (nueva), test-doctor-clinical-rules y test-doctor-preview-live. [Informe](ANALISIS_MODULO_DOCTOR_SUPABASE.md).
- **Verificaciones ejecutadas:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, test-patient-record, test-doctor-agenda, generate-models --check, check-project.py y git diff --check aprobados (simulados). test-clinical-labs sigue fallando, como en d828fd6.
- **Pendiente:** compilación y pruebas Swift, revisión visual, aplicación de las migraciones, pruebas con cuentas reales (dos médicos, recepción y paciente) y decisión sobre los hallazgos de privacidad.

## 2026-11-20 — Expedientes: búsqueda, expediente sin duplicados e historial ordenado

- **Objetivo:** rediseñar Expedientes para médico (buscador sin desplegable, expediente con cabecera única, VER HISTORIAL MÉDICO con detalle por consulta) y paciente (acceso directo a su expediente e historial), con paridad iOS/web-preview.
- **Backend (solo lectura):** doctor_native_patients, doctor_native_chart, doctor_native_patient_labs, native_mobile_lab_page, treats_patient, my_consultation_history y RLS de las tablas clínicas. Faltan patient_code en la búsqueda, especialidad/motivo/médico por consulta en chart, encounter_id en las recetas de chart, y motivo/recetas/exámenes en my_consultation_history.
- **Cambios:** iOS DoctorRecordsView (nuevo), DoctorModuleView, DoctorModels (DoctorRecordRules y campos opcionales), DoctorViewModel (searchPatients con espera y sin repetir; loadChart silencioso), PatientHistoryView, PatientClinicalView y DoctorModuleTests; Shared/hospital-core.js (historial sin campos vacíos, motivo, recetas y exámenes, código de paciente); web modules.js (recordsView), patient-history.js, clinical-labs.js y style.css; pruebas test-doctor-directory (reescrita), test-patient-record (nueva), test-doctor-alerts-history, test-doctor-laboratory y test-preview (temporizadores). Finales de línea de los archivos modificados normalizados al formato del commit (LF).
- **SQL preparado, no aplicado:** supabase/expedientes-historial.sql (amplía tres RPC existentes; sin RLS, GRANT ni datos). [Informe](EXPEDIENTES_2026-11-20.md).
- **Verificaciones ejecutadas:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, test-patient-record, generate-models --check, check-project.py y git diff --check aprobados (simulados). test-clinical-labs sigue fallando, como en d828fd6.
- **Pendiente:** compilación y pruebas Swift (sin Mac), revisión visual en varios iPhone, pruebas reales de aislamiento médico/recepción en Supabase y aplicación de la migración.

## 2026-11-20 — Doctor: abrir consulta a cualquier hora (modo de pruebas)

- **Objetivo:** a petición del usuario, permitir que el médico abra su consulta sin esperar a 30 minutos antes de la cita, para hacer pruebas.
- **Cambios:** `DoctorClinicalRules.openingLeadMinutes` (Swift) y `HospitalCore.doctorClinical.openingLeadMinutes` (JS) = nil/null, sin límite; con 30 se restaura la regla. Las citas canceladas, finalizadas o no asistidas siguen sin abrirse. Si el servidor aún rechaza la apertura por hora, ambos clientes indican que falta `supabase/doctor-start-anytime.sql`.
- **SQL preparado, no aplicado:** `supabase/doctor-start-anytime.sql` (retira solo la condición de 30 minutos de doctor_native_start; se mantienen médico asignado, idempotencia, estados válidos y expediente) y `supabase/doctor-start-restore-30min.sql` (definición original para revertir).
- **Rutas:** Core/{DoctorModels,DoctorViewModel}.swift, Doctor/DoctorConsultationTicketView.swift, DoctorModuleTests.swift, Shared/hospital-core.js, web-preview/modules.js, scripts/test-doctor-clinical-rules.mjs.
- **Verificaciones ejecutadas:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, check-project.py y git diff --check aprobados (simulados).
- **Pendiente:** aplicar el SQL en Supabase (sin él, el servidor sigue rechazando aperturas anticipadas), compilación Swift y revisión visual. Al terminar las pruebas: restaurar 30 minutos en ambos clientes y aplicar el SQL de restauración.

## 2026-11-19 — Doctor: formulario de consulta de seis campos

- **Objetivo:** simplificar ABRIR CONSULTA MÉDICA a peso, altura, temperatura, síntomas, diagnóstico y observaciones, con datos automáticos del paciente y de la cita y un diseño más claro en iOS y web-preview.
- **Backend inspeccionado (solo lectura):** start, save, finish, chart, workspace, native_doctor_encounter, my_consultation_history y patients.patient_code. save sobrescribe todas las columnas de signos vitales y de nota; finish desplegado exige plan.
- **Cambios:** tarjeta del paciente, datos de la cita, síntomas reportados, bloques A Datos físicos / B Evaluación médica / C Servicios adicionales. Se retiraron del formulario presión, frecuencia cardíaca, plan y código diagnóstico; sus valores guardados se reenvían sin cambios. Síntomas → subjective, Diagnóstico → assessment, Observaciones → objective. Si el servidor exige plan, se avisa sin cerrar ni inventar datos. Historial del paciente y del médico con las nuevas etiquetas.
- **Rutas:** iOS Doctor/{DoctorConsultationFormComponents (nuevo),DoctorModuleView,DoctorPatientHistoryView}, Core/{DoctorModels,DoctorViewModel}, DoctorModuleTests; Shared/hospital-core.js; web-preview/{modules,api,doctor-dashboard}.js y style.css; scripts/{test-doctor-preview-live,test-doctor-clinical-rules,test-doctor-alerts-history}.mjs; contracts/doctor-native-v1.json; supabase/doctor-consultation-six-fields.sql (nuevo). [Informe](DOCTOR_FORMULARIO_SEIS_CAMPOS_2026-11-19.md).
- **Verificaciones ejecutadas:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, generate-models --check, check-project.py y git diff --check aprobados (simulados). test-clinical-labs sigue fallando, como en d828fd6.
- **No ejecutado / pendiente:** compilación y pruebas Swift (sin Mac), revisión visual, aplicación de la migración (requiere autorización; sin ella el cierre se bloquea con aviso porque finish exige plan).

## 2026-11-19 — Doctor: flujo completo de consulta (agenda → detalle → consulta A–E → finalización)

- **Objetivo:** que el médico atienda desde su cita hasta cerrar la consulta, con paridad SwiftUI/web-preview y estados Programada → En consulta → Finalizada para médico y paciente. Recepción, panel externo y backend sin cambios.
- **Backend real (MCP solo lectura):** firmas, definiciones y permisos de las 15 RPC doctor_native_* y de my_consultation_history, columnas clínicas, RLS y funciones auxiliares. Hallazgos: vital_signs no tiene frecuencia respiratoria ni SpO₂; save mantiene un solo diagnóstico; workspace no devuelve patient_code ni birth_date; el servidor ordena la agenda por texto de tstzrange; Realtime sin tablas.
- **Cambios:** agenda de 14 días en hora de El Salvador con secciones, contadores, búsqueda y filtro, y orden cronológico garantizado en cliente. Detalle con ABRIR CONSULTA MÉDICA y regla de 30 minutos. Secciones A–E: precarga de lo enviado por el paciente, signos vitales con unidades, rangos del servidor e IMC calculado, cuatro notas obligatorias de finish. SOLICITAR EXÁMENES y RECETAR MEDICAMENTO abren los formularios existentes dentro de la consulta (hoja iOS, panel web); receta con búsqueda, varias líneas y revisión. Estados de guardado, conflicto 40001 que muestra la versión real antes de sobrescribir, aviso al salir con cambios y confirmación de finalización con los textos pedidos y regreso a la agenda. Reglas compartidas Swift DoctorClinicalRules ↔ JS HospitalCore.doctorClinical.
- **Rutas:** iOS Core/{DoctorModels,DoctorViewModel,HospitalAPI,SharedCore,MobileModuleModels}, Doctor/{DoctorModuleView,DoctorConsultationAgendaView,DoctorConsultationTicketView,DoctorDashboardView,DoctorPatientHistoryView}, Patient/{PatientAppointmentFlow,PatientDashboardComponents}, DoctorModuleTests; Shared/hospital-core.js; web-preview/{modules,doctor-dashboard,app,patient-appointments}.js y style.css; scripts/{test-doctor-clinical-rules (nuevo),test-doctor-preview-live,test-patient-dashboard}.mjs. [Informe](DOCTOR_FLUJO_CONSULTA_2026-11-19.md).
- **Verificaciones ejecutadas:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-applicant, generate-models --check, check-project.py y git diff --check aprobados (DOM y transporte simulados, datos sintéticos). test-clinical-labs falla igual que en d828fd6 (previo y ajeno).
- **No ejecutado:** compilación y pruebas Swift (sin SDK Apple; 7 pruebas nuevas preparadas), revisión visual, pruebas de escritura contra Supabase (MCP read_only; backend sin cambios y cubierto por la prueba reversible previa).
- **Pendiente de decisión o migración:** FR/SpO₂, diagnósticos múltiples, patient_code/birth_date en workspace, catálogo de diagnósticos, recetas y órdenes en el historial del paciente. Privacidad: lab_orders legible por recepcionista; vital_signs y prescriptions legibles por cualquier médico tratante y por el paciente con la consulta abierta. Nada aplicado.

## 2026-11-19 — Panel general Doctor y avisos flotantes

- **Solicitud:** evitar nombre repetido, retirar Consultas/Recetas de accesos rápidos y abrir notificaciones en un panel pequeño sin navegar; paridad SwiftUI/web.
- **Interfaz:** cabecera Panel general con una sola campana; saludo único con iniciales; resumen diario con Programadas/Pendientes/Completadas y próxima cita en tarjeta separada. Sin buscador en Inicio. Accesos: Agenda, Pacientes, Laboratorios e Ingresos hospitalarios. Consultas permanece en navegación inferior y Recetas en Más y en la atención.
- **Avisos:** popover anclado a la campana en SwiftUI (incluido iPhone) y panel superpuesto con fondo, cierre exterior/botón/Escape en web. Contador, fecha, leído/sin leer, paginación y actualización; marcar como leído no recarga consulta ni expediente. El modo diseño se identifica y no consulta Supabase.
- **Rutas:** ContentView.swift, DoctorDashboardView.swift, DoctorViewModel.swift; web-preview/{app.js,doctor-dashboard.js,style.css}; scripts/{test-preview,test-doctor-alerts-history,test-doctor-preview-live}.mjs; README y nota Doctor. Cambios anteriores preservados; sin SQL, cambios de permisos ni edición del panel externo.
- **Verificación:** test-preview, test-doctor-alerts-history y test-doctor-preview-live aprobados con DOM/transporte simulado. Nombre único, cuatro accesos, abrir/cerrar sin navegación, lectura de aviso sin recarga de workspace y acceso a Recetas por Más. check-project.py y git diff --check aprobados.
- **Revisión visual real:** navegador local 127.0.0.1:4173, modo diseño Doctor en marco iPhone; inspeccionados saludo único/resumen y panel anclado vacío; cierre devuelve el foco a campana sin cambiar pantalla. No se inició sesión ni se marcaron avisos reales para probar.
- **Pendiente:** compilar/ejecutar SwiftUI en Mac y revisar popover con Dynamic Type/dispositivo. Las pruebas de lectura con avisos usan transporte simulado; no se afirma recorrido autenticado nuevo.


## 2026-11-19 — Auditoría de solo lectura de la base real y diccionario técnico (Claude Code)

- **Objetivo:** inventariar mediante MCP de Supabase la estructura desplegada en `uvebpsbbwofthucghccc`: tablas, columnas, constraints, índices, RLS, RPC, triggers, Edge Functions, migraciones, Realtime, Storage y diferencias con los SQL locales. Relacionar cada objeto con ADMIN, Recepción, Paciente iOS y Médico iOS.
- **Rutas:** nuevo [docs/DICCIONARIO_BD_2026-11-19.md](DICCIONARIO_BD_2026-11-19.md); índice docs/README.md. Sin cambios de código, Swift, web-preview ni SQL.
- **Comprobaciones reales de Supabase (solo SELECT sobre catálogos, sin leer filas clínicas):** 52 tablas en `public`, todas con RLS; 9 enums; 89 RPC SECURITY DEFINER sin EXECUTE para anon; 40 triggers de aplicación (39 en public + 1 en auth.users); 31 migraciones; 1 Edge Function (`manage-employees` v8); Realtime sin tablas publicadas; Storage sin buckets. Advisors de seguridad y rendimiento consultados.
- **Hallazgos (no corregidos, pendientes de decisión del usuario):** (H1) `manage-employees` usa una contraseña temporal constante para todas las altas; (H2) `register_patient` vuelve a ser ejecutable por `authenticated` desde la migración 20261119052813, en contra de AGENTS.md; (H3) `doctor_native_workspace` desplegada no coincide con su migración ni con `supabase/doctor-ios.sql`; (H4) `anon` tiene grants DML en cuatro tablas, que hoy bloquea RLS; (H5) laboratorio solo admin, y `laboratory_authorizations` no se usa en la autorización.
- **No consultable con las herramientas disponibles:** configuración de Auth (`mailer_autoconfirm`, proveedores), secretos de Edge Functions, logs y configuración de Realtime a nivel de proyecto.
- **Verificaciones locales:** test-preview (21 pantallas), check-project.py y git diff --check aprobados. test-core y test-patient-registration no se ejecutaron porque no hubo cambios de Auth ni de backend.
- **Pendientes:** que el usuario decida sobre H1–H5; compilación y revisión visual en Mac no aplican (no hubo cambios de cliente).

## 2026-11-19 — Revisión de continuidad del módulo Doctor (Claude Code)

- **Objetivo:** confirmar dónde quedó la intervención anterior de consulta/avisos/historial y cerrarla sin alterar lo que funciona.
- **Cambios:** solo se retiraron espacios finales en web-preview/app.js:354, que hacían fallar `git diff --check` pese a lo registrado en la entrada anterior. Sin cambios de lógica, Swift, SQL ni Supabase.
- **Revisión estática Swift (no compilada):** símbolos usados por el código nuevo existen (`isValid`, `selectionGeneration`, `patientChart(showPicker:)`, `DoctorAlerts`, stub de pruebas); proyecto en Swift 5. Terminar consulta guarda → recarga → cierra con la versión recargada; un error de guardado detiene el cierre.
- **Supabase real (solo anónimo, sin datos):** check-backend.mjs aprobado. `doctor_native_alerts`, `my_consultation_history`, `doctor_native_start` y `doctor_native_save` existen y responden 401/42501 sin sesión. No hay conexión SQL directa disponible en esta herramienta; no se leyeron tablas.
- **Pruebas ejecutadas:** test-preview, test-core, test-patient-registration, test-doctor-preview-live, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions, test-patient-dashboard, test-attention-navigation, test-applicant, check-project.py y git diff --check aprobados.
- **Fallo conocido:** test-clinical-labs falla en el recorrido "Sesión" (campo `DUI o nombre del paciente` ausente tras entrar a Laboratorios con doctor conectado). Falla igual en el commit d828fd6, por lo que es anterior a esta intervención y a la del 19; queda pendiente de decidir si se actualiza la prueba al módulo conectado.
- **Pendientes:** compilación ⌘R/⌘U en Mac y revisión visual; push para avisos con app cerrada no configurado.


## 2026-11-19 — Doctor: avisos, consulta e historial propio

- **Objetivo:** mejorar Dashboard y consulta con paridad iOS/SwiftUI/web-preview, avisar asignaciones y proximidad, guardar observaciones/medidas/diagnóstico y mostrar historial al paciente.
- **Cambios:** campana/contador y bandeja paginada; avisos cada 30 s; recordatorios locales iOS con permiso; detalle → apertura → En consulta → guardado/cierre → Completada. Formulario en secciones y expediente previo accesible. Historial propio de consultas cerradas con médico, notas y medidas. Se conservan antecedentes y cambios locales previos.
- **Rutas:** Core/{DoctorModels,DoctorRepository,DoctorViewModel,HospitalAPI,HospitalStore}, ContentView, Doctor/{DoctorDashboardView,DoctorModuleView,DoctorConsultationTicketView}, Patient/PatientClinicalView, Shared/hospital-core.js; web-preview/{api,app,modules,doctor-dashboard,clinical-labs,style}; pruebas JS/DoctorModuleTests, contracts/doctor-native-v1.json y dos SQL de migración/prueba reversible. [Informe completo](DOCTOR_CONSULTA_AVISOS_2026-11-19.md).
- **Supabase real:** migraciones doctor_consultation_experience_v1 y patient_completed_consultation_history_v1 aplicadas al proyecto autorizado. El usuario aclaró acceso exclusivo del médico autor y paciente para notas/diagnósticos; RLS ajustada en esas lecturas. Operaciones clínicas/RPC existentes reutilizadas. Sin cambios de registro ni panel externo. Prueba SQL reversible aprobada; aislamiento, deduplicación, historial y cierre comprobados. Cero cuentas temporales posteriores y conteos originales intactos; RPC nuevas no ejecutables por anon.
- **Verificaciones locales:** test-preview, test-core, test-patient-registration, test-doctor-preview-live, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions y test-doctor-alerts-history con DOM/transporte simulado; check-project.py y git diff --check. Prueba Swift preparada, no ejecutada.
- **Límites:** revisión visual bloqueada por fallo del runtime del navegador; Xcode/SDK Apple pendientes. Avisos web en primer plano y recordatorios locales iOS para citas sincronizadas; push para nuevas asignaciones con app cerrada no configurado. Sin commit/push.


## 2026-11-14 — Enlace de configuración pública al bundle iOS

- **Objetivo:** corregir el aviso de configuración pública al ejecutar en Mac aunque Supabase.xcconfig ya contiene los valores.
- **Causa y cambio:** Configuration/App.xcconfig no enlazaba Configuration/Info.plist. Se añade INFOPLIST_FILE para expandir SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY en el bundle, manteniendo GENERATE_INFOPLIST_FILE para las propiedades generadas por Xcode. No se cambian claves ni permisos.
- **Rutas:** HospitalUniversitario/Configuration/App.xcconfig, scripts/check-project.py, README.md y docs/BITACORA.md. El comprobador verifica enlace y placeholders del plist. Web-preview conserva su contrato público ya conectado; sin cambios de funciones en ninguna plataforma.
- **Verificaciones:** test-preview, test-core y test-patient-registration aprobados con transporte simulado; check-project.py y git diff --check aprobados. Sin consultas ni cambios reales a Supabase.
- **Pendiente Mac:** limpiar build, recompilar y confirmar lectura del bundle/inicio de sesión en Xcode. Windows no acredita compilación Apple ni ejecución nativa.

## 2026-11-14 — Corrección de ButtonStyle para Xcode

- **Objetivo:** resolver el error de compilación reportado en Mac: ButtonStyleConfiguration no tiene isEnabled.
- **iOS:** Design/HospitalTheme.swift lee el estado con @Environment(\.isEnabled); conserva la opacidad deshabilitada, la respuesta a pulsación y todos los flujos existentes. Revisados los otros tres ButtonStyle sin encontrar el mismo acceso inválido.
- **Web-preview:** revisado el estilo button:disabled existente; no requiere cambios porque el defecto pertenece a la API SwiftUI. Sin cambios Auth, backend ni funciones de ninguna plataforma.
- **Verificaciones ejecutadas:** test-preview aprobado (21 pantallas, DOM/transporte simulado), python scripts/check-project.py y git diff --check aprobados. Referencias/esquema/configuración iOS revisados; no hay swift ni xcodebuild disponibles en este Windows.
- **Pendiente:** compilar y ejecutar con Xcode 16.2 o posterior en simulador iOS 18.2 o posterior y ejecutar pruebas nativas. La corrección del error reportado no acredita una compilación completa ni un recorrido funcional real en Mac.

## 2026-11-14 — Publicación del estado actual en main

- **Objetivo:** publicar para el equipo todos los commits del estado actual, anteriormente en HEAD separado (31406b4).
- **Git:** unir el historial de origin/main conservando el árbol actual del proyecto, sin restaurar archivos de la integración anterior ni reescribir commits remotos. Actualizar main y publicar mediante push normal.
- **Rutas:** docs/BITACORA.md; sin cambios funcionales en iOS ni web-preview.
- **Verificaciones ejecutadas:** test-preview (21 pantallas), test-core y test-patient-registration aprobados con transporte simulado; python scripts/check-project.py y git diff --check aprobados. No se ejecutaron pruebas reales de Supabase ni compilación/revisión visual Swift; Xcode pendiente de Mac.

## 2026-11-14 — Registro compatible con expediente presencial

- **Inspección puntual:** auth_new_user crea perfil/rol paciente sin paciente ni expediente; DUI único en patients, no en profiles. create_walkin_patient conserva expediente presencial; link_attention_patient exige solicitud, verificación y coincidencia de DUI/nacimiento, e impide reasignación entre cuentas. No hizo falta migración ni cambiar RLS/RPC.
- **Cambios:** Shared/hospital-core.js centraliza metadata Auth permitida y orientación de revisión, excluyendo roles/vínculos del cliente; Core/HospitalStore y Auth/RegisterView usan ese contrato, mensaje seguro y aviso informativo separado de errores en ContentView. web-preview/app.js replica el registro. README, scripts/test-core/test-patient-registration y prueba fuente HospitalUniversitarioTests actualizados. No se editó el panel externo ni se retomó la verificación clínica pendiente de otra intervención.
- **Prueba real:** supabase/test-walkin-account-rollback.sql aprobado: expediente previo → Auth/perfil con mismo DUI → ninguna duplicación/vinculación automática → RLS sin acceso → RPC de recepción confirmada → mismo expediente accesible; otra cuenta rechazada sin reasignación y registro normal conservado. Datos temporales revertidos. Acredita triggers/RPC/RLS, no signup HTTP ni ejecución iOS.
- **Pruebas locales:** test-patient-registration, test-core, test-patient-dashboard y recorridos test-preview importados aprobados con transporte simulado, incluidos orientación genérica, ausencia de consultas por DUI/escrituras clínicas y actualización de vínculo. check-project y git diff --check aprobados; prueba Swift preparada, pendiente Xcode.
- **Condición vigente:** link_attention_patient requiere una solicitud de atención; el registro no crea esa solicitud ni un expediente. Compilación y recorrido real de iOS pendientes de Mac; sin bloqueo de esquema detectado para registrar la cuenta.

## 2026-11-14 — Integridad clínica desplegada; verificación interrumpida

- Autorización explícita recibida. Preflight de trece dependencias/RLS/coherencia aprobado. Respaldo recuperable de ACL y script de restauración en `.local/integrity-backup-2026-11-14.json` y `.local/integrity-restore-2026-11-14.sql`, con huellas de datos previas.
- Aplicada una sola vez `clinical_write_integrity_v1` con BEGIN/COMMIT y límites de espera. Supabase confirmó success=true. Sin DML sobre datos clínicos ni cambios de interfaces.
- La preparación del ejecutor de pruebas falló en JavaScript: SyntaxError Unexpected token '||'. Ocurrió antes de ejecutar herramientas/SQL dentro de esa llamada; no se ejecutaron fixtures ni pruebas de compatibilidad. Se detuvo el trabajo según instrucción del usuario, sin corregir ni reintentar.
- Seguridad y compatibilidad dinámica pendientes. Próximo paso: corregir exclusivamente el ejecutor local y ejecutar pruebas revertidas; no reaplicar la migración.

## 2026-11-13 — Preparación de integridad clínica, sin despliegue

- **Objetivo:** preparar prioridad 1 solicitada, con aprobación explícita antes de migrar. Backend compartido únicamente; interfaces iOS/web-preview/panel intactas en esta intervención.
- **Lecturas reales:** GRANT por tabla/columna, RLS, triggers, funciones escritoras, propietarios y dependencias de clinical_encounters/diagnoses/vital_signs/lab_orders/prescriptions/prescription_items. Cero consultas con enlaces inconsistentes o sin cita. Detectada vía legítima de enfermería para signos vitales; no se propone revocarla indiscriminadamente.
- **Archivos preparados:** supabase/clinical-write-integrity.sql y [nota de riesgos/pruebas pendientes](INTEGRIDAD_CLINICA_PROPUESTA_2026-11-13.md), enlazada en docs/README.md. Borrador mixto: revocación de escrituras directas en cinco tablas, guardia de signos vitales y coherencia de vínculos/entidades padre. Preflight contra deriva de trece funciones. Sin modificación de datos ni ejecución de DDL en Supabase.
- **Compatibilidad/riesgos:** RPC SECURITY DEFINER conservadas, incluido laboratorio y dispensación tras cierre. Clientes externos que hagan INSERT directo deberán usar RPC; panel independiente no accesible. Enfermería no podrá registrar en consultas cerradas. Reasignaciones/fusiones de expedientes con consulta requieren flujo específico.
- **Pendiente:** autorización del usuario para desplegar; pruebas SQL controladas de permisos, enfermería, vínculos, cierre y regresión médica/laboratorio/dispensación. No se anuncian como aprobadas antes del despliegue. No se compiló Swift ni se modificaron interfaces.
- **Verificación local:** test-preview, test-core y test-patient-registration aprobados con transporte simulado; check-project y git diff --check aprobados (avisos LF/CRLF). No validan la ejecución PostgreSQL del borrador; no se instaló parser adicional ni se ejecutó DDL remoto.

## 2026-11-13 — Laboratorios: selección múltiple y resultados publicados iOS/web

- **Objetivo:** completar el flujo médico existente y lectura de resultados por doctor/paciente, conservando el panel externo. [Contrato y catálogo](LABORATORIOS_DOCTOR_2026-11-13.md).
- **Inspección real:** lab_test_types/orders/results, esquemas de parámetros, borradores, RLS, autorizaciones y RPC del panel. El otro proyecto ya incorporó validación/publicación y protección de borradores; se conservaron esas funciones y no se reaplicaron SQL anteriores.
- **Supabase:** desplegada doctor_laboratory_multiple_v1 desde supabase/doctor-laboratory-multiple.sql. code/category en catálogo, request_group en órdenes, tres RPC y helper privado; enriquecida lectura por paciente. Sin nuevas tablas ni ampliación RLS. Agregados seis exámenes ausentes: heces, colesterol total, triglicéridos, creatinina, urea y ácido úrico. Once activos, cero nombres/códigos duplicados. Ningún parámetro/rango clínico inventado.
- **iOS:** Core/DoctorModels/Repository/ViewModel/HospitalAPI, DoctorModuleView y DoctorModuleTests: catálogo, búsqueda, categorías, tarjetas multiselección, resumen/confirmación, envío atómico/reintento, órdenes propias y detalle estructurado. Corregida entrada desde consulta aunque el paciente no esté en primera página del directorio. PatientClinicalView y Shared/hospital-core.js protegen informe no liberado y presentan parámetros autorizados.
- **Web:** api.js/modules.js/style.css y clinical-labs.js replican las funciones reales y estados pastel. Nueva test-doctor-laboratory y ajustes de fixtures/test-core/test-doctor-preview-live. README, contrato e índice actualizados. No se editó el panel externo.
- **Verificación real:** test-laboratory-rollback.sql aprobado: dos exámenes → panel laboratorio → borrador → validación → publicación doctor → publicación paciente; reintento sin duplicar, errores sin filas parciales, aislamiento y protección de no publicados. Fixtures revertidos y cero cuentas temporales posteriores; once esquemas siguen vacíos/sin referencias inventadas. anon sin EXECUTE en RPC nuevas; asesores revisados.
- **Verificación local:** test-doctor-laboratory, test-doctor-preview-live, test-core, test-preview, test-patient-registration, test-patient-dashboard, test-doctor-directory, test-doctor-admissions, test-attention-navigation y check-project aprobados. Transporte JS simulado, fuente Swift preparada no ejecutada. git diff --check aprobado con avisos LF/CRLF.
- **Pendientes:** Xcode/SDK Apple, revisión visual y recorrido HTTPS de clientes; el laboratorio debe validar sus unidades/referencias/parámetros clínicos (el flujo descriptivo funciona). No se anuncia compilación Swift ni operación de la interfaz del panel externo.

## 2026-11-13 — Solicitudes de ingreso hospitalario Doctor iOS/web

- **Objetivo:** solicitar a recepción hospitalización con categoría/prioridad reales y seguimiento. Panel externo de recepción intacto. [Contrato breve](INGRESOS_DOCTOR_2026-11-13.md).
- **iOS:** Core/DoctorModels, DoctorRepository, DoctorViewModel, HospitalAPI, HospitalStore; ContentView, DoctorModuleView, DoctorDashboardView y Shared/screens.json. Selección autorizada por directorio/consulta, identidad real, formulario, confirmación, reintento del mismo envío, listado paginado y detalle de respuesta/asignación. DoctorModuleTests incorpora fuente de prueba del reintento y limpieza de sesión, pendiente Mac.
- **Web:** api.js, modules.js, app.js, doctor-dashboard.js, style.css utilizan las mismas RPC reales y navegación; nueva test-doctor-admissions.mjs y fixture test-preview; check-project actualizado a 21 pantallas. README, contrato e índice actualizados.
- **Supabase real:** inspección de columnas, enum, prioridades, índices, RLS y RPC existentes; migración doctor_admission_requests_v1 desde supabase/doctor-admissions.sql. Reutiliza hospital_admissions y assign_bed; añade clave/decisión, auditoría y cinco RPC para doctor/recepción. Sin nuevas tablas ni ampliación RLS. Primer despliegue rechazado por sintaxis CASE; se confirmó rollback completo, se corrigió y se desplegó correctamente.
- **Verificación:** test-admissions-rollback.sql real aprobado con identidades/espacios reversibles; solicitud, consulta de recepción, disponibilidad, asignación, rechazo, seguimiento, permisos y doble ocupación. Cero cuentas/habitaciones/camas temporales posteriores. anon sin EXECUTE y RLS activa. Asesores revisados. JS simulado: test-doctor-admissions aprobado, incluidos confirmación y reintento tras respuesta perdida; test-preview, test-core, test-patient-registration, test-attention-navigation, test-doctor-preview-live, test-doctor-directory y check-project aprobados. git diff --check aprobado con avisos LF/CRLF.
- **Pendientes:** compilar/ejecutar Swift y pruebas en Xcode; recorrido HTTPS de los clientes con credenciales autorizadas; integrar interfaz del panel externo al contrato. El intento de captura Edge local no acreditó revisión visual; no se anuncia compilación ni revisión visual iOS.

## 2026-11-13 — Directorio de pacientes y laboratorios iOS/web

- **Objetivo:** mejorar ambas pantallas médicas con tarjetas vino/blanco, búsqueda nombre/DUI/correo y acceso al expediente, sin depender de las citas del día.
- **Rutas:** Core/DoctorModels, DoctorRepository, DoctorViewModel, HospitalAPI; Doctor/DoctorModuleView y ContentView; web-preview/api.js, app.js, modules.js, style.css; DoctorModuleTests; scripts/test-preview, test-doctor-preview-live y nuevo test-doctor-directory; contratos y README. [Informe breve](DIRECTORIO_DOCTOR_2026-11-13.md).
- **Supabase real:** desplegada doctor_patient_directory_v1 desde supabase/doctor-patient-directory.sql: directorio paginado, órdenes/resultados por paciente y contacto autorizado en doctor_native_chart. Sin tablas nuevas ni ampliación RLS. Rol/staff y relación asistencial existentes se verifican en servidor. supabase/test-doctor-rollback.sql amplía el recorrido reversible con búsqueda y aislamiento. Prueba SQL aprobada, identidades temporales revertidas; asesores revisados, límites en informe.
- **Verificaciones:** test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation, test-doctor-preview-live y test-doctor-directory aprobados con transporte simulado; check-project aprobado. La nueva prueba nativa es fuente preparada, no ejecutada. Sin modificación del panel administrativo externo.
- **Pendientes:** compilar/probar Swift en Xcode, revisión visual de ambas plataformas y recorrido autenticado HTTPS con cuenta médica. Windows acredita estructura y pruebas JS, no compilación Apple. En web recargar Ctrl+F5 e ingresar como doctor → Pacientes/Laboratorios.
- **Cierre portable:** git diff --check aprobado con avisos LF/CRLF. Comprobación real de privilegios: anon sin EXECUTE en ambas RPC nuevas; authenticated con EXECUTE y validación interna obligatoria. La consulta final de limpieza tuvo un error de transporte del conector; el reintento confirmó cero cuentas temporales doctor-flow restantes, sin efectuar escrituras.

## 2026-11-13 — Réplica Windows del módulo Doctor y sincronización permanente

- **Decisión:** el usuario exige llevar siempre iOS y web-preview de la mano para ver los cambios sin Mac. Se distingue explícitamente la réplica local del panel administrativo/recepción independiente. Preferencia actualizada en AGENTS y README.
- **Rutas/cambios:** web-preview/api.js conecta las operaciones médicas al contrato doctor_native_* y comprueba categoría doctor; modules.js usa los catálogos reales, agenda, expediente, borrador/vitales, laboratorio, recetas con duración y cierre versionado; app.js retira desvíos al diseño local en sesión real y aplica filtros; doctor-dashboard.js replica pendientes/atendidas/próxima cita y cinco accesos. Pruebas: fixture actualizada en test-preview y nueva test-doctor-preview-live. Nota Doctor actualizada. No se modificaron Supabase, tablas, funciones ni panel externo; se conservaron cambios locales previos.
- **Verificación:** test-doctor-preview-live aprobó Dashboard → Agenda → paciente/motivo/síntomas → inicio → borrador → orden/receta → cierre y logout con transporte simulado, sin escrituras reales. test-preview, test-core, test-patient-registration, test-attention-navigation y check-project aprobados. Sintaxis JS y git diff --check aprobados (avisos LF/CRLF).
- **Pendientes:** revisión visual real en navegador y compilación/pruebas nativas en Xcode. Recargar http://127.0.0.1:4173 con Ctrl+F5 e iniciar sesión con cuenta doctor autorizada para probar la conexión real; el modo diseño permanece identificado y aislado de Supabase.

## 2026-11-13 — Módulo Doctor funcional en iOS

- **Objetivo:** implementar la experiencia médica nativa sin editar el proyecto web ni alterar registro, paciente o recepción. Se preservaron cambios locales previos.
- **Inspección:** metadatos reales de clinical_encounters, diagnoses, vitals, laboratorios, recetas, catálogos, personal, citas, restricciones, RLS y funciones. Doctor es user_roles.doctor activo más staff propio activo category=doctor; no hay tabla separada ni catálogo de diagnósticos que se deba inventar.
- **Rutas iOS:** ContentView/HospitalStore/HospitalAPI; Core/DoctorModels, DoctorRepository y DoctorViewModel; Doctor/DoctorDashboardView, DoctorModuleView, DoctorConsultationAgendaView y DoctorConsultationTicketView; DoctorModuleTests. Se retiraron ejemplos de la sesión real, se conectaron agenda y expediente y se agregaron borrador/vitales/diagnóstico, laboratorio, receta y cierre con control de versiones. Contrato Android en contracts/doctor-native-v1.json. README, AGENTS, índice y [nota breve](DOCTOR_IOS_2026-11-13.md).
- **Supabase desplegado:** doctor_native_clinical_flow_v1 desde supabase/doctor-ios.sql: campos de evaluación/versionado en encuentro y duración en ítem de receta; siete RPC autorizadas y guardia de finalización. Se reutilizan tablas, RLS y cambio de estado de citas existentes. Sin nuevas tablas clínicas, cambios Auth o claves administrativas en el cliente.
- **Verificación real:** supabase/test-doctor-rollback.sql aprobado con fixtures en subtransacción revertida: agenda propia, solicitud/síntomas, expediente/antecedentes, borrador, signos vitales, laboratorio/receta y cierre atómico; denegación a paciente/otro doctor/publicación de resultados; idempotencia y consulta cerrada inmutable. La primera aserción de peso se corrigió por escala numeric de Postgres antes de pasar. Cero cuentas/empleados/medicamentos de prueba persistentes; RLS conservada y nuevas RPC sin ejecución anónima. Asesores consultados.
- **Verificación portable:** test-preview, test-core, test-patient-registration, test-attention-navigation y check-project aprobados; regresiones JS con transporte simulado. Contrato JSON validado y git diff --check aprobado (avisos LF/CRLF). DoctorModuleTests preparado, no ejecutado.
- **Pendientes:** SDK Apple/Xcode, pruebas nativas y revisión visual, login HTTPS real y recorrido multirrol en dispositivo. La prueba SQL verifica backend con claims controlados; no equivale a ejecutar la app iOS. No se implementó Android ni se añadieron cambios web en esta intervención.

## 2026-11-13 — Corrección de navegación de Solicitar atención en la réplica Windows

- **Causa comprobada:** ContentView iOS ya priorizaba PatientAttentionLiveView para request/schedule/health. La web que el usuario utiliza en Windows mantenía una interceptación sin patient_id anterior al formulario y un renderizador antiguo de solicitudes vinculadas. Se había excluido la réplica en la intervención previa; el usuario autoriza corregirla ahora, manteniendo excluido el panel externo.
- **Cambios:** web-preview/app.js prioriza las rutas existentes y replica formulario/seguimiento mediante my_attention_context, submit_my_attention_request y my_attention_requests; api.js añade acceso limitado a esas RPC; style.css conserva vino/blanco y adaptación de ancho. Precarga, completado de faltantes, síntomas/Otro, especialidad real con médico, Indiferente, idempotencia y reconciliación de respuesta perdida. Catálogos vacíos o fallo de seguimiento no sustituyen el formulario por el mensaje anterior. Home tiene etiquetas accesibles en sus accesos. En iOS se retiró texto antiguo inalcanzable de la rama clínica y se identificó la vista para accesibilidad, sin otra pantalla paralela.
- **Verificaciones:** nueva test-attention-navigation aprobada con transporte simulado: Home/Salud con/sin expediente, datos precargados, envío único por doble pulsación, síntomas/Otro, estados, catálogos vacíos, recuperación y cierre. Fixtures y regresiones de registro/dashboard actualizadas para reconocer las RPC de lectura que usan POST. test-preview, test-core, test-patient-registration, test-patient-dashboard, check-project y git diff --check aprobados (avisos LF/CRLF). No se modificó Supabase ni el panel de recepción.
- **Ejecución:** README actualizado con recarga Ctrl+F5 en Windows y recompilación ⌘R en Mac. La vista web es una réplica, no un simulador Apple. Pendientes: compilación/pruebas nativas y revisión visual en Mac/navegador; las pruebas DOM no acreditan revisión visual ni envío real de solicitudes.

## 2026-11-13 — Solicitar atención iOS con cuenta sin expediente

- **Alcance autorizado:** solo iOS y cambios mínimos de Hospital Móviles; panel web en otro proyecto y web-preview excluidos por instrucción expresa. Esquema/funciones/RLS/catálogos inspeccionados antes de editar.
- **Cambios iOS:** PatientAttentionLiveView reescrito y nuevo PatientAttentionModel/repository/protocolo; HospitalAPI con RPC explícitas, HospitalStore y ContentView con ruta disponible sin paciente, limpieza por cuenta y actualización del seguimiento/citas. Datos de cuenta automáticos, completado solo de faltantes, síntomas reales múltiples/Otro, especialidades activas con médico, preferencia Indiferente, validación, doble pulsación y reconciliación de respuesta perdida. Pruebas nativas nuevas; README/AGENTS/índice y [contrato breve](ATENCION_IOS_2026-11-13.md).
- **Desplegado:** account_owned_attention_requests y attention_owner_validation. Fuentes SQL nuevas en supabase/: solicitud ligada a cuenta, paciente opcional, snapshot mínimo, síntomas, RLS propia, RPC de envío/seguimiento y de revisión/vinculación de recepción. Se conserva schedule_appointment y su unicidad. Nuevos síntomas maestros autorizados; sin datos clínicos permanentes de prueba ni cambios Auth.
- **Verificaciones reales:** flujo completo SQL con datos controlados en subtransacción revertida aprobado, incluidos aislamiento RLS, rol protegido, idempotencia, suplantación, perfil incompleto y especialidad sin médico. Revisión posterior confirmó cero cuentas/personal de prueba y cero solicitudes persistentes. Primer intento de migración rechazado por identity ALWAYS; se verificó rollback completo y se corrigió el INSERT antes del despliegue aprobado. Asesores revisados; avisos y límites en el contrato.
- **Verificaciones locales:** test-preview, test-core, test-patient-registration, check-project y git diff --check aprobados (avisos LF/CRLF); JS usa transporte simulado y comprueba regresión de la web no modificada. PatientAttentionTests preparado, no ejecutado. git diff confirma ausencia de cambios en web-preview.
- **Pendientes:** compilar/probar Swift e interfaz en Mac, recorrido autenticado HTTPS de iOS y conexión del panel externo al contrato. La prueba SQL acredita backend, no ejecución de iOS ni del panel.

## 2026-11-13 — Dashboard de paciente sin bloqueo por expediente

- **Objetivo:** recuperar el Home iOS y reflejarlo en web para cuentas de paciente con o sin vínculo clínico.
- **Cambios:** PatientDashboardView/Components (saludo real, tarjeta vino con próxima cita, cuatro accesos, carga/error/vacío); ContentView (portal sin pantalla bloqueante y orientación de recepción); HospitalStore/HospitalAPI (datos de Home); hospital-core.js (acceso de cuenta separado del vínculo, planes clínicos vacíos sin paciente y próxima cita propia); MobileModuleViewModel y modules.js (limpieza al cambiar vínculo); app.js/style.css; suites core/preview/registro/dashboard y prueba Swift. README, AGENTS e índice actualizados. [Nota breve](DASHBOARD_CUENTA_2026-11-13.md).
- **Verificaciones:** test-preview, test-core, test-patient-registration y test-patient-dashboard aprobados con transporte simulado para los cuatro accesos, cuentas con/sin vínculo, nombre real compuesto, filtros propios, cero escrituras clínicas, errores/reintento, cambio de vínculo y cierre. check-project y git diff --check aprobados (avisos LF/CRLF). Consulta real exclusivamente de metadatos para relaciones appointments/staff/profiles. Sin cambios remotos ni cuentas de prueba.
- **Pendientes:** compilación/pruebas Swift en Mac, revisión visual y recorrido autenticado real. El nombre del médico solo se muestra si RLS lo publica; si no, código real de empleado o dato no disponible. Registro conserva alta solo de cuenta; recepción gestiona expediente/citas.

## 2026-11-13 — Registro solo de cuenta y sin confirmación de correo

- **Objetivo:** aplicar la decisión explícita de que el usuario solo se registre en la app y recepción gestione expediente/citas, sin confirmación de correo.
- **Implementación iOS/web:** retiradas llamadas y métodos de alta clínica; núcleo compartido rechaza esa operación. Estado Cuenta registrada con actualizar/cerrar sesión, sin completar expediente. DUI declarado en metadatos sin autorización ni vinculación automática. Regresión JS y prueba nativa actualizadas; README, AGENTS, transición e índice actualizados. [Informe, rutas y límites](REGISTRO_SOLO_CUENTA_2026-11-13.md).
- **Supabase real:** aplicada migración `disable_patient_self_enrollment` que revoca EXECUTE de register_patient para PUBLIC/anon/authenticated. Privilegios posteriores verificados; RPC de recepción conservadas. HTTPS confirma registro habilitado y `mailer_autoconfirm=true`; se observó el ajuste efectivo, no se modificó Auth mediante el conector. Sin cuentas/pacientes/citas de prueba ni cambios de RLS.
- **Verificaciones:** test-core, test-preview, test-patient-registration y check-project aprobados; pruebas JS con transporte simulado. Se corrigieron eventos/selectores de la regresión de solicitudes antes de aprobarla. Asesores consultados, avisos ajenos al alcance registrados en informe. Comprobación HTTPS real repetida con aserción de correo desactivado aprobada. Sintaxis de app.js/api.js y git diff --check aprobados.
- **Pendientes:** compilación/pruebas Swift y revisión visual en Mac; registro autenticado real y gestión/vinculación desde recepción con identidad autorizada. La prueba nativa es fuente preparada, no ejecutada en Windows.

## 2026-11-13 — Verificación de conexión exclusiva a Hospital Móviles

- **Objetivo:** revisar iOS/web, retirar restos del backend sustituido y verificar la nueva conexión.
- **Cambios:** URL exacta y clave publicable exigidas en `Core/SharedCore.swift` y `web-preview/api.js`; regresión en `scripts/test-core.mjs` y cotejo iOS/web en `scripts/check-project.py`. Retirados nueve scripts de transición de un solo uso y el JSON del diccionario anterior; manifiesto actualizado. README e índice actualizados; [informe de revisión](REVISION_CONEXION_2026-11-13.md). Se preservaron cambios locales anteriores y referencias visuales.
- **Verificaciones:** conector Supabase confirma Hospital Móviles activo; HTTPS real confirma Auth 200, correo obligatorio y rechazo anónimo 401 en perfiles/pacientes/roles. Primer intento de red bloqueado por sandbox; repetición autorizada aprobada. test-core, test-preview, test-patient-registration, generate-models --check y check-project aprobados. Las pruebas JS usan transporte simulado. `git diff --check` aprobado con la configuración vigente y avisos LF/CRLF; una comprobación adicional con autocrlf desactivado interpreta los CRLF como espacios y no se usa como resultado del proyecto. Sin dominio ni RPC antiguos en iOS/web/scripts.
- **Pendientes:** compilar y probar Swift en Mac, revisar interfaz y recorrer registro/login con una identidad autorizada. Operaciones clínicas pendientes enumeradas en la transición. No se crearon cuentas/pacientes ni se modificaron esquema, permisos o Auth. La disponibilidad de la conexión no acredita todos los módulos.

## 2026-11-13 — Diagnóstico de transición a Hospital Móviles

- **Objetivo:** analizar el reemplazo del backend anterior manteniendo SwiftUI y web en paralelo, antes de implementarlo.
- **Hallazgos:** nuevo proyecto activo; estructura y RPC incompatibles con los contratos actuales. Web conserva URL/CSP anteriores; iOS requiere configuración local independiente, ausente en esta copia. [Informe y pasos necesarios](ANALISIS_HOSPITAL_MOVILES_2026-11-13.md).
- **Rutas modificadas:** solo este registro, `docs/README.md` e informe nuevo. Se preservaron cambios locales anteriores; no se cambió la conexión ni Supabase.
- **Verificaciones:** test-preview aprobado (ocho recorridos/veinte pantallas, transporte simulado), check-project aprobado y git diff --check aprobado con avisos LF/CRLF. Listados y SELECT de metadatos reales del proyecto nuevo; sin escrituras ni autenticación de prueba.
- **Pendientes:** adaptar contratos/modelos/repositorios en ambas plataformas, configurar nuevo destino y sesiones, validar acceso real y compilar/probar en Mac. No se ejecutó Xcode ni revisión visual.

## 2026-11-12 — Último bloqueo: atención sin expediente

- **Resultado:** consultas reales de solo lectura de funciones, columnas, FK/CHECK y políticas confirman que el registro no admite atención y las operaciones de atención exigen paciente o crean uno desde Recepción. No se modificó la aplicación, Supabase, permisos ni datos persistentes.
- **Cambios mínimos:** [contrato de dos RPC](CONTRATO_ATENCION_SIN_EXPEDIENTE.md), reutilizando `registration_requests` y proponiendo ampliar `appointment_requests`, sin tablas paralelas; aviso de superación en propuesta/borrador históricos e índice. Añadida regresión pendiente/rechazado en `scripts/test-patient-registration.mjs`: sin acceso clínico, llamadas inexistentes ni creación indirecta de expediente.
- **Verificación actual:** las 14 suites JS sin efectos externos aprobadas; `generate-models --check`, `python scripts/check-project.py` y `git diff --check` aprobados. SQL real únicamente de metadatos; ninguna escritura probada. Sin Xcode ni revisión visual nueva.
- **Pendiente:** backend debe acordar/autorizar ampliación y desplegar las dos RPC y adaptación de Recepción del contrato; después integrar ambos clientes y comprobar persistencia en entorno autorizado. Registro/login/citas actuales se conservan.

## 2026-11-12 — Registro funcional y solicitudes reales del Paciente

- **Objetivo:** implementar lo permitido por el backend existente sin modificar Supabase ni crear datos persistentes de prueba. Recuperación previa en `.local/patient-functional-backup/`; se preservaron cambios anteriores.
- **Implementación iOS/web:** Auth signup, sedes públicas, envío de nombres/apellidos/DUI/nacimiento/teléfono a `submit_patient_registration`; pantalla y estado propio mediante `my_access`, recuperación de sesión pendiente y reintento tras fallo parcial sin duplicar Auth. Sin creación de persona/expediente desde el registro. Atención para pacientes vinculados con `request_appointment` y lectura `mobile_module('request')`; se mantienen separados de citas. Retirados fallbacks a ejemplos en citas/recetas/historial reales, con vacíos y errores; diseño explícito conservado.
- **Rutas:** `Auth/RegisterView.swift`, `Core/{HospitalAPI,HospitalStore}.swift`, `ContentView.swift`, `Shared/hospital-core.js`, `Patient/{PatientAttentionLiveView,PatientAppointmentFlow,PatientDashboardComponents,PatientPrescriptionsView}.swift`; `web-preview/{api,app,patient-appointments,patient-prescriptions}.js`; nueva suite `scripts/test-patient-registration.mjs`, nuevo `scripts/check-registration-backend.mjs`, ajustes en seis suites de regresión y reglas de Applicant, pruebas nativas de Applicant y comprobación CRLF en `generate-models.mjs`; README e índice. [Informe completo](PACIENTE_REGISTRO_FUNCIONAL_2026-11-12.md).
- **Pruebas locales:** las 14 suites JS disponibles sin efectos externos aprobadas, incluyendo registro válido/inválido, doble envío, fallo parcial, reintento, restauración, estados, permisos/red, solicitud con paciente y aislamiento de ejemplos. Sintaxis JS, check-project y diff --check. `generate-models --check` inicialmente detectó únicamente CRLF/LF; equivalencia normalizada comprobada y herramienta corregida.
- **Comprobaciones reales:** SELECT de columnas, FK/CHECK/índices/permisos/RLS/trigger Auth y definiciones de RPC. HTTPS público 200: registro habilitado, email habilitado/autoconfirmado y una sede. Primera salida de red bloqueada por sandbox; repetición autorizada aprobada. Ninguna escritura, alta Auth, aprobación, migración, modificación de permisos o inscripción MFA.
- **Bloqueos/límites:** registro y solicitudes implementados pero pendientes de prueba real de persistencia y recorrido iOS. Solicitud/consulta de atención sin expediente bloqueada por falta de contrato autorizado; `registration_requests` es alta/vinculación revisada, no atención. No se ejecutó Xcode ni revisión visual en navegador. Pruebas nativas añadidas, pendientes de Mac. Las pruebas históricas no se atribuyen a esta intervención.

## 2026-11-12 — Verificación del diccionario de datos

- **Objetivo:** contrastar el diccionario del informe con el esquema real, sin ampliar el trabajo al módulo Paciente del adjunto.
- **Cambios:** advertencia histórica en `Informe_Hospital_Universitario.md`; informe `REVISION_DICCIONARIO_2026-11-12.md`, instantánea `diccionario-metadatos-2026-11-12.json`, diferencias `diccionario-diferencias-2026-11-12.json` e índice `docs/README.md`. Se conservan los cambios anteriores.
- **Verificaciones:** SELECT reales de metadatos en Supabase y cotejo Python: 91 tablas documentadas frente a 93 actuales; 819 columnas cotejadas en las tablas documentadas; faltan dos tablas, dos columnas y cuatro CHECK. Sin lecturas clínicas ni escrituras remotas. No hubo cambios visuales o funcionales ni compilación Swift.
- **Pendientes:** políticas, privilegios, triggers, índices y RPC equivalentes de registro requieren revisión independiente. [Detalle y evidencia](REVISION_DICCIONARIO_2026-11-12.md).

## 2026-11-12 - Frontend del solicitante sin expediente (iOS y web, sin conexión)

- **Solicitud:** implementar en local la fecha de nacimiento, el DUI con formato, la pantalla de datos personales, la navegación del solicitante, la solicitud sin cita y los estados visuales, con SwiftUI y `web-preview/` sincronizados. Sin cambios en Supabase, migraciones, Auth ni permisos.
- **Decisiones:** reglas y estados en `Shared/hospital-core.js` para iOS y web; `scheduled` solo derivado; registro sin confirmación de correo; el borrador SQL permanece separado y no aplicado.
- **Cambios:** `Shared/hospital-core.js`; iOS: `Applicant/ApplicantRules.swift`, `Applicant/ApplicantDemoStore.swift`, `Applicant/ApplicantDemoView.swift`, `Auth/RegisterView.swift` (reescrito), `ContentView.swift`, `HospitalUniversitarioTests/ApplicantRulesTests.swift`; web: `web-preview/applicant.js`, `app.js`, `index.html`, `server.mjs`, `style.css`, `scripts/test-preview.mjs`; nuevo `scripts/test-applicant.mjs`; documentación `docs/APLICANTE_FRONTEND_2026-11-12.md`, `README.md`, índice.
- **Verificaciones ejecutadas:** `scripts/test-applicant.mjs` aprobada; `scripts/test-core.mjs` aprobada; `test-preview`, `test-patient-appointments`, `test-modules`, `test-doctor-*`, `test-clinical-labs`, `test-patient-*`, `test-profile` y `test-account-tools` aprobadas; `node --check` de `applicant.js` y `app.js`; `python scripts/check-project.py` aprobado; `git diff --check` sin errores.
- **No verificado:** compilación SwiftUI y `ApplicantRulesTests` (sin Xcode en Windows); revisión visual; `test-account-codes` falla por falta de `.local/test-accounts.json` (entorno, no relacionado).
- **Bloqueos:** decisión E (código real del rol de recepción) y decisión F (definición real de `period_bounds`) requieren consultas de solo lectura en Supabase que no pude ejecutar. El frontend no usa ningún código de rol ni muestra horas.
- **Pendientes:** consultas de la sección 10 de la propuesta; autorización de la migración; conexión del registro y las solicitudes con bandera de configuración; `my_attention_requests()` (decisión C); compilación en Mac.

## 2026-11-12 - Borrador de migración y pruebas del solicitante (no aplicado)

- **Solicitud:** preparar el borrador SQL y las pruebas de la solicitud de atención sin expediente, sin ejecutar migraciones ni modificar Supabase.
- **Decisiones aplicadas:** `attention.verify` solo para `reception`; activación de cuenta y expediente en una sola transacción; `link_existing_patient` solo con conflicto de DUI y coincidencia verificada; `applicant_session()` separado de `session_active()`; la solicitud nunca crea cita.
- **Cambios:** `docs/sql/drafts/applicant-flow.DRAFT.sql` (tablas, funciones, wrappers y permisos con verificación previa que aborta), `docs/sql/drafts/test-applicant-flow.DRAFT.sql` (18 pruebas con rollback), y la sección 15 de `docs/PROPUESTA_REGISTRO_SOLICITUD_2026-11-12.md` con las respuestas a los seis puntos de revisión.
- **Verificaciones:** ninguna ejecutada contra Supabase ni en PostgreSQL local. Las firmas de `has_permission`, `session_active`, `register_patient`, `link_patient_account` y la numeración de expedientes siguen sin confirmar.
- **Pendientes y bloqueos:** función de numeración `private.next_medical_record_number()` (no existe en el repositorio); código de rol de recepción; columnas de `idempotency_keys`; horarios AM/PM; decisiones A–F de la sección 15.10; confirmación de firmas con las consultas de solo lectura de la sección 10.

## 2026-11-12 - Revisión 2 de la propuesta: registro sin verificación de correo

- **Decisiones:** se mantiene `mailer_autoconfirm = true` y el registro público; sin pantallas ni reenvío de confirmación; el solicitante entra sin `active`; DUI no vincula cuentas automáticamente; los módulos clínicos conservan `session_active()` y `my_access`.
- **Cambios:** `docs/PROPUESTA_REGISTRO_SOLICITUD_2026-11-12.md` reescrito con control `applicant_session()` solo para RPC del solicitante, tabla mínima `applicant_declarations` para el DUI declarado, RPC de recepción sin vinculación automática y consultas de solo lectura actualizadas.
- **Verificaciones:** `GET /auth/v1/settings` confirma la configuración que exigen las decisiones (sin cambios necesarios). Firmas y permisos de RPC siguen sin verificarse. No se ejecutaron migraciones ni cambios de configuración.
- **Pendientes:** decisiones de la sección 13 del documento; ejecución de las consultas de solo lectura; autorización de la migración.

## 2026-11-12 - Propuesta de registro y solicitud de atención sin expediente (Fases 0 y 1)

- **Solicitud:** diagnóstico y propuesta para que una persona se registre, confirme su correo, solicite atención sin expediente y que recepción (Android) verifique, cree o vincule el expediente y agende. Sin cambios de código, base de datos ni configuración.
- **Decisiones registradas:** registro en iOS sin expediente; confirmación de correo; solicitud sin cita automática; estado visible para el paciente; pacientes con expediente sin cambios.
- **Verificaciones realizadas:** `GET /auth/v1/settings` con la clave publicable: `disable_signup: false` (registro público activo) y `mailer_autoconfirm: true` (correo confirmado automáticamente). `GET /rest/v1/` exige clave secreta: **no se pudieron leer firmas ni permisos de RPC**. `git status` limpio antes de escribir el documento.
- **Cambios:** nuevo `docs/PROPUESTA_REGISTRO_SOLICITUD_2026-11-12.md`; esta entrada; enlace en `docs/README.md`.
- **Pendientes y bloqueos:** ejecutar las consultas de solo lectura de la sección 9 del informe para confirmar cuerpos de `request_appointment`, `my_access`, `can_person`, `register_patient`, trigger de Auth y permisos. Decisiones de la sección 8 pendientes de autorización. No se implementó nada; no se ejecutaron pruebas de app porque no hubo cambios funcionales.

## 2026-10-30 - Dashboard del paciente

- **Solicitud:** rediseñar el inicio del rol Paciente en SwiftUI, con la captura `Captura de pantalla 2026-10-30 133626.png` como referencia de estructura (saludo con avatar, card de próxima cita, cuatro accesos rápidos) pero con la paleta vino/rojo del proyecto, conservando la barra inferior y la navegación existentes, y replicándolo en la web por la convención vigente.
- **Cambios Swift:** nuevos `Design/HospitalPalette.swift` (extension `Color`: vinoPrincipal, rojoAcento, fondoCard, fondoApp y `LinearGradient.vinoDestacado`), `Patient/PatientDashboardComponents.swift` (cards de saludo, fecha/cita y acceso rápido con estado al presionar) y `Patient/PatientDashboardView.swift` (vista principal, modelo `ProximaCita` y `#Preview` con «Gaby Diaz»). En `ContentView.swift` el `case "home"` ahora bifurca: médico conserva su home anterior y paciente usa el dashboard; se pasa `store.name` o el ejemplo, y `proximaCita: nil` hasta existir el modelo de citas.
- **Cambios web:** `web-preview/app.js` (rama del paciente de `home()` derivada a `patientDashboard()`, con nombre real o de ejemplo y cita de ejemplo en modo diseño) y `web-preview/style.css` (reglas `.dash-*`, CRLF normalizado). Home del médico intacto.
- **Sin cambios de lógica:** encabezado, barra inferior, `go()`, `store`, catálogo y llamadas a datos permanecen igual; sin escrituras ni API nuevas; el ID de «Agendar cita» es el `request` existente.
- **Verificaciones ejecutadas:** `node --check web-preview/app.js` aprobado; `scripts/test-preview.mjs` con 8 recorridos DOM aprobados (incluido diseño patient sobre el nuevo home); `python scripts/check-project.py` aprobado; `git diff --check` aprobado.
- **Limites y pendientes:** no se compiló Swift en Windows; compilación y revisión visual en Mac siguen pendientes. `proximaCita` queda parametrizado sin datos reales; el nuevo home del paciente ya no muestra las métricas del resumen.
- **Informe:** [DASHBOARD_PACIENTE_2026-10-30.md](DASHBOARD_PACIENTE_2026-10-30.md).

## 2026-10-30 - Convención: todo cambio visible también en la web

- **Solicitud:** el usuario pide que todo el trabajo quede reflejado en la vista previa web para verlo en Windows, y que a la vez funcione bien al compilarlo en Xcode/Mac.
- **Decision:** se establece la convención de implementación por duplicado y coherente: iOS/SwiftUI como fuente de verdad y `web-preview/` como réplica visual, conservando la lógica existente en ambas plataformas y ejecutando las pruebas locales tras cada cambio. Queda registrada en `AGENTS.md` (Decisiones vigentes) para que la sigan las sesiones futuras.
- **Rutas:** `AGENTS.md` y esta bitácora. No se modifico codigo de app ni web en esta entrada.
- **Verificacion ejecutada:** `git diff --check` aprobado. No se ejecutaron pruebas de app porque no hubo cambios funcionales.
- **Pendiente:** la compilacion Swift en Mac sigue pendiente, como en las entradas anteriores.

## 2026-10-30 - Rediseño visual de login y nueva pantalla de registro

- **Solicitud:** rediseñar la pantalla de login existente (sin pantalla nueva de login y sin tocar su lógica) usando `docs/design-reference/` como base visual, y crear la pantalla de registro con los campos nombres, apellidos, DUI, edad, teléfono, correo, contraseña y confirmar contraseña, en Swift/SwiftUI para Xcode.
- **Decisiones del usuario:** mantener los ocho campos aunque el diccionario no tenga DUI ni edad (se usan 9 dígitos `0000-00000` y entero 1–120), y dejar el registro **a nivel de diseño, sin registrar en la base de datos**.
- **Diccionario:** `persons.given_names`/`family_names` (1–100) y teléfono en `person_contacts` (`update_my_phone`) coinciden; DUI no existe en ninguna tabla y la edad no se almacena (ambigüedad S04: `birth_date`).
- **Cambios:** `Design/HospitalTheme.swift` (componentes HospitalAuthHeader/InputField/SecureField/PrimaryButtonStyle/Notice/Link); `ContentView.swift` (solo composición de `login`, enlaces «¿Olvidaste tu contraseña?» y «Regístrate», estados de presentación y rama hacia el registro); archivo nuevo `Auth/RegisterView.swift` con los ocho campos, iconos mostrar/ocultar en ambas contraseñas y validación local. El archivo nuevo entra al target por el grupo sincronizado; no se tocó `project.pbxproj`.
- **Réplica web (decisión posterior del usuario):** al ejecutar `web-preview/server.mjs` no se veían los cambios Swift, porque la vista previa es otra implementación. Se replicó el mismo diseño en `web-preview/app.js` (helpers `authHeader`/`authField`/`revealButton`, `renderLogin` con la misma lógica de envío e IDs, y `renderRegister` con los ocho campos y validación local sin llamadas a API) y se añadieron las reglas `.auth-*` al final de `web-preview/style.css` (CRLF normalizado).
- **Sin cambios de lógica:** la llamada `store.signIn` y su condición de deshabilitado quedaron idénticas en iOS; en web, el manejador de envío del login (`api.signIn`, `resolve`, `load`) y `api.js` intactos. `HospitalStore`, `HospitalAPI`, modelos, rutas, sesión y Supabase no se modificaron ni se ejecutó ninguna operación sobre la base.
- **Verificaciones ejecutadas:** `python scripts/check-project.py` aprobado; `git diff --check` aprobado; `scripts/test-preview.mjs` con 8 recorridos DOM aprobados tras el cambio web; `node --check web-preview/app.js` aprobado; revisión directa de `screen-01.png`/`screen-03.png` e `inventory.json` (ninguna referencia es login/registro); búsqueda literal de DUI sin resultados en el diccionario.
- **Limites y pendientes:** no se compiló Swift en Windows (sin SDK de Apple); compilación y revisión visual en Mac siguen pendientes. El registro no crea cuentas: en el modelo real el administrador crea y activa, y el trigger deja los perfiles `pending`.
- **Informe:** [REDISENO_AUTH_2026-10-30.md](REDISENO_AUTH_2026-10-30.md).

## 2026-10-28 - Retirada de MFA por solicitud expresa

- **Decision:** el usuario indica que su proyecto no requiere MFA y solicita retirarlo. Sustituye la decision previa para los roles moviles doctor/patient; no autoriza cambios a administracion ni elimina factores existentes.
- **Implementacion:** retirados desafio, vistas, metodos y estado TOTP de web/iOS; retirado bloqueo AAL2 del Doctor y texto MFA en errores. SQL aplicado al auxiliar de sesion existente: cuentas exclusivamente doctor/patient usan contrasena, con identidad, perfil activo y sesion vigente. Otros roles conservan condicion MFA anterior. No se cambiaron RLS, ACL, contrasenas, factores ni vinculos.
- **Rutas:** web-preview/{app,api,modules}.js; ContentView.swift; Core/{HospitalStore,HospitalAPI,ScreenCatalog,DoctorViewModel}.swift; scripts/{test-preview,test-modules}.mjs; docs/sql/{mobile-password-access,mobile-modules,test-mobile-flows}.sql; README e indice documental.
- **Verificacion real:** prueba transaccional SQL con claims AAL1 aprobada, incluyendo flujos clinicos y rechazos por rol, vinculo, version, estado cerrado y sesion expirada; ROLLBACK sin fixtures permanentes. No representa login Auth real ni compilacion de Xcode.
- **Verificaciones locales:** ocho recorridos DOM base y siete funcionales aprobados, incluyendo dashboard AAL1 sin factores, suspension y aislamiento del modo de diseno; comprobacion portable Xcode aprobada. El asesor de seguridad conserva los seis INFO del esquema historico y el WARN previo de proteccion de contrasenas filtradas, sin nuevos avisos. Pendientes: compilacion/pruebas nativas en Mac y login HTTPS con credenciales reales.
- **Informe:** [ACCESO_SIN_MFA_2026-10-28.md](ACCESO_SIN_MFA_2026-10-28.md).
- **Comprobacion final:** scripts/check-backend.mjs confirma catalogo publico HTTP 200 y ocho RPC protegidas HTTP 401 anonimas; git diff --check aprobado y editor sin errores en archivos revisados. Se recargo la pestana compartida hasta login. scripts/test-real-login.mjs actualizado al contrato sin MFA, con sintaxis validada pero sin ejecutarlo por falta de credenciales locales; ya no permite inscribir factores ni acepta 403 como resultado esperado de resumen. Prueba SQL ampliada con dashboard AAL1 y rol revocado: aprobada con ROLLBACK.

## 2026-10-28 - Diagnostico del acceso del medico sin MFA

- **Reporte:** mensaje generico de autorizacion al abrir el modulo del medico.
- **Diagnostico:** consulta agregada real a Auth: dos cuentas y ninguna con factor MFA verificado. El dashboard invocaba doctor_workspace con AAL1, aunque exige AAL2. No se inspeccionaron contrasenas ni secretos.
- **Cambios:** web muestra verificacion pendiente sin solicitar datos clinicos en AAL1, con acceso a notificaciones y perfil; iOS evita cargar el dashboard clinico y presenta el requisito especifico. Se mantiene la verificacion existente al ingresar cuando hay un factor inscrito.
- **Rutas:** web-preview/modules.js, Core/DoctorViewModel.swift, Core/HospitalStore.swift, scripts/test-preview.mjs y scripts/test-modules.mjs.
- **Seguridad:** no se alteraron RLS, RPC, permisos, cuentas ni factores. La inscripcion TOTP sigue pendiente de autorizacion explicita. Una sesion AAL2 aun requiere perfil, permisos y vinculos validos.
- **Verificaciones:** scripts/test-modules.mjs aprobado: ocho recorridos previos, seis funcionales y una regresion nueva del medico sin MFA, todos con transporte simulado. scripts/check-project.py y git diff --check aprobados. No se compila con Xcode en Windows ni se afirma login real del medico: la pestana compartida estaba en login con Failed to fetch.

Cada IA que modifique el proyecto debe añadir una entrada con fecha, objetivo, rutas afectadas, verificaciones ejecutadas y pendientes. No incluir credenciales ni secretos. Las instrucciones completas están en `../AGENTS.md`.

## 2026-10-28 - Modulos funcionales de Medico y Paciente en iOS y web

- **Solicitud:** sustituir el aviso de entrega posterior por flujos funcionales, basados en `docs/Informe_Hospital_Universitario.md` aportado por el usuario. Se continuo con ambos roles y la vista previa existente; no se incorporaron administracion ni otros roles.
- **Cambios:** listas/detalles paginados, solicitudes y cancelacion de citas propias, expediente/historial, recetas y resultados publicados del Paciente; receta atomica multirrenglon del Medico, diagnostico por catalogo, conservacion de borradores/versiones, confirmacion de jornadas, perfil/contacto/preferencias y documentos autorizados. Se elimino el scaffold clinico y se integro el transporte real en la web. La autenticacion compartida anterior se conserva.
- **Backend real:** se instalaron las cinco RPC nuevas de las dos propuestas SQL y eventos de notificacion. Se reutilizaron tablas, RPC y RLS existentes. Las pruebas revelaron y corrigieron acceso indebido al esquema auth desde hospital_api, necesidad de SET LOCAL ROLE para reaplicar funciones y mapeo de conflictos PT409. No se cambiaron credenciales, factores MFA, politicas ni privilegios permanentes; CREATE temporal se revoca antes de commit. Los eventos nuevos limitan destinatarios a los roles adecuados.
- **Rutas:** `HospitalUniversitario/HospitalUniversitario/Core/MobileModule{Models,Repository,ViewModel}.swift`, `Modules/MobileModuleView.swift`, archivos del Doctor y su repositorio/modelos, `ContentView.swift`, `Core/HospitalStore.swift`, pruebas Swift de Doctor y MobileModule, `web-preview/{modules,api,app}.js`, `index.html`, `style.css`, `server.mjs`, `.vscode/tasks.json`, `scripts/{test-modules,test-preview,check-backend}.mjs`, `docs/sql/{doctor-module,mobile-modules,test-mobile-flows}.sql`, informe nuevo, README e indice. El informe aportado por el usuario no se modifico.
- **Verificaciones locales:** 11 pruebas del nucleo, 8 recorridos DOM previos adaptados y 6 nuevos recorridos funcionales. Se reforzo el doble DOM tras detectar en navegador que textarea.type es de solo lectura. Comprobaciones de sintaxis JS, referencias portables Xcode, diagnosticos del editor y git diff --check.
- **Verificaciones en servidor:** flujos positivos y negativos en PostgreSQL con sesiones/claims y datos transitorios, siempre ROLLBACK; idempotencia de solicitud/orden/receta, versiones, roles, MFA y atencion cerrada. Luego se desplegaron definiciones sin fixtures y se comprobaron RPC presentes, rol sin BYPASSRLS y ausencia de catalogos de prueba. HTTPS anonimo: catalogo 200 y ocho endpoints protegidos 401. Asesor de seguridad sin avisos nuevos, conservando los siete preexistentes.
- **Verificacion web:** servidor local iniciado en 4173, recursos 200, documento sin sesion 403 y credenciales fuera del servidor 404. Recorrido de receta del componente con repositorio simulado en Playwright; una emision y sin desbordamiento medido en 1280x900/390x844. No se acredita igualdad visual con todas las referencias ni login real por ese recorrido.
- **Pendientes y limites:** no hay credenciales locales en esta copia; no se ejecuto login HTTPS real ni se inscribio TOTP. Los catalogos institucionales de medicamentos/estudios estan vacios y no se rellenaron con ejemplos. Falta compilar/probar en Mac, resolver SPM/lockfile, validar documentos reales y completar el recorrido con sesiones/MFA autorizadas. Las pruebas SQL con claims simulados no equivalen a Supabase Auth real.
- **Informe actual:** [MODULOS_FUNCIONALES_2026-10-28.md](MODULOS_FUNCIONALES_2026-10-28.md).

## 2026-10-28 - Modulo Doctor iOS conectado y propuesta SQL

- **Objetivo:** implementar consultas, ordenes de laboratorio, expediente/historial, dashboard y notificaciones del Doctor respetando la estructura SwiftUI existente.
- **Implementacion:** modelos Codable, repositorio async/await con supabase-swift 2.28.0, ObservableObject y vistas integradas en la navegacion actual. Sesion/MFA migradas al SDK compartido; configuracion iOS por xcconfig local ignorado e Info.plist. El flujo Paciente comparte esta capa de autenticacion, sin nuevas operaciones clinicas. La web no se amplio.
- **Rutas:** `HospitalUniversitario/HospitalUniversitario/Core/{DoctorModels,DoctorRepository,DoctorViewModel,HospitalAPI,HospitalStore,SharedCore}.swift`, `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift`, `HospitalUniversitario/HospitalUniversitario/ContentView.swift`, `HospitalUniversitario/HospitalUniversitarioTests/DoctorModuleTests.swift`, `HospitalUniversitario/Configuration/`, `HospitalUniversitario/HospitalUniversitario.xcodeproj/project.pbxproj`, `.gitignore`, `docs/sql/doctor-module.sql`, `README.md`, `docs/README.md` y esta bitacora.
- **Backend:** se inspeccionaron metadatos, permisos y funciones reales. La propuesta reutiliza tablas/RPC/RLS y agrega tres funciones de modulo y eventos de notificacion. Se probo la creacion, denegaciones sin sesion y ACL en una transaccion con ROLLBACK; se confirmo que las funciones nuevas no quedaron instaladas. Las consultas de proyeccion se comprobaron con IDs nulos en otra transaccion revertida. No se generaron registros clinicos ni se inscribio MFA; no se relajaron politicas.
- **Pruebas locales ejecutadas:** 11 pruebas existentes del nucleo/adaptador web; 8 recorridos DOM existentes; comprobacion portable del proyecto y `git diff --check`. El editor no reporto problemas, sin compilador Swift disponible. Se escribieron cinco pruebas Swift nuevas, no ejecutadas aqui.
- **Modelos/configuracion:** el chequeo literal de modelos fallo por CRLF del checkout; la comparacion en memoria normalizando unicamente saltos de linea coincidio con el contrato. No se modificaron modelos ni generador. Info.plist se valido con plistlib y se comprobo que el xcconfig local queda ignorado.
- **Pendientes:** despliegue SQL revisado, resolucion y lockfile SPM, compilacion/pruebas nativas y revision visual en Mac, pruebas clinicas positivas/concurrencia con MFA autorizada y revision de seguridad/rendimiento. Las verificaciones web no acreditan el nuevo modulo nativo.
- **Informe y pruebas por pantalla:** [MODULO_DOCTOR_2026-10-28.md](MODULO_DOCTOR_2026-10-28.md).

## 2026-10-28 - Intento de eliminar la rama de agendamiento

- **Solicitud:** eliminar `feature/paciente-agendar-cita` y conservar el estado anterior en `main`; el usuario confirmo el nombre correcto de la rama.
- **Resultado:** se intento `git push origin --delete feature/paciente-agendar-cita`. GitHub rechazo la operacion con HTTP 403: la cuenta autenticada `gabrieladiaz1-dev` no tiene permiso de escritura en `Vic2910/Hospital-Universitario`. No se elimino la rama.
- **Cambios y rutas:** solo esta bitacora (`docs/BITACORA.md`); no se modifico el codigo ni se cambiaron commits de `main`.
- **Verificaciones:** `git ls-remote --heads origin` confirmo que la rama remota sigue en `d0f00bf` y `main` en `58be7ea`; `git status --short --branch` confirmo `main`, sin cambios pendientes antes de este registro. No existe una rama local de agendamiento que eliminar.
- **Pendiente:** eliminar la rama remota con una cuenta con permisos de escritura. No se ejecutaron pruebas de la app, Xcode ni operaciones contra Supabase porque no hubo cambios funcionales.

## 2026-10-24 — Contraseñas más cortas para las cuentas de prueba

- **Solicitud:** acortar las contraseñas del Médico y del Paciente de demostración.
- **Cambios:** se actualizaron únicamente las contraseñas de las dos identidades existentes mediante la API autenticada de Supabase Auth; quedaron en 9 y 11 caracteres, con mayúsculas, minúsculas, números y símbolo. Se actualizaron los archivos locales de credenciales, excluidos de Git. No se modificaron roles, RLS ni factores MFA.
- **Archivos:** `.local/test-accounts.json`, `.local/CREDENCIALES_PRUEBA.md`, `.local/password-change-verification.json`, `README.md` y esta bitácora. Los documentos compartidos no contienen las contraseñas.
- **Verificación real por HTTPS:** las contraseñas anteriores fueron rechazadas; ambas contraseñas nuevas permitieron iniciar sesión y resolver el rol correspondiente. Se cerraron globalmente las sesiones previas de cada cuenta y se cerraron las sesiones de prueba posteriores.
- **Pendientes:** permanecen los pendientes anteriores de Xcode, revisión visual y autorización de inscripción TOTP. No se ejecutó de nuevo la batería de interfaz, porque no se modificó el código de la app.

## 2026-10-23 — Consolidación de la sesión y nombre definitivo

- **Solicitud:** nombre visible «Hospital Universitario» y documentación del trabajo de esta sesión, con instrucciones para que las IA documenten sus intervenciones.
- **Cambios:** se actualizaron los encabezados de SwiftUI y web; se consolidaron contexto, alcance, arquitectura, modelos, cuentas autorizadas, pruebas y limitaciones en `SESION_2026-10-23.md`; se creó un índice y la instrucción raíz para agentes.
- **Archivos:** `HospitalUniversitario/HospitalUniversitario/ContentView.swift`, `web-preview/app.js`, `AGENTS.md`, `docs/README.md`, `docs/SESION_2026-10-23.md`, `docs/BITACORA.md`, `docs/CONTEXTO_IOS.md` y `README.md`.
- **Verificación:** búsqueda del nombre anterior en el código de la app/web y revisión de diferencias/espacios mediante `git diff --check`. No se volvió a ejecutar la batería de pruebas ni se compiló Xcode por este cambio de textos/documentación.
- **Pendientes:** compilación en Mac, revisión visual y autorización adicional antes de inscribir TOTP. Las capturas e informes originales se conservan como fuentes históricas.
- **Informe completo de la sesión:** [SESION_2026-10-23.md](SESION_2026-10-23.md).

## 2026-10-30 — Agendar cita SwiftUI y web

Acceso Paciente → schedule, jerarquía visual vino/rojo, resumen, validación e invalidación de confirmación al editar. Se reutiliza el código existente y se conservan los cambios locales previos. [Informe](AGENDAR_CITA_2026-10-30.md). Verificación en curso; Xcode pendiente en Mac.


## 2026-10-30 - Continuación de agendar cita tras interrupción

- **Objetivo:** analizar y completar el avance existente de SwiftUI y web sin sustituir la navegación ni los módulos previos.
- **Estado encontrado:** PatientAppointmentView, componentes, síntomas, seis especialidades, horarios, validación y ruta schedule implementados; documentación indicaba verificación pendiente.
- **Cambios de esta continuación:** eliminado desplazamiento anidado nativo; teclado de DUI con guion; formatos de validación visibles y botón de simulación explícito en ambas versiones; descarte del borrador web al salir/cambiar perfil; campos y horarios coherentes, marcas de selección, foco y movimiento reducido. Conservados los cambios locales previos. Sin cambios en autenticación, RPC, RLS o Supabase.
- **Rutas:** Patient/PatientAppointmentView.swift y PatientAppointmentComponents.swift; web-preview/app.js y style.css; scripts/test-preview.mjs; README.md; docs/AGENDAR_CITA_2026-10-30.md y esta bitácora. El informe ya está enlazado en docs/README.md.
- **Pruebas ejecutadas:** ocho recorridos DOM existentes y dos nuevos de agendamiento con transporte simulado aprobados. Comprobador portable del proyecto, sintaxis de app.js y git diff --check aprobados también tras los últimos ajustes. Los siete recorridos funcionales de scripts/test-modules.mjs aprobaron con transporte simulado. No se ejecutaron pruebas reales contra Supabase.
- **Pendientes:** compilación y pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se afirma compilación Xcode ni igualdad visual comprobada. [Informe](AGENDAR_CITA_2026-10-30.md).


## 2026-10-30 - Dashboard del doctor coherente con el paciente

- **Objetivo:** rediseñar Inicio del doctor en SwiftUI y web con bienvenida, fecha de hoy, citas programadas, accesos clínicos, historial propio y horario laboral.
- **Implementación:** nueva DoctorDashboardView y réplica doctor-dashboard.js reutilizando estilos/cards del paciente; integración con workspace, historial por paciente/fechas y jornadas propias existentes. Modo diseño web y Preview Swift con Dr. Luis Ramírez, cuatro citas y datos ficticios equivalentes; nunca se sustituyen datos de sesión real con fixtures. Hasta incluye todo el día y se descartan resultados antiguos/error/contexto.
- **Rutas:** Doctor/DoctorDashboardView.swift y DoctorModuleView.swift; Core/DoctorViewModel.swift y HospitalStore.swift; ContentView.swift; web-preview/{doctor-dashboard.js,app.js,modules.js,index.html,server.mjs,style.css}; scripts/{test-preview.mjs,test-doctor-dashboard.mjs}; README.md, docs/README.md, este registro e informe enlazado.
- **Verificaciones ejecutadas:** ocho recorridos DOM previos más dos de citas; siete recorridos funcionales; dos nuevos recorridos del dashboard con transporte simulado (demo y sesión), incluyendo exclusión de otro doctor; comprobador portable; sintaxis JS; git diff --check. HTTP 200 local en página y cuatro recursos relevantes, cerrando el servidor temporal. Sin pruebas reales contra Supabase ni cambios de backend.
- **Límites:** selector de pacientes de la agenda de hoy; para otra agenda se conserva el acceso a Pacientes. Resumen del horario con primera página y hasta siete jornadas; horario completo mantiene paginación existente. Xcode/pruebas Swift y comparación visual en navegador/dispositivo pendientes; no hay Playwright instalado.
- **Informe:** [DASHBOARD_DOCTOR_2026-10-30.md](DASHBOARD_DOCTOR_2026-10-30.md).


## 2026-10-30 - Corrección: historial en Pacientes y jornadas en Mi horario

- **Solicitud:** retirar historial clínico y horario del panel general del doctor; ubicar el primero en Pacientes y el segundo en su pantalla de horario. Sustituye la distribución de la entrada anterior.
- **Cambios SwiftUI:** extraído DoctorPatientHistoryView con su estado y filtros, integrado solo en Pacientes y reiniciado al cambiar la fecha de agenda. DoctorDashboardView conserva saludo, fecha, conteo y accesos. Retirada lectura de jornadas de Inicio; se conserva la pantalla turns y su carga. Método de lectura independiente renombrado a patientHistory.
- **Cambios web:** renderHistory se integra en Pacientes tanto en diseño como en sesión; Inicio conserva solo bienvenida y accesos. Retirado resumen y carga de jornadas en Inicio; horario existente en Más → Mi horario intacto. Se descartan filtros/resultados al salir de Pacientes.
- **Rutas:** Doctor/{DoctorDashboardView,DoctorPatientHistoryView,DoctorModuleView}.swift; Core/{DoctorViewModel,HospitalStore}.swift; ContentView.swift; web-preview/{doctor-dashboard,app,modules}.js; scripts/test-doctor-dashboard.mjs; README.md, informe DASHBOARD_DOCTOR_2026-10-30.md y bitácora. El informe sigue enlazado en docs/README.md.
- **Verificaciones:** scripts/test-preview.mjs aprobado (ocho recorridos previos y dos de agendar cita); scripts/test-doctor-dashboard.mjs aprobado, incluyendo ausencia de historial/horario en Inicio, filtros en Pacientes y lectura propia en Mi horario; siete recorridos de scripts/test-modules.mjs aprobados; python scripts/check-project.py, sintaxis de los tres JS modificados y git diff --check aprobados. No se hicieron escrituras ni pruebas reales contra Supabase.
- **Pendientes:** compilación y pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se afirma compilación Xcode.


## 2026-10-30 - Retirar Mis citas exclusivamente del Doctor

- **Solicitud:** eliminar Mis citas de la navegación y de todos los accesos/pantallas del rol Doctor, conservándolo en Paciente.
- **Implementación iOS/web:** retirado el destino appointments del catálogo compartido del Doctor, del menú inferior, del menú Más y de sus manejadores de módulos. La barra Doctor queda Inicio / Pacientes / Consultas / Más; web ajusta las columnas a cuatro. El acceso secundario del resumen anterior ahora apunta a Pacientes. Se retiraron ejemplos de esa pantalla del Doctor; la agenda clínica y su modelo de citas siguen utilizándose en Pacientes, Consultas y el conteo del día. Ningún cambio en autenticación, backend o datos reales.
- **Rutas:** Shared/screens.json; ContentView.swift; Core/HospitalStore.swift; Doctor/DoctorModuleView.swift; web-preview/{app.js,modules.js,style.css,design-fixtures.json}; scripts/{check-project.py,test-preview.mjs}; README.md y esta bitácora.
- **Verificaciones ejecutadas:** test-preview.mjs aprobado, comprobando ausencia de Mis citas en todas las pantallas de diseño del Doctor y presencia para Paciente; siete recorridos de test-modules.mjs y recorridos de test-doctor-dashboard.mjs aprobados. Sintaxis de app.js/modules.js, python scripts/check-project.py y git diff --check aprobados. El catálogo tiene 20 pantallas activas (11 Paciente, 9 Doctor); se conservan las 21 capturas históricas sin alterarlas.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se ejecutaron pruebas reales contra Supabase.


## 2026-10-30 - Agenda visual de Consultas del Doctor

- **Solicitud:** mejorar el estilo de Consultas con colores de la app, agenda de hoy, búsqueda por fecha para próximas consultas y datos precargados mientras no haya registros.
- **Implementación SwiftUI/web:** encabezado vino, total por fecha, calendario, accesos Hoy/Mañana/En 7 días, tarjetas de paciente/hora/estado, búsqueda y vacío. Datos equivalentes: cuatro consultas hoy, dos mañana, una en tres días y una en siete. El modo diseño y el resultado autorizado vacío muestran ejemplos identificados y sin acciones clínicas; los datos reales conservan selección y formulario previo. Sin cambios en autenticación, backend, RLS ni registros reales.
- **Rutas:** Doctor/{DoctorConsultationAgendaView,DoctorModuleView}.swift; ContentView.swift; Shared/screens.json; web-preview/{doctor-dashboard.js,app.js,modules.js,style.css}; scripts/test-doctor-consultations.mjs; README.md; docs/README.md; informe y bitácora.
- **Verificaciones ejecutadas:** test-preview.mjs aprobado (ocho recorridos anteriores y dos de citas); siete recorridos de test-modules.mjs aprobados; tres recorridos nuevos de agenda (diseño, sesión vacía y citas reales simuladas), con calendario, próximas fechas, búsqueda, ausencia de escrituras ficticias e intervalo diario RPC. Sintaxis JS, comprobador portable del proyecto y git diff --check aprobados. Se repiten tras el ajuste final de textos.
- **Pendientes:** Xcode/pruebas Swift en Mac y revisión visual en navegador/dispositivo. Sin pruebas reales contra Supabase.
- **Informe:** [CONSULTAS_DOCTOR_2026-10-30.md](CONSULTAS_DOCTOR_2026-10-30.md).


## 2026-10-30 - Tarjetas completas y ticket de Consultas Doctor

- **Solicitud:** rediseño acotado de lista/detalle de Consultas en SwiftUI y web; datos de paciente, edad, teléfono, hora, motivo y síntomas; etiquetas con No hay datos reales para faltantes.
- **Implementación:** tarjetas con campos ordenados y Ver detalle; hoja nativa y panel web accesible dentro de la consulta seleccionada. Círculo vino/check blanco, fecha/hora en negrita y botón azul de la captura revisada. Estado original visible; apertura de detalle separada de Abrir atención. Opcionales compatibles en DoctorAppointment y ejemplos idénticos enriquecidos. No se añadieron dependencias, operaciones de backend, permisos ni cambios en otros módulos.
- **Rutas:** Doctor/DoctorConsultationAgendaView.swift; nuevo Doctor/DoctorConsultationTicketView.swift; Core/DoctorModels.swift; web-preview/{doctor-dashboard.js,style.css}; scripts/test-doctor-consultations.mjs; README.md; docs/{README.md,TICKET_CONSULTA_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** pruebas DOM de preview, agenda/ticket y siete recorridos funcionales con transporte simulado aprobados; datos completos/faltantes, edad cero, texto largo, estado cancelado, apertura/cierre y ausencia de operaciones clínicas al abrir ticket. Sintaxis JS aprobada después de corregir un conflicto de nombre detectado por las pruebas. Comprobador portable y git diff --check aprobados; se repiten tras los últimos ajustes.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo, incluida medición de desbordamiento. Sin pruebas reales contra Supabase. El backend actual no expone edad/motivo/síntomas en agenda; se muestran los faltantes sin inventar valores reales.
- **Informe:** [TICKET_CONSULTA_DOCTOR_2026-10-30.md](TICKET_CONSULTA_DOCTOR_2026-10-30.md).


## 2026-10-30 - Laboratorios de diseño dentro del expediente por rol

- **Solicitud y aclaración:** buscar paciente por DUI/nombre en Expedientes, abrir su ficha y preparar desde ella una solicitud de laboratorio asignada a ese paciente. Paciente solo ve solicitudes/resultados. Tres estados: Pendiente, En Proceso y Completado. Trabajo de diseño, sin envío a base de datos.
- **SwiftUI/web:** modelos locales serializables, catálogo de siete estudios sencillos sin imágenes, datos de registro y ejemplo de primera visita, editor dentro del expediente, contexto automático de médico/clínica/fecha/hora/turno, validación obligatoria, sección de laboratorios con filtros por fecha/categoría/paciente y detalle. Estado compartido al navegar; guardas por rol y descarte de borradores al cambiar de paciente. Se conservan los módulos reales previos; iOS ofrece interruptor explícito de diseño y web usa su modo de diseño aislado.
- **Navegación:** Doctor incluye Laboratorios como quinto destino (Inicio/Pacientes/Consultas/Laboratorios/Más), sin restaurar Mis citas. El expediente sigue en el destino chart existente; no se crearon rutas nuevas.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; Shared/screens.json; web-preview/{clinical-labs.js,app.js,index.html,server.mjs,style.css}; scripts/{test-preview,test-clinical-labs}.mjs; README.md; docs/{README.md,LABORATORIOS_EXPEDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** tres recorridos nuevos de diseño/rol/modelo aprobados, con ausencia de llamadas reales; preview (ocho previos y dos de citas), siete flujos de módulos, dashboard y consultas/ticket aprobados con transporte simulado. Sintaxis JS, comprobador portable y git diff --check aprobados. HTTP 200 local de página y tres recursos en servidor temporal, cerrado al terminar.
- **Pendientes y límites:** Xcode/pruebas Swift en Mac y revisión visual en navegador/dispositivo; futura adaptación al catálogo y RPC autorizados. Sin pruebas reales contra Supabase, cambios de backend, credenciales ni registros clínicos. Los datos y solicitudes locales se reinician al salir/cambiar de modo o rol.
- **Informe:** [LABORATORIOS_EXPEDIENTE_2026-10-30.md](LABORATORIOS_EXPEDIENTE_2026-10-30.md).


## 2026-10-30 - Corrección de visibilidad del rediseño en sesión Doctor

- **Reporte y causa:** la captura del usuario mostraba el formulario anterior tras iniciar sesión. El renderer nuevo estaba condicionado al modo diseño externo y SwiftUI requería activar un interruptor; la navegación normal no mostraba lo solicitado.
- **Corrección web/iOS:** Expedientes y Laboratorios del Doctor muestran el diseño local por defecto también dentro de sesión. Laboratorios sin paciente seleccionado muestra inmediatamente búsqueda por DUI/nombre y acceso al expediente. Se conserva aviso visible de datos ficticios y ninguna solicitud local se envía al hospital. Web conserva Ver flujo conectado / Ver diseño de expediente y laboratorios para acceder al módulo real anterior; SwiftUI activa inicialmente el diseño al resolver el rol Doctor y conserva el interruptor. Los datos reales del Paciente no se sustituyen por ejemplos.
- **Rutas:** web-preview/{app.js,clinical-labs.js}; ContentView.swift; Modules/ClinicalLabDesignView.swift; scripts/test-clinical-labs.mjs; README.md; docs/{LABORATORIOS_EXPEDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** regresión nueva con sesión Doctor y recorrido idéntico al de la captura aprobada: búsqueda visible sin activar modo externo, expediente seleccionado, solicitud local, ausencia de emisión remota y conmutación al flujo conectado conservando el prototipo. Pruebas de laboratorio/diseño/modelo y siete flujos previos aprobados; test-preview.mjs ejecutado por importación y repetido al cierre; comprobador portable y git diff --check aprobados. Sin login real ni escrituras a Supabase.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo. La regresión es DOM con transporte simulado.


## 2026-10-30 - Laboratorio independiente y expediente modal compartido

- **Objetivo actual:** solicitar desde Laboratorio sin abrir expediente, mediante modal con fecha/doctor automáticos, motivo, examen, peso y altura; expediente separado con ficha completa, laboratorios y acciones de observación/receta.
- **Implementación iOS/web:** modales equivalentes, captura decimal validada, autor de cuenta activa, solicitud Pendiente y cierre/confirmación; modelo compartido para ficha, mediciones, resultados estructurados, notas y recetas locales no emitidas. Punto applyPublishedResult para aplicar resultados publicados, actualizando vistas sin duplicar y rechazando eventos antiguos. Se preserva el módulo conectado anterior y las rutas. Esta decisión sustituye el requisito previo de solicitar solo desde Expedientes.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{README.md,LABORATORIO_INDEPENDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** pruebas DOM de solicitud/modal, medidas inválidas/decimales, cierre, autor activo, notas/recetas aisladas, resultados y estados compartidos aprobadas; preview y siete recorridos de módulos previos, consultas/ticket aprobados. Comprobador portable, sintaxis JS y git diff --check aprobados. Se corrigió una etiqueta accesible ambigua detectada en las pruebas. No se ejecutaron escrituras ni pruebas reales contra Supabase.
- **Pendientes explícitos:** conectar eventos/resultados reales de recepción y persistencia remota, sin inventar permisos; compilar y probar Swift en Mac; revisar visualmente navegador/dispositivo. applyPublishedResult es un adaptador local probado, no una conexión de recepción ya desplegada. Las recetas nuevas son borradores locales y conservan el módulo real aparte.
- **Informe:** [LABORATORIO_INDEPENDIENTE_2026-10-30.md](LABORATORIO_INDEPENDIENTE_2026-10-30.md).


## 2026-10-30 - Tickets internos y separación visual de Laboratorios

- **Solicitud:** evitar ventanas externas; solicitud y expediente como tickets dentro de la app, con estilo de la captura de confirmación. Separar búsqueda/selección del formulario y de los filtros de resultados, que se mezclaban visualmente.
- **SwiftUI/web:** eliminados sheet/dialog del flujo local y sustituidos por paneles internos. Entrada con introducción vino, búsqueda y acciones; Solicitar exámenes muestra exclusivamente el ticket del formulario; Ver solicitudes y resultados abre su propio panel con filtros. Expediente/notas/recetas también quedan dentro del contenido de la app. Check vino/blanco, bloque central destacado, secciones numeradas, campos de medidas agrupados y acción azul de referencia. Eliminada la búsqueda genérica duplicada solo en el flujo local. Sin modificar modelos, backend ni operaciones reales.
- **Rutas:** Modules/ClinicalLabDesignView.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{LABORATORIO_INDEPENDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** test-clinical-labs.mjs aprobado, incluyendo ausencia de dialog y filtros/formulario antes de la acción, ticket interno, validaciones, resultados y aislamiento. Siete recorridos de módulos previos aprobados; preview (ocho previos y dos de citas), sintaxis JS, comprobador portable y git diff --check aprobados. No se realizó revisión visual automatizada ni compilación Swift.
- **Pendientes:** comparación visual en navegador/dispositivo y compilación/pruebas en Mac; conexión remota de recepción/persistencia sigue pendiente como se documentó anteriormente. [Informe actualizado](LABORATORIO_INDEPENDIENTE_2026-10-30.md).


## 2026-10-30 - Rediseño de Pacientes del Doctor con fecha, DUI y nombre

- **Solicitud:** mejorar visualmente Pacientes del Doctor, con búsqueda por fecha/DUI/nombre y acceso claro a datos e historial clínico del paciente coincidente.
- **SwiftUI/web:** cabecera vino, búsqueda única, accesos Todos/Hoy/Mañana, calendario, conteo y tarjetas con iniciales/demografía/seguimiento. Selección abre ticket interno con cronología de consultas propias, datos, signos disponibles, notas, recetas y estudios compartidos. La fecha filtra atenciones de agenda; citas futuras no se incluyen como antecedentes realizados. Filtros conservados al volver. El rediseño local queda visible en sesión Doctor; flujo conectado previo conservado.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/{test-doctor-patients,test-doctor-dashboard}.mjs; README.md; docs/{README.md,PACIENTES_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** dos recorridos nuevos (diseño y sesión simulada) aprobados, con búsquedas combinadas, ficha sin dialog, exclusión de otro médico/paciente y datos compartidos; regresiones de dashboard, laboratorio y preview aprobadas. Comprobador portable, sintaxis JS y git diff --check aprobados. Se separó la clase del estado de consulta de los estados de laboratorio para conservar sus tres estados exactos.
- **Límites:** pacientes e historial nuevo precargados e identificados; no se afirma búsqueda real por DUI ni escrituras remotas. Pendientes Xcode/pruebas Swift en Mac y revisión visual real. [Informe](PACIENTES_DOCTOR_2026-10-30.md).


## 2026-10-30 - Perfil reducido al nombre y apellido registrados

- **Solicitud:** mejorar Perfil para que únicamente muestre nombre y apellido del registro del usuario.
- **SwiftUI/web:** presentación de solo lectura con dos campos Nombre/Apellido, paleta existente y encabezado Datos de registro. Fuente real exclusiva my_profile.person.given_names/family_names; no se usa el nombre preferido, el del Doctor ni ejemplos como sustitutos en sesión. Faltantes o espacios se muestran como No disponible. Retirados de esta vista correo, datos profesionales, contacto, contraseña, preferencias y accesos secundarios; cierre de sesión sigue en Más. Sin modificar datos de usuario, autenticación o backend.
- **Carga:** Perfil ya no solicita mobile_module/profile ni monta su formulario de configuración; se conserva el código previo del módulo, sin mostrarlo en Perfil. Se elimina búsqueda innecesaria de esta pantalla. Los ejemplos del modo diseño tienen campos separados y explícitos de nombre/apellido.
- **Rutas:** ContentView.swift; Core/HospitalStore.swift; Shared/screens.json; web-preview/{app.js,style.css,design-fixtures.json}; scripts/test-profile.mjs; README.md y esta bitácora.
- **Verificaciones:** test-profile.mjs aprobado para Doctor/Paciente en sesión simulada, diseño y campos ausentes; confirma dos campos y ausencia de formularios/lecturas de ajustes. Preview (ocho recorridos previos y dos de citas), siete flujos de test-modules.mjs, sintaxis de app.js, python scripts/check-project.py y git diff --check aprobados. Sin pruebas reales contra Supabase ni escrituras.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo.


## 2026-10-30 - Expediente del Paciente con ticket interno de solo lectura

- **Solicitud:** el Paciente debe ver su expediente con el diseño interno del Doctor de la captura, limitado a información propia.
- **SwiftUI/web:** cabecera con check vino/blanco, título, nombre e identificación y secciones ordenadas en el mismo contenido de la app. Entrada directa, sin modales externos, selección de personas ni interruptor para ver los datos reales. Sesión utiliza mobile_module patient/chart existente; faltantes explícitos y modo diseño propio separado. Documentos publicados conservan autorización; se excluyen acciones de escritura en chart.
- **Rutas:** Modules/MobileModuleView.swift; ContentView.swift; web-preview/{modules.js,clinical-labs.js,app.js,style.css}; scripts/test-patient-chart.mjs; README.md; docs/{README.md,EXPEDIENTE_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-patient-chart.mjs aprobado (propietario, campos, faltantes y solo lectura); preview, laboratorios y siete recorridos clínicos previos aprobados con transporte simulado; sintaxis JS, comprobador portable y git diff --check aprobados. Sin pruebas reales contra Supabase ni cambios a sus permisos/datos.
- **Pendientes:** revisión visual en navegador/dispositivo y compilación/pruebas Swift en Mac. [Informe](EXPEDIENTE_PACIENTE_2026-10-30.md).


## 2026-10-30 - Volver en la esquina del expediente del Paciente

- **Solicitud:** incluir Volver en la esquina superior izquierda del expediente propio, con la misma cabecera del Doctor.
- **SwiftUI/web:** botón Volver y rótulo FICHA CLÍNICA antes del icono del ticket. Usa la navegación existente hacia Inicio, coherente con el expediente de diseño Paciente. Se conserva acceso exclusivo a datos propios y solo lectura.
- **Rutas:** Modules/MobileModuleView.swift; web-preview/modules.js; scripts/test-patient-chart.mjs; docs/EXPEDIENTE_PACIENTE_2026-10-30.md y bitácora.
- **Verificaciones:** test-patient-chart.mjs ampliado para comprobar Volver en sesión simulada y diseño; test-preview.mjs, python scripts/check-project.py y git diff --check ejecutados al cierre. No se compila Xcode ni se verifica visualmente en dispositivo en Windows.


## 2026-10-30 - Historial médico del Paciente con tarjetas de referencia y detalle

- **Solicitud:** rediseño de Historial médico en SwiftUI y web según captura 215451, con tres consultas exactas, orden descendente, línea verde existente y detalle pulsable.
- **Implementación:** PatientHistoryRecord y PatientHistoryView, equivalentes JS, tarjetas con jerarquía fecha/hora/especialidad/médico/motivo y detalle interno con Volver. Datos de ejemplo identificados solo en diseño o lectura propia exitosa vacía; registros reales sin mezcla y error sin ejemplos como sustituto. Estado vacío amable, búsqueda, reintento/paginación y solo lectura. La línea verde es estilo de referencia; no se califican citas pasadas como futuras.
- **Rutas:** nuevo Patient/PatientHistoryView.swift; ContentView.swift; nuevo web-preview/patient-history.js; web-preview/{app.js,style.css,index.html,server.mjs}; scripts/{test-patient-history,test-preview}.mjs; README.md y documentación enlazada.
- **Verificaciones:** pruebas nuevas de historia exacta/orden, tres detalles, búsqueda, vacío, error y alcance patient aprobadas; preview y siete flujos de módulos previos aprobados con transporte simulado; comprobador portable, sintaxis JS y git diff --check aprobados. Recurso nuevo HTTP 200 en 4173 tras actualizar la instancia local existente sin duplicar el servidor.
- **Pendientes:** revisión visual navegador/dispositivo y compilación/pruebas Swift en Mac. Sin pruebas reales ni escrituras de Supabase. [Informe](HISTORIAL_PACIENTE_2026-10-30.md).


## 2026-10-30 - Card Recetas y presentación del Paciente según receta.png

- **Solicitud:** sustituir Paciente por Recetas en el dashboard y presentar sus recetas ordenadas con estados de retiro y estilo de la referencia receta.png.
- **SwiftUI/web:** card Recetas apunta a prescriptions; nuevo listado por medicamento con dosis, frecuencia, vía, duración, cantidad, observaciones y estados Pendiente/Retirada. Registros ordenados por emisión descendente. Ejemplos identificados para diseño/listado vacío exitoso; datos reales propios sin mezcla. Si la fuente no expone retiro, Retiro por confirmar, sin traducir active/expired a entrega de farmacia. Se conserva texto clínico íntegro y faltantes estructurados explícitos.
- **Navegación preservada:** Agendar cita queda accesible desde Mis citas; no se elimina el formulario previo. Doctor no se modifica.
- **Rutas:** Patient/{PatientDashboardView,PatientPrescriptionsView}.swift; ContentView.swift; Modules/MobileModuleView.swift; web-preview/{patient-prescriptions.js,app.js,modules.js,index.html,server.mjs,style.css}; scripts/{test-preview,test-patient-prescriptions}.mjs; README.md; docs/{README.md,RECETAS_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-patient-prescriptions aprobado (acceso, orden, estados, detalles, búsqueda, alcance patient y ausencia de escritura), test-preview y siete flujos de test-modules aprobados; comprobador portable, sintaxis JS y git diff --check aprobados. Recurso web HTTP 200 tras actualizar el servidor local existente, sin dos procesos en el puerto.
- **Pendientes:** Xcode/pruebas Swift en Mac y revisión visual real; proyección autorizada de retiro y datos de farmacia cuando se conecte esa información. Sin pruebas reales ni cambios en Supabase. [Informe](RECETAS_PACIENTE_2026-10-30.md).


## 2026-10-30 - Campos completos de receta del Doctor

- **Solicitud:** al crear una receta el Doctor debe capturar medicamento, dosis, cantidad y todos los campos que ve el Paciente.
- **SwiftUI/web:** formulario local del expediente ampliado con dosis/unidad, frecuencia, vía, duración, cantidad y observaciones; snapshot estructurado y validación obligatoria. Formulario conectado conserva catálogo y permisos; añade Durante (días), etiqueta Observaciones y vista previa completa. Días se traducen a starts_on/ends_on existentes; no se agregan campos incompatibles al transporte. Se preserva tratamiento hasta nueva indicación cuando no se define fin. Pendiente/Retirada no se hacen editables por el Doctor.
- **Rutas:** Modules/{ClinicalLabDesignModels,ClinicalLabDesignView,MobileModuleView}.swift; web-preview/{clinical-labs.js,modules.js}; scripts/{test-clinical-labs,test-modules}.mjs; README.md; docs/{README.md,CAMPOS_RECETA_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-clinical-labs.mjs aprobado con campos de receta completos y bloqueo de incompletos; siete flujos de test-modules.mjs aprobados con duración de diez días entre 30 oct y 8 nov, observaciones y sin days en RPC. Preview, comprobador portable, sintaxis JS y git diff --check aprobados. Sin emisión real ni cambios de Supabase.
- **Pendientes:** Xcode/pruebas Swift en Mac, revisión visual y proyección estructurada de lectura real al Paciente según informe previo. [Informe](CAMPOS_RECETA_DOCTOR_2026-10-30.md).


## 2026-10-30 — Próxima cita y solicitud única del Paciente

- **Objetivo:** compartir el diseño del ticket del Doctor, eliminar el formulario duplicado, capturar preferencia Mañana/Tarde y simular Pendiente → Cita asignada por Recepción.
- **Implementación:** store/snapshots locales en SwiftUI y web; Mis citas con próxima cita y detalle interno; formulario de agendar renombrado Solicitar atención y validación de preferencia; confirmación Pendiente sin reserva; recepción local con asignación de fecha/hora, vínculo a cita y bloqueo de duplicados. Se retiró el formulario visual anterior. Estados compatibles con pending/scheduled/rejected/cancelled. Citas conectadas, cancelación y vistas del Doctor conservadas.
- **Rutas:** iOS Patient/{PatientAppointmentFlow,PatientAppointmentView,PatientAppointmentComponents}.swift; Doctor/DoctorConsultationTicketView.swift; ContentView.swift; Core/HospitalStore.swift; Modules/MobileModuleView.swift. Web {patient-appointments.js,app.js,modules.js,index.html,server.mjs}. Scripts {test-patient-appointments,test-preview,test-modules}.mjs. README.md; docs/{README.md,BITACORA.md,CITAS_SOLICITUDES_PACIENTE_2026-10-30.md}.
- **Verificaciones ejecutadas:** preview y 20 pantallas; prueba nueva de solicitud/preferencia/ticket/asignación, datos propios y errores; siete recorridos de módulos; pruebas de consultas y dashboard del Doctor; comprobador de proyecto, sintaxis JS y diff --check. DOM/transporte simulados, sin escribir en Supabase. Servidor local actualizado y tres recursos HTTP 200/no-store.
- **Pendientes/límites:** Xcode y revisión visual; persistencia real de solicitudes/preferencia, acceso autorizado y asignación de Recepción. La web ofrece Recepción (demo), SwiftUI su Preview/componente; no se creó un rol real ni se modificaron políticas, esquema o RPC. Los datos locales se reinician y no son registros clínicos. Esta decisión reemplaza los accesos separados anteriores. [Informe](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-30 — Mis citas: tarjeta única, ticket 180312 y selector AM/PM

- **Objetivo:** mostrar únicamente Cita asignada al entrar, abrir sus datos en un ticket elegante con Volver y mejorar la preferencia de horario en ambas plataformas.
- **Cambios:** se inspeccionó la captura 180312; entrada única sin buscador ni cola; ticket interno con check vino, título centrado, bloque de fecha/hora, secciones de datos y botón azul; Volver en esquina superior y al pie. Datos/estados/modelos conservados. Solicitar atención sigue en Más; cola local trasladada al formulario. Gestión/cancelación conectada permanece en desplegable del detalle. Preferencia exclusiva AM/PM con tarjetas, iconos, bordes y check, valores Mañana/Tarde intactos.
- **Rutas:** iOS Patient/{PatientAppointmentFlow,PatientAppointmentView,PatientAppointmentComponents}.swift y ContentView.swift; web-preview/{patient-appointments.js,app.js,style.css}; scripts/{test-preview,test-patient-appointments,test-modules}.mjs; README.md; docs/{CITAS_SOLICITUDES_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** preview/20 pantallas, prueba específica Paciente (entrada única, datos, ambos Volver, AM/PM excluyente, Pendiente/asignación local, datos autorizados y errores), siete recorridos de módulos incluida cancelación; consultas/ticket y dashboard del Doctor aprobados. Sintaxis JS, check-project.py y diff --check aprobados. Recursos actuales HTTP 200/no-store y contenido nuevo servido en el puerto existente 4173. Sin segunda instancia ni cambios de Supabase.
- **Pendientes:** compilación/revisión SwiftUI en Mac, revisión visual web en navegador y persistencia/Recepción real. Pruebas DOM/transporte simulados, no operaciones clínicas reales. [Informe actualizado](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-30 — Salud abre directamente Solicitar atención

- **Objetivo/cambios:** sustituir el menú de Salud del Paciente por el formulario existente, en SwiftUI y web. Se reutilizan health/request/schedule, el store y el estado Pendiente; Salud queda seleccionada y sin buscador. Se conservan autenticación, rutas históricas y recepción local.
- **Rutas:** ContentView.swift; Core/HospitalStore.swift; web-preview/app.js; scripts/test-preview.mjs; README.md; docs/{BITACORA.md,CITAS_SOLICITUDES_PACIENTE_2026-10-30.md}.
- **Verificaciones ejecutadas:** test-preview (20 pantallas y formulario desde Salud), test-patient-appointments (envío Pendiente/asignación de recepción local y datos propios), test-modules (siete flujos, incluida cancelación y atención del Doctor), check-project.py y git diff --check aprobados. DOM/transporte simulado, sin operaciones reales contra Supabase.
- **Pendientes:** compilación Swift en Mac, revisión visual y conexión/persistencia real con Recepción. [Informe actualizado](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-30 — Perfil del Paciente e Información general profesional

- **Objetivo:** mostrar nombre, correo y teléfono registrados; mejorar ubicación, orientación, contacto y especialidades con paridad SwiftUI/web y la paleta actual.
- **Cambios:** nuevo perfil con iniciales y card de contacto, faltantes explícitos y ejemplos aislados; Perfil Doctor conservado. Información general con portada, sede de referencia, mapa, Clínica Universitaria y WhatsApp institucional del directorio oficial UNICAES consultado, especialidades publicadas o seis ejemplos identificados, solicitud de atención y avisos/ocupación/habitaciones conservados. Rutas y autenticación intactas, sin dependencias ni cambios de backend.
- **Rutas:** Patient/PatientProfileInformationView.swift (nuevo), ContentView.swift, Shared/screens.json, web-preview/{app.js,style.css}, scripts/test-profile.mjs, README.md, docs/{README.md,BITACORA.md,PERFIL_INFORMACION_GENERAL_2026-10-30.md}.
- **Verificaciones:** test-preview (20 pantallas), test-profile (contactos propios/faltantes/diseño/Doctor, datos y enlaces públicos, especialidades y Salud), check-project.py, sintaxis JS y diff --check aprobados; HTTP 200/no-store en servidor existente. DOM y transporte simulados; sin llamadas reales de teléfono/WhatsApp ni escrituras Supabase.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual web y confirmación de disponibilidad clínica real. Se sustituye la decisión histórica de Perfil Paciente limitado a nombre/apellido. [Informe y fuente oficial](PERFIL_INFORMACION_GENERAL_2026-10-30.md).


## 2026-10-31 — Cronología y detalle de laboratorios del expediente Doctor

- **Objetivo:** exámenes realizados/pendientes visibles en orden, sin filtros en el expediente; detalle elegante dentro de la app con resultados o estado de espera.
- **Cambios:** cards por fecha de solicitud descendente, fecha destacada y estado, detalle tipo ticket por ID/paciente con retorno al expediente/origen, datos completos, valores/unidades/referencias y observaciones publicadas. Pendientes y En Proceso no muestran resultados. Se mantienen notas/recetas, publicación reactiva, filtros independientes de Laboratorio, rutas y acceso conectado. Paleta existente, sin dependencias.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{README.md,BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs y test-preview/20 pantallas aprobados; cronología, tres estados, falta de filtros, resultados, ambos retornos, acciones e aislamiento verificados con DOM/transporte simulado. Sintaxis JS, check-project.py y diff --check aprobados. HTTP 200/no-store del componente actualizado en servidor existente.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual y conexión real de resultados/Recepción al prototipo. Sin escrituras ni cambios de Supabase. [Informe](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Laboratorio Doctor solo solicita; resultados en Expedientes

- **Cambios:** se retiran Ver expediente y Ver solicitudes y resultados de Laboratorio del Doctor en SwiftUI/web; se conserva Solicitar exámenes. En el expediente Ver examen pasa a Ver detalle. Se mantiene publicación local → Completado, resultados exclusivamente para completados y mensajes sin resultados para Pendiente/En Proceso. No se cambia la vista del Paciente.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/clinical-labs.js; scripts/{test-clinical-labs,test-doctor-patients}.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs, test-doctor-patients en diseño/sesión simulada, test-preview/20 pantallas, check-project.py y diff --check aprobados. Sin llamadas clínicas reales ni cambios de Supabase.
- **Pendientes:** compilación en Mac, revisión visual y conexión real del prototipo. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Expedientes sin solicitud de examen y datos personales rediseñados

- **Cambios:** retirada del botón Solicitud de laboratorio de Expedientes Doctor en iOS/web; creación conservada en Laboratorio. Datos personales con iniciales, nombre, cuatro campos de identidad y tres filas de contacto/expediente con iconos. Misma paleta, datos, historial, laboratorios y notas/recetas.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs, test-doctor-patients (diseño/sesión), test-preview/20 pantallas, check-project.py y diff --check aprobados. DOM/transporte simulado; sin cambios de Supabase.
- **Pendientes:** Xcode en Mac y revisión visual. Se sustituye la creación de laboratorios desde Expedientes de decisiones anteriores. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Detalle de examen: paciente primero y resultados destacados

- **Cambios:** SwiftUI/web muestran primero nombre, edad y teléfono únicamente; después información del examen, estado y resultado. Iniciales/nombre destacados, franja de contacto, fecha en bloque y valores/unidades con referencias separadas. Los datos adicionales permanecen en el expediente/modelo. Estados, publicación, retorno y notas/recetas conservados.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs y test-preview/20 pantallas aprobados; orden de tarjetas y ausencia de datos personales adicionales comprobados, además de estados/resultados. Sintaxis JS, check-project.py y diff --check aprobados. DOM/transporte simulado, sin cambios de Supabase.
- **Pendientes:** Xcode en Mac, revisión visual y conexión real del prototipo. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Mi expediente y laboratorios propios con estilo del Doctor

- **Cambios:** Mi expediente y laboratorios del Paciente en SwiftUI/web, cards cronológicas, estados, detalle interno con datos mínimos primero y resultados exclusivamente publicados. Lectura sin acciones del Doctor ni selección de personas. Modelo de lectura de laboratorios independiente para conservar secciones/documentos del expediente. Errores, vacíos, actualización, paginación y autorización de documentos conservados; diseño local aislado de las páginas reales.
- **Rutas:** Patient/PatientClinicalView.swift (nuevo); Core/HospitalStore.swift; ContentView.swift; Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,app.js}; scripts/{test-patient-chart,test-clinical-labs}.mjs; README.md; docs/{README.md,BITACORA.md,MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md}.
- **Verificaciones:** test-patient-chart, test-clinical-labs, test-doctor-patients y test-preview aprobados con DOM/transporte simulado; datos propios, tres estados, cronología y ausencia de resultados pendientes/capacidades del Doctor. Check-project.py, sintaxis JS y diff --check aprobados. Sin pruebas nuevas ni escrituras en Supabase.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual y validación contra publicaciones reales de laboratorio. [Informe](MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md).

- **Coherencia de nombre en este ajuste:** el acceso rápido del Paciente también dice Mi expediente en Patient/PatientDashboardView.swift y web-preview/app.js; Doctor conserva Expedientes.


## 2026-10-31 — Paridad exacta del componente de datos personales por rol

- **Cambios:** se extrae ClinicalPatientIdentityView y HospitalClinicalIdentity para compartir tarjeta entre Doctor/Paciente: cabecera con iniciales/nombre, cuatro campos y tres contactos según captura. Laboratorios del Paciente iguala título/subtítulo, fecha destacada, mensajes de estado, divisor y Ver detalle de las cards del Doctor. Se mantiene el acceso propio y los resultados exclusivamente publicados.
- **Rutas:** Modules/ClinicalPatientIdentityView.swift (nuevo), Modules/ClinicalLabDesignView.swift, Patient/PatientClinicalView.swift, web-preview/{clinical-labs.js,style.css}, scripts/test-patient-chart.mjs, README.md, docs/{BITACORA.md,MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md}.
- **Verificaciones:** comparación de tarjeta Doctor/Paciente para el mismo ejemplo aprobada; cuatro campos y tres contactos en sesión propia; test-patient-chart, test-clinical-labs, test-doctor-patients y test-preview aprobados; check-project.py, sintaxis JS y diff --check. DOM/transporte simulado, sin cambios de Supabase.
- **Pendientes:** revisión visual en navegador y compilación Xcode en Mac. Se conserva el contrato autorizado y no se inventan datos reales ausentes. [Informe](MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md).
## 2026-11-12 — Revisión funcional del solicitante antes de conectar Supabase

- **Objetivo:** revisar registro → datos → inicio → solicitud → lista, validaciones, estados y regresión iOS/web, sin cambios de backend. Se preservó el trabajo previo sin atribuirlo a esta revisión.
- **Correcciones:** continuación explícita desde registro de demostración en ambas plataformas; salida antes de completar datos; aislamiento MainActor del registro/contenedor, import Combine y bloqueo de validación si falta JavaScript; tarjeta SwiftUI apilada; controles web adaptables y etiquetas accesibles. Los ejemplos rechazado/cancelado ya presentes se comprobaron; script visual corregido para informar ausencia de DevTools y usar la nueva continuación.
- **Rutas:** `Auth/RegisterView.swift`, `ContentView.swift`, `Applicant/{ApplicantRules,ApplicantDemoStore,ApplicantDemoView}.swift`, `web-preview/{app.js,applicant.js,style.css}`, `scripts/visual-applicant.mjs`, README e índice de docs; [informe completo](REVISION_FRONTEND_2026-11-12.md).
- **Verificaciones ejecutadas:** test-applicant, test-preview (ocho recorridos/veinte pantallas), test-core (once), test-modules (siete), test-patient-appointments, test-patient-chart, test-patient-history, test-patient-prescriptions, test-profile, test-doctor-dashboard, test-doctor-patients, test-doctor-consultations y test-clinical-labs aprobados. Check-project, sintaxis de tres JS y diff --check aprobados. HTTP 200 en raíz y applicant.js del servidor existente; el intento de arrancar otro servidor recibió EADDRINUSE.
- **Límites/bloqueos:** Edge headless no expuso DevTools; no hubo capturas ni revisión visual válida. La continuación nueva del registro se revisó estáticamente, pendiente de ejecución en navegador. No se compiló Swift ni se ejecutaron pruebas nativas en Windows. TextField(axis:) se revisó frente al deployment iOS 18.2; verificación definitiva en Xcode pendiente. Todas las pruebas funcionales usan DOM/reglas/transporte simulado; ninguna prueba real ni modificación de Supabase/Auth/SQL. Pasos manuales y revisión de tamaños iPhone documentados en el informe.
