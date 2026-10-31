# Rediseño visual de login y nueva pantalla de registro (2026-10-30)

Fecha en la zona del usuario: America/El_Salvador. Informe de la intervención de este día; no sustituye las fuentes originales ni acredita verificaciones pendientes.

## Solicitud

El usuario pidió rediseñar la pantalla de inicio de sesión existente —sin crear una pantalla nueva de login y **sin tocar la lógica de autenticación, validaciones, llamadas a API, sesión, rutas ni estado**— usando `docs/design-reference/` como base visual, y crear la pantalla de registro que no existía, con los campos indicados y el mismo lenguaje visual. Se confirmó además que el trabajo se escribe en Swift/SwiftUI para ejecutarse en Xcode desde Mac, aunque el desarrollo ocurra en Windows.

## Decisiones del usuario antes de implementar

1. **Campos DUI y Edad:** se mantienen los ocho campos solicitados, aunque el diccionario de datos no tenga columna para ellos. Edad se captura como número entero (1–120) y DUI con el formato salvadoreño de 9 dígitos `0000-00000`.
2. **Envío del registro:** la pantalla queda **a nivel de diseño**: valida los formatos en el cliente y muestra un aviso al enviar, pero **no registra en la base de datos** ni llama a Supabase.

## Contraste con el diccionario de datos

Fuente: `docs/Informe_Hospital_Universitario.md` (y su copia histórica en `docs/design-reference/`).

| Campo solicitado | Diccionario | Resultado |
|---|---|---|
| Nombres | `hospital.persons.given_names`, text, obligatorio, 1–100 | Coincide |
| Apellidos | `hospital.persons.family_names`, text, obligatorio, 1–100 | Coincide |
| DUI | Inexistente: búsqueda literal sin resultados en todo el informe | **No existe**; se captura por decisión del usuario |
| Edad | No hay columna; el informe (ambigüedad S04) guarda `persons.birth_date` (date) y calcula la edad | **No coincide**; se captura como número por decisión del usuario |
| Teléfono | `hospital.person_contacts` con `kind='phone'` (text); la app ya usa la RPC `update_my_phone` | Coincide como dato; se reutilizó su expresión regular `^[+]?[0-9() -]{7,25}$` |
| Correo electrónico | Supabase Auth (`auth.users`), fuera del diccionario hospital | Coincide |
| Contraseña y confirmación | Supabase Auth; sin columna en el diccionario | Coincide |

Pendiente de backend (no autorizado en esta solicitud): añadir columnas o mecanismos reales para DUI y edad, y un endpoint de registro si se desea el alta en línea. En el modelo actual, el administrador crea y activa las cuentas; el trigger deja los perfiles nuevos en estado `pending`.

## Cambios implementados (solo capa visual)

### `HospitalUniversitario/HospitalUniversitario/Design/HospitalTheme.swift`

Se añadieron, al final del archivo y sin modificar el contenido existente, los componentes visuales compartidos: `HospitalAuthHeader` (encabezado vino con esquina inferior derecha redondeada, según las capturas), `HospitalInputField` (campo con etiqueta y fondo gris claro), `HospitalSecureField` (campo de contraseña con icono de mostrar/ocultar), `HospitalPrimaryButtonStyle` (botón vino de ancho completo), `HospitalNotice` (franja rosa de avisos) y `HospitalLink` (enlace de texto).

### `HospitalUniversitario/HospitalUniversitario/ContentView.swift`

- Se rediseñó **únicamente la composición** de la propiedad `login`: encabezado vino, tarjeta blanca superpuesta al encabezado, campos con etiqueta, enlace «¿Olvidaste tu contraseña?» debajo del campo de contraseña (muestra una alerta informativa local, sin llamada de red) y enlace de texto «¿No tienes cuenta? Regístrate» —no un botón relleno— que abre el registro.
- Se conservaron **sin cambio** las líneas de lógica: la llamada `let value = password; password = ""` + `Task { await store.signIn(email: email, password: value) }`, la condición `.disabled(store.busy || email…isEmpty || password.isEmpty)`, los estados `email`, `password` y `showPassword`, y los tipos de teclado/autocompletado de los campos.
- Se añadieron dos estados de presentación (`showRegister`, `showRecoveryInfo`) y la rama `if showRegister { RegisterView(onBack:) } else { login }` dentro de `store.access == nil`. No se modificó `HospitalStore`, `HospitalAPI` ni ningún modelo.

### `HospitalUniversitario/HospitalUniversitario/Auth/RegisterView.swift` (archivo nuevo)

Pantalla de registro con los ocho campos en el orden solicitado: nombres, apellidos, DUI, edad, teléfono, correo electrónico, contraseña y confirmar contraseña. Ambos campos de contraseña tienen icono de mostrar/ocultar con etiqueta de accesibilidad. La validación es local y se documentó en la cabecera del archivo:

- Nombres y apellidos: obligatorios, máximo 100 caracteres (límites de `persons`).
- DUI: 9 dígitos con formato automático `0000-00000`.
- Edad: entero de 1 a 120.
- Teléfono: expresión regular existente del proyecto.
- Correo: expresión del diccionario `^[^\s@]+@[^\s@]+\.[^\s@]+$`.
- Contraseña: mínimo 8 caracteres; la confirmación debe coincidir.

Al enviar con todo válido muestra un aviso explícito de que el formulario no envía datos a la base de datos y que el hospital creará y activará la cuenta. No hay importes de red, ni `signUp`, ni escritura alguna.

El archivo nuevo entra en el target automáticamente: el proyecto usa `PBXFileSystemSynchronizedRootGroup`; no fue necesario tocar `project.pbxproj`.

## Qué no se modificó

- `Core/HospitalStore.swift`, `Core/HospitalAPI.swift` y el resto de `Core/`: intactos.
- Lógica de autenticación, sesión, renovación, cierre y rutas del catálogo: intactas.
- Base de datos, RPC, RLS y cuentas de Supabase: sin cambios ni operaciones.
- La vista previa web quedó inicialmente fuera de alcance (solo Swift/SwiftUI); una decisión posterior del usuario la incluyó, como se describe en la sección siguiente, **sin tocar su lógica de autenticación**.

## Réplica en la vista previa web (decisión posterior del usuario)

El usuario ejecuta la app en Windows con `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs` y no veía los cambios Swift, porque ese servidor sirve la réplica web (`web-preview/`: HTML/CSS/JavaScript), que no ejecuta SwiftUI. Pidió replicar allí el mismo diseño.

### `web-preview/app.js`

- Se añadieron los helper `authHeader`, `authField` y `revealButton`, y la variable de presentación `registerOpen` (se limpia en `reset()`).
- `renderLogin()` conserva **idéntico** su manejador de envío (`api.signIn`, `resolve`, `load`), los IDs `email`/`password`, los `autocomplete` y el comportamiento del botón de mostrar/ocultar; solo cambió la composición: encabezado vino, tarjeta superpuesta, enlace «¿Olvidaste tu contraseña?» (mensaje informativo local) y enlace «Regístrate».
- `render()` muestra el registro con `registerOpen ? renderRegister() : renderLogin()`.
- `renderRegister()` construye los ocho campos en el orden solicitado, con formato automático del DUI, iconos de mostrar/ocultar en ambas contraseñas y validación local con los mismos mensajes que iOS; **no llama a la API ni escribe en la base** (aviso explícito al enviar). Las funciones `registerProblem` y el resto de `api.js` quedaron intactas.

### `web-preview/style.css`

Se añadieron al final las reglas `.auth-*` (encabezado, tarjeta superpuesta, campos, avisos rosa, enlaces de texto) reutilizando las variables del tema (`--wine`, `--rose`, `--paper`, `--muted`). Los estilos existentes no se modificaron. Se normalizaron los finales de línea a CRLF, como el resto del repositorio.

## Verificaciones realmente ejecutadas

- `python scripts/check-project.py`: **aprobado** (referencias, recursos explícitos, esquema y 21 pantallas verificadas).
- `git diff --check`: **aprobado**, sin errores de espacio.
- `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`: **8 recorridos DOM aprobados** (login, roles, suspensión, resumen protegido y modo de diseño sin llamadas a Supabase) tras replicar el diseño en la web; confirma que la lógica de login web sigue intacta.
- `node --check web-preview/app.js`: sintaxis **aprobada**.
- Revisión de las 21 imágenes de `docs/design-reference/` (`screen-01.png` y `screen-03.png` vistas directamente) y de `inventory.json` para extraer el lenguaje visual; se confirmó que **ninguna es un login o registro**.
- Búsqueda literal de «dui» sin resultados en el diccionario y lectura de las secciones `persons`, `person_contacts` y `patients`.

**No se ejecutó Xcode ni se compiló Swift**: Windows no dispone del SDK de Apple. La compilación (`⌘R`) y la revisión visual en simulador siguen pendientes en Mac.

## Pendientes

1. Compilar y ejecutar en Mac; verificar login y registro en simulador con distintos tamaños de pantalla y teclados.
2. Decidir si el backend recibirá columnas/mecanismos para DUI y edad, o si el registro pasará a ser real con un endpoint autorizado.
3. Las capturas del login permanecen fuera del ZIP original; la identidad visual se adaptó, como en el avance previo.
