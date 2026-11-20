# Expedientes: búsqueda, expediente e historial — 20 de noviembre de 2026

Rediseño del módulo Expedientes en iOS/SwiftUI y en `web-preview/`, con el mismo comportamiento en ambos. No se modificaron el ADMIN, Recepción, la RLS, los permisos, las recetas ni el laboratorio.

## Backend inspeccionado (MCP, solo lectura)

| Elemento | Situación real |
|---|---|
| `doctor_native_patients(p_query, p_offset)` | Usa SECURITY DEFINER. La ejecuta `authenticated`, no `anon`. Solo devuelve pacientes con `private.treats_patient` (cita propia vigente o completada, consulta propia o asignación activa en el equipo de atención). Busca por nombre completo (nombre, apellido o ambos), correo, DUI (con o sin guion) y código de expediente. **No devuelve ni busca `patient_code`.** |
| `doctor_native_chart` | Exige `treats_patient`. Devuelve el paciente, los antecedentes y el historial **solo de las consultas del médico autenticado** (`e.doctor_id = d`), con signos vitales, código de diagnóstico y recetas. **Las recetas no indican `encounter_id`.** El historial no incluye especialidad, motivo ni médico, y no tiene paginación. |
| `doctor_native_patient_labs` | Exige `treats_patient`. Las órdenes incluyen `encounter_id`, y los resultados solo cuando están validados y publicados. Pagina de 25 en 25. |
| `my_consultation_history` | Exige el rol `paciente`. Solo devuelve consultas finalizadas (`ended_at IS NOT NULL`) del propio paciente (`p.profile_id = auth.uid()`). Pagina con cursor de 25 registros. Incluye médico, especialidad, diagnósticos y signos vitales. **No incluye motivo, recetas ni exámenes.** |
| RLS | `encounters_read` y `diagnoses_read`: el médico autor o el paciente tras el cierre. `patients` y `medical_records`: `can_read_patient`. `lab_results`: el paciente solo ve resultados publicados para él. Siguen pendientes de decisión los hallazgos ya documentados sobre `lab_orders`, `vital_signs` y `prescriptions`. |

## Qué hace ahora

**Médico** (pestaña Pacientes y pantalla Expediente; Laboratorios conserva su directorio):

- **Buscador amplio**, sin selector desplegable:
  - Espera 350 ms antes de consultar y cancela la búsqueda anterior al seguir escribiendo.
  - No repite una consulta con el mismo texto.
  - En la web solo se repintan los resultados, para no perder el foco del buscador.
- **Resultados en tarjetas**. Muestran nombre, código de paciente (cuando el servidor lo envíe), expediente, DUI, edad, estado del expediente y si hay una consulta en curso. No muestran información clínica.
- **Expediente**:
  - Una cabecera única con iniciales, nombre, código, expediente, edad, fecha de nacimiento, DUI, teléfono, correo y ciudad, cada dato una sola vez.
  - Información clínica en la que las alergias y condiciones no se repiten dentro de «Otros antecedentes».
  - Accesos: continuar la consulta, laboratorios y solicitar ingreso.
- **VER HISTORIAL MÉDICO** despliega una línea de tiempo:
  - Solo consultas finalizadas, de la más reciente a la más antigua, de 10 en 10.
  - Cada tarjeta muestra fecha, hora, médico y especialidad; también motivo, diagnóstico, observaciones y tratamiento cuando existen.
  - Si no hay consultas finalizadas, aparece un estado vacío.
- **Detalle de cada consulta**, que solo muestra los campos con valor:
  - Datos físicos (más IMC), síntomas, diagnóstico y código, observaciones y tratamiento.
  - Las recetas de esa consulta (requiere la migración).
  - Los exámenes de esa consulta, con su resultado cuando está publicado.
- **Actualización** cada 60 segundos mientras el expediente está abierto. Se descarta si cambió el paciente o la sesión, porque la caché está ligada a la selección y se limpia al cambiar de paciente o al cerrar sesión.

**Paciente** (Mi expediente):

- Entra directamente con su identidad; no hay buscador ni selector.
- Ve una cabecera única: la sección «Datos personales» ya no se repite debajo.
- **VER HISTORIAL MÉDICO** abre sus consultas finalizadas, de la más reciente a la más antigua, con «Cargar consultas anteriores».
- Las tarjetas muestran motivo y diagnóstico. El detalle se agrupa en datos físicos, evaluación médica, recetas y exámenes, solo con los campos reales.
- Los resultados solo aparecen si el laboratorio los publicó para el paciente.

## Migración preparada, no aplicada

`supabase/expedientes-historial.sql` solo amplía la salida de tres RPC existentes. No crea RPC, tablas ni columnas, no cambia RLS ni GRANT y no toca datos:

1. `doctor_native_patients`: devuelve y busca `patient_code`.
2. `doctor_native_chart`: añade `patient_code`. En cada consulta añade `ended_at`, `doctor_name`, `specialty` y `reason`, y en cada receta, `encounter_id`.
3. `my_consultation_history`: añade `reason`, y por cada consulta sus recetas y exámenes. El resumen del resultado solo aparece si está validado y publicado al paciente.

**Sin la migración**, la app sigue funcionando con lo que el servidor publica hoy:

- La búsqueda funciona por nombre, apellido, DUI, correo y expediente, pero **no por código de paciente**.
- Las tarjetas del médico no muestran especialidad ni motivo, y el médico que aparece es el usuario actual (correcto, porque el servidor solo devuelve sus consultas).
- Las recetas no se pueden asociar a una consulta; el detalle lo indica y remite a Recetas.
- Los exámenes por consulta sí funcionan, porque `doctor_native_patient_labs` ya incluye `encounter_id`.
- El paciente no ve recetas ni exámenes dentro de cada consulta; se le remite a Mis recetas y Mis laboratorios.

## Límites

- `doctor_native_chart` solo devuelve las consultas del médico autenticado. Un médico no ve consultas de otros médicos del mismo paciente; se mantiene así por privacidad, como está desplegado.
- El historial del médico llega completo en una sola respuesta y se pagina en pantalla. Los exámenes por consulta se buscan en las primeras páginas cargadas de `doctor_native_patient_labs`, de 25 en 25.
- No hay Realtime publicado. La actualización es periódica mientras la pantalla está abierta, y también al volver a abrirla.

## Archivos

- **iOS**:
  - `Doctor/DoctorRecordsView.swift` (nuevo).
  - `Doctor/DoctorModuleView.swift` (Pacientes y Expediente usan la vista nueva).
  - `Core/DoctorModels.swift` (`DoctorRecordRules` y campos opcionales nuevos).
  - `Core/DoctorViewModel.swift` (`searchPatients` con espera y sin repetir, `loadChart(silent:)`).
  - `Patient/PatientHistoryView.swift`, `Patient/PatientClinicalView.swift`.
  - `HospitalUniversitarioTests/DoctorModuleTests.swift`.
- **Compartido**: `Shared/hospital-core.js`. El historial ya no presenta campos vacíos; incluye motivo, recetas y exámenes cuando llegan, y el código de paciente en el expediente.
- **Web**: `web-preview/modules.js` (`recordsView`), `web-preview/patient-history.js`, `web-preview/clinical-labs.js` y `web-preview/style.css`.
- **Pruebas**:
  - `scripts/test-doctor-directory.mjs` (reescrita).
  - `scripts/test-patient-record.mjs` (nueva).
  - `scripts/test-doctor-alerts-history.mjs` y `scripts/test-doctor-laboratory.mjs` (ajustadas).
  - `scripts/test-preview.mjs` (el entorno simulado incluye temporizadores).
- **SQL**: `supabase/expedientes-historial.sql`.

## Verificaciones

Ejecutadas en Windows con DOM y transporte simulados y datos sintéticos. Todas aprobadas:

- test-preview, test-core, test-patient-registration, test-patient-dashboard, test-attention-navigation y test-applicant.
- test-doctor-preview-live, test-doctor-clinical-rules, test-doctor-alerts-history, test-doctor-directory, test-doctor-laboratory y test-doctor-admissions.
- test-patient-record.
- generate-models --check, check-project.py y git diff --check.

Qué cubren las pruebas de la lista de 18:

| Puntos | Qué se comprobó |
|---|---|
| 1–5 | Búsqueda por nombre, apellido, nombre y apellido, DUI, código y expediente, y que los resultados coinciden con el texto. |
| — | Una sola consulta por búsqueda y ninguna repetida. |
| 6 | Un paciente no autorizado nunca aparece. |
| 7 | Cada dato del expediente aparece una sola vez. |
| 8–12 | El historial se despliega, va de la más reciente a la más antigua, excluye las consultas abiertas, muestra el detalle de cada una, no muestra campos vacíos y tiene estado vacío. |
| 13–14 | El paciente entra a su expediente sin buscador ni selector, y sus RPC no envían identificadores. |

`test-clinical-labs` falla igual que en el commit d828fd6; es un fallo previo y ajeno a este trabajo.

**No ejecutado**:

- Compilación y pruebas Swift. Windows no tiene el SDK de Apple. Hay 3 pruebas nuevas en `DoctorModuleTests`. Falta ⌘B, ⌘R y ⌘U en Xcode 16.2 o posterior.
- Revisión visual en distintos tamaños de iPhone (punto 17).
- Pruebas contra Supabase real de los puntos 15, 16 y 18. Esas garantías dependen de las RPC y la RLS inspeccionadas, que no se modificaron.
- Aplicación de la migración.
