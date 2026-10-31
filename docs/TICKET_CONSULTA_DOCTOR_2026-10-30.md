# Lista y ticket de consulta del Doctor — 30 de octubre de 2026

## Implementación

Se revisó directamente `docs/design-reference/Captura de pantalla 2026-10-30 180312.png`. Se mantuvo el lenguaje visual existente: vino, rosa, fondo claro y tarjetas blancas. El ticket utiliza círculo vino con check blanco según la petición, título grande, bloque central de fecha/hora en negrita y botón azul `#2196F3` tomado de la captura. La captura tiene check azul; se priorizó explícitamente la indicación del usuario de usar vino para el círculo. El check es decorativo: el estado real de la consulta sigue visible, sin convertir una cita cancelada en confirmada.

Las tarjetas ahora muestran paciente, edad, teléfono, hora, motivo y síntomas; se mantienen calendario, búsqueda, fechas rápidas y estados existentes. **Ver detalle** abre una hoja SwiftUI desde la tarjeta seleccionada y un panel inline en la tarjeta web, sin ruta nueva ni pantalla desconectada. **Volver a consultas** cierra el ticket. Web expone región accesible, estado expandido y foco al abrir/cerrar; iOS usa la hoja nativa desplazable. Los textos largos pueden envolver y el contenido del ticket se desplaza.

Abrir el ticket es una operación de presentación y no selecciona ni modifica el borrador clínico. **Abrir atención**, visible solo para citas reales, conserva la selección y la carga autorizada del formulario clínico existente. Los ejemplos no tienen esa acción ni escrituras.

## Datos y faltantes

| Campo | Fuente actual y comportamiento |
|---|---|
| Paciente | `DoctorAppointment.patient_name` / `appointment.patient_name`; vacío o espacios: **No hay datos reales** |
| Edad | Nuevo opcional `age` entero en el mismo modelo/objeto; sin dato o negativo: **No hay datos reales**; cero es válido |
| Teléfono | `phone`, ya disponible en `doctor_workspace`; nulo, vacío o espacios: **No hay datos reales** |
| Hora | `period` y formateadores existentes; horario no interpretable: **No hay datos reales** |
| Fecha del ticket | Fecha seleccionada de la agenda que alimenta el intervalo de la consulta; si el horario es inválido, se muestra el marcador de faltante |
| Motivo | Nuevo opcional `reason`; ausencia o texto vacío: **No hay datos reales** |
| Síntomas | Nuevo opcional `symptoms`, lista de textos; se eliminan entradas vacías; lista ausente/vacía: **No hay datos reales** |

La proyección versionada actual de `doctor_workspace` incluye nombre, teléfono, periodo, expediente y estado, pero **no expone edad, motivo ni síntomas**. Se añadieron opcionales compatibles en el modelo para poder recibirlos cuando estén disponibles; no se modificó SQL ni se aplicaron cambios al backend. Mientras falten, se muestran etiquetas y el texto solicitado. No se derivan síntomas desde diagnósticos ni se atribuyen notas clínicas al motivo original del paciente. Una lista de síntomas vacía no se interpreta como «Ninguno».

Los mismos ejemplos locales ya existentes se enriquecieron en ambas plataformas: Carlos Mendoza (42 años, 7123-4567, Consulta de seguimiento, Tos/Fiebre), María López (67, 7234-5678, Revisión de resultados, síntomas ausentes), Juan Pérez (35, 7356-7890, Evaluación general, Dolor de cabeza) y Lucía García (29, teléfono/motivo/síntomas ausentes). Los ejemplos quedan identificados como ficticios, separados del workspace y nunca se envían al servidor. Se conserva la política de agenda vacía descrita en CONSULTAS_DOCTOR_2026-10-30.md.

## Archivos

- `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorConsultationAgendaView.swift`: tarjetas completas, datos de ejemplo enriquecidos y selección de hoja.
- `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorConsultationTicketView.swift`: ticket, campos reutilizables y normalización de faltantes. Archivo del grupo sincronizado en el target principal, sin modificar el proyecto Xcode.
- `HospitalUniversitario/HospitalUniversitario/Core/DoctorModels.swift`: opcionales `age`, `reason` y `symptoms` en DoctorAppointment, sin cambiar campos anteriores.
- `web-preview/doctor-dashboard.js`: tarjetas y panel de detalle, misma normalización y ejemplos, cierre y apertura separada de atención.
- `web-preview/style.css`: jerarquía de campos y ticket con los colores de referencia.
- `scripts/test-doctor-consultations.mjs`: recorridos ajustados al ticket, campos presentes/faltantes, texto largo, edad cero, estado cancelado y separación de la atención.

Sin dependencias nuevas, cambios de arquitectura, autenticación, RPC, RLS ni rediseños de otros módulos. Continúan vigentes historial en Pacientes, horario en Mi horario y ausencia de Mis citas en Doctor.

## Verificación y límites

Se ejecutaron pruebas DOM del preview y de la agenda/ticket con transporte simulado, además de los siete recorridos funcionales del módulo clínico; aprobaron. Se cubrieron apertura/cierre, datos completos, valores ausentes, síntomas parciales, edad cero, texto largo, estado original, ejemplos sin llamadas clínicas y apertura separada del formulario autorizado. Sintaxis JavaScript, comprobador portable del proyecto y git diff --check aprobados tras la corrección de un conflicto de nombre local detectado al validar JavaScript.

No se ejecutaron Xcode, pruebas Swift, revisión visual en navegador/dispositivo ni consultas reales contra Supabase. La prueba de textos largos es DOM, no una medición visual de desbordamiento. Quedan pendientes compilación y validación nativa en Mac y comparación visual final de ambas plataformas.

Para verlo en Windows, ejecutar el servidor habitual, seleccionar diseño **Médico**, abrir **Consultas** y pulsar **Ver detalle**. El Preview SwiftUI **Consultas · agenda local** utiliza las mismas tarjetas y abre la misma hoja desde ellas.
