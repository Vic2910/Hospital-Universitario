# Modulos funcionales de Medico y Paciente

## Solicitud y alcance actual

Se sustituyeron las pantallas que anunciaban la siguiente entrega por flujos conectados a Supabase, tomando como referencia [Informe_Hospital_Universitario.md](Informe_Hospital_Universitario.md) y contrastando sus firmas, tablas, permisos y restricciones con el servidor real.

La ampliacion cubre iOS/SwiftUI y la vista previa web existente en Windows para los roles doctor y patient. No incorpora Kotlin, administracion, recepcion, enfermeria ni laboratorio como roles de la app. Recepcion sigue siendo responsable de programar solicitudes y registrar el check-in. No se importaron los ejemplos del prototipo como datos reales.

## Flujos conectados

| Pantalla | Comportamiento |
|---|---|
| Inicio del Medico | Resumen diario propio, agenda, ordenes y avisos; fecha de jornada seleccionable |
| Pacientes y citas del Medico | Agenda propia por fecha, busqueda, seleccion de paciente y acceso a consulta/expediente |
| Consultas | Inicio tras check-in, nota de motivo/exploracion/evaluacion/plan, busqueda de catalogo CIE-10, guardado de borrador y firma/cierre confirmado |
| Expedientes del Medico | Demografia autorizada, sangre, antecedentes, alergias, condiciones, medicacion, signos vitales e historial propio con filtros de fecha/hora y texto |
| Recetas del Medico | Consulta abierta, revision de alergias registradas, uno o varios medicamentos del catalogo, dosis decimal, unidad, via, intervalo, cantidad, indicaciones y fechas; emision atomica |
| Laboratorio del Medico | Emision atomica de una orden y un estudio por accion; consulta posterior por fecha, paciente, turno, telefono, sede, medico e indicaciones |
| Mi horario | Lectura semanal existente y confirmacion de jornadas pendientes con control de version |
| Mis citas del Paciente | Citas propias con detalle y cancelacion de citas programadas/confirmadas, motivo y version del servidor |
| Solicitar atencion | Especialidad, motivo, fecha y franja preferida; solicitud pendiente y consulta de sus respuestas, sin simular una reserva confirmada |
| Expediente del Paciente | Identificacion, sangre, alergias, condiciones, antecedentes y documentos liberados propios |
| Historial del Paciente | Atenciones propias, notas firmadas, detalle, texto, fechas/horas y paginacion por cursor |
| Recetas del Paciente | Solo recetas emitidas, medicamentos y pautas con fechas; distingue tratamiento vigente, futuro y finalizado |
| Laboratorio del Paciente | Estudios propios; solo resultados liberados, sus valores/unidades y documentos autorizados; validado no se confunde con publicado |
| Notificaciones de ambos roles | Buzon propio paginado, filtros, marcar como leida y actualizacion en primer plano |
| Perfil de ambos roles | Datos existentes, cambio de telefono, preferencias in_app y cambio de contrasena; el Paciente tambien mantiene contacto de emergencia |
| Mi turno, Habitaciones e Informacion publica | Conservan sus lecturas funcionales anteriores; no se confunden colas de atencion, guardias laborales ni habitacion activa con cama libre |

No se expusieron operaciones administrativas al Paciente ni se modificaron RLS para habilitar acciones de otro rol. El modo de diseno sigue siendo local y de solo lectura: sus botones no escriben en Supabase ni conceden una sesion.

Al cambiar de paciente se limpian los renglones y campos de receta. El cierre de sesion limpia los datos clinicos visibles antes de esperar la confirmacion remota, y una respuesta tardia de documento no se abre si cambio la identidad.

## Archivos

Rutas relativas a la raiz:

- `HospitalUniversitario/HospitalUniversitario/Core/MobileModuleModels.swift`: contratos Codable de listas, detalles, opciones, preferencias y renglones de receta.
- `HospitalUniversitario/HospitalUniversitario/Core/MobileModuleRepository.swift`: RPC y documentos con la sesion compartida de supabase-swift.
- `HospitalUniversitario/HospitalUniversitario/Core/MobileModuleViewModel.swift`: cargas, cursores, formularios, acciones y limpieza por identidad.
- `HospitalUniversitario/HospitalUniversitario/Modules/MobileModuleView.swift`: vistas del Paciente, ajustes y formulario de recetas del Medico.
- `HospitalUniversitario/HospitalUniversitario/Core/DoctorModels.swift`, `DoctorRepository.swift`, `DoctorViewModel.swift`: decimales, catalogo diagnostico, control de versiones y conservacion del borrador al navegar.
- `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift`, `ContentView.swift` y `Core/HospitalStore.swift`: enrutamiento, consulta, horarios y notificaciones. Se elimino el scaffold clinico.
- `HospitalUniversitario/HospitalUniversitarioTests/MobileModuleTests.swift` y `DoctorModuleTests.swift`: contratos nativos y adaptacion del repositorio de prueba.
- `web-preview/modules.js`: flujos de ambos roles con transporte autenticado, formularios, listas y detalles.
- `web-preview/api.js`, `app.js`, `index.html`, `style.css` y `server.mjs`: integracion en la interfaz existente y proxy local de documentos.
- `.vscode/tasks.json`: tarea para iniciar la vista previa local.
- `scripts/test-modules.mjs`, `test-preview.mjs` y `check-backend.mjs`: recorridos y comprobaciones ampliadas.
- [doctor-module.sql](sql/doctor-module.sql), [mobile-modules.sql](sql/mobile-modules.sql) y [test-mobile-flows.sql](sql/test-mobile-flows.sql): definiciones desplegables y comprobaciones transaccionales.
- README principal, indice y bitacora: estado vigente y verificaciones reales.

La primera implementacion del Doctor se conserva en [MODULO_DOCTOR_2026-10-28.md](MODULO_DOCTOR_2026-10-28.md) como antecedente. Sus pendientes de despliegue SQL quedaron superados por esta intervencion; sus pruebas anteriores no se atribuyen a este trabajo.

## Backend instalado

Se instalaron realmente en `kgulityewtcyvjnxeskd`:

- `doctor_workspace`, `doctor_chart`, `doctor_issue_lab_order` y su comprobacion privada de acceso medico.
- `mobile_module`, que valida identidad, rol/sede, propietario y MFA segun la pantalla; devuelve listas con cursor compuesto, detalles y catalogos autorizados.
- `mobile_issue_prescription`, que crea cabecera y renglones y emite en una sola transaccion, con idempotencia por usuario y contenido.
- Eventos internos de check-in, citas, recetas emitidas, resultados liberados, asignacion de paciente, cambio de guardia y alergias relevantes. Se restringieron destinatarios a los roles correspondientes, respetando preferencias in_app.

Las tablas originales y las politicas MFA/RLS permanecen intactas. Las funciones de datos pertenecen a hospital_api, sin BYPASSRLS. Sus entradas publicas son SECURITY INVOKER y no se conceden a anon. Los disparadores de entrega se mantienen privados, sin EXECUTE del cliente, y generan mensajes genericos sin datos clinicos.

Se corrigieron dos aspectos revelados por pruebas reales: hospital_api no tiene USAGE sobre auth, por lo que las funciones nuevas usan el helper existente `private.current_profile_id()`; y postgres puede asumir hospital_api pero no hereda su propiedad, por lo que los scripts usan SET LOCAL ROLE para que su reaplicacion sea reproducible. El permiso CREATE temporal en private se revoca antes de commit. No se ampliaron permisos sobre auth ni privilegios permanentes del rol.

Los wrappers existentes convierten conflictos a SQLSTATE `PT409`. Se ajustaron el cliente Swift y el web para mostrar ese conflicto y preservar el borrador en lugar de tratarlo como un fallo generico de red.

Las firmas/campos de las RPC existentes se reutilizaron para solicitar/cancelar citas, guardar/cerrar consulta, confirmar jornada, actualizar contacto y preferencias. El paciente y el prescriptor no se eligen libremente en las escrituras: se validan o derivan de la sesion.

## Documentos

Se reutiliza la Edge Function `document-access`, que autoriza cada documento con el JWT del usuario antes de firmar un enlace de 60 segundos. iOS la invoca por el SDK. La web usa un proxy en el servidor local para no depender de cambiar la lista CORS del servicio.

El proxy solo acepta POST desde el origen local y con bearer, limita el cuerpo, admite un UUID de documento y reenvia exclusivamente a la funcion fija con la clave publica. No usa claves administrativas, no sirve archivos del repositorio ni omite la autorizacion del servidor. Los clientes validan que el enlace sea HTTPS y pertenezca al almacenamiento del proyecto. No se guardan enlaces firmados en disco.

## Verificaciones ejecutadas

1. **Locales:** 11 pruebas del nucleo/adaptador y 8 recorridos DOM existentes; los recorridos se adaptaron a las nuevas RPC sin retirar las comprobaciones anteriores.
2. **Nuevos recorridos DOM:** seis flujos de solicitud con doble envio bloqueado, cancelacion versionada, lectura de notificacion, consulta y conflicto sin perder borrador, receta con dosis decimal y cierre firmado. Se comprobo ademas que cambiar de paciente limpia el formulario de receta. Solo usan transporte simulado. No se asigna una duracion de tratamiento automaticamente.
3. **PostgreSQL real, transaccion revertida:** preparacion transitoria de sesiones SQL y filas de prueba, asuncion de authenticated, inicio/guardado/cierre de consulta, todas las lecturas de modulos del Paciente, orden y receta con reintentos idempotentes, solicitud/cancelacion, rechazo de rol falso, expediente sin vinculo, version antigua y escritura de receta por Paciente o sobre atencion cerrada. Se simularon claims JWT dentro de PostgreSQL para probar las politicas; esto NO acredita un login real ni MFA inscrita. Todo termino en ROLLBACK.
4. **Despliegue real:** comprobacion de existencia de las RPC, ausencia de BYPASSRLS y revocacion del CREATE temporal. No quedaron medicamentos ni estudios con prefijo de prueba `ROLLBACK-`.
5. **HTTP real anonimo:** catalogo publico 200; ocho endpoints protegidos, incluidos mobile_module, doctor_workspace y mobile_issue_prescription, rechazaron acceso con 401.
6. **Servidor local:** pagina, JavaScript nuevo y recursos con 200; proxy de documentos sin sesion 403; ruta de credenciales locales 404.
7. **Navegador conectado:** recorrido de receta del componente real usando un repositorio de prueba en memoria; una sola llamada de emision. Medicion en 1280x900 y 390x844 sin desbordamiento horizontal del documento ni de los campos. Se descubrio y corrigio la asignacion invalida de type en textarea; el doble DOM de pruebas ahora refleja esa propiedad de solo lectura. No se hizo comparacion pixel a pixel contra las capturas del prototipo.
8. **Proyecto:** comprobacion portable de referencias Xcode, diagnosticos del editor y `git diff --check`. Las pruebas Swift nuevas no se ejecutaron porque Windows no tiene Swift/Xcode.
9. **Asesor de seguridad:** permanecen los seis INFO de RLS sin politicas en el esquema historico de recuperacion y el aviso preexistente de proteccion de contrasenas filtradas deshabilitada. No se cambiaron esas opciones ni aparecieron advertencias nuevas por estas funciones.

No se modifico el informe historico `login-verification.json` ni se atribuyeron sus logins a esta sesion. Esta copia no contiene `.local/test-accounts.json`, por lo que no se ejecuto un login HTTPS con credenciales reales. No se inscribio TOTP ni se redujeron politicas para sustituirlo.

## Probar

Vista previa local, sin dependencias adicionales:

```powershell
node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
node scripts/test-core.mjs
node scripts/test-modules.mjs
node scripts/check-backend.mjs
python scripts/check-project.py
```

Abrir http://127.0.0.1:4173/. Los botones exteriores Medico/Paciente siguen abriendo ejemplos; para probar los servicios se utiliza el login real.

En Mac, configurar el xcconfig local, resolver Supabase 2.28.0, compilar y ejecutar el esquema HospitalUniversitario. Recorrer las pantallas de la tabla con una cuenta activa y vinculada; para las operaciones clinicas se necesita MFA autorizada y configurada previamente. Verificar solicitud pendiente, programacion por recepcion, check-in, consulta, orden/receta, cierre, resultados liberados, historial y avisos de cada destinatario. Comprobar dos cuentas distintas y perdida de red/version concurrente. Las instrucciones base de Xcode siguen en la guia del Doctor.

## Datos y pendientes reales

- Los catalogos reales de medicamentos y estudios estan vacios. La app muestra ese estado; no puede emitir un medicamento/estudio inexistente. La institucion debe cargar sus catalogos autorizados mediante su gestion existente. No se usaron ejemplos clinicos para rellenarlos.
- MFA sigue siendo requisito del servidor. La implementacion no inscribe factores en las cuentas demo; hacerlo continua requiriendo autorizacion explicita.
- Quedan pendientes compilacion, resolucion/lockfile de SPM y pruebas Swift/SwiftUI en Mac, y un recorrido HTTPS con sesiones reales autorizadas. No se anuncia una compilacion exitosa que no se ejecuto.
- La descarga se verifico como protegida, pero no se descargo un documento clinico real. La entrega en segundo plano/push no se implemento ni se promete: se utiliza el buzon interno mientras la app esta activa.
- El checker literal de modelos generados conserva su diferencia preexistente por CRLF en Windows; no se modificaron modelos generados ni el generador. No se cambiaron los recursos compartidos.

Estado final: codigo y backend de los modulos conectados, servidor web local iniciado, pruebas locales y transaccionales ejecutadas; datos institucionales, acceso MFA real y validacion nativa pendientes de su entorno correspondiente.
