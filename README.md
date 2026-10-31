# Hospital Universitario — avance del sábado 24 de octubre de 2026

El [índice de documentación](docs/README.md) reúne el [contexto completo de esta sesión](docs/SESION_2026-10-23.md) y la [bitácora](docs/BITACORA.md). Las IA que modifiquen el proyecto deben documentar sus cambios según [AGENTS.md](AGENTS.md). El nombre visible vigente es **Hospital Universitario**.

## Modulos funcionales - 28 de octubre

**Decision vigente de autenticacion:** por solicitud expresa, Medico y Paciente acceden con correo y contrasena, sin MFA. Se retiro el desafio en web/iOS y se aplico [mobile-password-access.sql](docs/sql/mobile-password-access.sql) en Supabase. Al reinstalar el backend, ejecutar este SQL despues de los scripts de modulos. Se mantienen sesion vigente, perfil activo, permisos, RLS y vinculos; otros roles conservan sus controles anteriores. Esta decision sustituye las menciones MFA historicas que siguen mas abajo. [Detalle y pruebas](docs/ACCESO_SIN_MFA_2026-10-28.md).

La ampliacion actual conecta los modulos de **Medico y Paciente en iOS y en la vista previa web**. Incluye consultas con diagnostico del catalogo y cierre firmado, ordenes y recetas atomicas, expediente/historial, citas y solicitudes del paciente, resultados publicados, notificaciones, ajustes de perfil y confirmacion de jornadas. Se mantiene el diseno y la estructura existentes. iOS usa **supabase-swift 2.28.0** con la sesion compartida.

**Preparacion obligatoria en Mac:** configurar `HospitalUniversitario/Configuration/Supabase.local.xcconfig` siguiendo la plantilla del mismo directorio y resolver Swift Packages. iOS lee URL/clave publica desde Info.plist/build settings, sin fallback al contrato web. No usar claves administrativas. El archivo local esta ignorado por Git.

Las funciones de [doctor-module.sql](docs/sql/doctor-module.sql) y [mobile-modules.sql](docs/sql/mobile-modules.sql) **ya estan desplegadas en Supabase**. Los flujos se probaron con filas y claims de sesion transitorios dentro de PostgreSQL y se revirtieron; no quedaron ejemplos clinicos instalados. MFA y vinculos siguen siendo obligatorios. Los catalogos reales de medicamentos/estudios estan vacios y deben ser proporcionados por la institucion; no se rellenaron con ejemplos.

La [guia actual de modulos funcionales](docs/MODULOS_FUNCIONALES_2026-10-28.md) detalla archivos, flujos, SQL, pruebas y limites reales. Pasaron 11 pruebas del nucleo y 14 recorridos DOM, ademas de pruebas SQL transaccionales y una comprobacion de receta/layout en navegador con repositorio simulado. **No se compilo Swift en Windows.** Falta validar en Mac y completar un recorrido HTTPS con credenciales reales/MFA; esta copia no contiene las credenciales locales.

**Alcance confirmado: app iOS en SwiftUI y vista previa web local para Windows.** Kotlin y el panel administrativo quedan fuera de esta entrega por indicación del usuario.

El avance original implemento login, navegacion y maquetacion base de 21 pantallas. La solicitud posterior del usuario amplia ese alcance a sus flujos funcionales para Medico y Paciente, sin agregar administracion ni otras plataformas.

## Ejecutar en Windows

Requisito: Node.js 22 o posterior. Desde la raíz del repositorio:

```powershell
node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
```

Abre **http://127.0.0.1:4173/**. Detén el servidor con `Ctrl+C`. Alternativa: entra en `web-preview` y ejecuta `npm run dev`. No se necesita `npm install`, Docker ni una compilación web. Se puede cambiar el puerto con la variable `PORT`.

La vista previa ofrece dos formas de uso:

- **Login real:** consulta Supabase Auth y los permisos del servidor. Requiere una cuenta activa y vinculada al Médico o Paciente correspondiente.
- **Modo de diseño:** botones **Paciente** y **Médico**, junto al iPhone. Permiten recorrer las 21 pantallas con los ejemplos locales del prototipo, sin credenciales y **sin hacer llamadas a Supabase**. El indicador exterior identifica este modo. Los formularios no guardan datos. Para regresar a la autenticación se utiliza **Volver al login real**.

El modo de diseño no concede acceso a datos reales ni existe como un bypass del login de iOS. Se requiere cerrar la sesión real antes de abrirlo. Los ejemplos se encuentran únicamente en `web-preview/design-fixtures.json` y nunca se importan a la base.

La superficie interior del iPhone mide 393 × 852 cuando hay espacio suficiente; incluye barra de estado, navegación inferior, indicador de inicio y contenido desplazable. En ventanas pequeñas se adapta al ancho disponible. Es una aplicación web, no el simulador ni el runtime SwiftUI de Apple.

## Qué funciona con Supabase

Proyecto: **Hospital Universitario**, referencia `kgulityewtcyvjnxeskd`. Se inspeccionaron tablas, funciones, restricciones y RLS reales. Se agregaron las funciones y eventos documentados para movil sin duplicar tablas ni relajar politicas.

| Bloque | Comportamiento |
|---|---|
| Autenticación | Correo/contraseña; validación de perfil activo, rol y vínculo; restauración y renovación de sesión; cierre `scope=local` |
| Roles | `doctor` → Médico; `patient` → Paciente; elección de perfil cuando la cuenta tiene ambos; Inicio como primera pantalla |
| MFA | Desafío/verificación TOTP si la cuenta tiene un autenticador previamente configurado; no muestra datos del portal antes de verificarlo |
| Inicio | Resumen autorizado del Paciente por `my_activity_summary`; jornada propia del Medico por `doctor_workspace`; no inventa contadores si falta autorizacion |
| Citas y solicitudes | Consulta propia, solicitud con preferencias y cancelacion permitida con motivo/version; recepcion conserva la programacion y el check-in |
| Consultas del Medico | Inicio, nota, busqueda de diagnostico, borrador y cierre firmado con versiones |
| Recetas y laboratorio | Emision atomica del Medico; lecturas propias del Paciente y solo resultados publicados |
| Expediente e historial | Lecturas autorizadas, detalle, texto, fechas/horas y cursores |
| Notificaciones y perfil | Buzon propio, marcar leida, preferencias, telefono, emergencia del Paciente y cambio de contrasena |
| Habitaciones | `read_resource('rooms', ...)`, 25 filas por página, búsqueda local y cargar más; muestra código y estado activo |
| Turnos del médico | `staff_shifts`, filtrados por el `staff_id` de la cuenta y la semana local de lunes a lunes; jornadas ordenadas y próxima jornada vigente |
| Turno del paciente | `queue_tickets`, filtrados por el paciente; `my_queue_status` devuelve número visible, personas anteriores, turno atendido y consultorio autorizado |
| Perfil | `my_profile`; nombre, correo y datos propios disponibles |
| Información pública | `hospital_overview`; capacidad/ocupación agregada, médicos de turno y avisos publicados |

El turno de atención se actualiza cada 30 segundos mientras esa pantalla está visible y la app está en primer plano. También se consulta al volver al primer plano. En iOS se puede deslizar hacia abajo para actualizar. No se inventa un tiempo estimado de espera cuando el servidor no lo calcula.

Las pantallas originales que anunciaban una entrega posterior ahora consultan los servicios de los flujos descritos arriba. El modo de diseno sigue siendo de solo lectura y no se importan sus ejemplos como datos reales. Compilacion y pruebas SwiftUI en Mac siguen pendientes.

## Diseño y pantallas

El ZIP aportado contiene 11 pantallas de Paciente y 10 de Médico. Se usaron como referencia visual: encabezado vino `#770727`, fondo `#F8F8FA`, tarjetas blancas, búsqueda superpuesta al encabezado, tipografía y jerarquía, badges y barra inferior por rol.

- Paciente: Inicio, Mis citas, Solicitar atención, Mi turno, Expediente, Historial médico, Mis recetas, Laboratorio, Información pública, Notificaciones y Perfil.
- Médico: Inicio, Mis pacientes, Mis citas, Consultas, Expedientes, Recetas, Laboratorio, Mi horario, Notificaciones y Perfil.

Las rutas **Más** y **Salud** reúnen las pantallas secundarias. Habitaciones es una consulta complementaria en Más, necesaria para demostrar este bloque; no se presenta como una pantalla exportada de Figma. El ZIP no incluye un login iOS, por lo que se adaptó la identidad visual para ese acceso.

El 30 de octubre se rediseñó la capa visual del login (encabezado vino, tarjeta con campos etiquetados, enlace «¿Olvidaste tu contraseña?» y enlace de texto «Regístrate») y se creó la pantalla de registro. El mismo diseño está replicado en la vista previa web (`web-preview/app.js` y `style.css`), visible en `http://127.0.0.1:4173/` al ejecutar el servidor local; la app Swift se ve compilando en Xcode. [Detalle](docs/REDISENO_AUTH_2026-10-30.md).

El 31 de octubre el **registro pasó de ser solo presentación a enviar los datos a la base de datos**. El formulario captura nombres, apellidos, DUI (formato salvadoreño `00000000-0`), fecha de nacimiento, sexo administrativo, teléfono (`0000-0000`), correo, contraseña y confirmar contraseña. El flujo real reutiliza `public.submit_patient_registration`: se crea la cuenta de autenticación con Supabase Auth (`signUp`) y, con el perfil todavía `pending`, se envía la solicitud (con DUI y teléfono) a la base de datos en un solo paso; si el signUp no entrega sesión, se intenta iniciar sesión una vez como respaldo. La confirmación de correo está desactivada en el proyecto (decisión del usuario del 31 de octubre), por lo que no hay paso intermedio: el registro envía la solicitud de inmediato. El hospital la revisa y, al aprobarla, activa la cuenta y la vincula al expediente. Para poder guardar DUI y teléfono se añadieron esas columnas a `hospital.persons` y `hospital.registration_requests` y se ampliaron las RPC de registro (autorizado explícitamente). [Informe](docs/REGISTRO_REAL_SUPABASE_2026-10-31.md).

Ese mismo día se rediseñó el **inicio del Paciente** (dashboard con saludo y avatar, card degradada con fecha de hoy y próxima cita, y accesos rápidos a Mis citas, Laboratorios, Expedientes y Agendar cita) usando la paleta vino/rojo como extensión de `Color` (`Design/HospitalPalette.swift`). El parámetro `nombrePaciente` admite el nombre real cuando exista el modelo de paciente, y `proximaCita` queda listo para conectarse al modelo de citas. El home del Médico y la barra de navegación no cambiaron. Está replicado en la vista previa web. [Detalle](docs/DASHBOARD_PACIENTE_2026-10-30.md).

Las imagenes de `docs/design-reference/` son referencias, no fondos para simular pantallas. Se comprobo el formulario web de recetas en navegador a 1280x900 y 390x844 sin desbordamiento horizontal. No se acredita igualdad pixel a pixel de las 21 pantallas ni una revision visual de SwiftUI.

## Modelos y reglas compartidos

`HospitalUniversitario/HospitalUniversitario/Shared/contract.json` es la fuente única de los campos y tipos de:

- `Room`: UUID, planta, tipo, código, estado activo, fechas y versión.
- `StaffShift`: UUID, personal, departamento, intervalo PostgreSQL `tstzrange`, estado, fechas y versión.
- `QueueTicket`: UUID, cola, paciente, prioridad opcional, número, estado, fechas opcionales de atención y versión.

Los modelos Swift `Codable` se generan y se incluyen ya generados en el repositorio. El navegador valida las filas contra el mismo contrato. Para regenerar:

```powershell
node --preserve-symlinks --preserve-symlinks-main scripts/generate-models.mjs
```

`Shared/hospital-core.js` se ejecuta en el navegador y en iOS mediante **JavaScriptCore**. Contiene la política de roles, filtros de propietario, solicitudes paginadas y lectura de intervalos. `Shared/screens.json` define los mismos nombres, rutas y estructuras de las 21 pantallas para ambas plataformas. El almacenamiento de credenciales, el transporte HTTP y los componentes visuales son nativos de cada plataforma.

Los tipos de respuesta `ActivitySummary`, `QueueStatus`, `UserProfile` y `HospitalOverview` reflejan las RPC inspeccionadas. Las consultas usan las funciones públicas existentes; no exponen directamente los esquemas `hospital` o `private`.

La base mantiene **11 habitaciones y 17 camas**: cinco VIP individuales y seis semiprivadas dobles. `rooms.active` no indica que haya una cama libre. La disponibilidad y las restricciones contra doble asignación siguen en el servidor; este avance no añade un algoritmo de asignación en el cliente.

## Seguridad y cuentas para probar

Se crearon, con autorización del usuario, **dos usuarios Supabase Auth de prueba**, con correo confirmado, perfil activo y rol/vínculo hospitalario correspondiente:

| Rol | Correo de prueba | Vínculo |
|---|---|---|
| Médico | `medico.demo@hospital.test` | Personal activo, Medicina interna, licencia marcada como demostración |
| Paciente | `paciente.demo@hospital.test` | Paciente y registro en Sede Central; expediente `DEMO-EXP-001` |

Las contraseñas vigentes están en **`.local/CREDENCIALES_PRUEBA.md`**, excluido de Git y fuera de la lista de recursos que sirve la web. El 24 de octubre se sustituyeron, por petición del usuario, las contraseñas iniciales por otras más cortas de 9 y 11 caracteres; se verificaron los dos logins y el rechazo de las anteriores. Usa esas credenciales en el **login real**; los botones del modo de diseño no inician sesión. El dominio reservado `.test` no recibe correo. No se concedió el rol de administrador ni se añadieron datos clínicos.

Las dos cuentas se prepararon mediante una semilla administrativa acotada a estas identidades, con hash bcrypt e identidad email en Auth, reutilizando el trigger existente de perfiles. La autenticación, emisión/renovación de JWT y revocación se probaron después con la API real de Supabase Auth. Este aprovisionamiento de demostración no es un formulario de registro ni reemplaza Auth Admin para personas reales.

No se ha inscrito MFA en estas cuentas. El login, los perfiles, las habitaciones y las consultas de turnos autorizadas funcionan con contraseña; los resúmenes protegidos devuelven 403 hasta completar MFA. La revisión automática rechazó inscribir factores y guardar sus secretos sin una autorización adicional expresa. No se redujeron las políticas RLS para eludir esa exigencia. Los turnos siguen vacíos porque no se crearon guardias ni tickets como parte de este pedido.

El administrador debe crear cuentas con correo confirmado y completar sus vínculos. El trigger existente crea `profiles` en estado `pending`: crear un usuario Auth por sí solo no activa su acceso.

- Médico: perfil activo, persona vinculada a personal activo, asignación vigente del rol `doctor` en una sede. La función administrativa existente `activate_staff_account` exige licencia, especialidad, asignación vigente y versión del perfil.
- Paciente: perfil activo, rol `patient` y vínculo verificado en `patient_accounts`, correspondientes a la misma persona.
- Si se necesita MFA, debe configurarse el autenticador de la cuenta. Este avance permite **verificar un TOTP ya inscrito**; no incluye alta/eliminación de factores ni MFA por SMS. Si existe otro factor obligatorio, se deniega la entrada con un aviso.
- El primer administrador y la activación se preparan mediante los procedimientos administrativos existentes. No se incluyen contraseñas, credenciales administrativas ni autoasignación de roles en los clientes.

La autorización final sigue en las funciones y políticas RLS del servidor. `my_access` se consulta antes de mostrar el portal y de cargar sus datos. La base comprueba la sesión y las asignaciones vigentes. El cliente no confía en roles elegidos libremente ni en `user_metadata`.

La app no guarda la contrasena. El archivo local de aprovisionamiento conserva las de las dos cuentas de prueba. En iOS, supabase-swift persiste la sesion en **Keychain** y renueva sus tokens; en web el acceso vive en memoria y la renovacion en **sessionStorage**. Si falla el cierre remoto, se descarta la sesion local y se muestra un aviso. El contrato conserva URL/clave publica para la web; iOS usa su configuracion local de compilacion. Nunca incluir `service_role`.

El servidor de vista previa escucha exclusivamente en `127.0.0.1`, sirve una lista explícita de recursos y aplica CSP y `no-store`. `localhost` y `127.0.0.1` tienen almacenamiento distinto en el navegador.

## Abrir y comprobar en Mac

1. Copia el repositorio completo y abre `HospitalUniversitario/HospitalUniversitario.xcodeproj` en **Xcode 16.2 o posterior**, con un simulador iOS 18.2 o posterior instalado.
2. Selecciona el esquema compartido **HospitalUniversitario** y un simulador iPhone. Para simulador no hace falta elegir un equipo de firma. Para dispositivo físico, configura tu equipo en Signing & Capabilities.
3. Configura el xcconfig local y resuelve el paquete Supabase segun la guia del Doctor; despues ejecuta `⌘R`. Los Swift pertenecen al grupo sincronizado del target y los tres recursos compartidos tienen pertenencia explicita a Copy Bundle Resources.
4. Ejecuta `⌘U`. Ademas de las cinco pruebas originales y cinco del Doctor, se agregaron dos de contratos moviles (decimales, nulos y cursor). Las pruebas Swift no se han ejecutado en Windows.
5. Con cuentas preparadas, verifica ambos roles, TOTP, doble perfil, cuenta pendiente/suspendida, contraseña errónea, cierre/reapertura, habitaciones, turnos vacíos y pérdida de conexión.

Comprobación opcional por terminal:

```bash
xcodebuild -list -project HospitalUniversitario/HospitalUniversitario.xcodeproj
xcodebuild -project HospitalUniversitario/HospitalUniversitario.xcodeproj -scheme HospitalUniversitario -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

**Dependencias SPM:** supabase-swift, version exacta 2.28.0, producto Supabase, requiere resolver paquetes en Mac y conservar el lockfile generado. Autenticacion/sesion/MFA y RPC del Doctor utilizan el SDK; las lecturas anteriores conservan su transporte REST con el token de la misma sesion. SwiftUI, Foundation, Security/Keychain y JavaScriptCore siguen siendo frameworks del SDK de Apple. No es necesario ejecutar Node desde Xcode.

## Archivos y pertenencia a targets

| Ruta desde la raíz | Target / finalidad |
|---|---|
| `HospitalUniversitario/HospitalUniversitario/ContentView.swift` | `HospitalUniversitario`: login rediseñado, TOTP, selección de rol, navegación y vistas |
| `HospitalUniversitario/HospitalUniversitario/Auth/RegisterView.swift` | `HospitalUniversitario`: pantalla de registro conectada (crea la cuenta, envía la solicitud con DUI/teléfono a la base) |
| `HospitalUniversitario/HospitalUniversitario/Patient/PatientDashboardView.swift` | `HospitalUniversitario`: dashboard del Paciente, modelo `ProximaCita` y `#Preview` |
| `HospitalUniversitario/HospitalUniversitario/Patient/PatientDashboardComponents.swift` | `HospitalUniversitario`: cards reutilizables del dashboard (saludo, fecha/cita, accesos) |
| `HospitalUniversitario/HospitalUniversitario/Design/HospitalPalette.swift` | `HospitalUniversitario`: extensión `Color` con la paleta vino y rojo |
| `HospitalUniversitario/HospitalUniversitario/Design/HospitalTheme.swift` | `HospitalUniversitario`: colores, tarjetas, badges y componentes de autenticación |
| `HospitalUniversitario/HospitalUniversitario/Core/HospitalAPI.swift` | `HospitalUniversitario`: Auth REST, Keychain, MFA y servicios RPC |
| `HospitalUniversitario/HospitalUniversitario/Core/HospitalStore.swift` | `HospitalUniversitario`: estado MVVM y carga de datos |
| `HospitalUniversitario/HospitalUniversitario/Core/SharedCore.swift` | `HospitalUniversitario`: puente JavaScriptCore y fechas |
| `HospitalUniversitario/HospitalUniversitario/Core/ScreenCatalog.swift` | `HospitalUniversitario`: catálogo de pantallas y modelos de respuesta RPC |
| `HospitalUniversitario/HospitalUniversitario/Core/Models.generated.swift` | `HospitalUniversitario`: modelos `Codable` de tablas |
| `HospitalUniversitario/HospitalUniversitario/Shared/contract.json` | Recurso explícito de `HospitalUniversitario`; contrato de modelos/configuración |
| `HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js` | Recurso explícito de `HospitalUniversitario`; núcleo compartido |
| `HospitalUniversitario/HospitalUniversitario/Shared/screens.json` | Recurso explícito de `HospitalUniversitario`; catálogo compartido |
| `HospitalUniversitario/HospitalUniversitarioTests/HospitalUniversitarioTests.swift` | `HospitalUniversitarioTests`; no pertenece al target de la app |
| `HospitalUniversitario/HospitalUniversitario.xcodeproj/project.pbxproj` | Configuración iOS/iOS Simulator, rutas relativas y recursos sin duplicación automática |
| `HospitalUniversitario/HospitalUniversitario.xcodeproj/xcshareddata/xcschemes/HospitalUniversitario.xcscheme` | Esquema compartido |
| `web-preview/` | Servidor, presentación web, adaptador Auth y ejemplos; ningún target Xcode |
| `scripts/` | Generación y comprobaciones; ningún target Xcode |

Los targets se limitan a iPhone/iPad con deployment iOS 18.2. Se retiró del target la referencia a los entitlements de sandbox de macOS; el archivo original permanece intacto. `DEVELOPMENT_ASSET_PATHS` apunta a la carpeta existente `HospitalUniversitario/Preview Content`. No se añadieron rutas absolutas a fuentes o recursos.

## Validaciones realizadas

```powershell
node --preserve-symlinks --preserve-symlinks-main scripts/generate-models.mjs --check
node --preserve-symlinks --preserve-symlinks-main scripts/test-core.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs
python scripts/check-project.py
node --preserve-symlinks --preserve-symlinks-main scripts/check-backend.mjs
```

- **11 pruebas del núcleo/adaptador:** roles permitidos/denegados, vínculos, intervalos, filtros, cursores, credenciales, renovación concurrente, validación de modelos y cierre sin conexión.
- **8 recorridos DOM con transporte de prueba:** Médico, Paciente, doble rol, MFA válido/inválido, suspensión, resumen protegido, navegación de todas las pantallas y modo de diseño sin llamadas a Supabase.
- **Proyecto:** IDs y referencias, recursos explícitos, rutas existentes, esquema XML y correspondencia de las 21 capturas con el catálogo.
- **Servidor local:** HTTP 200 en la página y los siete recursos requeridos.
- **Supabase real por HTTPS sin sesión:** `public_facilities` responde 200; `my_access`, `read_resource`, `my_profile`, `my_queue_status` y `my_activity_summary` responden 401.
- **Supabase real con las dos cuentas de prueba:** contraseña incorrecta rechazada; login y rol correctos; perfil propio; 11 habitaciones; turnos autorizados vacíos; renovación del token; cierre y rechazo de un JWT cuya sesión ya fue revocada. Informe sin secretos: `docs/login-verification.json`. Los resúmenes confirman que requieren MFA.

Para repetir la prueba de login real, que abre y cierra sesiones de las dos cuentas:

```powershell
node --preserve-symlinks --preserve-symlinks-main scripts/test-real-login.mjs
```

El comando anterior no inscribe MFA. La opción `--enroll-totp` está reservada para una autorización adicional expresa y no se ha ejecutado. `scripts/prepare-test-accounts.mjs` solo preparó los archivos locales de la semilla; no debe usarse para sobrescribir identidades existentes.

**Limites vigentes:** Windows no dispone del SDK de Apple: no se ejecuto xcodebuild ni las pruebas Swift. La comprobacion reciente en navegador uso un repositorio de prueba; las verificaciones HTTPS nuevas fueron sin sesion y las pruebas clinicas SQL usaron claims simulados con rollback. Las pruebas Auth reales descritas en el informe historico pertenecen a la sesion anterior, no a esta ampliacion. El recorrido con credenciales/MFA reales y la validacion nativa siguen pendientes.

La consulta más reciente del asesor de seguridad informa que la protección de contraseñas filtradas está deshabilitada; no se cambió esa configuración. [Configuración de protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). También persisten seis avisos INFO por RLS sin políticas en tablas de recuperación `hospital_recovery_3fn`, que no se modificaron. [Explicación del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Las fuentes y decisiones de alcance se conservan en [Contexto iOS](docs/CONTEXTO_IOS.md). El informe anterior es evidencia histórica del backend; sus pruebas no se anuncian como pruebas de esta app.

## Agendar cita: actualización del 30 de octubre

En Inicio del paciente, Accesos rápidos → **Paciente** abre Agendar cita. Datos editables de prueba, síntomas, motivo, especialidades, horarios y resumen equivalentes en SwiftUI y web. El botón prepara localmente; no reserva en Supabase. [Detalles y validaciones](docs/AGENDAR_CITA_2026-10-30.md).

Para ver el formulario sin credenciales, inicia el servidor local, abre `http://127.0.0.1:4173/`, selecciona **Diseño Paciente** y pulsa **Paciente** en Accesos rápidos. «Preparar cita de prueba» valida el formulario y muestra una simulación local. Las solicitudes reales existentes conservan su flujo separado.


## Dashboard del doctor (30 de octubre)

Inicio del doctor comparte las cards y paleta del panel de paciente: saludo con nombre completo, fecha actual, consultas programadas para hoy, accesos a Pacientes/Consultas/Laboratorios/Expedientes, historial propio por paciente y fechas y resumen de jornadas laborales. Se conserva el destino Mi horario para el detalle completo. La sesión real reutiliza `doctor_workspace`, `doctor_chart` y `staff_shifts`, sin cambios de autorización.

Para verlo con datos precargados, inicia la vista previa y pulsa **Médico** en los controles de diseño. SwiftUI ofrece el Preview **Doctor · datos locales** en `Doctor/DoctorDashboardView.swift`. Ambos usan los mismos ejemplos ficticios; no se envían al hospital ni reemplazan datos reales. El selector del historial ofrece pacientes de la agenda de hoy; otras fechas se consultan desde Pacientes. [Archivos, conexión de datos y límites](docs/DASHBOARD_DOCTOR_2026-10-30.md).

Prueba específica: `node --preserve-symlinks --preserve-symlinks-main scripts/test-doctor-dashboard.mjs`. Las pruebas con transporte simulado no sustituyen la compilación y revisión de SwiftUI en Mac.


**Corrección de navegación (2026-10-30):** el dashboard del doctor muestra bienvenida, fecha, conteo y accesos. El historial clínico por paciente y fechas está en **Pacientes**; el horario laboral se consulta en **Más → Mi horario**, sin resumen ni carga de jornadas en Inicio. La vista SwiftUI del historial es `Doctor/DoctorPatientHistoryView.swift`; la web usa `renderHistory` del componente del doctor. Esta ubicación sustituye la distribución anterior.


**Navegación Doctor actualizada (2026-10-30):** Inicio / Pacientes / Consultas / Más. Se retiró **Mis citas** exclusivamente del Doctor, incluido su acceso en Más; Paciente lo conserva. Las citas asignadas siguen disponibles como datos de agenda en los módulos clínicos. El catálogo actual contiene 20 pantallas; las 21 capturas de referencia se conservan como material histórico.


**Consultas Doctor (2026-10-30):** agenda visual con fecha actual, calendario y accesos Hoy/Mañana/En 7 días. El modo diseño y la sesión sin citas muestran una agenda local claramente identificada como ejemplo; nunca permite iniciar/guardar atenciones ficticias. Las citas reales conservan el formulario clínico. Ver [implementación y pruebas](docs/CONSULTAS_DOCTOR_2026-10-30.md). Prueba: `node --preserve-symlinks --preserve-symlinks-main scripts/test-doctor-consultations.mjs`.


**Ticket de Consultas Doctor (2026-10-30):** las tarjetas incluyen paciente, edad, teléfono, hora, motivo y síntomas. **Ver detalle** abre una hoja iOS o panel web dentro de la consulta seleccionada; el ticket conserva el estado real y muestra **No hay datos reales** en campos ausentes. **Abrir atención** conserva el flujo clínico solo para citas reales. [Archivos y origen de cada campo](docs/TICKET_CONSULTA_DOCTOR_2026-10-30.md).


## Expediente y Laboratorios: diseño por rol (30 de octubre)

Doctor puede buscar por DUI/nombre, abrir el expediente y pulsar **Solicitud de laboratorio**. El formulario local valida los datos obligatorios y agrega la solicitud como **Pendiente** a ese expediente. La sección integrada permite filtrar por fecha, tipo de examen y paciente seleccionado; ambos roles consultan detalle y estado. Paciente solo ve su ficha y resultados, sin creación. Estados de diseño: Pendiente / En Proceso / Completado.

En la web usa los controles de diseño **Médico → Expedientes**. En SwiftUI activa **Vista de diseño · datos locales** dentro de Expedientes/Laboratorio, o abre sus previews. Los flujos reales previos se conservan. La demostración no envía solicitudes ni persiste en Supabase.

La navegación actual del Doctor es **Inicio / Pacientes / Consultas / Laboratorios / Más**; sustituye la distribución anterior de cuatro destinos y mantiene Mis citas solo en Paciente. [Archivos, navegación, modelos y futura conexión](docs/LABORATORIOS_EXPEDIENTE_2026-10-30.md). Prueba: `node --preserve-symlinks --preserve-symlinks-main scripts/test-clinical-labs.mjs`.


**Corrección de visibilidad (2026-10-30):** al iniciar sesión como Doctor y abrir **Laboratorios** o **Expedientes**, el rediseño local se muestra por defecto, sin activar el modo diseño externo. Laboratorios incluye la búsqueda de expediente. El aviso aclara que los datos son ficticios; **Ver flujo conectado** conserva el acceso al módulo real. En SwiftUI el interruptor de diseño se activa inicialmente para Doctor. Paciente en sesión conserva sus datos reales.


**Actualización de Laboratorio (2026-10-30):** se puede buscar al paciente y pulsar **Solicitar exámenes** desde Laboratorio, sin abrir Expedientes. El modal captura examen, motivo, peso y altura; toma fecha y doctor automáticamente y crea una solicitud local Pendiente. Expedientes abre una ficha modal separada con datos disponibles, mediciones, notas, recetas locales y laboratorios/resultados compartidos. Sustituye la restricción anterior de iniciar solicitudes solo desde la ficha.

Los resultados estructurados tienen valor, unidad, referencia y observación. El adaptador local de resultados está probado; **la recepción/publicación real y la persistencia de este prototipo todavía necesitan conexión a Supabase**. Las recetas locales no se emiten clínicamente; el módulo conectado existente se conserva. [Detalles, archivos y verificaciones](docs/LABORATORIO_INDEPENDIENTE_2026-10-30.md).


**Ajuste visual de Laboratorio (2026-10-30):** solicitud y expediente se abren ahora como **tickets dentro de la aplicación**, sin dialog externo ni sheet. Buscar/seleccionar paciente no muestra formularios ni filtros. **Solicitar exámenes** abre el ticket con todos los campos; **Ver solicitudes y resultados** abre el panel de filtros y lista por separado. **Volver** conserva el paciente seleccionado. El estado local y las operaciones conectadas previas se mantienen.


**Pacientes Doctor (2026-10-30):** diseño con fecha de atención, DUI o nombre, tarjetas de coincidencias y ficha interna con historial propio, datos disponibles y seguimiento compartido con Expedientes/Laboratorios. En la web se muestra directamente en **Doctor → Pacientes**; los ejemplos locales siguen identificados y el flujo conectado se conserva. [Archivos y verificaciones](docs/PACIENTES_DOCTOR_2026-10-30.md). Prueba específica: `node --preserve-symlinks --preserve-symlinks-main scripts/test-doctor-patients.mjs`.


**Perfil (2026-10-30):** para ambos roles se muestra únicamente Nombre y Apellido, de solo lectura y tomados de `my_profile.person`; sin datos inventados ni formularios de ajustes. Si faltan, aparece No disponible. Cerrar sesión sigue en Más. Prueba: `node --preserve-symlinks --preserve-symlinks-main scripts/test-profile.mjs`.


**Expediente Paciente (2026-10-30):** abre directamente el ticket interno con el mismo estilo del Doctor, usando únicamente la información autorizada de su cuenta. Sin selección de personas ni edición. Faltantes explícitos y documentos publicados conservados. Los ejemplos están separados en modo diseño. [Archivos y pruebas](docs/EXPEDIENTE_PACIENTE_2026-10-30.md).


**Historial médico Paciente (2026-10-30):** tarjetas cronológicas según la captura 215451, con fecha/hora, especialidad, médico, motivo y acento verde de la paleta. Pulsar una tarjeta abre el detalle dentro de la app. Tres ejemplos solicitados, identificados y reemplazables por el historial autorizado existente; no se mezclan con datos reales ni se importan a Supabase. Acceso **Más → Historial médico**. [Archivos y verificaciones](docs/HISTORIAL_PACIENTE_2026-10-30.md).


**Recetas Paciente (2026-10-30):** Accesos rápidos muestra **Recetas** en lugar de Paciente. Tarjetas por medicamento según receta.png, ordenadas de más reciente a más antigua, con Pendiente/Retirada cuando la fuente informa retiro. Los ejemplos están identificados; el estado real sin datos de entrega aparece como Retiro por confirmar. **Agendar cita** se conserva en Mis citas. [Archivos y verificaciones](docs/RECETAS_PACIENTE_2026-10-30.md).


**Receta Doctor (2026-10-30):** tanto Añadir receta del expediente local como el formulario conectado incluyen medicamento, dosis/unidad, frecuencia, vía, duración, cantidad y observaciones, con vista previa completa. La duración utiliza las fechas existentes de la receta; no modifica el contrato ni la entrega de farmacia. [Implementación y pruebas](docs/CAMPOS_RECETA_DOCTOR_2026-10-30.md).


**Citas y solicitudes Paciente (2026-10-30):** Mis citas incorpora próxima cita y ticket con el mismo estilo del Doctor. Se unifican los dos formularios: el formulario de agendar ahora se envía con **Solicitar atención**, exige preferencia Mañana/Tarde y guarda una solicitud local **Pendiente**. **Recepción (demo)** en la vista previa permite asignar fecha/hora a ejemplos y comprobar el cambio a Cita asignada; en SwiftUI se incluye su componente y Preview. Los ejemplos son temporales y no se envían a Supabase. Se conservan citas y cancelación conectadas. Esta actualización sustituye la indicación anterior de conservar un acceso separado Agendar cita. [Archivos, datos y verificaciones](docs/CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).

Para verlo: abre `http://127.0.0.1:4173`, recarga con Ctrl+F5 y usa **Paciente → Mis citas → Solicitar atención** en modo diseño. El servidor existente utiliza `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs`; si está abierto no inicies otra instancia en el mismo puerto.


## Conexión completa y datos de ejemplo en Supabase (31 de octubre)

Las vistas de Doctor y Paciente (iOS y web) quedaron conectadas a los módulos reales sin ejemplos locales en modo sesión: **Solicitar atención** usa las especialidades del catálogo, «Fecha preferida» y preferencia Mañana/Tarde, y envía `request_appointment` con idempotencia; el inicio del Paciente muestra su próxima cita real; **Mis citas**, recetas, historial y la consulta del Doctor ya no cargan ejemplos de sustitución; el perfil se renderiza con el módulo real. Los síntomas se añaden al motivo porque la RPC no los admite.

La base de datos contiene ahora datos de demostración clínicos ficticios ligados a las cuentas demo existentes («Médico DE PRUEBA» / «Paciente de prueba»): tres citas (una pasada, la próxima confirmada y una futura), un encuentro cerrado con nota clínica firmada y diagnóstico, una receta emitida con dos medicamentos, una orden de laboratorio con dos resultados liberados, perfil clínico (alergia, condición resuelta, antecedente, contactos de emergencia), vínculo de cuidado médico–paciente, catálogos, consultorios, jornada del médico, cola del día y un aviso público. No se crearon cuentas ni se modificó esquema, RPC o políticas.

Verificación ejecutada contra Supabase con claims simulados en transacciones revertidas (`docs/sql/test-mobile-flows.sql`): módulos completos del Paciente (citas, solicitud, expediente, historial, recetas, laboratorio, notificaciones y perfil), idempotencia de `request_appointment`, módulos del Doctor (recetas y perfil) y rechazo de suplantación de rol y de cuentas sin vínculo. Nota: el Doctor solo ve recetas de pacientes con un `care_assignments` vigente; ese vínculo está incluido en la siembra. Localmente se aprobaron `scripts/test-preview.mjs`, `python scripts/check-project.py` y `git diff --check`. La compilación Swift en Mac y el login real con credenciales siguen pendientes. [Detalle](docs/CONECTAR_SUPABASE_DATOS_DEMO_2026-10-31.md).
