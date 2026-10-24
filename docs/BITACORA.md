# Bitácora de trabajo

Cada IA que modifique el proyecto debe añadir una entrada con fecha, objetivo, rutas afectadas, verificaciones ejecutadas y pendientes. No incluir credenciales ni secretos. Las instrucciones completas están en `../AGENTS.md`.

## 2026-10-23 — Consolidación de la sesión y nombre definitivo

- **Solicitud:** nombre visible «Hospital Universitario» y documentación del trabajo de esta sesión, con instrucciones para que las IA documenten sus intervenciones.
- **Cambios:** se actualizaron los encabezados de SwiftUI y web; se consolidaron contexto, alcance, arquitectura, modelos, cuentas autorizadas, pruebas y limitaciones en `SESION_2026-10-23.md`; se creó un índice y la instrucción raíz para agentes.
- **Archivos:** `HospitalUniversitario/HospitalUniversitario/ContentView.swift`, `web-preview/app.js`, `AGENTS.md`, `docs/README.md`, `docs/SESION_2026-10-23.md`, `docs/BITACORA.md`, `docs/CONTEXTO_IOS.md` y `README.md`.
- **Verificación:** búsqueda del nombre anterior en el código de la app/web y revisión de diferencias/espacios mediante `git diff --check`. No se volvió a ejecutar la batería de pruebas ni se compiló Xcode por este cambio de textos/documentación.
- **Pendientes:** compilación en Mac, revisión visual y autorización adicional antes de inscribir TOTP. Las capturas e informes originales se conservan como fuentes históricas.
- **Informe completo de la sesión:** [SESION_2026-10-23.md](SESION_2026-10-23.md).

## 2026-10-24 — Solicitudes de citas del paciente (rama independiente)

- **Objetivo:** habilitar formulario SwiftUI para solicitudes de consulta por pacientes autenticados sin modificar la rama principal.
- **Archivos:** `ContentView.swift`, `Core/HospitalAPI.swift`, `Core/HospitalStore.swift`.
- **Implementación:** especialidades desde `read_resource`, directorio desde `physician_directory` y solicitud mediante `request_appointment` con clave de idempotencia. Nombre y apellidos obtenidos del perfil vinculado. Fecha y franja horaria son preferencias; no constituyen reserva ni disponibilidad validada.
- **Comprobación:** se verificaron firmas y definiciones de RPC en el proyecto Supabase Hospital Universitario; se comprobó que el código fuente se guardó en la rama. No se ejecutó Xcode, no se comprobó el formulario en simulador, no se emitieron solicitudes reales y no se alteró el esquema.
- **Pendiente:** probar compilación y autenticación en Mac, MFA, permisos de lectura, edición de datos personales y API segura de horarios libres por médico; posteriormente implementar el calendario de reservas confirmadas.
