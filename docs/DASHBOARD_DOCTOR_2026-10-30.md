# Dashboard del doctor — 30 de octubre de 2026

## Resultado y referencias

Se sustituyó el resumen de métricas del doctor por una bienvenida coherente con el dashboard actual del paciente. Se revisaron directamente `docs/design-reference/screen-01.png`, `screen-12.png` y `screen-19.png`; se priorizaron las cards, radios, espacios y componentes del panel de paciente ya implementado. Se conserva la paleta vino `#770727`, rojo `#A4133C`, rosa y fondo `#F8F8FA`.

La vista muestra nombre y apellido, fecha local actual, total de citas programadas para hoy, accesos a Pacientes/Consultas/Laboratorios/Expedientes, historial por paciente e intervalo opcional de fechas, y jornadas laborales de esta semana. El botón de horario abre el destino `turns` existente, con su paginación y acciones previas. Las jornadas del personal permanecen separadas de los turnos de atención del paciente.

## Código e integración

| Archivo | Responsabilidad |
|---|---|
| `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorDashboardView.swift` | Vista, estado de búsqueda, cards, calendario y fixtures exclusivas de `#Preview` |
| `HospitalUniversitario/HospitalUniversitario/Doctor/DoctorModuleView.swift` | Adapta workspace y jornadas al dashboard en `home`; conserva los demás módulos |
| `HospitalUniversitario/HospitalUniversitario/Core/DoctorViewModel.swift` | Lectura independiente del historial del dashboard sin alterar el borrador de consulta ni la selección clínica |
| `HospitalUniversitario/HospitalUniversitario/Core/HospitalStore.swift` | Carga jornada actual y primera página de `staff_shifts` al entrar/actualizar Inicio |
| `HospitalUniversitario/HospitalUniversitario/ContentView.swift` | Pasa jornadas y aviso de carga al módulo existente |
| `web-preview/doctor-dashboard.js` | Réplica de la vista, filtros, estados vacíos/error y demostración local equivalente |
| `web-preview/app.js` | Adapta datos reales del módulo y abre demostración desde el modo diseño Médico |
| `web-preview/modules.js` | Carga workspace de hoy y jornadas propias, y delega la presentación del Inicio |
| `web-preview/index.html`, `server.mjs` | Carga y sirve el nuevo JS mediante la lista permitida existente |
| `web-preview/style.css` | Reutiliza `.dash-*` y agrega estilos para búsqueda, historial y jornadas |
| `scripts/test-preview.mjs`, `scripts/test-doctor-dashboard.mjs` | Carga del nuevo módulo en el doble DOM y recorridos específicos del dashboard |

Se reutilizan `HospitalCard`, `PatientQuickAccessCard`, `PatientFormCard`, `HospitalTheme` y `LinearGradient.vinoDestacado`. El nuevo Swift pertenece al grupo sincronizado Doctor del target principal; no se cambió el proyecto Xcode ni se añadieron dependencias.

En sesión real, `doctor_workspace` aporta identidad, sede y citas del día. El total cuenta citas que no estén canceladas, rechazadas o ausentes; incluye las finalizadas del día y no confunde el contador de encuentros clínicos con citas programadas. Inicio restablece el día actual, aunque se haya consultado otra fecha en otro módulo. `staff_shifts` se lee con el filtro de propietario y semana del adaptador existente. Si falla esa lectura se conserva el dashboard y se muestra un aviso; el enlace permite reintentar en Mi horario.

El selector muestra pacientes únicos de la agenda actual y permite buscarlos por nombre o expediente. Para agendas de otra fecha se usa el acceso a Pacientes y sus filtros existentes. El historial seleccionado puede abarcar todas las fechas o un intervalo; Hasta incluye el día completo. No se buscan identidades fuera de los datos autorizados disponibles. Se eliminan resultados al cambiar filtros o paciente, salir del contexto o recibir un error; las respuestas tardías se descartan.

`doctor_chart(p_patient, p_from, p_to, p_query)` conserva la autorización del servidor. La definición versionada filtra `e.attending_physician_id = private.staff_id()` y `private.can_encounter(...)`; el cliente no elige un doctor para autorizar. Esta sesión revisó el SQL del repositorio, sin consultar ni modificar el servidor. La lectura del dashboard no modifica notas, versiones ni borradores de los módulos clínicos.

## Datos de demostración y visualización

En Windows, ejecutar:

```powershell
node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs
```

Abrir `http://127.0.0.1:4173/` y pulsar **Médico** en los controles de diseño fuera del teléfono. Comparar con **Paciente** desde esos mismos controles. La demostración muestra **Dr. Luis Ramírez**, cuatro consultas programadas, Carlos Mendoza y María López, historial relativo al día actual y jornadas de lunes a viernes (07:00–15:00; jueves 15:00–23:00). Una consulta ficticia de otro doctor existe únicamente para verificar su exclusión; no se muestra. Los ejemplos no se cargan como sustitutos de datos reales.

En Mac, abrir el Preview **Doctor · datos locales** de `DoctorDashboardView.swift`. Usa los mismos nombres, conteo, pacientes, motivos e intervalos que la web; no habilita acceso sin sesión en la app. El flujo de inicio de sesión real sigue usando los módulos autorizados, incluso cuando no hay citas o jornadas.

## Verificaciones ejecutadas y límites

- `scripts/test-preview.mjs`: ocho recorridos previos y dos de agendar cita aprobados.
- `scripts/test-modules.mjs`: siete recorridos funcionales aprobados con transporte simulado.
- `scripts/test-doctor-dashboard.mjs`: demostración y sesión simulada; identidad, conteo, cuatro accesos, horario, filtro por nombre/fecha, intervalos inválidos/vacíos, exclusión de otro médico y paciente, formato de parámetros RPC, descarte al salir y error sin notas residuales. Aprobados; no acreditan autorización real de Supabase.
- `python scripts/check-project.py`: referencias, recursos y esquema aprobados; no compila Swift.
- Sintaxis Node de `doctor-dashboard.js`, `app.js` y `modules.js`, y `git diff --check`: aprobados.
- Servidor local temporal en 4187: HTTP 200 en `/`, `/doctor-dashboard.js`, `/app.js`, `/modules.js` y `/style.css`; cerrado al terminar.

No se ejecutaron Xcode, pruebas nativas ni revisión visual con navegador/dispositivo. Playwright no está instalado en esta copia. Compilación, comportamiento nativo y comparación visual final quedan pendientes en Mac/navegador. No hubo login real, escritura clínica, cambios en Supabase, credenciales, MFA, RPC ni RLS.


## Corrección de distribución solicitada el 30 de octubre

Esta decisión sustituye la ubicación descrita arriba: **Inicio** conserva únicamente bienvenida, fecha, consultas programadas y accesos rápidos. **Historial clínico** se trasladó a **Pacientes** (`DoctorPatientHistoryView.swift` y `renderHistory` en web), conservando selección de paciente, intervalo y consultas propias. En sesión real usa la agenda de la fecha seleccionada en Pacientes. El método del view model ahora se llama `patientHistory`; no modifica el borrador clínico.

**Mi horario** conserva exclusivamente las jornadas en su pantalla existente (`turns`, accesible desde Más). Se retiró del Inicio tanto su resumen como la lectura de `staff_shifts`; esa carga se mantiene en la pantalla de horario con los filtros previos. Los ejemplos web de horario ya existentes permanecen allí.

SwiftUI ofrece además el Preview «Pacientes · historial local» del nuevo componente, mientras el Preview del dashboard ya no incluye historial ni jornadas. No se modificaron autenticación, RPC ni políticas de servidor. Las pruebas se adaptaron para exigir la ausencia de ambas secciones en Inicio y verificar el historial en Pacientes y las jornadas en Mi horario.
