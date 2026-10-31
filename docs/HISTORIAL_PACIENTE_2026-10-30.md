# Historial médico del Paciente: tarjetas y detalle interno — 30 de octubre de 2026

## Resultado

Se rediseñó únicamente el destino Historial médico del Paciente (`history`), con su réplica web y componentes necesarios. Se revisaron directamente `docs/design-reference/Captura de pantalla 2026-10-30 215451.png` y `screen-06.png`. Se conserva el encabezado/navegación existente y se aplican tarjetas blancas con fecha en negrita a la izquierda, hora a la derecha, especialidad, médico y motivo en jerarquía decreciente, espaciado generoso y línea verde a la izquierda.

La línea utiliza el verde ya existente `HospitalTheme.green` / `#e3f6ea`, sin añadir colores. Dado que las tres fechas aportadas son anteriores al día actual de esta sesión, se conserva el acento verde de la referencia sin afirmar que esas citas sean próximas o vigentes. No se cambió la pantalla Mis citas ni las del Doctor.

Cada tarjeta es pulsable y accesible mediante botón. Abre **Detalle de consulta** en el mismo contenido de la app, sin dialog ni sheet externo. Presenta fecha, hora, especialidad, médico, motivo y campos adicionales autorizados si existen. **Volver** regresa al listado conservando la búsqueda. No incluye acciones de creación o edición clínica.

## Datos precargados y fuente real

Los ejemplos se mantienen exactamente como los pidió el usuario, ordenados de más reciente a más antiguo:

1. 1 oct 2026, 14:25 · Dermatología · Dra. Marta Romero · Citada dermatológico.
2. 2 sept 2026, 13:30 · Cardiología · Dr. Diego Santos · Consulta cardiológica.
3. 15 abr 2026, 08:35 · Medicina general · Dra. Laura Campos · Revisión general.

Se indica **Datos de ejemplo · No son registros clínicos reales**. Los ejemplos se usan en diseño y cuando una lectura autorizada del historial termina correctamente sin registros, conforme a la petición actual. No se importan a la base, no se mezclan con registros reales y no sustituyen errores de red o autorización. La vista también tiene un estado vacío amable cuando no hay registros proporcionados o cuando la búsqueda no coincide.

`PatientHistoryRecord` es Codable y su equivalente JS usa los mismos campos: id, startedAt, dateLabel, timeLabel, specialty, doctor, reason y details. Las fechas de ejemplo son explícitas con offset -06:00. El adaptador de `MobileItem` reutiliza la RPC existente `mobile_module` con rol patient/módulo history: toma especialidad de un campo explícito o del título, motivo del campo explícito o subtítulo, médico de los campos autorizados y detalles de la respuesta. Si el médico u otro campo no viene, muestra No hay datos reales; no lo deduce de una cuenta o consulta ajena. La hora del adaptador se presenta en America/Guatemala.

La identificación del paciente sigue resuelta por el servidor; el nuevo componente no agrega p_patient, selector de identidad ni consultas a otros historiales. Se conserva paginación y reintento cuando corresponden. La búsqueda superior filtra fecha, especialidad, médico y motivo dentro de los registros cargados.

## Archivos creados/modificados

### SwiftUI

- **Nuevo:** `HospitalUniversitario/HospitalUniversitario/Patient/PatientHistoryView.swift`: modelo, ejemplos, adaptador desde MobileItem, tarjetas, estado vacío y detalle interno. Incluye Preview interactivo.
- **Modificado:** `HospitalUniversitario/HospitalUniversitario/ContentView.swift`: conecta la vista exclusivamente para history del Paciente, reutilizando el view model/repositorio existente y su paginación/errores.

El nuevo Swift entra por el grupo sincronizado del target principal; no se modificó el proyecto Xcode ni se añadieron dependencias.

### Web

- **Nuevo:** `web-preview/patient-history.js`: modelo equivalente, adaptador, tarjetas y detalle interno.
- **Modificados:** `web-preview/app.js` (integración y limpieza de selección al salir), `style.css` (estilos acotados), `index.html` y `server.mjs` (carga/recurso permitido).
- **Pruebas:** `scripts/test-patient-history.mjs` nuevo y `scripts/test-preview.mjs` actualizado para cargar el componente.

No se reestructuraron otros módulos, autenticación o backend.

## Verificaciones ejecutadas

- `test-patient-history.mjs`: diseño y sesión vacía con los tres registros exactos, orden descendente, apertura/cierre de cada detalle, búsqueda sin acentos, vacío de búsqueda, solo lectura, registros propios reales simulados sin mezcla de ejemplos y error sin fallback ficticio. Prueba adicional de vacío sin registros.
- `test-preview.mjs`: ocho recorridos previos y dos de agendar cita aprobados.
- `test-modules.mjs`: siete recorridos funcionales anteriores aprobados con transporte simulado.
- Comprobador portable del proyecto, sintaxis JS y git diff --check aprobados.
- Se actualizó la instancia local existente del servidor para incorporar el nuevo recurso en su lista permitida, sin iniciar dos servidores en el mismo puerto; `/patient-history.js` comprobado HTTP 200 en 4173.

Pendientes: compilación/pruebas Swift en Mac y comparación visual real en navegador/dispositivo. No hubo login real, escrituras ni cambios de Supabase. Las pruebas DOM no acreditan revisión visual ni compilación nativa.

Para verlo en el servidor ya abierto, recargar con Ctrl+F5 y entrar como Paciente en **Más → Historial médico**. El modo de diseño Paciente permite recorrer los mismos ejemplos sin credenciales.
