# Transición a Hospital Móviles — 13 de noviembre de 2026

> **Actualización posterior:** el usuario sustituyó el registro clínico por [registro exclusivo de cuenta, sin confirmación de correo](REGISTRO_SOLO_CUENTA_2026-11-13.md). Ya no se llama a `register_patient`, su ejecución está revocada para usuarios de la app y HTTPS confirma `mailer_autoconfirm=true`. Las descripciones siguientes de creación de expediente y confirmación documentan el estado inicial de la transición, no el flujo vigente.

## Alcance y estado

Por petición expresa del usuario, se retiraron configuración, SQL, diccionarios, semillas, copias locales y verificadores exclusivos de la integración sustituida. La app y la vista web utilizan únicamente **Hospital Móviles**, referencia `uvebpsbbwofthucghccc`. No se eliminó ni modificó ningún proyecto remoto. Las referencias visuales locales se conservan; no son registros ni contratos de base de datos.

La conexión y el registro están implementados en ambas plataformas. La compilación Xcode y el recorrido autenticado con persistencia real siguen pendientes. No se crearon cuentas, pacientes ni datos clínicos de prueba, ni se aplicaron migraciones o cambios de permisos.

## Implementación compartida y web

- `Shared/contract.json` contiene URL/clave pública y modelos de habitaciones/jornadas del esquema actual. `floor_id` es entero; las jornadas usan `starts_at` y `ends_at`.
- `Shared/hospital-core.js` contiene validaciones, resolución del acceso y planes de consultas/adaptadores de presentación compartidos con JavaScriptCore. Los nombres de operaciones de interfaz no se envían como nombres de RPC.
- `web-preview/api.js` ejecuta Auth, consulta identidad con `/auth/v1/user` y obtiene perfiles, roles activos y vínculos propios mediante REST/RLS. El rol real `paciente` se presenta como `patient`; nunca se autoriza desde metadatos editables.
- Las sesiones utilizan una clave específica del proyecto. Se descarta el token web con el identificador local anterior; nunca se intenta renovarlo contra el proyecto nuevo.
- `web-preview/server.mjs` permite conexiones únicamente al dominio actual; se retiró el proxy de documentos sin equivalente validado.
- El registro web envía identidad personal a Auth. Cuando hay sesión llama a `register_patient(p_dui,p_phone,p_city)`. Un fallo parcial conserva la cuenta para reintentar. No hay selector de sede ni revisión de registro incompatible con este backend.
- La solicitud de atención usa `appointment_requests`, especialidad numérica y `preferred_period` Mañana/Tarde. Tiene identificador estable para reconocer un envío; no crea una cita ni promete una fecha que la tabla no almacena.

## Implementación iOS/SwiftUI

- `Configuration/Supabase.xcconfig` incluye exclusivamente configuración pública actual y se incorpora desde `App.xcconfig`, tanto Debug como Release. Ya no es necesario crear un archivo de configuración privado en Mac.
- `Core/HospitalAPI.swift` mantiene supabase-swift 2.28.0 y ejecuta los mismos planes del núcleo compartido con el JWT del usuario. No importa sesiones del llavero de la integración sustituida.
- `Core/HospitalStore.swift`, `DoctorRepository.swift` y `MobileModuleRepository.swift` utilizan el adaptador actual. `Models.generated.swift` se genera del contrato vigente; el intervalo de la jornada se forma solo para presentación.
- `Auth/RegisterView.swift` replica el registro web: identidad al crear Auth, DUI/contacto al completar paciente, ciudad opcional y reintentos. `PatientAttentionLiveView.swift` replica especialidad y preferencia de la solicitud actual.
- Se actualizaron las pruebas nativas para los tipos y planes actuales. Son fuentes preparadas para Xcode; no se ejecutaron en Windows.

## Confirmación de correo y expediente

La consulta HTTPS real de `/auth/v1/settings` confirmó `disable_signup=false` y `mailer_autoconfirm=false`. Por tanto, el flujo habitual es crear cuenta → confirmar correo → iniciar sesión → completar DUI/contacto → registrar paciente. Ambos clientes también admiten completar directamente si Auth entrega una sesión.

La inspección de la función real `register_patient` confirmó que crea paciente y expediente dentro de la misma operación. Su trigger de Auth guarda perfil y asigna rol `paciente`. Se inspeccionaron políticas y permisos de estas tablas, sin modificar datos. No se ha verificado todavía el envío/recepción del correo, el enlace de confirmación ni una inscripción completa real.

## Funcionalidades y límites

Lecturas adaptadas al esquema actual: perfil propio, habitaciones, jornadas del médico, citas, solicitudes, expediente/historial del paciente, laboratorios, recetas y notificaciones. Las consultas clínicas usan filtros de identidad más RLS. La presentación de resultados del paciente omite los no publicados. Las pruebas actuales de estas rutas son locales; no acreditan el recorrido real de todos los módulos.

Operaciones que requieren adaptación adicional: iniciar/guardar/cerrar consulta, emitir recetas u órdenes, contacto de emergencia, preferencias de notificación, confirmar jornadas y descargar documentos. El adaptador las rechaza antes de hacer llamadas a servicios inexistentes. La lectura detallada del expediente del médico también sigue pendiente. La agenda básica del médico se obtiene de las citas autorizadas; no se debe interpretar como laboratorio ni consulta clínica completamente integrados.

La nueva base no ofrece la fila numerada de atención del prototipo. Se muestra una explicación y acceso a citas; no se deduce posición contando pacientes ajenos. No se fabrican ocupación o contadores de actividad. Los ejemplos visuales permanecen identificados como diseño.

## Limpieza y trazabilidad

El [manifiesto de rutas retiradas](ARCHIVOS_RETIRADOS_2026-11-13.json) registra los archivos eliminados. Las suites que dependían de contratos sustituidos se retiraron y se reemplazaron por verificaciones del backend actual. Se conservan las suites visuales aplicables y las imágenes del diseño.

La bitácora conserva las entradas visuales independientes que siguen siendo útiles; las instrucciones de conexión y pruebas actuales son las de este informe y README. No se restauraron archivos retirados ni se reescribió el historial Git.

## Verificación y pendientes

Verificaciones ejecutadas durante esta transición:

- `test-preview`: login/roles, vínculos, jornadas/citas, habitaciones y cierre con transporte simulado; navegación de veinte pantallas y aislamiento del modo diseño.
- `test-patient-registration`: datos enviados a Auth/RPC actual, doble envío, fallo parcial, reintento, confirmación sin sesión, cuenta incompleta existente, DUI inválido y solicitud de atención.
- `test-core`: acceso sin confiar en user_metadata, filtros propios, semana/paginación, resultados publicados, renovación concurrente y cierre sin red.
- `test-applicant`, `test-clinical-labs` y `test-doctor-patients`: validaciones y regresión del diseño local. No son pruebas clínicas reales.
- `check-project.py`: referencias, recursos compartidos y esquema Xcode; no compila Swift.
- `check-backend.mjs`: HTTPS real a Auth y rechazo anónimo 401 de perfiles, pacientes y roles. La primera ejecución fue bloqueada por la red del sandbox; la repetición autorizada pasó.

Comprobaciones finales de sintaxis, modelos generados y `git diff --check` se registran en la bitácora al terminar. No se realizó revisión visual nueva en navegador.

Pendientes: compilar y ejecutar pruebas en Mac; recorrer confirmación/login/registro con una identidad autorizada; verificar persistencia y aislamiento entre usuarios reales; completar las operaciones clínicas señaladas. Las lecturas de metadatos y pruebas simuladas no sustituyen esos pasos.
