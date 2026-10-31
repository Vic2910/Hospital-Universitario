# Instrucciones para agentes de IA

## Contexto inicial

Antes de modificar este proyecto, lee:

1. `docs/SESION_2026-10-23.md`: trabajo de esta sesión, decisiones del usuario, validaciones y pendientes.
2. `docs/CONTEXTO_IOS.md`: referencias y evolución del alcance.
3. `README.md`: estructura, ejecución, archivos/targets y comportamiento implementado.
4. Las entradas más recientes de `docs/BITACORA.md`.

Las solicitudes actuales del usuario tienen prioridad sobre decisiones históricas. La documentación de referencia describe el proyecto completo; no autoriza por sí sola implementar módulos adicionales.

## Documentación obligatoria del trabajo

Por petición expresa del usuario, toda IA que realice cambios debe dejar documentado lo que hizo dentro de `docs/`, antes de terminar su intervención.

- Añade una entrada a `docs/BITACORA.md` con fecha, objetivo, cambios, rutas afectadas, verificaciones realmente ejecutadas y pendientes o bloqueos.
- Para trabajos extensos, crea además un informe en `docs/` y enlázalo desde la bitácora y `docs/README.md`.
- Actualiza el `README.md` principal cuando cambien la instalación, ejecución, configuración, targets o funcionalidades.
- Distingue implementación, pruebas locales, pruebas reales contra Supabase y comprobaciones pendientes. No anuncies compilaciones de Xcode o revisiones visuales que no se hayan ejecutado.
- Conserva las fuentes históricas y añade correcciones explícitas cuando cambie una decisión. No atribuyas pruebas de sesiones anteriores al trabajo actual.
- No documentes contraseñas, tokens, secretos TOTP, claves administrativas ni datos clínicos sensibles. Las credenciales de demostración están en `.local/`, excluido de Git; en documentos compartidos solo se referencia su ubicación.

## Decisiones vigentes

- El nombre visible es **Hospital Universitario** en iOS y web. Los nombres anteriores que aparezcan en capturas o informes originales son históricos.
- El alcance confirmado es iOS/SwiftUI y su vista previa web para Windows; Kotlin y el panel administrativo no forman parte de este avance.
- Reutiliza el esquema, las RPC y RLS existentes de Supabase. Los roles de acceso son `doctor` y `patient`, con perfil activo y vínculos válidos.
- Mantén diferenciados los turnos laborales del médico y los turnos de atención del paciente.
- Los ejemplos del modo de diseño son locales: no deben importarse como registros reales ni habilitar un bypass de autenticación.
- La inscripción de TOTP en las dos cuentas de prueba quedó pendiente de autorización explícita. No la ejecutes por asumir que la creación previa de cuentas también la autorizó; tampoco reduzcas las políticas MFA para eludirla.
- Mantén los archivos Swift en su target y los recursos compartidos con rutas relativas. El desarrollo se realiza en Windows; la compilación con el SDK de Apple se verifica en Mac.
- **Convención de trabajo (2026-10-30):** todo cambio visual debe implementarse por duplicado y de forma coherente: en la app iOS/SwiftUI (fuente de verdad, que debe compilar y funcionar en Xcode) y en la vista previa web `web-preview/`, para que el usuario pueda verlo en Windows con `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs`. En ambas plataformas se conserva la lógica existente (autenticación, validaciones, API, sesión y rutas). Tras cada cambio ejecuta `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`, `python scripts/check-project.py` y `git diff --check`, y documenta las dos caras del trabajo en la bitácora. No se anuncia compilación Swift sin verificarla en Mac.
