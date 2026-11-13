# Hospital Universitario

App iOS/SwiftUI y vista previa web para Windows, conectadas exclusivamente a **Hospital Móviles** (`uvebpsbbwofthucghccc`). El nombre visible de la app sigue siendo Hospital Universitario.

## Ejecutar en Windows

Node.js 22 o posterior, sin instalar dependencias:

```powershell
node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
```

Abre http://127.0.0.1:4173/. Reinicia cualquier servidor que estuviera abierto antes del cambio de conexión y recarga la página para tomar la nueva política de conexión.

El login y registro utilizan Supabase real. Los botones de diseño usan ejemplos locales identificados, sin crear cuentas, pacientes ni datos clínicos.

## Registro del paciente

1. Introduce nombres, apellidos, fecha de nacimiento, DUI, teléfono, ciudad opcional, correo y contraseña.
2. Supabase Auth crea la cuenta; su trigger guarda el perfil y asigna el rol `paciente`. Los metadatos del usuario no autorizan roles.
3. Entra directamente con la sesión de Auth: **sin confirmación de correo** (`mailer_autoconfirm=true`, verificado por HTTPS el 13 de noviembre de 2026).
4. Entras al **Dashboard del paciente**, tengas o no expediente. Incluye saludo con tu primer nombre/apellido real, fecha, próxima cita autorizada y accesos a Mis citas, Solicitar atención, Laboratorios y Recetas. Sin vínculo clínico, los módulos muestran vacíos y orientación de recepción; no se bloquea el Home ni se crea expediente o cita. Actualizar el Home consulta nuevamente el vínculo.

El registro crea únicamente la cuenta y su perfil. No crea paciente, expediente ni cita. El DUI declarado permanece en los metadatos de la cuenta; no acredita identidad, autoriza roles ni vincula expedientes automáticamente. Se retiró la llamada a `register_patient` de ambos clientes y se revocó su ejecución a usuarios de la app en el servidor. La recepción conserva sus operaciones de alta y programación. Los pacientes ya vinculados conservan sus lecturas y solicitudes de atención, que no son citas.

Si Auth vuelve a exigir correo, la app informa de la discrepancia sin simular una sesión ni crear datos clínicos. Si falla la lectura tras crear la cuenta, se recupera mediante login sin repetir signup. [Detalle del flujo vigente](docs/REGISTRO_SOLO_CUENTA_2026-11-13.md).

## Integración actual

- Configuración web y tipos Postgres: `HospitalUniversitario/HospitalUniversitario/Shared/contract.json`.
- Configuración Xcode: `HospitalUniversitario/Configuration/Supabase.xcconfig`, incluida por `App.xcconfig`. Contiene únicamente URL y clave pública publicable. No hacen falta archivos privados de configuración ni claves administrativas.
- Ambos clientes rechazan una URL distinta de Hospital Móviles o una clave que no sea publicable. El comprobador portable verifica que la configuración iOS coincida con la web.
- `Shared/hospital-core.js`: validaciones, resolución de acceso, planes de consultas y adaptación de filas a la presentación, compartidos por SwiftUI y web.
- `Core/HospitalAPI.swift` y `web-preview/api.js`: Auth, sesión y ejecución de esos planes con el JWT del usuario y RLS existente. Las sesiones usan una clave específica del proyecto.
- Solicitudes de atención: `appointment_requests`, especialidad numérica y preferencia Mañana/Tarde. La base no guarda una fecha/horario propuesto en esta solicitud. Recepción programa las citas por separado.
- Lecturas adaptadas: perfil propio, habitaciones, jornadas del médico, citas, solicitudes, expediente e historial del paciente, recetas, laboratorios y notificaciones. Resultados de laboratorio únicamente publicados para el paciente. Filtros de identidad más RLS en el servidor.

**Límites actuales:** las lecturas clínicas y sus relaciones están implementadas y probadas con transporte simulado, pendientes de recorrido autenticado real. Las operaciones de consulta médica (iniciar/guardar/cerrar), emisión de recetas/órdenes, contacto de emergencia, preferencias, confirmación de jornada y descarga de documentos todavía requieren adaptación al nuevo backend: se rechazan localmente, sin llamar a servicios inexistentes. No se presenta una fila numerada ni ocupación/cifras que la base no haya publicado. Los diseños locales permanecen disponibles y no equivalen a persistencia clínica real.

## Abrir en Mac

1. Copia o clona el proyecto completo, conservando rutas relativas.
2. Abre `HospitalUniversitario/HospitalUniversitario.xcodeproj` con Xcode 16.2 o posterior.
3. Resuelve Swift Packages: `supabase-swift` está fijado a **2.28.0**.
4. Selecciona el esquema compartido **HospitalUniversitario** y un simulador iOS **18.2 o posterior**. Ejecuta `⌘R` para compilar y `⌘U` para pruebas.
5. Para un dispositivo físico, configura tu equipo de firma.

**No se ha compilado Swift en esta intervención**: Windows no dispone del SDK de Apple. La revisión portable comprueba referencias, recursos y esquema; no sustituye Xcode ni una revisión visual.

## Verificaciones

```powershell
node --preserve-symlinks --preserve-symlinks-main scripts/test-core.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-patient-registration.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-patient-dashboard.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-applicant.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/test-clinical-labs.mjs
node --preserve-symlinks --preserve-symlinks-main scripts/generate-models.mjs --check
python scripts/check-project.py
git diff --check
```

`scripts/check-backend.mjs` comprueba HTTPS y rechazo anónimo sin crear cuentas ni pacientes. Las demás pruebas anteriores usan datos/transporte locales. Las pruebas nativas requieren Mac.

[Documentación actual](docs/README.md) · [Transición y límites verificados](docs/TRANSICION_HOSPITAL_MOVILES_2026-11-13.md) · [Bitácora](docs/BITACORA.md).

[Revisión de conexión del 13 de noviembre](docs/REVISION_CONEXION_2026-11-13.md): comprobación HTTPS real, limpieza de herramientas de transición y pendientes de iOS.
