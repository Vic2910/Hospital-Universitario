# Agendar cita — 30 de octubre de 2026

Implementado en el proyecto iOS original y en `web-preview/`; AdminHospital permanece sin cambios.

Acceso Paciente en el dashboard usa el destino existente `schedule`. Se conservan catálogo, sesión y navegación. Tarjeta introductoria, secciones de datos editables, síntomas con Ninguno excluyente, motivo, seis especialidades con sus franjas precargadas y resumen de selección. Se reutilizan HospitalTheme, HospitalPalette y los componentes Patient existentes. Referencia: docs/design-reference/Captura de pantalla 2026-10-30 133626.png; se conserva vino/rojo en lugar del violeta de la referencia.

Datos iguales en ambas versiones: Gaby Diaz, 0123-45678, 7123-4567, gaby.diaz@ejemplo.test. Son ejemplos ficticios y no se envían al backend. El botón prepara una cita local; no confirma una reserva real. Los horarios son etiquetas de demostración, no fechas de disponibilidad reales.

Validación equivalente: nombres/apellidos no vacíos, DUI 0000-00000, teléfono 0000-0000, correo con formato, motivo no vacío, especialidad y horario elegidos. Editar cualquier campo invalida la confirmación anterior. Cambiar especialidad borra horario. Selección accesible y visual mediante estado y marcas. La web conserva foco de opciones tras repintar y respeta movimiento reducido.

## Continuación y cierre de verificación

Se revisó el avance interrumpido antes de modificarlo: las dos pantallas, los componentes Patient, la ruta schedule y los datos de prueba ya estaban implementados. Se conservaron los cambios locales de dashboard, login y registro.

Se corrigió el ScrollView anidado del formulario SwiftUI, reutilizando el desplazamiento del portal. El teclado de DUI permite introducir el guion. La web descarta los datos editados al cerrar sesión o cambiar de modo/perfil. Ambas versiones explican el formato de los campos y usan el botón «Preparar cita de prueba», con confirmación explícita de simulación. Se armonizó el apilado de campos y el espacio de horarios, con marcas de selección, foco visible web y respeto al movimiento reducido en ambas versiones.

Verificaciones ejecutadas en esta continuación: los ocho recorridos DOM existentes aprobaron; se añadieron y aprobaron dos recorridos de agendamiento (diseño y sesión con transporte simulado). Cubren los cinco datos precargados, síntomas múltiples y Ninguno excluyente, las seis especialidades, descarte de horario al cambiar especialidad, campos inválidos, preparación, invalidación al editar y ausencia de llamadas API al interactuar. Se comprobó además el descarte del borrador al salir del modo diseño.

Pendientes: revisión visual en navegador y dispositivo/simulador; compilación y pruebas Swift en Mac. Las pruebas DOM no acreditan apariencia ni compilación nativa. No se probaron reservas reales ni se modificó Supabase: este formulario utiliza exclusivamente datos locales de prueba. El flujo existente de solicitudes reales conserva su destino request.

Comprobación final: `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs`, `python scripts/check-project.py`, `node --check web-preview/app.js` y `git diff --check` aprobados. También aprobaron los siete recorridos funcionales de `scripts/test-modules.mjs` con transporte simulado.
