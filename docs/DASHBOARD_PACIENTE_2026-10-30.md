# Dashboard del paciente (2026-10-30)

Fecha en la zona del usuario: America/El_Salvador. Informe del rediseño del inicio del rol Paciente; no acredita compilación Swift pendiente en Mac.

## Solicitud

Rediseñar la pantalla principal que ve el paciente al entrar, en Swift/SwiftUI con el estilo del proyecto, tomando como base `docs/design-reference/Captura de pantalla 2026-10-30 133626.png` (app de ejemplo púrpura): saludo con avatar circular, card destacada con fecha y próxima cita, cuatro cards de acceso rápido y la barra de navegación inferior del rol intacta. Paleta obligatoria vino y rojo del proyecto. Por la convención vigente en `AGENTS.md`, el diseño se implementó también en la vista previa web.

## Estructura tomada de la referencia (con la paleta del proyecto)

| Referencia (púrpura) | Implementación del proyecto |
|---|---|
| «Hola, Federico» + foto circular | `PatientGreetingCard`: «Hola, {nombre} 👋», subtítulo y avatar con iniciales (patrón ya usado en Perfil) |
| Card degradada «próxima cita» con hora grande | `PatientDateAppointmentCard`: sección HOY con fecha larga en español (`es_SV`) y, debajo, «PRÓXIMA CITA» con día, hora grande y médico; sin cita muestra un estado vacío honesto |
| «Registra Tu Día» con 4 cards | «Accesos rápidos»: Mis citas, Laboratorios, Expedientes y Agendar cita |
| Banner de fotografía de comida | **No se copió**, por instrucción expresa del usuario |

Se omitieron también las secciones de sueño, agua y ejercicio.

## Archivos nuevos (Swift)

| Archivo | Contenido |
|---|---|
| `HospitalUniversitario/HospitalUniversitario/Design/HospitalPalette.swift` | Extensión `Color` con `vinoPrincipal` (#770727), `rojoAcento` (#A4133C), `fondoCard`, `fondoApp` y `LinearGradient.vinoDestacado` |
| `HospitalUniversitario/HospitalUniversitario/Patient/PatientDashboardComponents.swift` | `PatientGreetingCard`, `PatientDateAppointmentCard`, `PatientQuickAccessCard` y `PatientQuickAccessStyle` (estado al presionar) |
| `HospitalUniversitario/HospitalUniversitario/Patient/PatientDashboardView.swift` | `PatientDashboardView`, modelo `ProximaCita` y `#Preview` con «Gaby Diaz» y una cita de ejemplo |

Los tres archivos entran al target por el grupo sincronizado; no se tocó `project.pbxproj`.

## Parametrización y decisiones

- `nombrePaciente`: propiedad con valor por defecto «Gaby Diaz»; el nombre real llegará con el modelo de paciente. En `ContentView` se pasa `store.name` cuando existe y el ejemplo cuando es el marcador «Bienvenido».
- `proximaCita: ProximaCita?`: el home actual no carga la lista de citas (eso pertenece a la pantalla Mis citas), así que se pasa `nil` y la card muestra el estado vacío. Cuando exista el modelo de citas, basta construir el `ProximaCita` con día, hora y médico.
- Destinos de los accesos: IDs ya existentes del catálogo — `appointments`, `laboratory`, `chart` y `request` (Agendar cita) — mediante la misma clossure `navigate: go` que usan los módulos del Doctor.
- La fecha usa `DateFormatter` con locale `es_SV`, consistente con la convención de semana local del proyecto.

## Qué no se modificó

- La lógica del portal: encabezado, barra inferior, `go()`, `store` y carga de datos permanecen intactos; el doctor conserva su home anterior.
- En `ContentView` el único cambio funcional fue la rama del `case "home"`: `if isDoctor { home } else { patientDashboard }`. La propiedad `home` anterior permanece para el rol Médico.
- No se añadieron llamadas a API ni se escribió en la base de datos. El resumen (`my_activity_summary`) sigue cargándose, aunque el nuevo home del paciente ya no muestra esas métricas.

## Réplica web (convención vigente)

- `web-preview/app.js`: `home(content)` deriva el rol Paciente a `patientDashboard(content)` (saludo con `displayName()`, card de fecha con `Intl.DateTimeFormat('es-SV')`, próxima cita de ejemplo en modo diseño usando `fixtures.patient.rows.appointments[0]`, estado vacío en login real y las cuatro cards con `matches()` para respetar el buscador). El home del médico quedó idéntico.
- `web-preview/style.css`: reglas nuevas `.dash-*` al final (tarjetas, avatar, degradado vino, grid 2×2 con estado `:active`), reutilizando las variables del tema; CRLF normalizado.

## Verificaciones realmente ejecutadas

- `node --check web-preview/app.js`: sintaxis aprobada.
- `scripts/test-preview.mjs`: **8 recorridos DOM aprobados**, incluido «Diseño patient: todas las pantallas navegables; cero llamadas a Supabase» sobre el nuevo home.
- `python scripts/check-project.py`: aprobado.
- `git diff --check`: aprobado.
- Revisión directa de la captura de referencia y de `screen-01.png`/`screen-03.png` para la paleta y la jerarquía.

**No se compiló Swift**: Windows no tiene el SDK de Apple. La compilación en Xcode y la revisión visual en simulador siguen pendientes en Mac.

## Pendientes

1. Compilar en Mac (`⌘R`) y revisar el dashboard en simulador, incluido el `#Preview` de `PatientDashboardView`.
2. Conectar `proximaCita` cuando exista el modelo de citas del paciente; hoy es un parámetro opcional sin datos reales.
3. Verificar nombres reales del perfil (`store.name`) en un dispositivo con sesión activa.
