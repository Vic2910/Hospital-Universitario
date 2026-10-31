# Recetas en el dashboard del Paciente — 30 de octubre de 2026

## Interfaz y navegación

Se sustituyó la card **Paciente** del dashboard por **Recetas**, enlazada al destino `prescriptions` existente. En SwiftUI y web se usa una composición basada en `docs/design-reference/receta.png`, revisada directamente: tarjeta blanca redondeada por medicamento, estado de retiro en la parte superior, nombre destacado, filas de dosis/frecuencia/vía/duración/cantidad separadas por líneas discontinuas y observaciones al final. Se conserva la paleta vino, gris, blanco y fondos existentes verde/amarillo para estados.

Las recetas se ordenan por fecha de emisión de más reciente a más antigua. Se conservan búsqueda y paginación; los resultados vacíos o fallos tienen mensajes y reintento según corresponda. La vista del Paciente es de solo lectura y no cambia el estado de farmacia.

Para no perder el acceso anterior de la card retirada, **Agendar cita** se mantiene dentro de **Mis citas**, junto al flujo existente de Solicitar atención. No se eliminó la vista de agendamiento ni se restauró Mis citas al Doctor.

## Estados de retiro y datos

La interfaz distingue **Pendiente** y **Retirada** cuando la fuente lo indica. Los ejemplos muestran ambos estados, en fechas 30 oct 2026 y 1 oct 2026. Se identifican como «Recetas de ejemplo · No corresponden a una prescripción real». Uno es un medicamento genérico de ejemplo y otro utiliza la composición ilustrativa de CLARITROMICINA 500 MG / TABLETA de la captura; no se prescribe ni se emite medicación real.

Los ejemplos se muestran en diseño y tras una lectura autorizada exitosa sin recetas, siguiendo la convención vigente del prototipo. Nunca se mezclan con recetas reales ni se importan al servidor. En sesión real se conserva `mobile_module` con rol patient/módulo prescriptions y el propietario se resuelve en servidor.

**Limitación importante de la proyección actual:** `active`, `expired` o `scheduled` describen tratamiento/fechas; no demuestran retiro de farmacia. No se reinterpretan como Retirada o Pendiente. El adaptador acepta un campo explícito Estado de retiro y estados de entrega `dispensed`, `collected`, `withdrawn` o `pickup_pending`; si la respuesta no aporta entrega, muestra **Retiro por confirmar**. No se modificaron RPC, estados ni permisos de servidor para inventar esa información.

La respuesta real existente combina la dosis, vía, frecuencia e instrucciones en el texto de cada medicamento. El adaptador conserva ese texto íntegro en Observaciones y muestra No hay datos reales en columnas que no pueda obtener de forma estructurada, evitando interpretar incorrectamente instrucciones clínicas. Los ejemplos sí contienen las columnas separadas. Conectar todos los campos y estados de farmacia requiere ampliar la proyección autorizada en un trabajo posterior.

## Archivos

### iOS/SwiftUI

- `Patient/PatientDashboardView.swift`: acceso Recetas en lugar de Paciente.
- Nuevo `Patient/PatientPrescriptionsView.swift`: modelos Codable, ejemplos, adaptador de MobileItem, tarjetas y orden/estados.
- `ContentView.swift`: integra la vista solo para prescriptions del Paciente, reutilizando carga y paginación.
- `Modules/MobileModuleView.swift`: conserva Agendar cita dentro de Mis citas.

Los archivos nuevos pertenecen al grupo sincronizado del target principal. Sin cambios en project.pbxproj ni dependencias nuevas.

### Web

- Nuevo `web-preview/patient-prescriptions.js`: modelo equivalente y renderer de recetas del Paciente.
- `web-preview/app.js`: cambio de acceso e integración del listado; agendamiento conservado en Mis citas.
- `web-preview/modules.js`: acceso a Agendar cita en el listado real existente.
- `web-preview/{index.html,server.mjs,style.css}`: nuevo recurso permitido, carga y estilos acotados.
- `scripts/{test-patient-prescriptions,test-preview}.mjs`: pruebas específicas, nuevo script y recorrido de agendamiento adaptado a su acceso actual.

No se alteró el módulo de prescripción del Doctor, la autenticación, las recetas reales ni otras rutas.

## Verificaciones

Se aprobaron: prueba de dashboard/listado en diseño y sesión vacía, orden de fechas, dos estados, campos de medicamento, búsqueda y ausencia de escrituras; recetas reales simuladas sin mezcla de ejemplos y sin confundir tratamiento activo con retiro; ocho recorridos previos del preview y dos de agendar cita; siete flujos clínicos existentes. Comprobador portable, sintaxis JS y git diff --check aprobados.

Se actualizó únicamente la instancia del servidor local gestionada por el agente para cargar el nuevo recurso, sin duplicar puertos; `/patient-prescriptions.js` responde HTTP 200 en 4173. Para verlo, recargar con Ctrl+F5 y pulsar **Recetas** en Accesos rápidos del Paciente.

Pendientes: compilación/pruebas Swift en Mac y revisión visual real en navegador/dispositivo. No se ejecutaron pruebas reales contra Supabase ni cambios de backend.
