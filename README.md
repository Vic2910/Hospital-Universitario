# Hospital Universitario — avance del sábado 24 de octubre de 2026

El [índice de documentación](docs/README.md) reúne el [contexto completo de esta sesión](docs/SESION_2026-10-23.md) y la [bitácora](docs/BITACORA.md). Las IA que modifiquen el proyecto deben documentar sus cambios según [AGENTS.md](AGENTS.md). El nombre visible vigente es **Hospital Universitario**.

**Alcance confirmado: app iOS en SwiftUI y vista previa web local para Windows.** Kotlin y el panel administrativo quedan fuera de esta entrega por indicación del usuario.

Se implementaron el login por roles, la navegación y maquetación base de las 21 pantallas iOS exportadas, y los modelos/servicios de habitaciones y turnos sobre el esquema existente de Supabase. Los formularios clínicos están maquetados, con las operaciones de guardado deshabilitadas para mantener el alcance del avance.

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

Proyecto: **Hospital Universitario**, referencia `kgulityewtcyvjnxeskd`. Se inspeccionaron las tablas y funciones reales antes de implementar los modelos. No se crearon tablas duplicadas ni se ejecutaron nuevas migraciones.

| Bloque | Comportamiento |
|---|---|
| Autenticación | Correo/contraseña; validación de perfil activo, rol y vínculo; restauración y renovación de sesión; cierre `scope=local` |
| Roles | `doctor` → Médico; `patient` → Paciente; elección de perfil cuando la cuenta tiene ambos; Inicio como primera pantalla |
| MFA | Desafío/verificación TOTP si la cuenta tiene un autenticador previamente configurado; no muestra datos del portal antes de verificarlo |
| Inicio | Perfil real y métricas autorizadas por `my_activity_summary`; muestra `—` cuando el resumen requiere una autorización adicional |
| Habitaciones | `read_resource('rooms', ...)`, 25 filas por página, búsqueda local y cargar más; muestra código y estado activo |
| Turnos del médico | `staff_shifts`, filtrados por el `staff_id` de la cuenta y la semana local de lunes a lunes; jornadas ordenadas y próxima jornada vigente |
| Turno del paciente | `queue_tickets`, filtrados por el paciente; `my_queue_status` devuelve número visible, personas anteriores, turno atendido y consultorio autorizado |
| Perfil | `my_profile`; nombre, correo y datos propios disponibles |
| Información pública | `hospital_overview`; capacidad/ocupación agregada, médicos de turno y avisos publicados |

El turno de atención se actualiza cada 30 segundos mientras esa pantalla está visible y la app está en primer plano. También se consulta al volver al primer plano. En iOS se puede deslizar hacia abajo para actualizar. No se inventa un tiempo estimado de espera cuando el servidor no lo calcula.

Las otras pantallas corresponden a **maquetación y navegación base**: citas, pacientes, solicitud de atención, consultas, expediente, historial, recetas, laboratorio y notificaciones. La app real no presenta los ejemplos del prototipo como datos reales. Las operaciones clínicas, altas, reservas y edición quedan para avances posteriores.

## Diseño y pantallas

El ZIP aportado contiene 11 pantallas de Paciente y 10 de Médico. Se usaron como referencia visual: encabezado vino `#770727`, fondo `#F8F8FA`, tarjetas blancas, búsqueda superpuesta al encabezado, tipografía y jerarquía, badges y barra inferior por rol.

- Paciente: Inicio, Mis citas, Solicitar atención, Mi turno, Expediente, Historial médico, Mis recetas, Laboratorio, Información pública, Notificaciones y Perfil.
- Médico: Inicio, Mis pacientes, Mis citas, Consultas, Expedientes, Recetas, Laboratorio, Mi horario, Notificaciones y Perfil.

Las rutas **Más** y **Salud** reúnen las pantallas secundarias. Habitaciones es una consulta complementaria en Más, necesaria para demostrar este bloque; no se presenta como una pantalla exportada de Figma. El ZIP no incluye un login iOS, por lo que se adaptó la identidad visual para ese acceso.

Las imágenes de `docs/design-reference/` son referencias de trabajo: **no se utilizan como fondos para simular pantallas**. No se ha acreditado igualdad píxel a píxel: las capturas no incluyen fuentes, componentes o recursos originales, y este entorno no ofrece un navegador conectado para validación visual.

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

Las contraseñas aleatorias están en **`.local/CREDENCIALES_PRUEBA.md`**, excluido de Git y fuera de la lista de recursos que sirve la web. Usa esas credenciales en el **login real**; los botones del modo de diseño no inician sesión. El dominio reservado `.test` no recibe correo. No se concedió el rol de administrador ni se añadieron datos clínicos.

Las dos cuentas se prepararon mediante una semilla administrativa acotada a estas identidades, con hash bcrypt e identidad email en Auth, reutilizando el trigger existente de perfiles. La autenticación, emisión/renovación de JWT y revocación se probaron después con la API real de Supabase Auth. Este aprovisionamiento de demostración no es un formulario de registro ni reemplaza Auth Admin para personas reales.

No se ha inscrito MFA en estas cuentas. El login, los perfiles, las habitaciones y las consultas de turnos autorizadas funcionan con contraseña; los resúmenes protegidos devuelven 403 hasta completar MFA. La revisión automática rechazó inscribir factores y guardar sus secretos sin una autorización adicional expresa. No se redujeron las políticas RLS para eludir esa exigencia. Los turnos siguen vacíos porque no se crearon guardias ni tickets como parte de este pedido.

El administrador debe crear cuentas con correo confirmado y completar sus vínculos. El trigger existente crea `profiles` en estado `pending`: crear un usuario Auth por sí solo no activa su acceso.

- Médico: perfil activo, persona vinculada a personal activo, asignación vigente del rol `doctor` en una sede. La función administrativa existente `activate_staff_account` exige licencia, especialidad, asignación vigente y versión del perfil.
- Paciente: perfil activo, rol `patient` y vínculo verificado en `patient_accounts`, correspondientes a la misma persona.
- Si se necesita MFA, debe configurarse el autenticador de la cuenta. Este avance permite **verificar un TOTP ya inscrito**; no incluye alta/eliminación de factores ni MFA por SMS. Si existe otro factor obligatorio, se deniega la entrada con un aviso.
- El primer administrador y la activación se preparan mediante los procedimientos administrativos existentes. No se incluyen contraseñas, credenciales administrativas ni autoasignación de roles en los clientes.

La autorización final sigue en las funciones y políticas RLS del servidor. `my_access` se consulta antes de mostrar el portal y de cargar sus datos. La base comprueba la sesión y las asignaciones vigentes. El cliente no confía en roles elegidos libremente ni en `user_metadata`.

La app no guarda la contraseña. El archivo local de aprovisionamiento sí conserva las contraseñas de estas dos cuentas de prueba, para que el usuario pueda utilizarlas. El token de acceso vive en memoria; el de renovación se guarda en **Keychain** en iOS y **sessionStorage** en el navegador. Si falla el cierre remoto, se descarta la sesión local y se muestra un aviso. El contrato solo contiene URL y clave pública publicable; nunca `service_role`.

El servidor de vista previa escucha exclusivamente en `127.0.0.1`, sirve una lista explícita de recursos y aplica CSP y `no-store`. `localhost` y `127.0.0.1` tienen almacenamiento distinto en el navegador.

## Abrir y comprobar en Mac

1. Copia el repositorio completo y abre `HospitalUniversitario/HospitalUniversitario.xcodeproj` en **Xcode 16.2 o posterior**, con un simulador iOS 18.2 o posterior instalado.
2. Selecciona el esquema compartido **HospitalUniversitario** y un simulador iPhone. Para simulador no hace falta elegir un equipo de firma. Para dispositivo físico, configura tu equipo en Signing & Capabilities.
3. Ejecuta `⌘R`. No necesitas copiar archivos manualmente ni instalar paquetes: los Swift pertenecen al grupo sincronizado del target y los tres recursos compartidos tienen pertenencia explícita a Copy Bundle Resources.
4. Ejecuta `⌘U`. Las cinco pruebas del target `HospitalUniversitarioTests` comprueban recursos en el bundle, roles, filtros de propietario, campos nulos y respuestas de turno.
5. Con cuentas preparadas, verifica ambos roles, TOTP, doble perfil, cuenta pendiente/suspendida, contraseña errónea, cierre/reapertura, habitaciones, turnos vacíos y pérdida de conexión.

Comprobación opcional por terminal:

```bash
xcodebuild -list -project HospitalUniversitario/HospitalUniversitario.xcodeproj
xcodebuild -project HospitalUniversitario/HospitalUniversitario.xcodeproj -scheme HospitalUniversitario -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

**Dependencias SPM:** ninguna. SwiftUI, Foundation/URLSession, Security/Keychain y JavaScriptCore vienen en el SDK de Apple. La app usa las [API REST de Supabase Auth](https://supabase.com/docs/reference/self-hosting-auth) y [RPC Postgres](https://supabase.com/docs/guides/database/functions). No es necesario resolver paquetes ni ejecutar Node desde Xcode.

## Archivos y pertenencia a targets

| Ruta desde la raíz | Target / finalidad |
|---|---|
| `HospitalUniversitario/HospitalUniversitario/ContentView.swift` | `HospitalUniversitario`: login, TOTP, selección de rol, navegación y vistas |
| `HospitalUniversitario/HospitalUniversitario/Design/HospitalTheme.swift` | `HospitalUniversitario`: colores, tarjetas y badges |
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

**Límites de verificación:** Windows no dispone del SDK de Apple: no se ejecutó `xcodebuild` ni las pruebas Swift. No hay navegador conectado para automatización visual; las pruebas DOM no sustituyen una captura real. La prueba real de Auth/HTTP ya pasó para ambos roles; la inscripción TOTP y los resúmenes con `aal2` permanecen pendientes.

La consulta más reciente del asesor de seguridad informa que la protección de contraseñas filtradas está deshabilitada; no se cambió esa configuración. [Configuración de protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). También persisten seis avisos INFO por RLS sin políticas en tablas de recuperación `hospital_recovery_3fn`, que no se modificaron. [Explicación del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Las fuentes y decisiones de alcance se conservan en [Contexto iOS](docs/CONTEXTO_IOS.md). El informe anterior es evidencia histórica del backend; sus pruebas no se anuncian como pruebas de esta app.


### Solicitud de citas del paciente (rama `feature/paciente-agendar-cita`)

La pantalla **Solicitar atención** permite elegir especialidad, consultar el directorio médico de esa especialidad, indicar fecha y franja preferidas y describir el motivo. Envía una **solicitud pendiente**, no una reserva confirmada, mediante la RPC `request_appointment` del proyecto Supabase; usa el paciente y la sede obtenidos de la sesión, con idempotencia de envío. La ficha de identidad proviene del perfil y no se edita durante la solicitud. No existe aún un endpoint de horarios disponibles por médico ni se ofrece selección de un cupo confirmado. La ejecución y compilación en Xcode aún deben verificarse en Mac.
