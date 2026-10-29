# Modulo Doctor: implementacion iOS y despliegue pendiente

> Actualizacion posterior: el SQL ya fue corregido y desplegado y los modulos se extendieron a Medico/Paciente en iOS y web. Consultar [MODULOS_FUNCIONALES_2026-10-28.md](MODULOS_FUNCIONALES_2026-10-28.md). Este documento conserva el estado de la primera implementacion; la compilacion en Mac sigue pendiente.

## Alcance y estado

Se conectaron las pantallas SwiftUI existentes de Doctor a un repositorio Supabase: dashboard diario, agenda propia, inicio/guardado/cierre de consulta, expediente con historial propio y filtros de fecha/hora, emision y consulta de ordenes de laboratorio y buzon de notificaciones. Se conservaron los colores, tarjetas, encabezado y navegacion del proyecto. No se implementaron recetas ni operaciones adicionales de Paciente.

**El codigo esta implementado, pero no esta acreditado como compilado ni desplegado.** El desarrollo de esta intervencion se realizo en Windows, sin Swift, Xcode ni SDK de Apple. Las tres RPC nuevas siguen sin existir en el servidor al cierre: la propuesta SQL se probo con rollback, no se instalo. Para usar el modulo son necesarios su despliegue revisado y la configuracion local descrita abajo.

La peticion actual amplia el alcance historico para el rol Doctor. No autoriza inscribir TOTP en las cuentas de prueba. No se cambiaron usuarios, contrasenas, roles, RLS ni politicas MFA.

## Archivos completos

Rutas relativas a la raiz del repositorio:

| Archivo | Responsabilidad |
|---|---|
| [DoctorModels.swift](../HospitalUniversitario/HospitalUniversitario/Core/DoctorModels.swift) | Modelos Codable de las proyecciones y borrador de consulta; conserva nombres snake_case del servidor sin mapeos artificiales |
| [DoctorRepository.swift](../HospitalUniversitario/HospitalUniversitario/Core/DoctorRepository.swift) | RPC async/await con el mismo SupabaseClient de la sesion |
| [DoctorViewModel.swift](../HospitalUniversitario/HospitalUniversitario/Core/DoctorViewModel.swift) | ObservableObject, seleccion, carga, errores, guardado, versiones e idempotencia |
| [DoctorModuleView.swift](../HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift) | Vistas SwiftUI del modulo dentro de la navegacion existente |
| [ContentView.swift](../HospitalUniversitario/HospitalUniversitario/ContentView.swift) | Enrutamiento exclusivo del Doctor y actualizacion en primer plano |
| [HospitalStore.swift](../HospitalUniversitario/HospitalUniversitario/Core/HospitalStore.swift) | Integracion, identidad/sede autorizada y limpieza de datos al cerrar/cambiar perfil |
| [HospitalAPI.swift](../HospitalUniversitario/HospitalUniversitario/Core/HospitalAPI.swift) | Autenticacion, renovacion, TOTP y cierre con supabase-swift; mantiene interfaz y lecturas REST existentes |
| [SharedCore.swift](../HospitalUniversitario/HospitalUniversitario/Core/SharedCore.swift) | Configuracion iOS desde el bundle; conserva reglas compartidas y lectura de intervalos |
| [project.pbxproj](../HospitalUniversitario/HospitalUniversitario.xcodeproj/project.pbxproj) | Producto Supabase, version exacta 2.28.0 y configuracion Debug/Release |
| [App.xcconfig](../HospitalUniversitario/Configuration/App.xcconfig) | Incluye configuracion local e Info.plist |
| [Supabase.example.xcconfig](../HospitalUniversitario/Configuration/Supabase.example.xcconfig) | Plantilla sin credenciales |
| [Info.plist](../HospitalUniversitario/Configuration/Info.plist) | Expansion de URL y clave publica desde build settings |
| [DoctorModuleTests.swift](../HospitalUniversitario/HospitalUniversitarioTests/DoctorModuleTests.swift) | Cinco pruebas nativas nuevas, pendientes de ejecutar en Mac |
| [doctor-module.sql](sql/doctor-module.sql) | Propuesta de funciones y eventos de notificacion reutilizando las tablas actuales |

Los archivos Swift nuevos quedan en los grupos sincronizados de sus targets respectivos. Configuracion queda fuera del grupo de fuentes, para no copiar accidentalmente el xcconfig local al bundle como recurso. La URL y clave publica se incorporan al Info.plist final: no son secretos recuperables solo por el desarrollador. Nunca usar service_role, sb_secret ni credenciales administrativas en una app distribuida.

## Configurar y abrir en Mac

1. En `HospitalUniversitario/Configuration/`, duplicar `Supabase.example.xcconfig` como `Supabase.local.xcconfig` y completar la URL y clave publica del proyecto. El archivo local esta ignorado por Git. Mantener la sintaxis `https:/$()/...` para que xcconfig no interprete `//` como comentario. No hay fallback de configuracion iOS al contrato web.
2. Abrir `HospitalUniversitario/HospitalUniversitario.xcodeproj` con Xcode 16.2 o posterior y seleccionar HospitalUniversitario / iPhone iOS 18.2 o posterior.
3. Resolver Swift Packages. Se fijo supabase-swift **2.28.0**, cuyo manifiesto usa Swift tools 5.9, compatible con la herramienta base del proyecto. La version actual consultada 2.55.5 requiere tools 6.1; no se elevo Xcode implicitamente. La resolucion transitiva y el archivo `Package.resolved` deben verificarse y conservarse desde Mac; no se genero un lockfile ficticio en Windows.
4. Revisar [doctor-module.sql](sql/doctor-module.sql) en staging antes de instalarlo con el propietario de la base. Ejecutar el archivo completo, con su transaccion. No crea tablas clinicas duplicadas. El permiso CREATE temporal a hospital_api se revoca dentro de la misma transaccion antes de commit.
5. Compilar y ejecutar. Ejecutar tambien las pruebas del esquema compartido; las nuevas pruebas no necesitan red, pero el bundle de pruebas existente requiere configuracion del hospital.

Comandos para Mac (no ejecutados aqui):

```bash
xcodebuild -resolvePackageDependencies -project HospitalUniversitario/HospitalUniversitario.xcodeproj -scheme HospitalUniversitario
xcodebuild -project HospitalUniversitario/HospitalUniversitario.xcodeproj -scheme HospitalUniversitario -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# Elegir el nombre de un simulador instalado:
xcodebuild -project HospitalUniversitario/HospitalUniversitario.xcodeproj -scheme HospitalUniversitario -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Contrato y permisos

- `doctor_workspace(p_facility,p_from,p_to)` devuelve agenda, ordenes, catalogo de estudios, metricas y hasta 100 notificaciones recientes. El dia utiliza la zona horaria local, un rango semiabierto y duracion maxima de dos dias para contemplar cambios horarios. Las filas clinicas se restringen al medico autenticado y sede autorizada; el buzon es propio del usuario.
- `doctor_chart(p_patient,p_from,p_to,p_query)` reutiliza `patient_chart` y sus controles/auditoria. El historial no tiene un limite oculto de 20 filas: obtiene todas las consultas propias autorizadas que coincidan con el intervalo y texto. Las fechas incluyen hora; el extremo final es inclusivo. Las notas se limitan al autor autenticado. Se muestran identificadores, contactos primarios, sangre, alergias, condiciones, antecedentes, medicacion y ultimos signos vitales disponibles.
- `doctor_issue_lab_order(p_encounter,p_test,p_instructions,p_request_key)` crea cabecera, un estudio y emision en una sola transaccion, utilizando create_record/finalize_clinical_record. Un fallo revierte todo. La misma clave y contenido reutilizan la orden en un reintento; no se impone una unica orden de por vida por paciente. Cada accion emite una orden de un paciente y un estudio.
- La orden referencia la atencion. Nombre, telefono y turno se proyectan mediante relaciones; no se duplican como columnas. `ordered_at` lo fija el servidor al emitir. El numero de turno nunca se confunde con el turno laboral del medico. Contactos/identificadores actuales pueden cambiar despues: no son una instantanea documental de la emision.
- Consulta usa `start_consultation`, `save_consultation` y `close_consultation` existentes. Solo se inicia desde `checked_in` o `in_progress`; la recepcion debe haber registrado al paciente. Se guarda como borrador y se confirma explicitamente la firma/cierre. La evaluacion es texto clinico; no se crea un catalogo CIE-10 alternativo.
- Se respetan row_version y RLS. Las funciones privadas de proyeccion pertenecen a hospital_api, sin BYPASSRLS; las entradas publicas son SECURITY INVOKER. Las funciones nuevas no se conceden a anon ni PUBLIC. MFA y vinculo asistencial siguen siendo necesarios.
- Si no hay vinculo demografico vigente antes de iniciar la consulta, la agenda conserva la cita propia pero muestra acceso restringido en lugar de inventar el nombre o telefono. No se amplio la RLS para eludir esta restriccion. Los expedientes historicos requieren tambien un vinculo asistencial vigente conforme a las politicas existentes; no se concede acceso longitudinal por haber atendido alguna vez al paciente.
- El esquema inspeccionado no tiene direccion de paciente en persons ni una tabla person_addresses. La proyeccion devuelve `address: null`, mostrado como no registrado. No se invento una columna ni se creo una tabla de domicilios, que no es necesaria para los campos minimos de laboratorio solicitados.

## Notificaciones

Se reutilizan notifications, notification_topics y notification_preferences. La propuesta incluye eventos al registrar una cita en recepcion, liberar un resultado y firmar una nota. Los avisos son genericos, por destinatario, respetan la preferencia in_app y caducan a los 30 dias. Marcar como leida utiliza update_record y row_version.

Se consulta al entrar, volver a primer plano y cada 30 segundos en Inicio, Pacientes y Notificaciones mientras la app esta activa. No se garantiza entrega con la app cerrada ni en segundo plano. No se anadieron notificaciones locales o push porque ya existe un buzon soportado; APNs y un proveedor de envio no estan configurados y un aviso local tampoco sustituiria un evento remoto cuando la app esta cerrada. No se muestra informacion clinica en la pantalla bloqueada.

## Prueba de cada pantalla

Usar cuentas y pacientes de staging con perfil activo, rol doctor, sede, vinculo de personal, permisos clinicos y MFA previamente configurada por un administrador autorizado. Las cuentas demo actuales no tienen factores inscritos; este trabajo no los inscribe ni elimina esa limitacion.

1. **Inicio:** login como Doctor; verificar la sede y metricas contra atenciones/ordenes propias del dia. Cambiar fecha y comprobar vacios sin datos inventados. Una segunda identidad no debe ver los contadores de la primera.
2. **Pacientes/Mis citas:** preparar desde recepcion una cita propia con turno y check-in. Buscar nombre/expediente/turno; comprobar que no aparecen citas de otro medico. El check-in no se ejecuta desde esta app.
3. **Consultas:** seleccionar al paciente, iniciar, completar motivo, exploracion, evaluacion y plan, guardar. Recargar y comprobar persistencia. Editar la misma nota desde otra sesion para probar version desactualizada. Firmar y cerrar con confirmacion; comprobar cita/turno finalizados y nota ya no editable.
4. **Laboratorio:** con consulta abierta seleccionar un estudio activo, agregar indicaciones y emitir. Verificar nombre, turno, telefono si existe, tipo, hora del servidor, sede, medico y observaciones en la lista. Simular perdida de respuesta y reintentar sin editar: comprobar que no se duplica la orden. Los registros incompletos no deben persistir tras un fallo.
5. **Expedientes:** seleccionar paciente autorizado, revisar identificacion/contactos, antecedentes y datos clinicos. Buscar un texto y filtrar por fecha y hora; verificar todas las consultas propias en el rango. Un rango invertido no debe hacer una llamada. Probar denegacion con un paciente sin vinculo vigente.
6. **Notificaciones:** generar en staging un check-in, una liberacion de resultado y firma de nota. Actualizar el buzon, marcar leida y recargar. Comprobar que otra cuenta no lee ni modifica ese aviso. Probar preferencia in_app desactivada.
7. **Sesion/red:** probar restauracion, expiracion, sin red, MFA y cierre/cambio de perfil; no deben conservarse expedientes ni borradores del medico anterior. Probar tambien login y lecturas de Paciente porque comparten autenticacion.

## Verificaciones de esta intervencion

Ejecutadas:

- Inspeccion de metadatos reales: firmas, cuerpos de RPC, columnas, defaults, roles propietarios, grants, RLS y triggers. No se exportaron registros clinicos.
- Consulta del changelog y fuentes oficiales de supabase-swift para inicializacion, almacenamiento, sesion, MFA y versiones de herramientas.
- Propuesta SQL creada y probada en transaccion real terminada en ROLLBACK: creacion de objetos, tres llamadas sin sesion rechazadas, ausencia de EXECUTE para anon y aislamiento del trigger. Confirmacion posterior de que las tres RPC nuevas no quedaron instaladas. Un primer intento revelo el requisito CREATE del cambio de propietario; se corrigio con concesion temporal y revocacion atomica.
- Planificacion/ejecucion de las dos consultas de proyeccion con identificadores nulos, sin devolver datos de personas, dentro de otra transaccion revertida. No sustituye pruebas positivas de un medico con MFA.
- 11 pruebas existentes del nucleo/adaptador web y 8 recorridos DOM existentes. No prueban el SDK Swift ni las nuevas pantallas nativas.
- Revision portable del proyecto Xcode y `git diff --check`. El diagnostico del editor no reporto errores, pero no tiene un compilador Swift instalado.
- El chequeo literal `generate-models.mjs --check` fallo por CRLF del checkout Windows (`core.autocrlf=true`). Una comparacion en memoria contra el contrato, normalizando solo CRLF a LF, paso; no se cambiaron el generador ni los modelos generados. Info.plist se valido con el parser plistlib.

Pendientes: resolucion/lockfile SPM, compilacion y pruebas nativas en Mac, revision visual del simulador, despliegue SQL revisado, pruebas positivas y de concurrencia con dos medicos autorizados, validacion real de eventos, asesor de seguridad y rendimiento tras despliegue. No se ejecutaron altas clinicas reales ni inscripcion MFA.

Fuentes tecnicas: [Inicializacion Swift](https://supabase.com/docs/reference/swift/initializing), [fuentes SDK 2.28.0](https://github.com/supabase/supabase-swift/tree/v2.28.0), [changelog](https://supabase.com/changelog).
