# Solicitar atención iOS — contrato de integración

Actualización posterior: la vista previa de Windows replica ahora el formulario mediante las mismas RPC. Se retiró la interceptación de cuentas sin expediente de las rutas request/schedule/health. Esto no modifica el panel externo de recepción ni despliega nuevos objetos de base de datos.

Implementado en `PatientAttentionLiveView.swift` y `PatientAttentionModel.swift`, conectado por `HospitalAPI` y `HospitalStore`. Datos existentes de cuenta en lectura; solo se completan los faltantes. Catálogos reales, síntomas múltiples/Otro, especialidades con médico activo asignado, preferencia Mañana/Tarde/Indiferente, motivo, aviso de emergencias y seguimiento. El envío no crea paciente, expediente ni cita. El usuario autorizó cambios mínimos de Supabase y excluyó ambos frontends web.

## Supabase desplegado

- Migraciones `account_owned_attention_requests` y `attention_owner_validation`. Fuentes actuales: `supabase/attention-account.sql` y `supabase/attention-validation.sql`; no son SQL de la integración anterior.
- Se reutilizan `appointment_requests`, `appointment_request_symptoms`, `symptom_catalog`, `specialties`, `doctor_specialties` y roles existentes. Solicitudes añaden `requester_id`, `applicant_data` y `other_symptoms`; `patient_id` admite nulo. Se conservan las filas y RLS. Preferencia añade `indiferente`. Síntomas maestros añadidos: Gripe, Lesión o posible fractura y Otro; sin doctores ficticios ni asignaciones nuevas permanentes.
- `my_attention_context()` devuelve exclusivamente datos de la cuenta autenticada y catálogos. DUI de paciente propio o declaración de Auth/solicitud anterior; no acredita identidad ni vincula automáticamente. Campos inválidos se presentan faltantes para completarlos.
- `submit_my_attention_request(p_key uuid,p_specialty bigint,p_period text,p_reason text,p_symptoms bigint[],p_other text,p_missing jsonb)` obtiene propietario y vínculo desde `auth.uid()`, valida rol activo, catálogos y campos, guarda snapshot y síntomas atómicamente. `p_missing` admite solo first_name, last_name, birth_date, phone y dui; no sustituye datos existentes ni permite user_id, roles o paciente ajeno. Clave estable por intento y bloqueo transaccional para idempotencia.
- `my_attention_requests()` devuelve como máximo las cien solicitudes propias más recientes con estado y appointment_id. RLS también permite SELECT propio y de recepción/admin. Las nuevas RPC públicas no conceden EXECUTE a anon/PUBLIC; las de personal comprueban rol activo dentro del servidor.

## Para el otro proyecto de recepción

El panel no fue editado. Debe listar `appointment_requests` mediante su JWT de recepcionista/admin, incluyendo filas con **patient_id nulo**, y usar `applicant_data` como declaración, no como identidad verificada. Sus SELECT no deben exigir un INNER JOIN a patients. Síntomas en `appointment_request_symptoms` y catálogo; descripción adicional en `other_symptoms`.

1. `review_attention_request(p_request,p_status)` acepta en_revision, rechazada o cancelada desde pendiente/en_revision. Nunca permite fijar agendada manualmente.
2. Buscar paciente existente o crearlo con la función **existente** `create_walkin_patient`. Esta operación es de recepción, nunca de iOS.
3. `link_attention_patient(p_request,p_patient,p_identity_confirmed=true)` requiere verificación explícita del personal, coincidencia de DUI/nacimiento y ausencia de conflictos de vínculo. No busca ni crea pacientes automáticamente.
4. Consultar disponibilidad real con `get_medical_availability` y programar mediante la función **existente** `schedule_appointment(...,p_request)`. Se conserva su validación de jornada/consultorio y la restricción única de appointments.request_id, sin segunda lógica de citas.

iOS actualiza sus solicitudes y las pantallas Home/Mis citas al refrescar, volver a primer plano y periódicamente mientras están visibles. Los lectores existentes siguen filtrando por el vínculo clínico propio. El cliente no usa un permiso de empleado para estas acciones.

## Verificación ejecutada y límites

Prueba real en Supabase: `supabase/test-attention-rollback.sql` pasó con cuentas y personal temporales dentro de una subtransacción revertida. Cubrió solicitud sin paciente, recepción por RLS, creación autorizada/vínculo, cita real por schedule_appointment, lectura propia final, doble envío, aislamiento entre cuentas, rechazo de autoasignación de roles/suplantación, especialidad sin médico y completado de perfil. Verificación posterior: cero cuentas/personas de prueba y cero solicitudes persistentes del test. No se enviaron correos ni se crearon sesiones Auth de prueba.

El primer intento de migración detectó que el ID del catálogo era identity ALWAYS; se confirmó reversión completa y se corrigió para usar IDs generados. El despliegue corregido y la prueba final pasaron. Asesores consultados: los cinco RPC nuevos aparecen por ser SECURITY DEFINER, con autorización revisada y ejecución anónima revocada; permanecen avisos ajenos al alcance de extensión, política de inventario y protección de contraseñas.

test-preview, test-core, test-patient-registration y check-project aprobados. `PatientAttentionTests` cubre el modelo con transporte simulado, pero **no se ejecutó** en Windows. Pendientes: compilar y ejecutar pruebas/interfaz en Xcode, recorrido HTTPS con identidad autorizada y conectar el panel externo a este contrato. La prueba SQL real no acredita esos recorridos de cliente.
