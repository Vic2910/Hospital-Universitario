# Documentación del proyecto

El nombre vigente del producto es **Hospital Universitario**. Las capturas y el informe original se conservan como evidencia histórica, aunque contengan nombres anteriores.

| Documento | Contenido |
|---|---|
| [DASHBOARD_PACIENTE_2026-10-30.md](DASHBOARD_PACIENTE_2026-10-30.md) | Rediseño del inicio del Paciente: paleta vino/rojo, componentes, parametrización y réplica web |
| [REDISENO_AUTH_2026-10-30.md](REDISENO_AUTH_2026-10-30.md) | Rediseño visual del login y nueva pantalla de registro (solo capa visual, sin registro en base) |
| [MODULOS_FUNCIONALES_2026-10-28.md](MODULOS_FUNCIONALES_2026-10-28.md) | Estado actual: Medico/Paciente en iOS y web, backend instalado, pruebas y pendientes |
| [Informe_Hospital_Universitario.md](Informe_Hospital_Universitario.md) | Informe aportado por el usuario para los flujos; contrastado con el esquema real |
| [sql/mobile-modules.sql](sql/mobile-modules.sql) | RPC de modulos, recetas atomicas y eventos; desplegados |
| [sql/test-mobile-flows.sql](sql/test-mobile-flows.sql) | Pruebas transaccionales revertidas con claims simulados, sin altas reales |
| [MODULO_DOCTOR_2026-10-28.md](MODULO_DOCTOR_2026-10-28.md) | Modulo Doctor, archivos Swift, configuracion SDK, SQL propuesto, pruebas y limites reales |
| [sql/doctor-module.sql](sql/doctor-module.sql) | RPC y eventos del Doctor; corregidos, validados y desplegados |
| [SESION_2026-10-23.md](SESION_2026-10-23.md) | Contexto consolidado de esta sesión: alcance, implementación, Supabase, cuentas, pruebas y pendientes |
| [BITACORA.md](BITACORA.md) | Registro de cambios que deben mantener las IA en cada intervención |
| [CONTEXTO_IOS.md](CONTEXTO_IOS.md) | Análisis de requisitos y pantallas, decisiones iniciales y actualizaciones posteriores |
| [login-verification.json](login-verification.json) | Resultado de las pruebas reales de login por rol, sin credenciales |
| [design-reference/inventory.json](design-reference/inventory.json) | Correspondencia entre las 21 exportaciones originales y sus archivos locales |
| [design-reference/contact-sheet.jpg](design-reference/contact-sheet.jpg) | Hoja de contacto de las pantallas iOS de referencia |
| [design-reference/requirements.txt](design-reference/requirements.txt) | Texto extraído de las cinco páginas del PDF de requisitos |
| [design-reference/Informe_Hospital_Universitario.md](design-reference/Informe_Hospital_Universitario.md) | Informe original de la conversación anterior; evidencia histórica del backend |

La guía de instalación y ejecución está en el [README principal](../README.md). Las instrucciones para agentes de IA están en [AGENTS.md](../AGENTS.md).

No añadas contraseñas, tokens o secretos a esta carpeta. Las credenciales de prueba permanecen únicamente en `.local/`, fuera de Git y del servidor de vista previa.

## Decision vigente de acceso

[Acceso con contrasena sin MFA para Medico/Paciente (2026-10-28)](ACCESO_SIN_MFA_2026-10-28.md). Sustituye los requisitos MFA de los informes historicos para estos roles.

- [Agendar cita SwiftUI y web, 30 de octubre](AGENDAR_CITA_2026-10-30.md).

- [Dashboard del doctor: SwiftUI, web, datos y verificaciones (30 de octubre)](DASHBOARD_DOCTOR_2026-10-30.md).

- [Consultas Doctor: agenda de hoy, próximas fechas y ejemplos locales](CONSULTAS_DOCTOR_2026-10-30.md).

- [Consultas Doctor: lista y detalle tipo ticket, datos y faltantes](TICKET_CONSULTA_DOCTOR_2026-10-30.md).

- [Laboratorios por rol e integración dentro del expediente: diseño y pruebas](LABORATORIOS_EXPEDIENTE_2026-10-30.md).

- [Laboratorio independiente, expediente modal, resultados y alcance de conexión](LABORATORIO_INDEPENDIENTE_2026-10-30.md).

- [Pacientes del Doctor: diseño, filtros combinados y ficha clínica interna](PACIENTES_DOCTOR_2026-10-30.md).

- [Expediente propio del Paciente: diseño de ticket interno y solo lectura](EXPEDIENTE_PACIENTE_2026-10-30.md).

- [Historial médico del Paciente: tarjetas cronológicas y detalle interno](HISTORIAL_PACIENTE_2026-10-30.md).

- [Recetas del Paciente: dashboard, tarjetas y estado de retiro](RECETAS_PACIENTE_2026-10-30.md).

- [Campos de receta del Doctor iguales a la presentación del Paciente](CAMPOS_RECETA_DOCTOR_2026-10-30.md).

- [Próxima cita, formulario único, preferencia y solicitudes Pendientes del Paciente; recepción de demostración](CITAS_SOLICITUDES_PACIENTE_2026-10-30.md).

- [Conexión de Doctor/Paciente a Supabase y datos de ejemplo creados en la base](CONECTAR_SUPABASE_DATOS_DEMO_2026-10-31.md).

- [Registro de pacientes conectado a Supabase (DUI y teléfono)](REGISTRO_REAL_SUPABASE_2026-10-31.md).

- [Perfil del Paciente e Información general: ubicación, contacto y especialidades](PERFIL_INFORMACION_GENERAL_2026-10-30.md).

- [Laboratorios del expediente Doctor: cronología sin filtros y detalle interno de resultados](LABORATORIOS_EXPEDIENTE_2026-10-31.md).

- [Mi expediente y Mis laboratorios del Paciente: diseño, datos propios y resultados publicados](MI_EXPEDIENTE_LABORATORIOS_PACIENTE_2026-10-31.md).

- [Resolución de fusión Git y validaciones (2026-10-31)](FUSION_GIT_2026-10-31.md).
