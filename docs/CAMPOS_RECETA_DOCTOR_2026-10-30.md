# Campos de receta del Doctor coherentes con el Paciente — 30 de octubre de 2026

## Cambio

Se igualaron los campos de captura de recetas del Doctor con los que presenta la tarjeta del Paciente:

| Presentación Paciente | Captura Doctor |
|---|---|
| Medicamento | Nombre/selección de medicamento |
| Dosis | Valor positivo y unidad de dosis |
| Cada | Frecuencia en horas |
| Vía | Vía de administración |
| Durante | Días de duración o fechas de tratamiento en el formulario conectado |
| Cantidad | Cantidad a dispensar |
| Observaciones | Texto de observaciones/indicaciones |

Pendiente/Retirada siguen siendo estados de entrega de farmacia, no una selección que pueda marcar el Doctor al prescribir.

Se revisaron y actualizaron **ambos flujos existentes**: la receta local añadida desde el expediente (antes solo medicamento e indicaciones) y el formulario de emisión clínica conectado (que ya tenía medicamento/dosis/unidad/vía/frecuencia/cantidad/fechas). No se eliminaron las validaciones de consulta abierta, catálogo institucional, firma o idempotencia.

## Expediente local

La receta local ahora requiere medicamento, dosis, unidad, frecuencia, vía, días, cantidad y observaciones. Los valores de dosis/frecuencia/cantidad deben ser positivos y válidos; aceptan coma o punto. La duración es un entero positivo y el texto no admite solo espacios. Se guarda un snapshot estructurado ClinicalPrescriptionDetails y su equivalente JS, asociado al paciente y autor de la cuenta activa. La ficha muestra los campos por separado.

La receta del prototipo continúa marcada como **local / no emitida**; no crea una receta clínica en Supabase. No se conceden controles de prescripción al Paciente. Las observaciones generales siguen funcionando sin exigir datos de medicación.

## Formulario conectado

Se añadió Durante (días), se usa Observaciones como etiqueta del campo instructions y se amplió la vista previa de cada medicamento a todos los datos. Se conserva el catálogo autorizado para medicamento, unidad y vía, dosis decimales, múltiples renglones, retirar renglones y confirmar emisión.

La duración se representa con los campos existentes `starts_on`/`ends_on`: fecha inicial más días menos uno, contando ambos días. Ejemplo validado: inicio 2026-10-30 y diez días produce fin 2026-11-08. No se envía un parámetro days no soportado por la RPC. Se puede usar la fecha final directamente; si no se especifican días ni fin se conserva «Hasta nueva indicación», comportamiento previo necesario para tratamientos sin fin definido. Cambiar de paciente descarta el borrador y la duración.

La emisión conectada conserva `mobile_issue_prescription` y su validación de consulta abierta. La interfaz no altera el estado de retiro del paciente ni publica recetas de prueba. La proyección de lectura actual todavía combina indicaciones del medicamento en texto; exponer todos los campos estructurados al Paciente real sigue requiriendo la adaptación de lectura descrita en RECETAS_PACIENTE_2026-10-30.md.

## Archivos

- `Modules/ClinicalLabDesignModels.swift`: ClinicalPrescriptionDetails, validación y snapshot en entradas locales.
- `Modules/ClinicalLabDesignView.swift`: campos completos en Añadir receta y presentación en la ficha.
- `Modules/MobileModuleView.swift`: DoctorPrescriptionView, duración, fechas y vista previa completa.
- `web-preview/clinical-labs.js`: formulario local equivalente, validación y persistencia del snapshot en memoria.
- `web-preview/modules.js`: formulario conectado, duración traducida a fechas y vista previa de todos los campos.
- `scripts/test-clinical-labs.mjs` y `scripts/test-modules.mjs`: campos obligatorios locales y emisión simulada con duración.

Sin nuevas dependencias, tablas, RPC ni cambios en project.pbxproj o permisos.

## Verificaciones

Aprobados los recorridos de laboratorios/expediente local, incluyendo receta incompleta bloqueada y guardado de todos los campos. Aprobados los siete flujos clínicos previos; la receta simulada verifica dosis decimal, cantidad, autoría/vínculo de consulta, observaciones, fechas e inexistencia del parámetro days en el transporte. Preview, sintaxis JS, comprobador portable y git diff --check aprobados.

No se emitieron recetas ni se ejecutaron pruebas reales contra Supabase. La compilación/pruebas Swift en Mac y la revisión visual en navegador/dispositivo permanecen pendientes.
