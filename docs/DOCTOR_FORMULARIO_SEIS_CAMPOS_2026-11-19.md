# Doctor: formulario de consulta de seis campos — 19 de noviembre de 2026

iOS/SwiftUI y `web-preview/` comparten el rediseño. Las reglas comunes están en Swift `DoctorClinicalRules` y en JS `HospitalCore.doctorClinical`. No se modificaron recetas, laboratorio, Recepción, el panel administrativo ni la RLS.

## Qué ve el médico

1. **Tarjeta del paciente**. Muestra:
   - Nombre completo, estado (Programada, En consulta o Finalizada), expediente y edad.
   - **Código del paciente**, solo cuando el servidor lo publique (ver la migración).
2. **Datos de la cita**. Se cargan solos:
   - Fecha y hora de la consulta en hora de El Salvador, con su duración.
   - Médico responsable, especialidad, consultorio y hora de apertura.
   - **Motivo de consulta** enviado en la solicitud.
3. **Síntomas reportados**. Aparecen como etiquetas, tal como los marcó el paciente.
4. **Bloque A — Datos físicos**:
   - Peso (kg), Altura (cm) y Temperatura (°C).
   - Campos amplios con unidades visibles. No admiten letras.
   - Rangos de `doctor_native_save`: peso mayor que 0 y hasta 1000; altura mayor que 0 y hasta 300; temperatura de 25 a 50.
   - Son opcionales: lo que el médico no registra no se envía.
   - El IMC aparece calculado solo cuando hay peso y altura, y no se guarda.
5. **Bloque B — Evaluación médica**. Los tres campos son obligatorios para finalizar:
   - **Síntomas que presentaba** → `subjective`. En la primera apertura se precarga con los síntomas que envió el paciente.
   - **Diagnóstico** → `assessment`, y también `public.diagnoses` mediante `doctor_native_save`.
   - **Observaciones** → `objective`.
6. **Bloque C — Servicios adicionales**. **Solicitar exámenes** y **Recetar medicamentos** abren los mismos formularios de antes, sin salir de la consulta.
7. **Guardado y cierre**. Se mantienen sin cambios: Guardar consulta, los estados de guardado, el conflicto de versión, el aviso al salir y la confirmación «¿Estás seguro de que deseas finalizar esta consulta?».

Se retiraron del formulario estos campos:

- Presión sistólica y diastólica.
- Frecuencia cardíaca.
- Plan de tratamiento.
- Código de diagnóstico.
- El acceso a ingreso hospitalario. Sigue disponible desde el panel y desde Más.

Frecuencia respiratoria y SpO₂ nunca existieron en la base.

## Compatibilidad con Supabase (inspección de solo lectura)

- `doctor_native_save` sobrescribe en cada guardado las seis columnas de `vital_signs`, además de `subjective`, `objective`, `assessment` y `plan`. Si el cliente dejara de enviar presión, frecuencia cardíaca o plan, los borraría de una consulta abierta. Por eso el borrador conserva esos valores tal como llegaron del servidor y los reenvía sin cambios: **no se pierde información ni se inventa**. El historial sigue mostrando esas medidas cuando existen, y el plan de consultas anteriores aparece como «Plan de tratamiento (registro anterior)».
- `doctor_native_finish` (versión desplegada) exige `subjective`, `objective`, `assessment` **y `plan`**. Como el formulario ya no tiene plan, el cierre falla mientras no se aplique la migración. En ese caso:
  - la app explica que falta aplicar `supabase/doctor-consultation-six-fields.sql`;
  - la consulta no se cierra;
  - no se pierde lo escrito;
  - no se rellena un plan ficticio.
- `patients.patient_code` existe (`text NOT NULL`), pero ni `doctor_native_workspace` ni `doctor_native_chart` lo devuelven. Hasta aplicar la migración solo se muestra el expediente.

### Migración propuesta (preparada, **no aplicada**)

`supabase/doctor-consultation-six-fields.sql` contiene:

1. `doctor_native_finish` **y el disparador `private.native_complete_guard`** exigen síntomas, diagnóstico y observaciones. El disparador también validaba `plan`; se añadió al archivo el 20 de noviembre, tras la auditoría. Sin ese ajuste el cierre seguiría fallando. `plan` pasa a ser opcional y se conserva. Se mantienen el control de versión, la comprobación de consulta propia y abierta, el cambio atómico de la cita a `completada` y la auditoría.
2. `doctor_native_workspace` y `doctor_native_chart` añaden `patient_code`.

No crea tablas, no cambia RLS ni GRANT y no modifica datos. Se redactó a partir de `pg_get_functiondef` del servidor actual. No se pudo validar en el servidor porque el MCP es de solo lectura.

## Expediente y privacidad

- Historial del paciente (`my_consultation_history`, adaptador compartido iOS/web): muestra médico, especialidad, Síntomas que presentaba, Diagnóstico, Observaciones, Peso, Altura y Temperatura. Si existen, también el plan anterior, el código diagnóstico y las medidas antiguas. Solo incluye consultas cerradas del propio paciente.
- Historial del médico (`doctor_native_chart`): solo las consultas propias, con diagnóstico, síntomas y observaciones.
- Recepción no lee notas ni diagnósticos. Siguen pendientes de decisión los hallazgos ya documentados sobre `lab_orders`, `vital_signs` y `prescriptions` ([informe del flujo](DOCTOR_FLUJO_CONSULTA_2026-11-19.md)).

## Archivos

- iOS:
  - `Doctor/DoctorConsultationFormComponents.swift` (nuevo; carpeta sincronizada del target).
  - `Doctor/DoctorModuleView.swift`, `Doctor/DoctorPatientHistoryView.swift`.
  - `Core/DoctorModels.swift`, `Core/DoctorViewModel.swift`.
  - `HospitalUniversitarioTests/DoctorModuleTests.swift`.
- Compartido: `Shared/hospital-core.js`.
- Web: `web-preview/modules.js`, `web-preview/api.js` (conserva el texto del servidor en `error.detail` para reconocer causas concretas), `web-preview/doctor-dashboard.js` y `web-preview/style.css`.
- Pruebas: `scripts/test-doctor-preview-live.mjs`, `scripts/test-doctor-clinical-rules.mjs`, `scripts/test-doctor-alerts-history.mjs`.
- Contrato: `contracts/doctor-native-v1.json`.
- SQL: `supabase/doctor-consultation-six-fields.sql`.

## Verificaciones

- **Ejecutadas en Windows**, con DOM y transporte simulados y datos sintéticos. Aprobadas:
  - test-preview, test-core, test-patient-registration y test-patient-dashboard.
  - test-attention-navigation y test-applicant.
  - test-doctor-preview-live, test-doctor-clinical-rules y test-doctor-alerts-history.
  - test-doctor-directory, test-doctor-laboratory y test-doctor-admissions.
  - generate-models --check, check-project.py y git diff --check.
- **Lo que cubre la réplica web**:
  - Existen solo los seis campos y no aparecen presión, frecuencia cardíaca, plan ni código.
  - Los campos numéricos no admiten texto y los valores fuera de rango se rechazan.
  - Se guardan los seis valores y se conservan la presión antigua y el plan.
  - Conflicto de versión.
  - Exámenes y receta de dos medicamentos.
  - El cierre se bloquea sin diagnóstico.
  - Si falla el guardado, no se cierra.
  - Con el servidor sin migración, la consulta no se cierra, se muestra el aviso y no se inventa el plan.
  - Con la migración aplicada, el cierre funciona.
  - Los seis campos aparecen en la consulta finalizada y en el historial del paciente.
- `test-clinical-labs` falla igual que en el commit d828fd6, ajeno a este cambio.
- **No ejecutado**:
  - Compilación y pruebas Swift: Windows no tiene SDK de Apple. Hay dos pruebas nuevas y cuatro ajustadas en `DoctorModuleTests`. Falta ⌘B, ⌘R y ⌘U en Xcode 16.2 o posterior.
  - Revisión visual.
  - Aplicación y prueba de la migración en Supabase.
