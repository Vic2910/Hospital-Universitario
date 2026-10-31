# Laboratorio independiente y expediente modal — 30 de octubre de 2026

## Decisión vigente

La petición actual sustituye la restricción anterior de solicitar únicamente desde Expedientes. **Laboratorios** tiene búsqueda propia por DUI/nombre, selección de paciente y botón **Solicitar exámenes**, sin exigir abrir expediente. **Expedientes** conserva su destino y búsqueda propia, y abre la ficha completa en un modal. Se conserva el acceso anterior desde el expediente y el módulo conectado existente; no se eliminaron rutas ni operaciones clínicas.

La implementación de esta fase sigue siendo el prototipo local ya identificado en la interfaz. Las solicitudes, notas, recetas locales y publicaciones simuladas no se escriben en Supabase ni sobreviven al cierre/cambio de sesión. Esta aclaración es esencial: no se afirma que un dato de demostración sea un expediente clínico real.

## Solicitud modal

Se replica en SwiftUI mediante una hoja con NavigationStack y en web mediante un dialog nativo desplazable con backdrop, foco modal y cierre por Escape. Contiene paciente seleccionado, examen, motivo, peso en kg, altura en cm, fecha no editable y doctor solicitante. La clínica y el turno existentes se conservan.

La fecha se fija al abrir el formulario y se guarda con ese mismo timestamp. El nombre del doctor, cuando hay una sesión abierta, se toma de los datos cargados de la cuenta: workspace/profile; también se guarda su identificador de personal. Solo el modo diseño externo utiliza al Dr. Luis Ramírez ficticio. Los campos automáticos se presentan como texto, no como entradas editables.

Peso y altura son obligatorios, aceptan coma o punto y hasta dos decimales; se rechazan signos negativos, texto con unidades, notación exponencial y valores no finitos. Límites de captura del prototipo: 0,1–500 kg y 20–250 cm. No son rangos diagnósticos. Motivo obligatorio de hasta 2000 caracteres, sin aceptar solo espacios; examen debe existir en el catálogo. Se valida también el paciente completo y el rol Doctor.

**Solicitar** crea la solicitud Pendiente, cierra el modal y muestra confirmación. Conserva el vínculo al paciente, mediciones y autor. Cancelar no genera registros. El segundo envío del mismo formulario no duplica la solicitud.

## Expediente modal

Incluye datos personales completos disponibles, historial/signos vitales, notas/recetas y laboratorios por fecha/tipo/estado. Peso y altura proceden de la última solicitud registrada para ese paciente y muestran autor/fecha. Otros antecedentes o signos no disponibles se indican como ausentes; no se fabrican antecedentes para primeras visitas.

Las solicitudes nuevas aparecen en el mismo expediente mediante el store compartido, sin importar si se crearon desde Laboratorios o desde la ficha. Los resultados disponen de fecha de publicación, nombre de prueba, valor, unidad, referencia y narrativa del laboratorio. Las referencias del ejemplo están etiquetadas como ilustrativas y no constituyen resultados reales.

Desde el expediente o un resultado se pueden añadir observaciones o recetas **locales**. Se registra paciente, vínculo opcional al examen, autor y fecha. La receta local requiere medicamento e indicaciones y se identifica como «No emitida»; no reemplaza ni elude el módulo real de prescripciones, que sigue disponible con sus validaciones. La edición no está disponible para Paciente. No se pueden vincular notas a un examen de otro paciente.

## Recepción y actualización automática: alcance real

Se añadieron `applyPublishedResult` en ambos stores como entrada para un resultado publicado por un adaptador autorizado. Actualiza en el mismo registro estado Completado, valores, narrativa y fecha, y repinta/notifica al expediente observado automáticamente. Rechaza IDs desconocidos y publicaciones anteriores a la última recibida. La prueba simula la llegada de un resultado y verifica la actualización visible sin duplicación de solicitudes.

**Pendiente de conexión:** esta sesión no implementa ni despliega el proceso real de recepción, no crea permisos de recepcionista y no conecta un canal de eventos de Supabase al prototipo. Para actualizar resultados reales desde recepción se deberá conectar este adaptador a las RPC/eventos autorizados, mapear IDs institucionales y verificar permisos/estados con la sesión real. No basta con invocar un método de presentación para autorizar una publicación. Tampoco se afirman escrituras remotas de notas o recetas nuevas de este prototipo.

Los flujos conectados previos se conservan mediante **Ver flujo conectado** en web y el interruptor de diseño en SwiftUI. No se alteraron SQL, RLS, Auth, tablas, factores ni credenciales.

## Archivos y navegación

| Archivo | Cambio |
|---|---|
| `Modules/ClinicalLabDesignModels.swift` | Medidas, fecha fija, autor, resultados estructurados, observaciones/recetas y recepción de resultados publicados |
| `Modules/ClinicalLabDesignView.swift` | Laboratorio independiente; modales de solicitud, expediente y edición; validaciones y presentación por rol |
| `ContentView.swift` | Contexto de nombre/identificador del Doctor desde la cuenta cargada |
| `web-preview/clinical-labs.js` | Réplica de estado, guardas y modales, actualización del resultado observado |
| `web-preview/app.js` | Contexto del autor desde workspace/profile autenticados |
| `web-preview/style.css` | Modal nativo y tabla legible de resultados con valores/referencias |
| `scripts/test-clinical-labs.mjs` | Regresiones del nuevo flujo, validaciones y aislamiento |

Las rutas existentes chart y laboratory permanecen. Doctor sigue Inicio/Pacientes/Consultas/Laboratorios/Más; no se restaura Mis citas. Paciente conserva lectura de resultados propios y no recibe controles de creación/edición. Sin dependencias nuevas ni cambios de arquitectura.

## Cómo verlo y verificaciones

En la sesión Doctor o diseño Médico, abrir Laboratorios, buscar Ana Reyes y pulsar **Solicitar exámenes**. Completar examen, motivo, peso y altura; confirmar. **Ver expediente** lleva al módulo separado; seleccionar o abrir la ficha para ver el modal con la solicitud y las mediciones. María López tiene un ejemplo completado con tabla de valores. En SwiftUI el Preview «Laboratorios · solicitud independiente» permite el mismo recorrido local.

Pruebas ejecutadas con transporte simulado: preview (ocho recorridos previos y dos de citas), laboratorios (solicitud independiente, modal, validación, cuenta activa, notas/recetas, aislamiento y publicación observada), siete flujos clínicos existentes y consultas/ticket. Comprobador portable del proyecto y git diff --check aprobados. Se revisó sintaxis de JS. No hay pruebas reales de Supabase.

Pendientes: compilación/pruebas Swift en Mac, revisión visual real de modales y comparación navegador/iOS, y la conexión remota descrita arriba. Las pruebas DOM no acreditan foco/trampa de teclado visual ni compilación Xcode.


## Corrección visual vigente: tickets dentro de la app

Por la aclaración posterior del usuario, se retiraron tanto `dialog/showModal` de la web como la hoja `.sheet` de este flujo SwiftUI. Solicitud, expediente, resultados y editor de notas/recetas se presentan como paneles tipo ticket **dentro del área de contenido existente**, conservando el marco, encabezado y navegación de la aplicación. Esta decisión sustituye las referencias a modales externos de este informe.

La entrada de Laboratorio ahora muestra una introducción y búsqueda/selección de paciente, seguida de acciones claras. No se renderizan campos de solicitud ni filtros de laboratorio debajo de la búsqueda. **Solicitar exámenes** reemplaza el contenido por su ticket: botón Volver, círculo vino con check blanco decorativo, título, paciente, fecha/doctor destacados y grupos «01 · Examen y motivo» y «02 · Valoración clínica». La acción principal azul reutiliza la referencia de confirmación aportada. Los metadatos automáticos se compactaron, y peso/altura se presentan juntos.

**Ver solicitudes y resultados** abre otro ticket interno con filtros y lista, separado del formulario. **Ver expediente** abre la ficha interna con información personal, historial, notas, recetas y laboratorios. Volver retorna a la selección sin perder el estado compartido. Se retiró la búsqueda genérica duplicada del encabezado exclusivamente en este flujo local; los módulos conectados conservan la suya. No se alteraron datos, validación, permisos ni métodos de recepción de resultados.

Archivos ajustados: `Modules/ClinicalLabDesignView.swift`, `ContentView.swift`, `web-preview/{clinical-labs.js,app.js,style.css}` y `scripts/test-clinical-labs.mjs`. Las pruebas verifican ausencia de `dialog`, presencia de ticket interno, ausencia de formulario/filtros en la búsqueda, ausencia de filtros en la solicitud y acceso separado a resultados, además de todas las validaciones y aislamiento previos. Pruebas DOM, regresiones de módulos, sintaxis JS, comprobador portable y git diff --check aprobados. La apariencia final no se ha verificado en navegador real ni compilado en Xcode; siguen pendientes las comprobaciones visuales y nativas.
