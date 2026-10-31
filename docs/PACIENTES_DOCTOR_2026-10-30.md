# Pacientes del Doctor: búsqueda y ficha interna — 30 de octubre de 2026

Se rediseñó Pacientes en SwiftUI y web, siguiendo la paleta vino/rosa y las cards del proyecto. El flujo reutiliza el expediente tipo ticket interno, sin ventanas externas ni nuevas rutas. Se conserva el módulo conectado mediante el control de flujo existente.

## Diseño y comportamiento

- Cabecera vino «Tus pacientes, su evolución», con instrucciones breves.
- Búsqueda única por nombre o DUI, aceptando DUI con/sin guion, espacios laterales y nombres sin acentos en los ejemplos.
- Fecha de atención y accesos Todos / Hoy / Mañana. Se combinan fecha y texto, y se muestra el número de coincidencias y un vacío claro si no hay resultados. La fecha corresponde a una atención/cita de la agenda, no a nacimiento o registro del paciente.
- Tarjetas con iniciales, nombre, DUI, edad, teléfono, última/próxima atención, consultas previas y estudios pendientes. La acción abre «Ver ficha e historial» sin salir del marco de la aplicación.
- Ticket con datos personales, cronología de consultas propias, signos vitales disponibles, notas/recetas y laboratorios/resultados. Volver conserva los filtros. Las citas programadas sirven para encontrar al paciente por fecha, pero no se presentan como antecedentes clínicos realizados.
- Notas y solicitudes se comparten con Expedientes y Laboratorios; cambiar de módulo cierra la ficha interna y conserva el paciente/datos locales.

La demostración incluye María López (consulta hoy y hace siete días), Carlos Mendoza (atención de hoy) y Ana Reyes (primera cita mañana, sin consultas previas). Se incluye una consulta de otro doctor únicamente para comprobar que se excluya. Los casos son ficticios y están identificados en la interfaz.

## Datos y aislamiento

El componente local `ClinicalLabDesignStore` se amplió con `ClinicalPatientVisit` y su equivalente JS. Cada visita tiene paciente, doctor, fecha, motivo, plan y estado. `ownVisits` filtra por paciente y por doctor activo. Al configurar el contexto autenticado se reasignan solamente las visitas locales del doctor representado a su identificador actual; no se modifican registros de servidor. La consulta ajena permanece excluida.

El nombre/identificador del Doctor se toma de la sesión cargada cuando existe. Los pacientes, DUI, fechas e historiales de esta vista siguen siendo ejemplos locales; no se afirma una búsqueda real por DUI en Supabase ni se crean datos clínicos remotos. La proyección real anterior no dispone de todos esos campos y se conserva intacta mediante Ver flujo conectado o el interruptor SwiftUI.

Los filtros de fecha/texto limitan las coincidencias, pero abrir una ficha muestra todas las consultas previas disponibles de ese paciente con ese doctor. El aislamiento clínico real sigue delegado a las RPC/RLS existentes cuando se utiliza el módulo conectado; las guardas locales no reemplazan permisos de servidor.

## Archivos

- `Modules/ClinicalLabDesignModels.swift`: modelo de visitas, fixtures, contexto del Doctor y filtrado de consultas propias.
- `Modules/ClinicalLabDesignView.swift`: cabecera, búsqueda combinada, tarjetas, filtro de atención y cronología dentro del ticket.
- `ContentView.swift`: integra Pacientes con el estado compartido y evita la búsqueda genérica duplicada en este flujo.
- `web-preview/clinical-labs.js`: réplica de tarjetas, filtros e historial compartido.
- `web-preview/app.js`: rediseño visible por defecto también en sesión Doctor y transición de módulos conservando el flujo conectado.
- `web-preview/style.css`: tarjetas con iniciales, resumen de seguimiento y cronología.
- `scripts/test-doctor-patients.mjs`: regresiones de búsqueda/ficha en diseño y sesión simulada.
- `scripts/test-doctor-dashboard.mjs`: adapta la navegación nueva y mantiene la regresión de historial real con transporte de prueba al seleccionar flujo conectado.

No se agregaron dependencias ni rutas, ni se cambió la navegación del Paciente, la autenticación o el backend. Mis citas sigue ausente del Doctor. El historial permanece en Pacientes/Expediente, sin trasladarlo al dashboard.

## Verificaciones

Se aprobaron los dos recorridos nuevos de Pacientes (diseño y sesión simulada): DUI, nombre sin acentos, filtro combinado por fecha, fechas futuras, ausencia de coincidencias, fichas internas, datos personales, consultas propias, exclusión de otro médico/paciente, conservación de filtros y seguimiento compartido. También aprobaron las regresiones de dashboard y laboratorio, el preview, el comprobador portable y git diff --check. Se verificó sintaxis JavaScript.

Pendientes: compilación/pruebas Swift en Mac y comparación visual en navegador/dispositivo. Las pruebas DOM no acreditan una revisión visual. No se hicieron pruebas reales ni escrituras de Supabase.

Para verlo, recargar la web y abrir **Doctor → Pacientes**. Probar «Hoy», «Mañana» o `012345678`; seleccionar una coincidencia para abrir el ticket. El prototipo se muestra por defecto en la sesión Doctor; el flujo conectado anterior sigue disponible.
