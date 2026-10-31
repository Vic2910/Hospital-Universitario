# Expediente propio del Paciente: ticket interno — 30 de octubre de 2026

Se aplicó en SwiftUI y web el diseño de expediente interno del Doctor a la vista del Paciente, siguiendo la captura aportada: círculo vino con check blanco decorativo, título Expediente completo, nombre centrado, bloque rosa de identificación y tarjetas blancas ordenadas por sección. Permanece dentro del área de contenido de la app, sin dialog, sheet o ventana externa, y se abre directamente al entrar en su expediente.

## Datos, privacidad y permisos

En sesión real se reutilizan la carga y la respuesta existentes de `mobile_module` para `role=patient/module=chart`. El servidor resuelve el paciente de la sesión: el cliente no agrega un selector de paciente ni envía un ID ajeno. No se sustituye esa respuesta con María López ni con otras identidades de demostración.

La cabecera toma Nombre, Expediente y DUI de los campos autorizados de las secciones. Si un campo no viene o está vacío, se muestra No hay datos reales. La proyección versionada actual no expone DUI, por lo que no se inventa su valor. Se muestran las secciones ya disponibles (identificación, alergias, condiciones y antecedentes) y los documentos publicados, conservando su autorización/lectura existente. Si no hay documentos, el mensaje se refiere a documentos ausentes, sin afirmar que el expediente entero esté vacío.

El diseño es de solo lectura: sin búsqueda de otros pacientes, solicitud de exámenes, observaciones, recetas ni formularios. Se bloquea también la presentación de acciones de mutación de ítems dentro de chart. No se modificaron RLS, RPC, Auth ni datos clínicos.

En el modo diseño Paciente se abre directamente el ticket del paciente propio de ejemplo, con los avisos locales existentes; no se muestran resultados de búsquedas ni fichas de otras personas. La sesión real y el modo de diseño siguen separados. SwiftUI ya no requiere un interruptor de diseño para mostrar el ticket propio real.

## Archivos

- `Modules/MobileModuleView.swift`: cabecera y contenedor tipo ticket para chart de Paciente, faltantes y solo lectura; se reutilizan sus secciones/documentos.
- `ContentView.swift`: entrada directa al expediente real del Paciente y retirada de búsqueda/interruptor innecesarios en esa pantalla.
- `web-preview/modules.js`: réplica del ticket utilizando la respuesta propia existente y manteniendo documentos autorizados.
- `web-preview/clinical-labs.js`: apertura directa del ticket propio en diseño Paciente.
- `web-preview/app.js`, `style.css`: superficie interna sin buscador genérico y ajuste de tarjetas.
- `scripts/test-patient-chart.mjs`: pruebas de datos propios, faltantes, diseño y ausencia de formularios/controles clínicos.

No se añadieron rutas, modelos de pacientes alternativos, dependencias o cambios al proyecto Xcode.

## Verificación

Aprobados: recorrido nuevo de expediente Paciente con transporte simulado, incluyendo respuesta propia, campos faltantes y diseño separado; preview (ocho recorridos previos y dos de citas), laboratorios y siete flujos clínicos existentes; comprobador portable del proyecto y git diff --check. Se comprobó sintaxis JS. La prueba confirma que el request usa rol patient y no recibe un p_patient elegido desde la interfaz.

Pendientes: compilación/pruebas Swift en Mac y comparación visual real en navegador/dispositivo. No se hicieron pruebas reales contra Supabase. Las pruebas DOM no acreditan exactitud visual ni una auditoría nueva de RLS.

Para verlo: recargar la web, entrar como Paciente y abrir su expediente desde Inicio o Más. El modo diseño Paciente permite revisar la apariencia con ejemplos propios sin credenciales.

Actualización: la cabecera del ticket propio incluye **Volver** en la esquina superior izquierda y el rótulo FICHA CLÍNICA, igual que el Doctor. El botón regresa a Inicio mediante la navegación existente, tanto en sesión como en diseño; no cambia los datos ni los permisos.
