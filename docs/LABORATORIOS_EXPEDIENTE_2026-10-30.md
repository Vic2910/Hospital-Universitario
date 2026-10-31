# Expediente y Laboratorios por rol — 30 de octubre de 2026

## Alcance y decisión vigente

Se implementó el diseño local solicitado dentro de los destinos existentes **Expedientes** (`chart`) y **Laboratorios** (`laboratory`), sin crear rutas nuevas. La aclaración del usuario determina el flujo: buscar paciente por DUI/nombre, abrir su expediente y preparar la solicitud para ese paciente. No se puede reasignar el paciente dentro del formulario.

Se revisaron directamente `docs/design-reference/screen-16.png`, `screen-18.png` y `screen-08.png`. Se reutilizaron HospitalTheme, HospitalCard, PatientFormCard, campos de consulta y estilos web existentes. Los estados usan los fondos de referencia: Pendiente amarillo claro, En Proceso azul claro y Completado verde claro, siempre con texto; SwiftUI añade iconos. La paleta principal vino/rosa y las tarjetas blancas se mantienen.

El proyecto ya tiene una emisión clínica real que requiere consulta activa y catálogo institucional. **No se reemplazó, simuló como real ni se alteró esa operación.** El nuevo diseño usa un estado MVVM local y serializable, identificado como ficticio, sin llamadas a Supabase ni importación de ejemplos. Las vistas reales y sus validaciones permanecen disponibles.

## Navegación y demostración

| Rol | Entrada y contenido |
|---|---|
| Doctor | Barra Inicio / Pacientes / Consultas / **Laboratorios** / Más. Expedientes sigue en el acceso rápido y Más. Desde Expedientes busca por DUI o nombre, abre el registro y pulsa **Solicitud de laboratorio**. |
| Paciente | Conserva su navegación. Expediente y Laboratorios muestran únicamente el paciente de ejemplo propio y sus solicitudes/resultados. No hay búsqueda de otras personas ni creación. |

La barra del Doctor incorpora Laboratorios y vuelve a cinco destinos; **Mis citas continúa retirado exclusivamente del Doctor**. Esta decisión sustituye la distribución de cuatro destinos documentada anteriormente.

**Web en Windows:** iniciar `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs`, abrir `http://127.0.0.1:4173/` y seleccionar **Médico** en los controles de diseño. Entrar en **Expedientes**, buscar `034567890` o `Ana Reyes`, abrir el expediente y crear una solicitud. Ana representa primera visita: solo datos de registro y sin antecedentes/laboratorios iniciales. El botón se integra en ese expediente; el resultado aparece en su sección **Laboratorios del expediente**. El acceso Laboratorios conserva el paciente seleccionado y permite regresar al expediente. Si no hay selección, indica abrir un expediente antes de solicitar.

Para ver Paciente, elegir su modo de diseño y abrir Laboratorio o Expediente desde Más. Se muestran ejemplos propios con los tres estados. Cambiar de modo reinicia la demostración; no hay persistencia ni sincronización entre sesiones. Las solicitudes nuevas se conservan mientras se navega entre Expedientes y Laboratorios dentro del mismo modo Doctor.

**SwiftUI:** en los destinos existentes Expedientes/Laboratorio está el interruptor **Vista de diseño · datos locales**. Desactivado conserva el contenido real anterior. Activado muestra el flujo local, compartiendo el mismo objeto observable entre ambos destinos. Salir/cambiar de rol reinicia los ejemplos. En Mac también están los previews **Expediente y laboratorios · Doctor** y **Expediente y laboratorios · Paciente**. No se añadió login alternativo ni bypass de autenticación.

## Solicitud y permisos

1. Buscar y seleccionar expediente. Se muestran nombre, apellido, correo, edad, DUI, teléfono y número de expediente.
2. Pulsar Solicitud de laboratorio. Elegir un estudio básico y escribir motivo/observación clínica (1–2000 caracteres, sin aceptar solo espacios).
3. Confirmar con **Solicitar laboratorio**. Se crea un snapshot local ligado al ID del paciente y se lista como **Pendiente**. No se envía al hospital.

Todos los datos necesarios son obligatorios: paciente completo, examen válido, observación, médico, clínica, fecha/hora generada y turno de consulta. El turno precargado es el **turno de atención**, no una jornada laboral del médico. No se habilita el botón si falta examen, motivo o algún dato obligatorio del contexto. Cambiar de paciente descarta el borrador y reinicia filtros. Cancelar no crea registros; después de confirmar se cierra el editor, bloqueando un segundo envío del mismo formulario.

El catálogo contiene siete estudios sencillos: orina, heces, biometría hemática, glucosa, perfil lipídico, parásitos y antígeno. Categorías: Orina / Heces / Sangre / Otros. No incluye radiografías, tomografías ni resonancias.

Los estados del modelo local son **exactamente** Pendiente, En Proceso y Completado. No se añadió una interfaz para cambiar estados; los ejemplos permiten revisar las tres presentaciones. Un resultado aún no disponible se indica con texto. Un ejemplo completado contiene solo un aviso de resultado ficticio, sin documento ni valores clínicos reales.

El paciente no recibe formulario ni controles de solicitud. El método de creación también valida el rol, aunque se invoque fuera de la vista. La selección para Paciente se fija a su identidad de demostración; los filtros no permiten ampliar el alcance a otros pacientes.

## Laboratorios dentro del expediente

La sección se incorpora al expediente existente, no a otra pantalla. Lista examen, fecha/hora y estado; **Ver detalle** despliega datos completos del paciente, médico, clínica, fecha/hora, turno, observación y resultado/disponibilidad. Está disponible en ambos roles según su contexto.

Filtra por fecha local y categoría del examen. El filtro de paciente es el expediente seleccionado mediante búsqueda por DUI/nombre; nunca mezcla laboratorios ajenos en una misma ficha. En Paciente esa identidad queda fija. La primera visita sin registros muestra solamente identificación y el estado vacío de laboratorios, sin inventar antecedentes o diagnósticos.

## Modelos y futura conexión

`ClinicalLabRequest` es Codable, con ID de solicitud, snapshot del paciente (incluido su ID), examen/categoría, observación, nombre del doctor, clínica, timestamp, turno y estado/resultado. En web el objeto contiene los mismos campos y es serializable como JSON. Los datos son todos locales: María López, Carlos Mendoza y Ana Reyes, con dominios `.test` y números ficticios. No se copiaron datos clínicos reales ni credenciales.

| Campo | Fuente actual |
|---|---|
| Paciente y datos personales | Registro local seleccionado; `patient.id` vincula la solicitud a su expediente |
| Examen | Catálogo local fijo; solo admite una entrada válida |
| Observación | Texto obligatorio escrito por el doctor |
| Doctor y clínica | Contexto ficticio de la demostración, precargado y de solo lectura |
| Fecha/hora | Reloj local al confirmar; el formulario muestra la referencia actual |
| Turno | Turno de consulta del paciente seleccionado |
| Estado inicial | Pendiente, asignado por el método de creación |

Para la conexión futura se deben sustituir los registros/catálogos locales por identidades y UUID institucionales autorizados, resolver médico/clínica/turno desde el servidor y adaptar el comando a las RPC/RLS existentes. No se deben enviar IDs `p1`/`urine` al backend ni permitir que datos de presentación autoricen una emisión. El servidor deberá mantener la validación de consulta activa exigida por el flujo real. La traducción de estados operativos a los tres estados de presentación requiere un mapeo explícito; esta sesión no cambió estados en la base.

## Archivos

- `HospitalUniversitario/HospitalUniversitario/Modules/ClinicalLabDesignModels.swift`: pacientes, examen/categorías, tres estados, solicitud Codable y store observable con validación/guardas.
- `HospitalUniversitario/HospitalUniversitario/Modules/ClinicalLabDesignView.swift`: búsqueda de expediente, registro inicial, formulario integrado, filtros, detalles y badge reutilizable.
- `HospitalUniversitario/HospitalUniversitario/ContentView.swift`: objeto local compartido, entrada explícita al diseño en las rutas existentes, reinicio por rol y navegación Doctor con Laboratorios.
- `HospitalUniversitario/HospitalUniversitario/Shared/screens.json`: tab de Laboratorios del Doctor para selección visual correcta.
- `web-preview/clinical-labs.js`: equivalente de modelos/store y renderer para Expedientes/Laboratorios por rol.
- `web-preview/app.js`, `index.html`, `server.mjs`, `style.css`: integración del diseño, recurso permitido y estilo/menú; sin dependencias nuevas.
- `scripts/test-clinical-labs.mjs` y `test-preview.mjs`: pruebas específicas y carga del nuevo recurso en el doble DOM.

Los nuevos Swift están dentro del grupo sincronizado del target principal; no se modificó el proyecto Xcode ni la arquitectura de repositorios reales.

## Verificaciones ejecutadas y pendientes

- `scripts/test-clinical-labs.mjs`: Doctor, Paciente y modelo; búsqueda con/sin guion y acentos, primera visita, campos obligatorios, espacios, límite de observación, doble envío, asignación al expediente, descarte de borrador al cambiar paciente, filtros, estados, snapshot JSON y rechazo por rol. Aprobados; modo diseño sin llamadas a Supabase.
- `scripts/test-preview.mjs`: ocho recorridos previos y dos de agendar cita aprobados.
- `scripts/test-modules.mjs`: siete flujos clínicos existentes aprobados con transporte simulado, incluida la emisión real de laboratorio simulada.
- `scripts/test-doctor-dashboard.mjs` y `test-doctor-consultations.mjs`: regresiones aprobadas.
- Sintaxis de clinical-labs.js/app.js, `python scripts/check-project.py` y `git diff --check`: aprobados.
- Servidor temporal local en 4188: HTTP 200 para página, clinical-labs.js, app.js y style.css; cerrado al finalizar.

No se ejecutaron Xcode, pruebas Swift ni revisión visual automatizada en navegador/dispositivo. Quedan pendientes compilación/pruebas nativas en Mac y comparación visual final. No hubo pruebas reales contra Supabase, escrituras clínicas, cambios de esquema/RPC/RLS o credenciales. Las pruebas DOM no equivalen a una verificación visual ni de permisos reales de servidor.


## Corrección de acceso tras la captura del usuario

La condición inicial de visibilidad descrita arriba se sustituye: **el Doctor ve el rediseño por defecto al abrir Expedientes o Laboratorios también tras iniciar sesión**, sin cambiar al modo de diseño externo. Laboratorios sin expediente seleccionado incluye la búsqueda por DUI/nombre. La presentación sigue identificada como local y no crea registros reales. Web permite conmutar al módulo anterior mediante **Ver flujo conectado** y regresar con **Ver diseño de expediente y laboratorios**; iOS activa el interruptor de diseño al resolver el rol Doctor. El Paciente en sesión conserva sus datos reales; sus ejemplos siguen en el modo de diseño. Una prueba de sesión simulada reproduce la captura y verifica este acceso, la asignación local, la ausencia de emisión remota y el acceso al flujo conectado.
