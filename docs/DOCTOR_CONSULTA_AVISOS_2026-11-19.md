# Doctor: consulta, avisos e historial — 19 de noviembre de 2026

## Alcance implementado

iOS/SwiftUI y web-preview avanzan juntos. Dashboard con campana y contador, bandeja personal ordenada de más reciente a más antigua, lectura y paginación. Avisos de asignación/reprogramación desde un trigger sobre appointments; recordatorio 15 minutos antes generado al actualizar la bandeja. Actualización cada 30 segundos en primer plano, sin recargar los campos de consulta.

Detalle → Abrir consulta llama a doctor_native_start; el servidor valida médico, cita, expediente y horario (desde 30 minutos antes). Muestra En consulta. Área de trabajo con identidad, expediente/historial previo desplegable, evaluación y observaciones, medidas y signos vitales, diagnóstico y plan. Terminar consulta solicita confirmación, guarda primero y después usa doctor_native_finish con la versión guardada. Un fallo de guardado impide finalizar. El estado pasa a Completada; la nota queda no editable mediante la app.

Mi expediente conserva datos personales, antecedentes y laboratorios e incorpora acceso al historial propio. El historial presenta consultas finalizadas, médico autor, observaciones, diagnóstico, plan y medidas; admite paginación por fecha/id. No muestra borradores ni sustituye vacíos por ejemplos. El mismo médico puede revisar sus consultas previas en doctor_native_chart.

## Backend inspeccionado y desplegado

Proyecto verificado por URL: uvebpsbbwofthucghccc. Inspeccionadas tablas, restricciones, índices, triggers, definiciones doctor_native_*, funciones de notificaciones y políticas RLS; no se consultaron historias clínicas reales para diseñar las pantallas.

- Migración doctor_consultation_experience_v1: supabase/doctor-consultation-experience.sql. Reutiliza notifications y su índice de eventos únicos; añade trigger doctor_appointment_notice, doctor_native_alerts y helper de autoría. Cambia únicamente SELECT de clinical_encounters y diagnoses: autor médico activo o paciente propietario tras cierre.
- Migración patient_completed_consultation_history_v1: supabase/patient-consultation-history.sql. RPC de lectura propia, identidad desde auth.uid(), rol paciente activo, sin patient_id/doctor_id suministrados como autorización. Incluye nombre del médico sin ampliar lecturas de perfiles ajenos.
- Autorización de privacidad aclarada expresamente por el usuario: solo médico que atendió y paciente para notas, diagnóstico e historial. Los permisos operativos de enfermería sobre signos vitales, laboratorios, farmacia, ingreso y recepción no fueron revocados. Esos módulos no adquieren acceso a las notas por estas RPC.
- Se reutilizaron doctor_native_start/save/finish existentes; no se restauró SQL histórico, ni se modificó registro/Auth, ni el proyecto externo de recepción. No se crearon tablas clínicas.
- Respaldo de políticas y conteos previos en .local/doctor-experience-baseline-2026-11-19.json (local, excluido de Git).

## Avisos: alcance y límites

La asignación se persiste incluso con clientes cerrados; se muestra al sincronizar. La web muestra bandeja, contador y aviso en pantalla mientras está abierta. No hay web push ni APNs configurados para asignaciones nuevas con la aplicación cerrada.

iOS utiliza UserNotifications y el botón Activar recordatorios en este iPhone. Programa hasta 50 citas autorizadas de los próximos siete días, 15 minutos antes; no incluye nombres ni notas clínicas en el aviso del sistema. Las citas que ya están dentro de los 15 minutos aparecen en la bandeja al sincronizar. Los cambios/cancelaciones se reconcilian al siguiente refresco: sin conexión pueden quedar recordatorios locales obsoletos hasta reabrir. Cerrar sesión elimina los avisos locales. No se afirma entrega en un dispositivo real.

Referencia de API consultada: [programar notificaciones locales — Apple](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app). Notificaciones nuevas con la app cerrada requieren una integración push y configuración Apple adicional.

## Verificaciones realizadas

- Supabase real: supabase/test-doctor-experience-rollback.sql pasó con identidades y registros exclusivamente transaccionales, revertidos. Verifica asignación, recordatorio sin duplicados, rol/categoría, agenda, apertura idempotente, guardado de notas/vitales, receta/laboratorio, cierre atómico, inmutabilidad, paciente sin acceso a borrador y con historial finalizado, rechazo de otro médico aun asignado al paciente, aislamiento de avisos y prohibición de publicar resultados desde doctor.
- La prueba histórica requería adaptar localidad obligatoria a Santa Ana y capturar insufficient_privilege del laboratorio; se adaptó el test a las reglas vigentes, no el backend a la prueba.
- Comprobación posterior: cero cuentas temporales; 8 citas, 16 notificaciones y cero consultas/diagnósticos/vitales, iguales al preflight. anon sin EXECUTE en las dos RPC nuevas.
- Pruebas locales con DOM/transporte simulado: test-preview, test-core, test-patient-registration, test-doctor-preview-live, test-doctor-directory, test-doctor-laboratory, test-doctor-admissions y test-doctor-alerts-history. Incluyen apertura desde detalle, peso/altura, fallo de guardado sin cierre y lectura del historial por el paciente.
- Comprobador portable check-project.py y git diff --check. Prueba Swift finishingNeverClosesWhenSaveFails preparada en DoctorModuleTests; NO ejecutada.
- Asesores Supabase revisados: siguen avisos previos de extensión en public, protección de contraseñas y tablas protegidas sin políticas. Las dos RPC nuevas añaden dos avisos de SECURITY DEFINER ejecutable por authenticated (89 total); su ejecución está prevista y valida identidad/rol internamente. [Explicación del asesor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Pendientes y revisión manual

No hay compilación ni ejecución nativa acreditada: abrir el proyecto con Xcode 16.2+, iOS 18.2+, ejecutar ⌘R y ⌘U; comprobar permisos, aviso local, cierre de sesión y cambios de horario en un dispositivo. No se añadieron recursos con rutas absolutas ni dependencias nuevas.

El intento de revisión visual mediante el navegador de herramientas falló al iniciar su runtime. No se afirma revisión visual web ni SwiftUI. En Windows, ejecutar el servidor indicado en README, recargar con Ctrl+F5 e ingresar con una cuenta doctor autorizada. Revisar Dashboard → campana → Consultas → detalle → apertura; utilizar datos clínicos reales solo en una atención legítima, nunca crear datos de producción para probar el diseño.

Se conservaron los cambios locales previos, incluidos los de citas del paciente; no se hizo commit ni push.

## Ajuste visual posterior del 19 de noviembre

Panel general con un solo saludo, una campana, sin buscador en Inicio, resumen en tres contadores y próxima cita separada. Accesos rápidos limitados a Agenda, Pacientes, Laboratorios e Ingresos; Consultas y Recetas siguen disponibles en la navegación habitual.

Notificaciones abre un popover/panel sobre la pantalla actual. Cierre por botón/exterior y Escape en web, lectura, fecha, actualización y paginación. Marcar leído no vuelve a cargar el expediente ni la consulta; conserva el borrador. Mismos avisos y permisos existentes.

Revisión visual nueva ejecutada en navegador local y modo diseño Doctor: saludo único, resumen, panel vacío anclado y cierre con foco en la campana. Las notificaciones con contenido y lectura se verificaron con DOM/transporte simulado. Sin escrituras a Supabase en este ajuste. La revisión visual pendiente del informe original queda superada únicamente para estas vistas web en modo diseño; SwiftUI continúa pendiente de Mac.
