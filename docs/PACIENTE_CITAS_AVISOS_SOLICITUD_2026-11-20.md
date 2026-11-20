# Paciente: citas a la vista, avisos propios y solicitud única — 20 de noviembre de 2026

iOS/SwiftUI y `web-preview/` tienen el mismo comportamiento. Recepción y el ADMIN no se modificaron.

## Backend inspeccionado (MCP, solo lectura)

- **Avisos**:
  - `notifications` tiene la RLS `recipient_id = auth.uid()` para leer y actualizar.
  - **Hoy el paciente solo recibe avisos de resultados de laboratorio**, que crea `private.laboratory_notifications` al publicarse un resultado para él.
  - **No hay aviso** cuando recepción programa, reprograma o cancela su cita (`doctor_appointment_notice` solo avisa al médico), ni cuando su receta pasa a `entregada`, ni cuando su solicitud se rechaza.
- **Solicitudes**:
  - `submit_my_attention_request` no impide enviar otra solicitud si ya hay una pendiente o una cita programada.
  - Estados de `request_state`: pendiente, en_revision, agendada, rechazada y cancelada.
- **Citas del paciente**: `appointments` con RLS del paciente.
  - `staff` y `consulting_rooms` son legibles.
  - `profiles` del médico **no** es legible para el paciente, así que se muestra «Médico · código».
  - `appointment_requests` y `specialties` aportan el motivo y la especialidad.

## Cambios

1. **Mis citas, sin pantallas intermedias** (iOS `PatientAppointmentsView`, web `HospitalPatientAppointments.renderLive`):
   - La próxima cita se muestra destacada, con fecha, hora, estado, médico, especialidad, consultorio, motivo e indicaciones.
   - Debajo aparecen las siguientes citas y el historial de citas, del más reciente al más antiguo, con el motivo de cancelación cuando existe.
   - La cancelación se hace en la misma tarjeta, pide un motivo y usa la acción existente `cancel_appointment`.
   - La consulta de citas del paciente (`HospitalCore`, módulo `appointments`) ahora incluye médico, especialidad y motivo.
2. **Campana de avisos del paciente**, como la del médico (iOS `PatientNotificationBell`, web `patientNotificationPanel`):
   - Contador de avisos sin leer, panel con icono según el tipo y botón «Ver» que lleva a Laboratorios, Recetas, Mis citas o Solicitar atención.
   - Opción «Marcar como leída».
   - Actualización cada 30 s en primer plano.
   - Solo muestra avisos de la propia cuenta, por la RLS.
3. **Una sola solicitud activa** (Swift `AttentionRules.blocker` y JS `HospitalCore.attentionBlocker`):
   - Con una solicitud pendiente o en revisión, aparece «Tu solicitud está en revisión» y el formulario no se muestra.
   - Con una cita programada, confirmada o en atención vigente, aparece «Ya tienes una cita programada para el …».
   - Tras un rechazo o una cancelación se puede volver a solicitar.
   - La cita vigente se obtiene de `patientDashboard`.
4. **SQL preparado, no aplicado**: `supabase/paciente-avisos-solicitud-unica.sql`.
   - Tres disparadores que solo insertan avisos al paciente: cita programada, reprogramada o cancelada; receta entregada; solicitud rechazada.
   - La misma regla de solicitud única **en el servidor**, dentro de `submit_my_attention_request`. Así no depende solo de la app.

## Verificaciones

- **Ejecutadas en Windows**, con DOM y transporte simulados y datos sintéticos. Todas aprobadas:
  - las 15 pruebas web, incluidas **test-patient-portal** (nueva) y **test-attention-navigation**, que cubre el bloqueo con solicitud pendiente, el nuevo envío tras un rechazo y el bloqueo con cita programada;
  - generate-models --check, check-project.py y git diff --check.
- **No ejecutado**:
  - Compilación y pruebas Swift. Hay una prueba nueva `AttentionSingleRequestTests`.
  - Revisión visual.
  - Aplicación del SQL.
- **Hasta aplicar el SQL**:
  - El paciente solo recibe avisos de resultados de laboratorio.
  - La regla de solicitud única se aplica solo en la app.
