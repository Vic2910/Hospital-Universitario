# Laboratorios del expediente del Doctor — 2026-10-31

## Cambio implementado en SwiftUI y web

Dentro del expediente seleccionado se retiran tipo de examen y filtro por fecha. Se muestran directamente todas las solicitudes del paciente, ordenadas por fecha de solicitud descendente (más recientes primero), con día/mes, fecha/hora, nombre del examen, estado y resumen de disponibilidad. El orden usa fechas reales del modelo; no se inventa una fecha de realización que el modelo no tiene. El vacío informa que el paciente aún no tiene exámenes registrados.

Las tarjetas tienen fondo blanco, borde redondeado, acento lateral vino, fecha destacada y botón Ver examen. Pendiente, En Proceso y Completado conservan texto y colores existentes. Un completado sin informe indica que la publicación está pendiente.

Ver examen sustituye el contenido por un ticket interno con Volver en la esquina, fecha/examen destacados, estado y secciones Solicitud de laboratorio, Datos del paciente y Resultado del examen. Incluye solicitante, clínica, turno, motivo, nombre, DUI, expediente, edad, teléfono, correo y mediciones disponibles. En completados muestra fecha de publicación, valores/unidades/referencias y observación del laboratorio; si no hay informe lo indica. Pendiente y En Proceso presentan mensajes propios, sin mostrar resultados ni valores de otro examen. El icono de espera no indica falsamente que el pendiente esté completado.

Volver y el botón inferior regresan al expediente o a Solicitudes y resultados, según el origen, conservando al paciente seleccionado. Se mantienen Añadir observación/Añadir receta del Doctor, vinculadas al ID del examen. El detalle verifica que ese ID pertenezca al paciente activo. La publicación local existente actualiza el detalle visible y el estado sin duplicar solicitudes.

Los filtros se conservan en la vista independiente Solicitudes y resultados de Laboratorio; se retiran específicamente del bloque del expediente. No cambia la búsqueda inicial de pacientes.

## Archivos

- `HospitalUniversitario/HospitalUniversitario/Modules/ClinicalLabDesignView.swift`: cronología, exclusión de filtros del expediente, selección de examen y ticket interno, navegación de retorno y resultados por estado.
- `web-preview/clinical-labs.js`: réplica de lista, ticket, selección aislada, retorno y reacción a resultados publicados.
- `web-preview/style.css`: cards, acento lateral, fechas e indicadores de valores con la paleta existente.
- `scripts/test-clinical-labs.mjs`: pruebas ajustadas a la apertura explícita del detalle y nuevos casos de orden cronológico, ausencia de filtros y estados sin resultados.
- README.md, docs/README.md y docs/BITACORA.md: documentación.

## Verificaciones ejecutadas

- `node --preserve-symlinks --preserve-symlinks-main scripts/test-clinical-labs.mjs`: solicitud/validación, orden descendente, tres estados, expediente sin filtros, resultados con referencia, retorno superior/inferior, notas/recetas, paciente solo lectura, aislamiento, autor de cuenta activa, rechazo de publicaciones antiguas y actualización reactiva sin duplicados. Aprobado.
- `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`: recorridos de Doctor/Paciente, 20 pantallas y formulario. Aprobado.
- `python scripts/check-project.py`, sintaxis JS de clinical-labs.js y `git diff --check`: aprobados.
- El servidor existente devuelve `/clinical-labs.js` HTTP 200/no-store con las cards nuevas, sin levantar otra instancia.

Son pruebas DOM/transporte simulado y HTTP local. Se mantiene el prototipo clínico local existente, identificado como ejemplo, y el acceso alternativo al módulo conectado. No se modificaron RPC, RLS, autenticación, esquema ni datos clínicos reales; no se importaron solicitudes de prueba. Pendiente compilación SwiftUI en Mac, revisión visual en navegador y conexión real del prototipo a las publicaciones de laboratorio de Recepción.


## Ajuste posterior: Laboratorio solo solicita, Expedientes consulta

Por petición del usuario, tras seleccionar paciente en Laboratorio del Doctor queda únicamente Solicitar exámenes. Se retiran Ver expediente y Ver solicitudes y resultados de esa card en SwiftUI y web. El acceso a resultados del Paciente se conserva. El Doctor consulta resultados entrando a Expedientes; allí el botón de cada estudio se llama Ver detalle.

El detalle muestra valores/informe exclusivamente en Completado. Pendiente y En Proceso conservan sus estados y mensajes sin resultados. La operación local existente de publicación actualiza el estudio a Completado; no se marca como completado al abrirlo ni se inventan resultados.

Archivos de este ajuste: Modules/ClinicalLabDesignView.swift, web-preview/clinical-labs.js, scripts/test-clinical-labs.mjs y scripts/test-doctor-patients.mjs. Se verificaron la ausencia de los dos botones en Laboratorio, el acceso independiente por Expedientes, Ver detalle con Completado y resultados, y pendientes/procesamiento sin resultados. test-clinical-labs, test-doctor-patients (diseño y sesión simulada), test-preview, check-project.py y git diff --check aprobaron. No se compiló Swift ni se probaron operaciones reales en Supabase. Esta decisión sustituye el acceso directo al expediente desde Laboratorio indicado en avances anteriores.


## Ajuste posterior: datos personales y retirada de solicitud desde Expedientes

Se elimina el botón Solicitud de laboratorio de la sección Expedientes del Doctor en SwiftUI y web. Solicitar exámenes se conserva en Laboratorio. No se elimina el bloque informativo Solicitud de laboratorio del detalle de un estudio, que describe su procedencia y no crea solicitudes.

Datos personales del expediente presenta ahora una cabecera suave con iniciales y nombre del paciente, una cuadrícula para Nombre/Apellido/Edad/DUI y filas de contacto con iconos para correo, teléfono y expediente. Se reutilizan la paleta vino/rosa, los datos del paciente seleccionado y los normalizadores existentes, sin edición ni campos inventados. Se mantienen historial, laboratorios, resultados y acciones de notas/recetas.

Archivos: Modules/ClinicalLabDesignView.swift, web-preview/{clinical-labs.js,style.css}, scripts/test-clinical-labs.mjs. Pruebas aprobadas: test-clinical-labs (ausencia de solicitud y cuatro campos/tres filas, más flujos existentes), test-doctor-patients (diseño/sesión simulada), test-preview (20 pantallas), check-project.py y git diff --check. Son verificaciones con DOM/transporte simulado; quedan pendientes compilación Xcode y revisión visual. No se modificó Supabase. Esta decisión reemplaza el acceso histórico de crear laboratorios desde Expedientes.


## Ajuste posterior: paciente primero y resultados con mayor jerarquía

En Ver detalle de examen se muestra primero la tarjeta Paciente, únicamente con Nombre completo, Edad y Teléfono; nombre destacado, iniciales y franja de contacto. Se ocultan del detalle DUI, expediente, correo, peso y altura, conservando esos datos en sus modelos y en el expediente completo. La cabecera genérica ya no antepone el examen ni repite datos personales adicionales.

Después se presenta Información del examen: nombre, estado, fecha destacada, tipo, solicitante, turno, clínica y motivo. Resultado del examen utiliza tarjetas por determinación con nombre de prueba, etiqueta Valor obtenido, valor/unidad destacados y referencia separada visualmente. Se mantienen fecha de publicación y observación del laboratorio. Los resultados continúan disponibles solo para Completado; Pendiente/En Proceso conservan mensajes sin valores. Volver, notas/recetas y la actualización reactiva siguen funcionando. No hay interpretación automática de valores.

Archivos: Modules/ClinicalLabDesignView.swift, web-preview/{clinical-labs.js,style.css}, scripts/test-clinical-labs.mjs. Test-clinical-labs verifica el orden de paciente antes del examen, los tres campos y la ausencia de los adicionales, junto con estados/resultados/retorno. Test-preview, check-project.py y diff --check aprobados. Verificaciones DOM/transporte simulados; pendientes Mac, revisión visual y conexión real del prototipo. Este ajuste sustituye la presentación anterior del detalle que listaba información del examen antes de todos los datos del paciente.
