# Consultas del Doctor: agenda visual — 30 de octubre de 2026

Se rediseñó la pantalla existente `consultation`, en SwiftUI y web, como agenda diaria. Se conserva la paleta vino/rojo, tarjetas blancas, fondo claro y jerarquía del panel de paciente; se reutilizan `PatientFormCard`, `HospitalCard`, `HospitalTheme`, `LinearGradient.vinoDestacado` y `.sched-*`.

## Comportamiento

- Inicio con fecha actual al entrar sin una selección clínica previa, encabezado de agenda, fecha y total de consultas.
- Calendario para buscar cualquier fecha, con accesos Hoy, Mañana y En 7 días.
- Tarjetas ordenadas por horario, con paciente, expediente, estado y detalle/selección. La búsqueda superior filtra por nombre o expediente.
- Cero coincidencias muestra un estado vacío y permite elegir otra fecha.
- En sesión real, cambiar la fecha recarga `doctor_workspace` con el intervalo local de medianoche a medianoche siguiente y conserva la sede autorizada. La identidad del médico sigue resuelta por el servidor.
- Seleccionar una cita real conserva el formulario previo y sus validaciones para iniciar, guardar, diagnosticar y cerrar consultas; el rediseño no elimina esa lógica ni cambia los permisos.

## Ejemplos precargados solicitados

El modo de diseño web y el Preview SwiftUI utilizan la misma agenda ficticia. También se presenta como **Agenda de ejemplo** cuando la consulta autorizada al servidor devuelve una lista vacía, atendiendo la petición actual del usuario. Esta presentación local es explícita, nunca se añade al workspace, no concede autenticación, no consulta expedientes de ejemplo ni puede iniciar/guardar atenciones. No se usa como sustituto ante errores de autorización/red.

Los ejemplos están anclados al día local actual: cuatro consultas hoy (Carlos Mendoza 08:30, María López 10:00, Juan Pérez 11:30 y Lucía García 14:00), dos mañana (09:00 y 11:00), una dentro de tres días (10:30) y una en siete días (08:30). Duran 30 minutos. Otras fechas quedan vacías; no se inventan consultas para todos los días. Los detalles de ejemplo solo explican que se trata de una demostración.

## Archivos

| Ruta | Cambio |
|---|---|
| `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorConsultationAgendaView.swift` | Vista nueva reutilizable, calendario, tarjetas, datos locales y Preview interactivo |
| `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift` | Integra la agenda antes del formulario clínico y recarga al cambiar la fecha |
| `HospitalUniversitario/HospitalUniversitario/ContentView.swift` | Inicia Consultas en hoy cuando no hay paciente seleccionado previamente |
| `HospitalUniversitario/HospitalUniversitario/Shared/screens.json` | Actualiza subtítulo y sección del destino existente |
| `web-preview/doctor-dashboard.js` | Clase HospitalDoctorConsultations, réplica de agenda y fixtures locales |
| `web-preview/app.js` | Conecta diseño, sesión vacía y citas reales con sus acciones separadas |
| `web-preview/modules.js` | Conserva carga por fecha y formulario; integra agenda sin duplicar calendario |
| `web-preview/style.css` | Tarjetas, encabezado vino, estados y accesos de fecha |
| `scripts/test-doctor-consultations.mjs` | Tres recorridos con transporte simulado |

El nuevo Swift pertenece al grupo sincronizado del target principal; no se modificó el proyecto Xcode ni se agregaron dependencias.

## Cómo verlo

Ejecutar `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs`, abrir `http://127.0.0.1:4173/`, elegir **Médico** en diseño y entrar en **Consultas**. Probar Hoy/Mañana/En 7 días y el calendario. En Mac, abrir el Preview **Consultas · agenda local** de `DoctorConsultationAgendaView.swift`.

## Verificaciones y pendientes

Los recorridos nuevos comprueban hoy, fechas futuras, calendario sin ejemplos, búsqueda por paciente, detalle local sin operaciones clínicas, sesión vacía, sesión con citas autorizadas, intervalo RPC por día y selección sin eludir validaciones. Los recorridos existentes del preview y los módulos clínicos se ejecutaron con transporte simulado; el comprobador portable del proyecto y git diff --check aprobaron. No se probaron accesos ni escrituras reales contra Supabase.

No hay compilación Xcode ni ejecución de pruebas Swift en Windows. Quedan pendientes la compilación en Mac y la revisión visual en navegador/dispositivo; las pruebas DOM no acreditan apariencia ni comportamiento nativo.
