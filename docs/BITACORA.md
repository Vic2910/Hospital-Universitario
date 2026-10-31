# Bitácora de trabajo

## 2026-10-30 - Dashboard del paciente

- **Solicitud:** rediseñar el inicio del rol Paciente en SwiftUI, con la captura `Captura de pantalla 2026-10-30 133626.png` como referencia de estructura (saludo con avatar, card de próxima cita, cuatro accesos rápidos) pero con la paleta vino/rojo del proyecto, conservando la barra inferior y la navegación existentes, y replicándolo en la web por la convención vigente.
- **Cambios Swift:** nuevos `Design/HospitalPalette.swift` (extension `Color`: vinoPrincipal, rojoAcento, fondoCard, fondoApp y `LinearGradient.vinoDestacado`), `Patient/PatientDashboardComponents.swift` (cards de saludo, fecha/cita y acceso rápido con estado al presionar) y `Patient/PatientDashboardView.swift` (vista principal, modelo `ProximaCita` y `#Preview` con «Gaby Diaz»). En `ContentView.swift` el `case "home"` ahora bifurca: médico conserva su home anterior y paciente usa el dashboard; se pasa `store.name` o el ejemplo, y `proximaCita: nil` hasta existir el modelo de citas.
- **Cambios web:** `web-preview/app.js` (rama del paciente de `home()` derivada a `patientDashboard()`, con nombre real o de ejemplo y cita de ejemplo en modo diseño) y `web-preview/style.css` (reglas `.dash-*`, CRLF normalizado). Home del médico intacto.
- **Sin cambios de lógica:** encabezado, barra inferior, `go()`, `store`, catálogo y llamadas a datos permanecen igual; sin escrituras ni API nuevas; el ID de «Agendar cita» es el `request` existente.
- **Verificaciones ejecutadas:** `node --check web-preview/app.js` aprobado; `scripts/test-preview.mjs` con 8 recorridos DOM aprobados (incluido diseño patient sobre el nuevo home); `python scripts/check-project.py` aprobado; `git diff --check` aprobado.
- **Limites y pendientes:** no se compiló Swift en Windows; compilación y revisión visual en Mac siguen pendientes. `proximaCita` queda parametrizado sin datos reales; el nuevo home del paciente ya no muestra las métricas del resumen.
- **Informe:** [DASHBOARD_PACIENTE_2026-10-30.md](DASHBOARD_PACIENTE_2026-10-30.md).

## 2026-10-30 - Convención: todo cambio visible también en la web

- **Solicitud:** el usuario pide que todo el trabajo quede reflejado en la vista previa web para verlo en Windows, y que a la vez funcione bien al compilarlo en Xcode/Mac.
- **Decision:** se establece la convención de implementación por duplicado y coherente: iOS/SwiftUI como fuente de verdad y `web-preview/` como réplica visual, conservando la lógica existente en ambas plataformas y ejecutando las pruebas locales tras cada cambio. Queda registrada en `AGENTS.md` (Decisiones vigentes) para que la sigan las sesiones futuras.
- **Rutas:** `AGENTS.md` y esta bitácora. No se modifico codigo de app ni web en esta entrada.
- **Verificacion ejecutada:** `git diff --check` aprobado. No se ejecutaron pruebas de app porque no hubo cambios funcionales.
- **Pendiente:** la compilacion Swift en Mac sigue pendiente, como en las entradas anteriores.

## 2026-10-30 - Rediseño visual de login y nueva pantalla de registro

- **Solicitud:** rediseñar la pantalla de login existente (sin pantalla nueva de login y sin tocar su lógica) usando `docs/design-reference/` como base visual, y crear la pantalla de registro con los campos nombres, apellidos, DUI, edad, teléfono, correo, contraseña y confirmar contraseña, en Swift/SwiftUI para Xcode.
- **Decisiones del usuario:** mantener los ocho campos aunque el diccionario no tenga DUI ni edad (se usan 9 dígitos `0000-00000` y entero 1–120), y dejar el registro **a nivel de diseño, sin registrar en la base de datos**.
- **Diccionario:** `persons.given_names`/`family_names` (1–100) y teléfono en `person_contacts` (`update_my_phone`) coinciden; DUI no existe en ninguna tabla y la edad no se almacena (ambigüedad S04: `birth_date`).
- **Cambios:** `Design/HospitalTheme.swift` (componentes HospitalAuthHeader/InputField/SecureField/PrimaryButtonStyle/Notice/Link); `ContentView.swift` (solo composición de `login`, enlaces «¿Olvidaste tu contraseña?» y «Regístrate», estados de presentación y rama hacia el registro); archivo nuevo `Auth/RegisterView.swift` con los ocho campos, iconos mostrar/ocultar en ambas contraseñas y validación local. El archivo nuevo entra al target por el grupo sincronizado; no se tocó `project.pbxproj`.
- **Réplica web (decisión posterior del usuario):** al ejecutar `web-preview/server.mjs` no se veían los cambios Swift, porque la vista previa es otra implementación. Se replicó el mismo diseño en `web-preview/app.js` (helpers `authHeader`/`authField`/`revealButton`, `renderLogin` con la misma lógica de envío e IDs, y `renderRegister` con los ocho campos y validación local sin llamadas a API) y se añadieron las reglas `.auth-*` al final de `web-preview/style.css` (CRLF normalizado).
- **Sin cambios de lógica:** la llamada `store.signIn` y su condición de deshabilitado quedaron idénticas en iOS; en web, el manejador de envío del login (`api.signIn`, `resolve`, `load`) y `api.js` intactos. `HospitalStore`, `HospitalAPI`, modelos, rutas, sesión y Supabase no se modificaron ni se ejecutó ninguna operación sobre la base.
- **Verificaciones ejecutadas:** `python scripts/check-project.py` aprobado; `git diff --check` aprobado; `scripts/test-preview.mjs` con 8 recorridos DOM aprobados tras el cambio web; `node --check web-preview/app.js` aprobado; revisión directa de `screen-01.png`/`screen-03.png` e `inventory.json` (ninguna referencia es login/registro); búsqueda literal de DUI sin resultados en el diccionario.
- **Limites y pendientes:** no se compiló Swift en Windows (sin SDK de Apple); compilación y revisión visual en Mac siguen pendientes. El registro no crea cuentas: en el modelo real el administrador crea y activa, y el trigger deja los perfiles `pending`.
- **Informe:** [REDISENO_AUTH_2026-10-30.md](REDISENO_AUTH_2026-10-30.md).

## 2026-10-28 - Retirada de MFA por solicitud expresa

- **Decision:** el usuario indica que su proyecto no requiere MFA y solicita retirarlo. Sustituye la decision previa para los roles moviles doctor/patient; no autoriza cambios a administracion ni elimina factores existentes.
- **Implementacion:** retirados desafio, vistas, metodos y estado TOTP de web/iOS; retirado bloqueo AAL2 del Doctor y texto MFA en errores. SQL aplicado al auxiliar de sesion existente: cuentas exclusivamente doctor/patient usan contrasena, con identidad, perfil activo y sesion vigente. Otros roles conservan condicion MFA anterior. No se cambiaron RLS, ACL, contrasenas, factores ni vinculos.
- **Rutas:** web-preview/{app,api,modules}.js; ContentView.swift; Core/{HospitalStore,HospitalAPI,ScreenCatalog,DoctorViewModel}.swift; scripts/{test-preview,test-modules}.mjs; docs/sql/{mobile-password-access,mobile-modules,test-mobile-flows}.sql; README e indice documental.
- **Verificacion real:** prueba transaccional SQL con claims AAL1 aprobada, incluyendo flujos clinicos y rechazos por rol, vinculo, version, estado cerrado y sesion expirada; ROLLBACK sin fixtures permanentes. No representa login Auth real ni compilacion de Xcode.
- **Verificaciones locales:** ocho recorridos DOM base y siete funcionales aprobados, incluyendo dashboard AAL1 sin factores, suspension y aislamiento del modo de diseno; comprobacion portable Xcode aprobada. El asesor de seguridad conserva los seis INFO del esquema historico y el WARN previo de proteccion de contrasenas filtradas, sin nuevos avisos. Pendientes: compilacion/pruebas nativas en Mac y login HTTPS con credenciales reales.
- **Informe:** [ACCESO_SIN_MFA_2026-10-28.md](ACCESO_SIN_MFA_2026-10-28.md).
- **Comprobacion final:** scripts/check-backend.mjs confirma catalogo publico HTTP 200 y ocho RPC protegidas HTTP 401 anonimas; git diff --check aprobado y editor sin errores en archivos revisados. Se recargo la pestana compartida hasta login. scripts/test-real-login.mjs actualizado al contrato sin MFA, con sintaxis validada pero sin ejecutarlo por falta de credenciales locales; ya no permite inscribir factores ni acepta 403 como resultado esperado de resumen. Prueba SQL ampliada con dashboard AAL1 y rol revocado: aprobada con ROLLBACK.

## 2026-10-28 - Diagnostico del acceso del medico sin MFA

- **Reporte:** mensaje generico de autorizacion al abrir el modulo del medico.
- **Diagnostico:** consulta agregada real a Auth: dos cuentas y ninguna con factor MFA verificado. El dashboard invocaba doctor_workspace con AAL1, aunque exige AAL2. No se inspeccionaron contrasenas ni secretos.
- **Cambios:** web muestra verificacion pendiente sin solicitar datos clinicos en AAL1, con acceso a notificaciones y perfil; iOS evita cargar el dashboard clinico y presenta el requisito especifico. Se mantiene la verificacion existente al ingresar cuando hay un factor inscrito.
- **Rutas:** web-preview/modules.js, Core/DoctorViewModel.swift, Core/HospitalStore.swift, scripts/test-preview.mjs y scripts/test-modules.mjs.
- **Seguridad:** no se alteraron RLS, RPC, permisos, cuentas ni factores. La inscripcion TOTP sigue pendiente de autorizacion explicita. Una sesion AAL2 aun requiere perfil, permisos y vinculos validos.
- **Verificaciones:** scripts/test-modules.mjs aprobado: ocho recorridos previos, seis funcionales y una regresion nueva del medico sin MFA, todos con transporte simulado. scripts/check-project.py y git diff --check aprobados. No se compila con Xcode en Windows ni se afirma login real del medico: la pestana compartida estaba en login con Failed to fetch.

Cada IA que modifique el proyecto debe añadir una entrada con fecha, objetivo, rutas afectadas, verificaciones ejecutadas y pendientes. No incluir credenciales ni secretos. Las instrucciones completas están en `../AGENTS.md`.

## 2026-10-28 - Modulos funcionales de Medico y Paciente en iOS y web

- **Solicitud:** sustituir el aviso de entrega posterior por flujos funcionales, basados en `docs/Informe_Hospital_Universitario.md` aportado por el usuario. Se continuo con ambos roles y la vista previa existente; no se incorporaron administracion ni otros roles.
- **Cambios:** listas/detalles paginados, solicitudes y cancelacion de citas propias, expediente/historial, recetas y resultados publicados del Paciente; receta atomica multirrenglon del Medico, diagnostico por catalogo, conservacion de borradores/versiones, confirmacion de jornadas, perfil/contacto/preferencias y documentos autorizados. Se elimino el scaffold clinico y se integro el transporte real en la web. La autenticacion compartida anterior se conserva.
- **Backend real:** se instalaron las cinco RPC nuevas de las dos propuestas SQL y eventos de notificacion. Se reutilizaron tablas, RPC y RLS existentes. Las pruebas revelaron y corrigieron acceso indebido al esquema auth desde hospital_api, necesidad de SET LOCAL ROLE para reaplicar funciones y mapeo de conflictos PT409. No se cambiaron credenciales, factores MFA, politicas ni privilegios permanentes; CREATE temporal se revoca antes de commit. Los eventos nuevos limitan destinatarios a los roles adecuados.
- **Rutas:** `HospitalUniversitario/HospitalUniversitario/Core/MobileModule{Models,Repository,ViewModel}.swift`, `Modules/MobileModuleView.swift`, archivos del Doctor y su repositorio/modelos, `ContentView.swift`, `Core/HospitalStore.swift`, pruebas Swift de Doctor y MobileModule, `web-preview/{modules,api,app}.js`, `index.html`, `style.css`, `server.mjs`, `.vscode/tasks.json`, `scripts/{test-modules,test-preview,check-backend}.mjs`, `docs/sql/{doctor-module,mobile-modules,test-mobile-flows}.sql`, informe nuevo, README e indice. El informe aportado por el usuario no se modifico.
- **Verificaciones locales:** 11 pruebas del nucleo, 8 recorridos DOM previos adaptados y 6 nuevos recorridos funcionales. Se reforzo el doble DOM tras detectar en navegador que textarea.type es de solo lectura. Comprobaciones de sintaxis JS, referencias portables Xcode, diagnosticos del editor y git diff --check.
- **Verificaciones en servidor:** flujos positivos y negativos en PostgreSQL con sesiones/claims y datos transitorios, siempre ROLLBACK; idempotencia de solicitud/orden/receta, versiones, roles, MFA y atencion cerrada. Luego se desplegaron definiciones sin fixtures y se comprobaron RPC presentes, rol sin BYPASSRLS y ausencia de catalogos de prueba. HTTPS anonimo: catalogo 200 y ocho endpoints protegidos 401. Asesor de seguridad sin avisos nuevos, conservando los siete preexistentes.
- **Verificacion web:** servidor local iniciado en 4173, recursos 200, documento sin sesion 403 y credenciales fuera del servidor 404. Recorrido de receta del componente con repositorio simulado en Playwright; una emision y sin desbordamiento medido en 1280x900/390x844. No se acredita igualdad visual con todas las referencias ni login real por ese recorrido.
- **Pendientes y limites:** no hay credenciales locales en esta copia; no se ejecuto login HTTPS real ni se inscribio TOTP. Los catalogos institucionales de medicamentos/estudios estan vacios y no se rellenaron con ejemplos. Falta compilar/probar en Mac, resolver SPM/lockfile, validar documentos reales y completar el recorrido con sesiones/MFA autorizadas. Las pruebas SQL con claims simulados no equivalen a Supabase Auth real.
- **Informe actual:** [MODULOS_FUNCIONALES_2026-10-28.md](MODULOS_FUNCIONALES_2026-10-28.md).

## 2026-10-28 - Modulo Doctor iOS conectado y propuesta SQL

- **Objetivo:** implementar consultas, ordenes de laboratorio, expediente/historial, dashboard y notificaciones del Doctor respetando la estructura SwiftUI existente.
- **Implementacion:** modelos Codable, repositorio async/await con supabase-swift 2.28.0, ObservableObject y vistas integradas en la navegacion actual. Sesion/MFA migradas al SDK compartido; configuracion iOS por xcconfig local ignorado e Info.plist. El flujo Paciente comparte esta capa de autenticacion, sin nuevas operaciones clinicas. La web no se amplio.
- **Rutas:** `HospitalUniversitario/HospitalUniversitario/Core/{DoctorModels,DoctorRepository,DoctorViewModel,HospitalAPI,HospitalStore,SharedCore}.swift`, `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift`, `HospitalUniversitario/HospitalUniversitario/ContentView.swift`, `HospitalUniversitario/HospitalUniversitarioTests/DoctorModuleTests.swift`, `HospitalUniversitario/Configuration/`, `HospitalUniversitario/HospitalUniversitario.xcodeproj/project.pbxproj`, `.gitignore`, `docs/sql/doctor-module.sql`, `README.md`, `docs/README.md` y esta bitacora.
- **Backend:** se inspeccionaron metadatos, permisos y funciones reales. La propuesta reutiliza tablas/RPC/RLS y agrega tres funciones de modulo y eventos de notificacion. Se probo la creacion, denegaciones sin sesion y ACL en una transaccion con ROLLBACK; se confirmo que las funciones nuevas no quedaron instaladas. Las consultas de proyeccion se comprobaron con IDs nulos en otra transaccion revertida. No se generaron registros clinicos ni se inscribio MFA; no se relajaron politicas.
- **Pruebas locales ejecutadas:** 11 pruebas existentes del nucleo/adaptador web; 8 recorridos DOM existentes; comprobacion portable del proyecto y `git diff --check`. El editor no reporto problemas, sin compilador Swift disponible. Se escribieron cinco pruebas Swift nuevas, no ejecutadas aqui.
- **Modelos/configuracion:** el chequeo literal de modelos fallo por CRLF del checkout; la comparacion en memoria normalizando unicamente saltos de linea coincidio con el contrato. No se modificaron modelos ni generador. Info.plist se valido con plistlib y se comprobo que el xcconfig local queda ignorado.
- **Pendientes:** despliegue SQL revisado, resolucion y lockfile SPM, compilacion/pruebas nativas y revision visual en Mac, pruebas clinicas positivas/concurrencia con MFA autorizada y revision de seguridad/rendimiento. Las verificaciones web no acreditan el nuevo modulo nativo.
- **Informe y pruebas por pantalla:** [MODULO_DOCTOR_2026-10-28.md](MODULO_DOCTOR_2026-10-28.md).

## 2026-10-28 - Intento de eliminar la rama de agendamiento

- **Solicitud:** eliminar `feature/paciente-agendar-cita` y conservar el estado anterior en `main`; el usuario confirmo el nombre correcto de la rama.
- **Resultado:** se intento `git push origin --delete feature/paciente-agendar-cita`. GitHub rechazo la operacion con HTTP 403: la cuenta autenticada `gabrieladiaz1-dev` no tiene permiso de escritura en `Vic2910/Hospital-Universitario`. No se elimino la rama.
- **Cambios y rutas:** solo esta bitacora (`docs/BITACORA.md`); no se modifico el codigo ni se cambiaron commits de `main`.
- **Verificaciones:** `git ls-remote --heads origin` confirmo que la rama remota sigue en `d0f00bf` y `main` en `58be7ea`; `git status --short --branch` confirmo `main`, sin cambios pendientes antes de este registro. No existe una rama local de agendamiento que eliminar.
- **Pendiente:** eliminar la rama remota con una cuenta con permisos de escritura. No se ejecutaron pruebas de la app, Xcode ni operaciones contra Supabase porque no hubo cambios funcionales.

## 2026-10-24 — Contraseñas más cortas para las cuentas de prueba

- **Solicitud:** acortar las contraseñas del Médico y del Paciente de demostración.
- **Cambios:** se actualizaron únicamente las contraseñas de las dos identidades existentes mediante la API autenticada de Supabase Auth; quedaron en 9 y 11 caracteres, con mayúsculas, minúsculas, números y símbolo. Se actualizaron los archivos locales de credenciales, excluidos de Git. No se modificaron roles, RLS ni factores MFA.
- **Archivos:** `.local/test-accounts.json`, `.local/CREDENCIALES_PRUEBA.md`, `.local/password-change-verification.json`, `README.md` y esta bitácora. Los documentos compartidos no contienen las contraseñas.
- **Verificación real por HTTPS:** las contraseñas anteriores fueron rechazadas; ambas contraseñas nuevas permitieron iniciar sesión y resolver el rol correspondiente. Se cerraron globalmente las sesiones previas de cada cuenta y se cerraron las sesiones de prueba posteriores.
- **Pendientes:** permanecen los pendientes anteriores de Xcode, revisión visual y autorización de inscripción TOTP. No se ejecutó de nuevo la batería de interfaz, porque no se modificó el código de la app.

## 2026-10-23 — Consolidación de la sesión y nombre definitivo

- **Solicitud:** nombre visible «Hospital Universitario» y documentación del trabajo de esta sesión, con instrucciones para que las IA documenten sus intervenciones.
- **Cambios:** se actualizaron los encabezados de SwiftUI y web; se consolidaron contexto, alcance, arquitectura, modelos, cuentas autorizadas, pruebas y limitaciones en `SESION_2026-10-23.md`; se creó un índice y la instrucción raíz para agentes.
- **Archivos:** `HospitalUniversitario/HospitalUniversitario/ContentView.swift`, `web-preview/app.js`, `AGENTS.md`, `docs/README.md`, `docs/SESION_2026-10-23.md`, `docs/BITACORA.md`, `docs/CONTEXTO_IOS.md` y `README.md`.
- **Verificación:** búsqueda del nombre anterior en el código de la app/web y revisión de diferencias/espacios mediante `git diff --check`. No se volvió a ejecutar la batería de pruebas ni se compiló Xcode por este cambio de textos/documentación.
- **Pendientes:** compilación en Mac, revisión visual y autorización adicional antes de inscribir TOTP. Las capturas e informes originales se conservan como fuentes históricas.
- **Informe completo de la sesión:** [SESION_2026-10-23.md](SESION_2026-10-23.md).

## 2026-10-30 — Agendar cita SwiftUI y web

Acceso Paciente → schedule, jerarquía visual vino/rojo, resumen, validación e invalidación de confirmación al editar. Se reutiliza el código existente y se conservan los cambios locales previos. [Informe](AGENDAR_CITA_2026-10-30.md). Verificación en curso; Xcode pendiente en Mac.


## 2026-10-30 - Continuación de agendar cita tras interrupción

- **Objetivo:** analizar y completar el avance existente de SwiftUI y web sin sustituir la navegación ni los módulos previos.
- **Estado encontrado:** PatientAppointmentView, componentes, síntomas, seis especialidades, horarios, validación y ruta schedule implementados; documentación indicaba verificación pendiente.
- **Cambios de esta continuación:** eliminado desplazamiento anidado nativo; teclado de DUI con guion; formatos de validación visibles y botón de simulación explícito en ambas versiones; descarte del borrador web al salir/cambiar perfil; campos y horarios coherentes, marcas de selección, foco y movimiento reducido. Conservados los cambios locales previos. Sin cambios en autenticación, RPC, RLS o Supabase.
- **Rutas:** Patient/PatientAppointmentView.swift y PatientAppointmentComponents.swift; web-preview/app.js y style.css; scripts/test-preview.mjs; README.md; docs/AGENDAR_CITA_2026-10-30.md y esta bitácora. El informe ya está enlazado en docs/README.md.
- **Pruebas ejecutadas:** ocho recorridos DOM existentes y dos nuevos de agendamiento con transporte simulado aprobados. Comprobador portable del proyecto, sintaxis de app.js y git diff --check aprobados también tras los últimos ajustes. Los siete recorridos funcionales de scripts/test-modules.mjs aprobaron con transporte simulado. No se ejecutaron pruebas reales contra Supabase.
- **Pendientes:** compilación y pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se afirma compilación Xcode ni igualdad visual comprobada. [Informe](AGENDAR_CITA_2026-10-30.md).


## 2026-10-30 - Dashboard del doctor coherente con el paciente

- **Objetivo:** rediseñar Inicio del doctor en SwiftUI y web con bienvenida, fecha de hoy, citas programadas, accesos clínicos, historial propio y horario laboral.
- **Implementación:** nueva DoctorDashboardView y réplica doctor-dashboard.js reutilizando estilos/cards del paciente; integración con workspace, historial por paciente/fechas y jornadas propias existentes. Modo diseño web y Preview Swift con Dr. Luis Ramírez, cuatro citas y datos ficticios equivalentes; nunca se sustituyen datos de sesión real con fixtures. Hasta incluye todo el día y se descartan resultados antiguos/error/contexto.
- **Rutas:** Doctor/DoctorDashboardView.swift y DoctorModuleView.swift; Core/DoctorViewModel.swift y HospitalStore.swift; ContentView.swift; web-preview/{doctor-dashboard.js,app.js,modules.js,index.html,server.mjs,style.css}; scripts/{test-preview.mjs,test-doctor-dashboard.mjs}; README.md, docs/README.md, este registro e informe enlazado.
- **Verificaciones ejecutadas:** ocho recorridos DOM previos más dos de citas; siete recorridos funcionales; dos nuevos recorridos del dashboard con transporte simulado (demo y sesión), incluyendo exclusión de otro doctor; comprobador portable; sintaxis JS; git diff --check. HTTP 200 local en página y cuatro recursos relevantes, cerrando el servidor temporal. Sin pruebas reales contra Supabase ni cambios de backend.
- **Límites:** selector de pacientes de la agenda de hoy; para otra agenda se conserva el acceso a Pacientes. Resumen del horario con primera página y hasta siete jornadas; horario completo mantiene paginación existente. Xcode/pruebas Swift y comparación visual en navegador/dispositivo pendientes; no hay Playwright instalado.
- **Informe:** [DASHBOARD_DOCTOR_2026-10-30.md](DASHBOARD_DOCTOR_2026-10-30.md).


## 2026-10-30 - Corrección: historial en Pacientes y jornadas en Mi horario

- **Solicitud:** retirar historial clínico y horario del panel general del doctor; ubicar el primero en Pacientes y el segundo en su pantalla de horario. Sustituye la distribución de la entrada anterior.
- **Cambios SwiftUI:** extraído DoctorPatientHistoryView con su estado y filtros, integrado solo en Pacientes y reiniciado al cambiar la fecha de agenda. DoctorDashboardView conserva saludo, fecha, conteo y accesos. Retirada lectura de jornadas de Inicio; se conserva la pantalla turns y su carga. Método de lectura independiente renombrado a patientHistory.
- **Cambios web:** renderHistory se integra en Pacientes tanto en diseño como en sesión; Inicio conserva solo bienvenida y accesos. Retirado resumen y carga de jornadas en Inicio; horario existente en Más → Mi horario intacto. Se descartan filtros/resultados al salir de Pacientes.
- **Rutas:** Doctor/{DoctorDashboardView,DoctorPatientHistoryView,DoctorModuleView}.swift; Core/{DoctorViewModel,HospitalStore}.swift; ContentView.swift; web-preview/{doctor-dashboard,app,modules}.js; scripts/test-doctor-dashboard.mjs; README.md, informe DASHBOARD_DOCTOR_2026-10-30.md y bitácora. El informe sigue enlazado en docs/README.md.
- **Verificaciones:** scripts/test-preview.mjs aprobado (ocho recorridos previos y dos de agendar cita); scripts/test-doctor-dashboard.mjs aprobado, incluyendo ausencia de historial/horario en Inicio, filtros en Pacientes y lectura propia en Mi horario; siete recorridos de scripts/test-modules.mjs aprobados; python scripts/check-project.py, sintaxis de los tres JS modificados y git diff --check aprobados. No se hicieron escrituras ni pruebas reales contra Supabase.
- **Pendientes:** compilación y pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se afirma compilación Xcode.


## 2026-10-30 - Retirar Mis citas exclusivamente del Doctor

- **Solicitud:** eliminar Mis citas de la navegación y de todos los accesos/pantallas del rol Doctor, conservándolo en Paciente.
- **Implementación iOS/web:** retirado el destino appointments del catálogo compartido del Doctor, del menú inferior, del menú Más y de sus manejadores de módulos. La barra Doctor queda Inicio / Pacientes / Consultas / Más; web ajusta las columnas a cuatro. El acceso secundario del resumen anterior ahora apunta a Pacientes. Se retiraron ejemplos de esa pantalla del Doctor; la agenda clínica y su modelo de citas siguen utilizándose en Pacientes, Consultas y el conteo del día. Ningún cambio en autenticación, backend o datos reales.
- **Rutas:** Shared/screens.json; ContentView.swift; Core/HospitalStore.swift; Doctor/DoctorModuleView.swift; web-preview/{app.js,modules.js,style.css,design-fixtures.json}; scripts/{check-project.py,test-preview.mjs}; README.md y esta bitácora.
- **Verificaciones ejecutadas:** test-preview.mjs aprobado, comprobando ausencia de Mis citas en todas las pantallas de diseño del Doctor y presencia para Paciente; siete recorridos de test-modules.mjs y recorridos de test-doctor-dashboard.mjs aprobados. Sintaxis de app.js/modules.js, python scripts/check-project.py y git diff --check aprobados. El catálogo tiene 20 pantallas activas (11 Paciente, 9 Doctor); se conservan las 21 capturas históricas sin alterarlas.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo. No se ejecutaron pruebas reales contra Supabase.


## 2026-10-30 - Agenda visual de Consultas del Doctor

- **Solicitud:** mejorar el estilo de Consultas con colores de la app, agenda de hoy, búsqueda por fecha para próximas consultas y datos precargados mientras no haya registros.
- **Implementación SwiftUI/web:** encabezado vino, total por fecha, calendario, accesos Hoy/Mañana/En 7 días, tarjetas de paciente/hora/estado, búsqueda y vacío. Datos equivalentes: cuatro consultas hoy, dos mañana, una en tres días y una en siete. El modo diseño y el resultado autorizado vacío muestran ejemplos identificados y sin acciones clínicas; los datos reales conservan selección y formulario previo. Sin cambios en autenticación, backend, RLS ni registros reales.
- **Rutas:** Doctor/{DoctorConsultationAgendaView,DoctorModuleView}.swift; ContentView.swift; Shared/screens.json; web-preview/{doctor-dashboard.js,app.js,modules.js,style.css}; scripts/test-doctor-consultations.mjs; README.md; docs/README.md; informe y bitácora.
- **Verificaciones ejecutadas:** test-preview.mjs aprobado (ocho recorridos anteriores y dos de citas); siete recorridos de test-modules.mjs aprobados; tres recorridos nuevos de agenda (diseño, sesión vacía y citas reales simuladas), con calendario, próximas fechas, búsqueda, ausencia de escrituras ficticias e intervalo diario RPC. Sintaxis JS, comprobador portable del proyecto y git diff --check aprobados. Se repiten tras el ajuste final de textos.
- **Pendientes:** Xcode/pruebas Swift en Mac y revisión visual en navegador/dispositivo. Sin pruebas reales contra Supabase.
- **Informe:** [CONSULTAS_DOCTOR_2026-10-30.md](CONSULTAS_DOCTOR_2026-10-30.md).


## 2026-10-30 - Tarjetas completas y ticket de Consultas Doctor

- **Solicitud:** rediseño acotado de lista/detalle de Consultas en SwiftUI y web; datos de paciente, edad, teléfono, hora, motivo y síntomas; etiquetas con No hay datos reales para faltantes.
- **Implementación:** tarjetas con campos ordenados y Ver detalle; hoja nativa y panel web accesible dentro de la consulta seleccionada. Círculo vino/check blanco, fecha/hora en negrita y botón azul de la captura revisada. Estado original visible; apertura de detalle separada de Abrir atención. Opcionales compatibles en DoctorAppointment y ejemplos idénticos enriquecidos. No se añadieron dependencias, operaciones de backend, permisos ni cambios en otros módulos.
- **Rutas:** Doctor/DoctorConsultationAgendaView.swift; nuevo Doctor/DoctorConsultationTicketView.swift; Core/DoctorModels.swift; web-preview/{doctor-dashboard.js,style.css}; scripts/test-doctor-consultations.mjs; README.md; docs/{README.md,TICKET_CONSULTA_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** pruebas DOM de preview, agenda/ticket y siete recorridos funcionales con transporte simulado aprobados; datos completos/faltantes, edad cero, texto largo, estado cancelado, apertura/cierre y ausencia de operaciones clínicas al abrir ticket. Sintaxis JS aprobada después de corregir un conflicto de nombre detectado por las pruebas. Comprobador portable y git diff --check aprobados; se repiten tras los últimos ajustes.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo, incluida medición de desbordamiento. Sin pruebas reales contra Supabase. El backend actual no expone edad/motivo/síntomas en agenda; se muestran los faltantes sin inventar valores reales.
- **Informe:** [TICKET_CONSULTA_DOCTOR_2026-10-30.md](TICKET_CONSULTA_DOCTOR_2026-10-30.md).


## 2026-10-30 - Laboratorios de diseño dentro del expediente por rol

- **Solicitud y aclaración:** buscar paciente por DUI/nombre en Expedientes, abrir su ficha y preparar desde ella una solicitud de laboratorio asignada a ese paciente. Paciente solo ve solicitudes/resultados. Tres estados: Pendiente, En Proceso y Completado. Trabajo de diseño, sin envío a base de datos.
- **SwiftUI/web:** modelos locales serializables, catálogo de siete estudios sencillos sin imágenes, datos de registro y ejemplo de primera visita, editor dentro del expediente, contexto automático de médico/clínica/fecha/hora/turno, validación obligatoria, sección de laboratorios con filtros por fecha/categoría/paciente y detalle. Estado compartido al navegar; guardas por rol y descarte de borradores al cambiar de paciente. Se conservan los módulos reales previos; iOS ofrece interruptor explícito de diseño y web usa su modo de diseño aislado.
- **Navegación:** Doctor incluye Laboratorios como quinto destino (Inicio/Pacientes/Consultas/Laboratorios/Más), sin restaurar Mis citas. El expediente sigue en el destino chart existente; no se crearon rutas nuevas.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; Shared/screens.json; web-preview/{clinical-labs.js,app.js,index.html,server.mjs,style.css}; scripts/{test-preview,test-clinical-labs}.mjs; README.md; docs/{README.md,LABORATORIOS_EXPEDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** tres recorridos nuevos de diseño/rol/modelo aprobados, con ausencia de llamadas reales; preview (ocho previos y dos de citas), siete flujos de módulos, dashboard y consultas/ticket aprobados con transporte simulado. Sintaxis JS, comprobador portable y git diff --check aprobados. HTTP 200 local de página y tres recursos en servidor temporal, cerrado al terminar.
- **Pendientes y límites:** Xcode/pruebas Swift en Mac y revisión visual en navegador/dispositivo; futura adaptación al catálogo y RPC autorizados. Sin pruebas reales contra Supabase, cambios de backend, credenciales ni registros clínicos. Los datos y solicitudes locales se reinician al salir/cambiar de modo o rol.
- **Informe:** [LABORATORIOS_EXPEDIENTE_2026-10-30.md](LABORATORIOS_EXPEDIENTE_2026-10-30.md).


## 2026-10-30 - Corrección de visibilidad del rediseño en sesión Doctor

- **Reporte y causa:** la captura del usuario mostraba el formulario anterior tras iniciar sesión. El renderer nuevo estaba condicionado al modo diseño externo y SwiftUI requería activar un interruptor; la navegación normal no mostraba lo solicitado.
- **Corrección web/iOS:** Expedientes y Laboratorios del Doctor muestran el diseño local por defecto también dentro de sesión. Laboratorios sin paciente seleccionado muestra inmediatamente búsqueda por DUI/nombre y acceso al expediente. Se conserva aviso visible de datos ficticios y ninguna solicitud local se envía al hospital. Web conserva Ver flujo conectado / Ver diseño de expediente y laboratorios para acceder al módulo real anterior; SwiftUI activa inicialmente el diseño al resolver el rol Doctor y conserva el interruptor. Los datos reales del Paciente no se sustituyen por ejemplos.
- **Rutas:** web-preview/{app.js,clinical-labs.js}; ContentView.swift; Modules/ClinicalLabDesignView.swift; scripts/test-clinical-labs.mjs; README.md; docs/{LABORATORIOS_EXPEDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** regresión nueva con sesión Doctor y recorrido idéntico al de la captura aprobada: búsqueda visible sin activar modo externo, expediente seleccionado, solicitud local, ausencia de emisión remota y conmutación al flujo conectado conservando el prototipo. Pruebas de laboratorio/diseño/modelo y siete flujos previos aprobados; test-preview.mjs ejecutado por importación y repetido al cierre; comprobador portable y git diff --check aprobados. Sin login real ni escrituras a Supabase.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo. La regresión es DOM con transporte simulado.


## 2026-10-30 - Laboratorio independiente y expediente modal compartido

- **Objetivo actual:** solicitar desde Laboratorio sin abrir expediente, mediante modal con fecha/doctor automáticos, motivo, examen, peso y altura; expediente separado con ficha completa, laboratorios y acciones de observación/receta.
- **Implementación iOS/web:** modales equivalentes, captura decimal validada, autor de cuenta activa, solicitud Pendiente y cierre/confirmación; modelo compartido para ficha, mediciones, resultados estructurados, notas y recetas locales no emitidas. Punto applyPublishedResult para aplicar resultados publicados, actualizando vistas sin duplicar y rechazando eventos antiguos. Se preserva el módulo conectado anterior y las rutas. Esta decisión sustituye el requisito previo de solicitar solo desde Expedientes.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{README.md,LABORATORIO_INDEPENDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** pruebas DOM de solicitud/modal, medidas inválidas/decimales, cierre, autor activo, notas/recetas aisladas, resultados y estados compartidos aprobadas; preview y siete recorridos de módulos previos, consultas/ticket aprobados. Comprobador portable, sintaxis JS y git diff --check aprobados. Se corrigió una etiqueta accesible ambigua detectada en las pruebas. No se ejecutaron escrituras ni pruebas reales contra Supabase.
- **Pendientes explícitos:** conectar eventos/resultados reales de recepción y persistencia remota, sin inventar permisos; compilar y probar Swift en Mac; revisar visualmente navegador/dispositivo. applyPublishedResult es un adaptador local probado, no una conexión de recepción ya desplegada. Las recetas nuevas son borradores locales y conservan el módulo real aparte.
- **Informe:** [LABORATORIO_INDEPENDIENTE_2026-10-30.md](LABORATORIO_INDEPENDIENTE_2026-10-30.md).


## 2026-10-30 - Tickets internos y separación visual de Laboratorios

- **Solicitud:** evitar ventanas externas; solicitud y expediente como tickets dentro de la app, con estilo de la captura de confirmación. Separar búsqueda/selección del formulario y de los filtros de resultados, que se mezclaban visualmente.
- **SwiftUI/web:** eliminados sheet/dialog del flujo local y sustituidos por paneles internos. Entrada con introducción vino, búsqueda y acciones; Solicitar exámenes muestra exclusivamente el ticket del formulario; Ver solicitudes y resultados abre su propio panel con filtros. Expediente/notas/recetas también quedan dentro del contenido de la app. Check vino/blanco, bloque central destacado, secciones numeradas, campos de medidas agrupados y acción azul de referencia. Eliminada la búsqueda genérica duplicada solo en el flujo local. Sin modificar modelos, backend ni operaciones reales.
- **Rutas:** Modules/ClinicalLabDesignView.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{LABORATORIO_INDEPENDIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** test-clinical-labs.mjs aprobado, incluyendo ausencia de dialog y filtros/formulario antes de la acción, ticket interno, validaciones, resultados y aislamiento. Siete recorridos de módulos previos aprobados; preview (ocho previos y dos de citas), sintaxis JS, comprobador portable y git diff --check aprobados. No se realizó revisión visual automatizada ni compilación Swift.
- **Pendientes:** comparación visual en navegador/dispositivo y compilación/pruebas en Mac; conexión remota de recepción/persistencia sigue pendiente como se documentó anteriormente. [Informe actualizado](LABORATORIO_INDEPENDIENTE_2026-10-30.md).


## 2026-10-30 - Rediseño de Pacientes del Doctor con fecha, DUI y nombre

- **Solicitud:** mejorar visualmente Pacientes del Doctor, con búsqueda por fecha/DUI/nombre y acceso claro a datos e historial clínico del paciente coincidente.
- **SwiftUI/web:** cabecera vino, búsqueda única, accesos Todos/Hoy/Mañana, calendario, conteo y tarjetas con iniciales/demografía/seguimiento. Selección abre ticket interno con cronología de consultas propias, datos, signos disponibles, notas, recetas y estudios compartidos. La fecha filtra atenciones de agenda; citas futuras no se incluyen como antecedentes realizados. Filtros conservados al volver. El rediseño local queda visible en sesión Doctor; flujo conectado previo conservado.
- **Rutas:** Modules/ClinicalLabDesign{Models,View}.swift; ContentView.swift; web-preview/{clinical-labs.js,app.js,style.css}; scripts/{test-doctor-patients,test-doctor-dashboard}.mjs; README.md; docs/{README.md,PACIENTES_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones ejecutadas:** dos recorridos nuevos (diseño y sesión simulada) aprobados, con búsquedas combinadas, ficha sin dialog, exclusión de otro médico/paciente y datos compartidos; regresiones de dashboard, laboratorio y preview aprobadas. Comprobador portable, sintaxis JS y git diff --check aprobados. Se separó la clase del estado de consulta de los estados de laboratorio para conservar sus tres estados exactos.
- **Límites:** pacientes e historial nuevo precargados e identificados; no se afirma búsqueda real por DUI ni escrituras remotas. Pendientes Xcode/pruebas Swift en Mac y revisión visual real. [Informe](PACIENTES_DOCTOR_2026-10-30.md).


## 2026-10-30 - Perfil reducido al nombre y apellido registrados

- **Solicitud:** mejorar Perfil para que únicamente muestre nombre y apellido del registro del usuario.
- **SwiftUI/web:** presentación de solo lectura con dos campos Nombre/Apellido, paleta existente y encabezado Datos de registro. Fuente real exclusiva my_profile.person.given_names/family_names; no se usa el nombre preferido, el del Doctor ni ejemplos como sustitutos en sesión. Faltantes o espacios se muestran como No disponible. Retirados de esta vista correo, datos profesionales, contacto, contraseña, preferencias y accesos secundarios; cierre de sesión sigue en Más. Sin modificar datos de usuario, autenticación o backend.
- **Carga:** Perfil ya no solicita mobile_module/profile ni monta su formulario de configuración; se conserva el código previo del módulo, sin mostrarlo en Perfil. Se elimina búsqueda innecesaria de esta pantalla. Los ejemplos del modo diseño tienen campos separados y explícitos de nombre/apellido.
- **Rutas:** ContentView.swift; Core/HospitalStore.swift; Shared/screens.json; web-preview/{app.js,style.css,design-fixtures.json}; scripts/test-profile.mjs; README.md y esta bitácora.
- **Verificaciones:** test-profile.mjs aprobado para Doctor/Paciente en sesión simulada, diseño y campos ausentes; confirma dos campos y ausencia de formularios/lecturas de ajustes. Preview (ocho recorridos previos y dos de citas), siete flujos de test-modules.mjs, sintaxis de app.js, python scripts/check-project.py y git diff --check aprobados. Sin pruebas reales contra Supabase ni escrituras.
- **Pendientes:** compilación/pruebas Swift en Mac y revisión visual en navegador/dispositivo.


## 2026-10-30 - Expediente del Paciente con ticket interno de solo lectura

- **Solicitud:** el Paciente debe ver su expediente con el diseño interno del Doctor de la captura, limitado a información propia.
- **SwiftUI/web:** cabecera con check vino/blanco, título, nombre e identificación y secciones ordenadas en el mismo contenido de la app. Entrada directa, sin modales externos, selección de personas ni interruptor para ver los datos reales. Sesión utiliza mobile_module patient/chart existente; faltantes explícitos y modo diseño propio separado. Documentos publicados conservan autorización; se excluyen acciones de escritura en chart.
- **Rutas:** Modules/MobileModuleView.swift; ContentView.swift; web-preview/{modules.js,clinical-labs.js,app.js,style.css}; scripts/test-patient-chart.mjs; README.md; docs/{README.md,EXPEDIENTE_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-patient-chart.mjs aprobado (propietario, campos, faltantes y solo lectura); preview, laboratorios y siete recorridos clínicos previos aprobados con transporte simulado; sintaxis JS, comprobador portable y git diff --check aprobados. Sin pruebas reales contra Supabase ni cambios a sus permisos/datos.
- **Pendientes:** revisión visual en navegador/dispositivo y compilación/pruebas Swift en Mac. [Informe](EXPEDIENTE_PACIENTE_2026-10-30.md).


## 2026-10-30 - Volver en la esquina del expediente del Paciente

- **Solicitud:** incluir Volver en la esquina superior izquierda del expediente propio, con la misma cabecera del Doctor.
- **SwiftUI/web:** botón Volver y rótulo FICHA CLÍNICA antes del icono del ticket. Usa la navegación existente hacia Inicio, coherente con el expediente de diseño Paciente. Se conserva acceso exclusivo a datos propios y solo lectura.
- **Rutas:** Modules/MobileModuleView.swift; web-preview/modules.js; scripts/test-patient-chart.mjs; docs/EXPEDIENTE_PACIENTE_2026-10-30.md y bitácora.
- **Verificaciones:** test-patient-chart.mjs ampliado para comprobar Volver en sesión simulada y diseño; test-preview.mjs, python scripts/check-project.py y git diff --check ejecutados al cierre. No se compila Xcode ni se verifica visualmente en dispositivo en Windows.


## 2026-10-30 - Historial médico del Paciente con tarjetas de referencia y detalle

- **Solicitud:** rediseño de Historial médico en SwiftUI y web según captura 215451, con tres consultas exactas, orden descendente, línea verde existente y detalle pulsable.
- **Implementación:** PatientHistoryRecord y PatientHistoryView, equivalentes JS, tarjetas con jerarquía fecha/hora/especialidad/médico/motivo y detalle interno con Volver. Datos de ejemplo identificados solo en diseño o lectura propia exitosa vacía; registros reales sin mezcla y error sin ejemplos como sustituto. Estado vacío amable, búsqueda, reintento/paginación y solo lectura. La línea verde es estilo de referencia; no se califican citas pasadas como futuras.
- **Rutas:** nuevo Patient/PatientHistoryView.swift; ContentView.swift; nuevo web-preview/patient-history.js; web-preview/{app.js,style.css,index.html,server.mjs}; scripts/{test-patient-history,test-preview}.mjs; README.md y documentación enlazada.
- **Verificaciones:** pruebas nuevas de historia exacta/orden, tres detalles, búsqueda, vacío, error y alcance patient aprobadas; preview y siete flujos de módulos previos aprobados con transporte simulado; comprobador portable, sintaxis JS y git diff --check aprobados. Recurso nuevo HTTP 200 en 4173 tras actualizar la instancia local existente sin duplicar el servidor.
- **Pendientes:** revisión visual navegador/dispositivo y compilación/pruebas Swift en Mac. Sin pruebas reales ni escrituras de Supabase. [Informe](HISTORIAL_PACIENTE_2026-10-30.md).


## 2026-10-30 - Card Recetas y presentación del Paciente según receta.png

- **Solicitud:** sustituir Paciente por Recetas en el dashboard y presentar sus recetas ordenadas con estados de retiro y estilo de la referencia receta.png.
- **SwiftUI/web:** card Recetas apunta a prescriptions; nuevo listado por medicamento con dosis, frecuencia, vía, duración, cantidad, observaciones y estados Pendiente/Retirada. Registros ordenados por emisión descendente. Ejemplos identificados para diseño/listado vacío exitoso; datos reales propios sin mezcla. Si la fuente no expone retiro, Retiro por confirmar, sin traducir active/expired a entrega de farmacia. Se conserva texto clínico íntegro y faltantes estructurados explícitos.
- **Navegación preservada:** Agendar cita queda accesible desde Mis citas; no se elimina el formulario previo. Doctor no se modifica.
- **Rutas:** Patient/{PatientDashboardView,PatientPrescriptionsView}.swift; ContentView.swift; Modules/MobileModuleView.swift; web-preview/{patient-prescriptions.js,app.js,modules.js,index.html,server.mjs,style.css}; scripts/{test-preview,test-patient-prescriptions}.mjs; README.md; docs/{README.md,RECETAS_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-patient-prescriptions aprobado (acceso, orden, estados, detalles, búsqueda, alcance patient y ausencia de escritura), test-preview y siete flujos de test-modules aprobados; comprobador portable, sintaxis JS y git diff --check aprobados. Recurso web HTTP 200 tras actualizar el servidor local existente, sin dos procesos en el puerto.
- **Pendientes:** Xcode/pruebas Swift en Mac y revisión visual real; proyección autorizada de retiro y datos de farmacia cuando se conecte esa información. Sin pruebas reales ni cambios en Supabase. [Informe](RECETAS_PACIENTE_2026-10-30.md).


## 2026-10-30 - Campos completos de receta del Doctor

- **Solicitud:** al crear una receta el Doctor debe capturar medicamento, dosis, cantidad y todos los campos que ve el Paciente.
- **SwiftUI/web:** formulario local del expediente ampliado con dosis/unidad, frecuencia, vía, duración, cantidad y observaciones; snapshot estructurado y validación obligatoria. Formulario conectado conserva catálogo y permisos; añade Durante (días), etiqueta Observaciones y vista previa completa. Días se traducen a starts_on/ends_on existentes; no se agregan campos incompatibles al transporte. Se preserva tratamiento hasta nueva indicación cuando no se define fin. Pendiente/Retirada no se hacen editables por el Doctor.
- **Rutas:** Modules/{ClinicalLabDesignModels,ClinicalLabDesignView,MobileModuleView}.swift; web-preview/{clinical-labs.js,modules.js}; scripts/{test-clinical-labs,test-modules}.mjs; README.md; docs/{README.md,CAMPOS_RECETA_DOCTOR_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** test-clinical-labs.mjs aprobado con campos de receta completos y bloqueo de incompletos; siete flujos de test-modules.mjs aprobados con duración de diez días entre 30 oct y 8 nov, observaciones y sin days en RPC. Preview, comprobador portable, sintaxis JS y git diff --check aprobados. Sin emisión real ni cambios de Supabase.
- **Pendientes:** Xcode/pruebas Swift en Mac, revisión visual y proyección estructurada de lectura real al Paciente según informe previo. [Informe](CAMPOS_RECETA_DOCTOR_2026-10-30.md).


## 2026-10-30 — Próxima cita y solicitud única del Paciente

- **Objetivo:** compartir el diseño del ticket del Doctor, eliminar el formulario duplicado, capturar preferencia Mañana/Tarde y simular Pendiente → Cita asignada por Recepción.
- **Implementación:** store/snapshots locales en SwiftUI y web; Mis citas con próxima cita y detalle interno; formulario de agendar renombrado Solicitar atención y validación de preferencia; confirmación Pendiente sin reserva; recepción local con asignación de fecha/hora, vínculo a cita y bloqueo de duplicados. Se retiró el formulario visual anterior. Estados compatibles con pending/scheduled/rejected/cancelled. Citas conectadas, cancelación y vistas del Doctor conservadas.
- **Rutas:** iOS Patient/{PatientAppointmentFlow,PatientAppointmentView,PatientAppointmentComponents}.swift; Doctor/DoctorConsultationTicketView.swift; ContentView.swift; Core/HospitalStore.swift; Modules/MobileModuleView.swift. Web {patient-appointments.js,app.js,modules.js,index.html,server.mjs}. Scripts {test-patient-appointments,test-preview,test-modules}.mjs. README.md; docs/{README.md,BITACORA.md,CITAS_SOLICITUDES_PACIENTE_2026-10-30.md}.
- **Verificaciones ejecutadas:** preview y 20 pantallas; prueba nueva de solicitud/preferencia/ticket/asignación, datos propios y errores; siete recorridos de módulos; pruebas de consultas y dashboard del Doctor; comprobador de proyecto, sintaxis JS y diff --check. DOM/transporte simulados, sin escribir en Supabase. Servidor local actualizado y tres recursos HTTP 200/no-store.
- **Pendientes/límites:** Xcode y revisión visual; persistencia real de solicitudes/preferencia, acceso autorizado y asignación de Recepción. La web ofrece Recepción (demo), SwiftUI su Preview/componente; no se creó un rol real ni se modificaron políticas, esquema o RPC. Los datos locales se reinician y no son registros clínicos. Esta decisión reemplaza los accesos separados anteriores. [Informe](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-31 — Conexión de Doctor/Paciente a Supabase y datos de ejemplo en la base

- **Objetivo:** cerrar los gaps de conexión de las vistas de Doctor y Paciente (iOS/SwiftUI y réplica web) con Supabase, eliminar los ejemplos locales de las listas conectadas y crear esos ejemplos dentro de la base de datos (antes solo existía «Paciente de prueba»), verificando lectura/escritura y permisos por rol.
- **Aplicación iOS/web (por duplicado):** archivos modificados en esta sesión — iOS: `ContentView.swift`, `Core/HospitalStore.swift`, `Core/MobileModuleViewModel.swift`, `Doctor/DoctorModuleView.swift`, `Patient/PatientAppointmentFlow.swift`, `Patient/PatientAppointmentView.swift`; web: `web-preview/app.js`, `web-preview/patient-appointments.js`. `HospitalStore.refreshScreen` carga por pantalla (`request`/`schedule` → `my_profile()` + `modules.load("request")`, inicio del Paciente → `appointments`, perfil → `my_profile()` + `modules.load("profile")`); `PatientAppointmentRealView` conectado con especialidades reales, datos del Paciente en solo lectura, «Fecha preferida» y preferencia Mañana/Tarde; «Mis citas» sin ejemplos; próxima cita real en el inicio del Paciente; perfil con `MobileModuleView(module:"profile")`; `symptoms` concatenados a `p_reason` en `requestAppointment()`; consulta del Doctor sin fallback de agenda demo. Réplica equivalente en `web-preview/` (`app.js`, `patient-appointments.js`). Seis suites de `scripts/` actualizadas para el modo real.
- **Datos sembrados en Supabase (sin tocar esquema, RPC ni políticas):** consultorios, jornada del médico, aviso público, cola del día con turno; 3 citas del Paciente (pasada `completed`, próxima `confirmed` hoy, futura `scheduled`); encuentro cerrado con nota clínica firmada y diagnóstico; receta `issued` con 2 ítems; orden de laboratorio `completed` con 2 resultados liberados y sus valores; alergia, condición resuelta, antecedente familiar, contactos, contacto de emergencia y `care_assignments` médico–paciente; catálogos de medicamentos, analitos, pruebas, diagnósticos y alérgenos. Todo respetando `touch_and_audit`/`validate_record` (receta en `draft` antes de emitir, resultados en `draft` antes de liberar).
- **Hallazgos:** `private.mobile_module` corre como `hospital_api` con RLS `FORCE`, por lo que las policies sí aplican dentro del RPC; el Doctor solo ve recetas si existe un `care_assignments` vigente que active `can_encounter(...,'clinical.read')`. Una receta `issued` es inmutable y sus vías no se pueden corregir en caliente. `request_appointment` no admite síntomas ni preferencia: la app los traduce.
- **Verificaciones realmente ejecutadas:** verificación contra Supabase con claims simulados en transacción con `ROLLBACK` (plantilla `docs/sql/test-mobile-flows.sql`): Paciente — `my_access`, módulos appointments/request/chart/history/prescriptions/laboratory/notifications/profile, idempotencia de `request_appointment`, suplantación de rol y cuenta sin vínculo rechazadas; Doctor — `my_access`, prescriptions (`issued` propia) y profile, con acceso a módulos de Paciente rechazado. Locales: `test-preview.mjs` (8 recorridos + 20 pantallas + agendar cita), `python scripts/check-project.py` y `git diff --check`, todos en verde.
- **Pendientes/límites:** compilación y pruebas Swift en Mac (no se anuncia ninguna compilación); login real con credenciales de `.local/` no ejecutado en esta copia; revisión visual en navegador/dispositivo. La cita «próxima» sembrada vence con el tiempo y deberá renovarse. [Informe](CONECTAR_SUPABASE_DATOS_DEMO_2026-10-31.md).


## 2026-10-31 — Formulario de registro conectado a Supabase (DUI y teléfono)

- **Objetivo:** el formulario de crear cuenta mostraba «Formulario de demostración: no se envía a la base de datos» y el DUI estaba mal implementado (formato `0000-00000`); se pidió que el registro **sí** se enviara a la base y que se corrigiera el DUI. Decisiones del usuario: auto-registro completo (signUp → confirmación de correo → submit), añadir columnas de DUI/teléfono al esquema (autorización explícita) y campo «Fecha de nacimiento» en lugar de «Edad».
- **Aplicación iOS/web (por duplicado):** iOS — `Core/HospitalAPI.swift` (`signUp`, `submitPatientRegistration`, struct `RegistrationDraft` con la sede CENTRAL), `Core/HospitalStore.swift` (`signUpForRegistration`/`signInForRegistration`/`submitRegistration`/`endRegistrationSession`, sin tocar el `busy` principal), `Auth/RegisterView.swift` (reescrito: fecha de nacimiento, sexo administrativo, DUI `00000000-0`, teléfono `0000-0000`, máscaras y las dos fases del flujo), `ContentView.swift` (inyecta el store). Web — `web-preview/api.js` (`signUp`, `submitPatientRegistration`, mensajes para `email_not_confirmed` y cuenta existente), `web-preview/app.js` (`renderRegister`/`registerProblem` reescritos, mismos campos y fases), `web-preview/style.css` (estilos de `select` y título de auth).
- **Migración en Supabase (autorizada y aplicada):** `hospital.persons` y `hospital.registration_requests` + columnas `dui`/`phone` con CHECK `^[0-9]{8}-[0-9]$` y `^[0-9]{4}-[0-9]{4}$`; `private/public.submit_patient_registration` ampliadas a 7 parámetros (`p_dui`, `p_phone` DEFAULT NULL, validan y almacenan); `review_patient_registration` copia dui/phone a `persons` al aprobar. Artefactos: `docs/sql/registration-dui-phone-migration.sql` y `docs/sql/test-registration-dui-phone.sql`.
- **Verificaciones realmente ejecutadas:** Supabase — migración aplicada y verificada en transacción con `ROLLBACK` (submit almacena DUI/teléfono, idempotencia, `PT409` con datos distintos, `PT422` con formatos inválidos, aprobación que copia a `persons`); sin objetos temporales residuales. Locales — `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs` (8 recorridos + 20 pantallas + agendar cita + 2 pruebas nuevas del registro: render/máscaras y envío real a `submit_patient_registration`), `python scripts/check-project.py`, `git diff --check` y suites `test-core`, `test-modules`, `test-profile`, `test-patient-appointments`, `test-patient-chart`, `test-doctor-patients` en verde.
- **Pendientes/límites:** compilación y pruebas Swift en Mac (no se anuncia ninguna compilación); revisión visual en navegador/dispositivo; la confirmación de correo depende de la configuración del proyecto y no se redujo ninguna política para eludirla; DUI/teléfono solo se persisten en el registro (el DUI de agendar cita es decorativo y no se tocó); no hay usuarios demo con `patients.write` para ejercitar la aprobación desde una app. [Informe](REGISTRO_REAL_SUPABASE_2026-10-31.md).

## 2026-10-30 — Mis citas: tarjeta única, ticket 180312 y selector AM/PM

- **Objetivo:** mostrar únicamente Cita asignada al entrar, abrir sus datos en un ticket elegante con Volver y mejorar la preferencia de horario en ambas plataformas.
- **Cambios:** se inspeccionó la captura 180312; entrada única sin buscador ni cola; ticket interno con check vino, título centrado, bloque de fecha/hora, secciones de datos y botón azul; Volver en esquina superior y al pie. Datos/estados/modelos conservados. Solicitar atención sigue en Más; cola local trasladada al formulario. Gestión/cancelación conectada permanece en desplegable del detalle. Preferencia exclusiva AM/PM con tarjetas, iconos, bordes y check, valores Mañana/Tarde intactos.
- **Rutas:** iOS Patient/{PatientAppointmentFlow,PatientAppointmentView,PatientAppointmentComponents}.swift y ContentView.swift; web-preview/{patient-appointments.js,app.js,style.css}; scripts/{test-preview,test-patient-appointments,test-modules}.mjs; README.md; docs/{CITAS_SOLICITUDES_PACIENTE_2026-10-30.md,BITACORA.md}.
- **Verificaciones:** preview/20 pantallas, prueba específica Paciente (entrada única, datos, ambos Volver, AM/PM excluyente, Pendiente/asignación local, datos autorizados y errores), siete recorridos de módulos incluida cancelación; consultas/ticket y dashboard del Doctor aprobados. Sintaxis JS, check-project.py y diff --check aprobados. Recursos actuales HTTP 200/no-store y contenido nuevo servido en el puerto existente 4173. Sin segunda instancia ni cambios de Supabase.
- **Pendientes:** compilación/revisión SwiftUI en Mac, revisión visual web en navegador y persistencia/Recepción real. Pruebas DOM/transporte simulados, no operaciones clínicas reales. [Informe actualizado](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-30 — Salud abre directamente Solicitar atención

- **Objetivo/cambios:** sustituir el menú de Salud del Paciente por el formulario existente, en SwiftUI y web. Se reutilizan health/request/schedule, el store y el estado Pendiente; Salud queda seleccionada y sin buscador. Se conservan autenticación, rutas históricas y recepción local.
- **Rutas:** ContentView.swift; Core/HospitalStore.swift; web-preview/app.js; scripts/test-preview.mjs; README.md; docs/{BITACORA.md,CITAS_SOLICITUDES_PACIENTE_2026-10-30.md}.
- **Verificaciones ejecutadas:** test-preview (20 pantallas y formulario desde Salud), test-patient-appointments (envío Pendiente/asignación de recepción local y datos propios), test-modules (siete flujos, incluida cancelación y atención del Doctor), check-project.py y git diff --check aprobados. DOM/transporte simulado, sin operaciones reales contra Supabase.
- **Pendientes:** compilación Swift en Mac, revisión visual y conexión/persistencia real con Recepción. [Informe actualizado](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).


## 2026-10-30 — Perfil del Paciente e Información general profesional

- **Objetivo:** mostrar nombre, correo y teléfono registrados; mejorar ubicación, orientación, contacto y especialidades con paridad SwiftUI/web y la paleta actual.
- **Cambios:** nuevo perfil con iniciales y card de contacto, faltantes explícitos y ejemplos aislados; Perfil Doctor conservado. Información general con portada, sede de referencia, mapa, Clínica Universitaria y WhatsApp institucional del directorio oficial UNICAES consultado, especialidades publicadas o seis ejemplos identificados, solicitud de atención y avisos/ocupación/habitaciones conservados. Rutas y autenticación intactas, sin dependencias ni cambios de backend.
- **Rutas:** Patient/PatientProfileInformationView.swift (nuevo), ContentView.swift, Shared/screens.json, web-preview/{app.js,style.css}, scripts/test-profile.mjs, README.md, docs/{README.md,BITACORA.md,PERFIL_INFORMACION_GENERAL_2026-10-30.md}.
- **Verificaciones:** test-preview (20 pantallas), test-profile (contactos propios/faltantes/diseño/Doctor, datos y enlaces públicos, especialidades y Salud), check-project.py, sintaxis JS y diff --check aprobados; HTTP 200/no-store en servidor existente. DOM y transporte simulados; sin llamadas reales de teléfono/WhatsApp ni escrituras Supabase.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual web y confirmación de disponibilidad clínica real. Se sustituye la decisión histórica de Perfil Paciente limitado a nombre/apellido. [Informe y fuente oficial](PERFIL_INFORMACION_GENERAL_2026-10-30.md).


## 2026-10-31 — Cronología y detalle de laboratorios del expediente Doctor

- **Objetivo:** exámenes realizados/pendientes visibles en orden, sin filtros en el expediente; detalle elegante dentro de la app con resultados o estado de espera.
- **Cambios:** cards por fecha de solicitud descendente, fecha destacada y estado, detalle tipo ticket por ID/paciente con retorno al expediente/origen, datos completos, valores/unidades/referencias y observaciones publicadas. Pendientes y En Proceso no muestran resultados. Se mantienen notas/recetas, publicación reactiva, filtros independientes de Laboratorio, rutas y acceso conectado. Paleta existente, sin dependencias.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{README.md,BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs y test-preview/20 pantallas aprobados; cronología, tres estados, falta de filtros, resultados, ambos retornos, acciones e aislamiento verificados con DOM/transporte simulado. Sintaxis JS, check-project.py y diff --check aprobados. HTTP 200/no-store del componente actualizado en servidor existente.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual y conexión real de resultados/Recepción al prototipo. Sin escrituras ni cambios de Supabase. [Informe](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Laboratorio Doctor solo solicita; resultados en Expedientes

- **Cambios:** se retiran Ver expediente y Ver solicitudes y resultados de Laboratorio del Doctor en SwiftUI/web; se conserva Solicitar exámenes. En el expediente Ver examen pasa a Ver detalle. Se mantiene publicación local → Completado, resultados exclusivamente para completados y mensajes sin resultados para Pendiente/En Proceso. No se cambia la vista del Paciente.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/clinical-labs.js; scripts/{test-clinical-labs,test-doctor-patients}.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs, test-doctor-patients en diseño/sesión simulada, test-preview/20 pantallas, check-project.py y diff --check aprobados. Sin llamadas clínicas reales ni cambios de Supabase.
- **Pendientes:** compilación en Mac, revisión visual y conexión real del prototipo. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Expedientes sin solicitud de examen y datos personales rediseñados

- **Cambios:** retirada del botón Solicitud de laboratorio de Expedientes Doctor en iOS/web; creación conservada en Laboratorio. Datos personales con iniciales, nombre, cuatro campos de identidad y tres filas de contacto/expediente con iconos. Misma paleta, datos, historial, laboratorios y notas/recetas.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs, test-doctor-patients (diseño/sesión), test-preview/20 pantallas, check-project.py y diff --check aprobados. DOM/transporte simulado; sin cambios de Supabase.
- **Pendientes:** Xcode en Mac y revisión visual. Se sustituye la creación de laboratorios desde Expedientes de decisiones anteriores. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Detalle de examen: paciente primero y resultados destacados

- **Cambios:** SwiftUI/web muestran primero nombre, edad y teléfono únicamente; después información del examen, estado y resultado. Iniciales/nombre destacados, franja de contacto, fecha en bloque y valores/unidades con referencias separadas. Los datos adicionales permanecen en el expediente/modelo. Estados, publicación, retorno y notas/recetas conservados.
- **Rutas:** Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,style.css}; scripts/test-clinical-labs.mjs; README.md; docs/{BITACORA.md,LABORATORIOS_EXPEDIENTE_2026-10-31.md}.
- **Verificaciones:** test-clinical-labs y test-preview/20 pantallas aprobados; orden de tarjetas y ausencia de datos personales adicionales comprobados, además de estados/resultados. Sintaxis JS, check-project.py y diff --check aprobados. DOM/transporte simulado, sin cambios de Supabase.
- **Pendientes:** Xcode en Mac, revisión visual y conexión real del prototipo. [Informe actualizado](LABORATORIOS_EXPEDIENTE_2026-10-31.md).


## 2026-10-31 — Mi expediente y laboratorios propios con estilo del Doctor

- **Cambios:** Mi expediente y laboratorios del Paciente en SwiftUI/web, cards cronológicas, estados, detalle interno con datos mínimos primero y resultados exclusivamente publicados. Lectura sin acciones del Doctor ni selección de personas. Modelo de lectura de laboratorios independiente para conservar secciones/documentos del expediente. Errores, vacíos, actualización, paginación y autorización de documentos conservados; diseño local aislado de las páginas reales.
- **Rutas:** Patient/PatientClinicalView.swift (nuevo); Core/HospitalStore.swift; ContentView.swift; Modules/ClinicalLabDesignView.swift; web-preview/{clinical-labs.js,app.js}; scripts/{test-patient-chart,test-clinical-labs}.mjs; README.md; docs/{README.md,BITACORA.md,MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md}.
- **Verificaciones:** test-patient-chart, test-clinical-labs, test-doctor-patients y test-preview aprobados con DOM/transporte simulado; datos propios, tres estados, cronología y ausencia de resultados pendientes/capacidades del Doctor. Check-project.py, sintaxis JS y diff --check aprobados. Sin pruebas nuevas ni escrituras en Supabase.
- **Pendientes:** compilación SwiftUI en Mac, revisión visual y validación contra publicaciones reales de laboratorio. [Informe](MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md).

- **Coherencia de nombre en este ajuste:** el acceso rápido del Paciente también dice Mi expediente en Patient/PatientDashboardView.swift y web-preview/app.js; Doctor conserva Expedientes.


## 2026-10-31 — Paridad exacta del componente de datos personales por rol

- **Cambios:** se extrae ClinicalPatientIdentityView y HospitalClinicalIdentity para compartir tarjeta entre Doctor/Paciente: cabecera con iniciales/nombre, cuatro campos y tres contactos según captura. Laboratorios del Paciente iguala título/subtítulo, fecha destacada, mensajes de estado, divisor y Ver detalle de las cards del Doctor. Se mantiene el acceso propio y los resultados exclusivamente publicados.
- **Rutas:** Modules/ClinicalPatientIdentityView.swift (nuevo), Modules/ClinicalLabDesignView.swift, Patient/PatientClinicalView.swift, web-preview/{clinical-labs.js,style.css}, scripts/test-patient-chart.mjs, README.md, docs/{BITACORA.md,MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md}.
- **Verificaciones:** comparación de tarjeta Doctor/Paciente para el mismo ejemplo aprobada; cuatro campos y tres contactos en sesión propia; test-patient-chart, test-clinical-labs, test-doctor-patients y test-preview aprobados; check-project.py, sintaxis JS y diff --check. DOM/transporte simulado, sin cambios de Supabase.
- **Pendientes:** revisión visual en navegador y compilación Xcode en Mac. Se conserva el contrato autorizado y no se inventan datos reales ausentes. [Informe](MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md).


## 2026-10-31 — Resolución de conflictos para sincronizar main

- **Objetivo:** completar la fusión pendiente y subir los cambios conservando ambos commits.
- **Cambios:** integración de datos/registro reales con ticket de citas, perfil y expediente/laboratorios remotos; Salud carga la solicitud real; AM/PM coherente en iOS/web; ejemplos aislados; ajustes de perfil conservados. Eliminada referencia Swift obsoleta a useExamples.
- **Rutas:** ContentView.swift, Core/HospitalStore.swift, Patient/{PatientAppointmentFlow,PatientAppointmentView}.swift; web-preview/{app,patient-appointments}.js; scripts/{test-preview,test-profile}.mjs; README.md y docs/{README,BITACORA,FUSION_GIT_2026-10-31}.md.
- **Verificaciones:** doce suites locales aprobadas (preview, core, profile, modules, patient-appointments, patient-chart, clinical-labs, doctor-patients, doctor-consultations, doctor-dashboard, patient-history, patient-prescriptions); check-project.py, sintaxis JS y git diff --check. DOM/transporte simulado, sin operaciones nuevas contra Supabase.
- **Pendientes/límites:** compilación Xcode en Mac y revisión visual. [Informe de resolución](FUSION_GIT_2026-10-31.md).
