# Bitácora de trabajo

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
