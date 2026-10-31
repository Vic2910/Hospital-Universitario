# Mi expediente y Mis laboratorios del Paciente — 2026-10-31

## Presentación y navegación

Se mantiene la ruta `chart` con el título **Mi expediente**. La vista del Paciente usa el lenguaje visual del Doctor: ticket interno, Volver, cabecera, card de identidad, secciones con fondo blanco/bordes suaves y acentos vino/rosa. El detalle del examen muestra primero Paciente (nombre, edad y teléfono), seguido de Información del examen y Resultado del examen. No abre ventanas externas para las fichas.

Laboratorios abre directamente **Mis laboratorios**, sin selección de paciente, buscador ni filtros. También se incluye su lista dentro de Mi expediente. Las cards usan fecha destacada, nombre del estudio, estado y Ver detalle; se ordenan por fecha de solicitud descendente. Se incluyen vacíos, errores/reintento, actualización manual y paginación. El retorno conserva el origen y el paciente, sin acciones de Doctor.

Pendiente y En Proceso no muestran resultados. En datos reales `released` se presenta como Completado; se admite completed cuando lo informa la fuente. Cancelado conserva su etiqueta y no se convierte en completado. El resultado publicado presenta las determinaciones recibidas, valores/unidades/referencias que incluya la respuesta y narración; no se inventan referencias ni fecha de publicación cuando el contrato no las devuelve. Los documentos conservan su autorización previa mediante URL firmada y paginación. Los campos ausentes muestran No hay datos reales.

## Datos y permisos

En sesión real se usa `mobile_module` con rol patient para `chart` y `laboratory`, junto con `my_profile`. No se envía un paciente elegido por la UI: el backend resuelve el paciente vinculado a la sesión y conserva las RLS existentes. Mi expediente usa un segundo modelo de lectura para laboratorios, de forma que cargar sus estudios no sobrescriba las secciones/documentos del expediente.

La identidad de sesión configura ambos modelos; se limpian al salir/cambiar de rol y en errores de acceso. El detalle se resuelve únicamente entre los elementos de la lista autorizada actual. No hay botones de solicitud de laboratorio, notas, recetas ni búsqueda de otras personas en las vistas del Paciente. El diseño local reutiliza el componente clínico con el paciente propio de prueba; es de solo lectura, está identificado y no se mezcla con páginas reales ni se activa como reemplazo de un error/una respuesta vacía real.

Los datos personales y secciones/documentos publicados del expediente se conservan. El modelo no expande el contrato del backend a historias o signos vitales que esa RPC no entregue. La consulta de datos nuevos se realiza al abrir la sección o con Actualizar laboratorios; no se añadió una suscripción Realtime.

## Archivos

- Nuevo `HospitalUniversitario/HospitalUniversitario/Patient/PatientClinicalView.swift`: Mi expediente, lista cronológica propia y detalle de laboratorio de solo lectura; reutiliza PatientFormCard, DoctorConsultationField y ClinicalLabStateBadge.
- `Core/HospitalStore.swift`: modelo separado patientLaboratory, configuración/limpieza por sesión y carga autorizada de estudios al abrir Mi expediente.
- `ContentView.swift`: integración del Paciente sin toggle del prototipo ni buscador en estas vistas.
- `Modules/ClinicalLabDesignView.swift`: títulos del Paciente coherentes en el componente local existente.
- `web-preview/clinical-labs.js`: diseño local del Paciente y HospitalPatientClinical para páginas reales, con las mismas clases visuales del Doctor.
- `web-preview/app.js`: segundo modelo de lectura, configuración, limpieza y rutas propias del Paciente.
- `scripts/test-patient-chart.mjs`, `scripts/test-clinical-labs.mjs`: pruebas ajustadas/ampliadas.
- README.md, docs/README.md y docs/BITACORA.md: documentación.

El archivo Swift entra en el grupo sincronizado del target existente. Sin dependencias, migraciones ni cambios de arquitectura de acceso.

## Verificación de esta intervención

- test-patient-chart.mjs: identidad/datos propios, Mi expediente y Volver, faltantes sin fixtures, diseño aislado; laboratorios directos y sin filtros; detalle completado de ejemplo; sesión simulada con tres estados, orden cronológico, valores publicados y ausencia de valores en pendientes aunque el payload los contenga; sin parámetro p_patient ni acciones clínicas.
- test-clinical-labs.mjs: permisos, estados, resultados publicados reactivos, solicitudes del Doctor y lectura del Paciente conservados.
- test-doctor-patients.mjs: diseño y sesión simulada del Doctor conservados.
- test-preview.mjs, check-project.py, sintaxis JS y git diff --check.

Son pruebas con DOM y transporte simulados. No se realizaron pruebas nuevas contra Supabase, escrituras clínicas, revisión visual en navegador ni compilación Swift/Xcode. Pendientes compilación y revisión visual en Mac y validación real con datos de laboratorio publicados por el flujo autorizado de Recepción.

El acceso rápido del inicio también se renombra **Mi expediente** en Patient/PatientDashboardView.swift y web-preview/app.js. El dashboard del Doctor conserva Expedientes.


## Corrección visual según las dos imágenes del usuario

La tarjeta de datos personales ya no tiene una implementación distinta por rol. Se extrae `ClinicalPatientIdentityView.swift`, usado en el expediente del Doctor y en Mi expediente. En web ambos usan `HospitalClinicalIdentity`. La composición coincide con la segunda imagen: iniciales/nombre en bloque rosa, cuadrícula Nombre/Apellido/Edad/DUI y tres filas con icono para Correo electrónico/Teléfono/Expediente. Se mantienen los datos recibidos de la cuenta/expediente, faltantes explícitos y el aislamiento por paciente; no se rellenan cuentas reales con datos de demostración. El detalle de examen continúa mostrando solo nombre/edad/teléfono, como se solicitó antes.

Laboratorios usa Laboratorios del expediente como título del bloque, el mismo subtítulo del Doctor y cards con fecha destacada, nombre, fecha/hora, estado, explicación y Ver detalle separado por una línea. Los mensajes de Pendiente/En Proceso/Completado se igualan al Doctor. Actualizar laboratorios queda después de las cards. El orden y acceso a resultados no cambian.

Archivos de este ajuste: nuevo Modules/ClinicalPatientIdentityView.swift; Modules/ClinicalLabDesignView.swift; Patient/PatientClinicalView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-patient-chart.mjs. La prueba compara el contenido completo de la tarjeta del Doctor y del Paciente para la misma María López de demostración, además de verificar cuatro campos y tres filas de contacto en sesión simulada. Comparación aprobada; también test-clinical-labs, test-doctor-patients, test-preview, check-project.py y diff --check. Son pruebas DOM/transporte simulado, sin revisión visual en navegador ni compilación Xcode. La igualdad de origen de datos reales continúa dependiendo de las proyecciones autorizadas existentes; no se cambió el backend ni se inventaron datos ausentes.
