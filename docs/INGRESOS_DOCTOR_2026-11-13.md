# Solicitudes de ingreso — contrato iOS, Windows y recepción

Hospital Móviles `uvebpsbbwofthucghccc`. iOS y `web-preview/` llaman las mismas RPC con JWT del usuario y clave publicable. Dashboard del doctor → **Ingresos hospitalarios**; también desde paciente/consulta → **Solicitar ingreso hospitalario**. En Windows iniciar servidor de README, abrir http://127.0.0.1:4173/, Ctrl+F5 e iniciar sesión con doctor autorizado. El modo diseño continúa siendo local y no acredita persistencia.

## Doctor

`doctor_native_admissions(p_offset=0)` devuelve `doctor_name`, `categories`, `priorities`, `items`, `total`, `has_more`, `next_offset` (25 por página). Lista únicamente solicitudes del doctor activo y pacientes con relación asistencial vigente. Cada ítem incluye paciente/expediente, médico, categoría, motivo, observaciones, prioridad, estado, decisión, motivo de respuesta, asignación real y eventos de estado. La búsqueda de paciente usa `doctor_native_patients`, independiente de la agenda del día.

`doctor_native_admission_request(p_patient uuid, p_kind room_kind, p_reason text, p_instructions text, p_priority text, p_encounter uuid|null, p_key uuid)` devuelve UUID. Médico derivado del JWT y staff activo categoría doctor; paciente autorizado; encuentro propio y del mismo paciente si se proporciona. Motivo obligatorio, textos hasta 10000 caracteres. Misma clave y contenido devuelve la misma solicitud; una solicitud activa por paciente continúa protegida por índice existente. Un error de transporte conserva el envío exacto para reintentar. No asigna ni ocupa cama.

Categorías reales inspeccionadas: `vip` (**VIP**) y `semiprivada` (**Semiprivada**). Prioridades reales: `normal`, `urgente`. Los clientes cargan estos valores del contrato del servidor; no prometen disponibilidad ni inventan “Semi VIP”.

## Recepción: integración pendiente en el otro proyecto

| RPC | Uso |
|---|---|
| `reception_admissions(p_offset=0,p_status=null)` | Listado con paciente, expediente, solicitante, categoría, motivo, prioridad, asignación e historial. `p_status='solicitado'` para pendientes. |
| `reception_admission_availability(p_admission uuid)` | `beds[]` con `bed_id`, cama, habitación, categoría y piso reales; `checked_at` y `reservation=false`. No reserva. |
| `reception_resolve_admission(p_admission,p_action,p_reason=null,p_bed=null)` | `asignar` + cama invoca `assign_bed`; `rechazar` o `cancelar` exige motivo y solicitud todavía pendiente sin cama. |

Estas RPC requieren rol activo `recepcionista` o `admin`. También se conserva `assign_bed(p_admission,p_bed)` y sus permisos existentes. Al confirmar se bloquean solicitud/cama, se revisan estado y categoría, y se actualizan asignación, cama e ingreso en la misma transacción. Índices existentes impiden dos pacientes en la misma cama, dos camas activas para un paciente y dos ingresos activos para el mismo paciente. Una habitación con varias camas no equivale a una habitación ocupada en exclusiva.

Estados existentes, sin ampliar enum: `solicitado` → `hospitalizado` al asignar; `alta_medica` → `cerrado` mediante `medical_discharge` / `release_bed` existentes. `asignado` se conserva si lo usa otro flujo. Rechazo y cancelación previos al ingreso usan `cancelado` con `decision='rechazada'|'cancelada'`, justificación, actor y fecha. No existen estados “en revisión” o “aprobada” en este enum; no se simulan. El doctor ve la respuesta al actualizar. Tras ingreso no se cancela para liberar camas: se respeta el circuito de alta existente.

El otro proyecto debe construir su interfaz sobre este contrato: pendientes → disponibilidad → confirmar cama/rechazar/cancelar → actualizar listado. No se modificó ese repositorio.

## Cambios y verificación

Migración desplegada `doctor_admission_requests_v1`, fuente `supabase/doctor-admissions.sql`. Reutiliza `hospital_admissions`, `patients`, `medical_records`, `staff`, `user_roles`, `rooms`, `beds`, `bed_assignments`, `hospital_floors`, `audit_logs` y `bed_status_history`. Añade clave de reintento e información de decisión a hospital_admissions; trigger de estados hacia audit_logs; cinco RPC y helper privado. Refuerza la firma existente de request_admission con vínculo doctor activo y validación de textos. Sin tablas clínicas nuevas ni cambios en RLS, login o citas; sin service_role en clientes.

SQL real `supabase/test-admissions-rollback.sql`: solicitud → recepción → disponibilidad → asignación → seguimiento y rechazo justificado aprobados, con aislamiento de roles y bloqueo de doble ocupación/reintento duplicado. Todos los fixtures se revirtieron; consulta posterior confirmó cero cuentas, habitaciones y camas temporales. RLS sigue activa y anon no puede ejecutar las cinco RPC nuevas. Asesores revisados: avisos de funciones SECURITY DEFINER para authenticated son intencionales y tienen controles internos; persisten avisos previos de extensión en public, RLS sin políticas y contraseñas filtradas. [Criterio de revisión de funciones](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Prueba web `scripts/test-doctor-admissions.mjs` con transporte simulado: selección, categorías/prioridad, confirmación previa, respuesta perdida/reintento idéntico, estado/asignación/rechazo, catálogo vacío y logout. Regresiones core, preview, registro, atención, directorio y flujo médico aprobadas; comprobador portable aprobado. Prueba Swift añadida a DoctorModuleTests, pendiente de ejecutar en Mac. Windows no compila SDK Apple. El SQL acredita backend, no ejecución del cliente nativo ni login HTTPS del recorrido completo.
