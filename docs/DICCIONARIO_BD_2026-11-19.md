# Diccionario técnico de la base de datos — Hospital Móviles

**Proyecto:** `uvebpsbbwofthucghccc` (`https://uvebpsbbwofthucghccc.supabase.co`) · **PostgreSQL 17.11** · **Fecha de la auditoría:** 19 de noviembre de 2026.

**Método:** auditoría **de solo lectura** con las herramientas MCP de Supabase: `list_tables`, `list_migrations`, `list_edge_functions`, `get_edge_function`, `list_extensions`, `get_advisors` (security y performance), `get_project_url` y `execute_sql`, este último solo con `SELECT` sobre catálogos (`pg_catalog`, `information_schema`, `pg_policies`, `supabase_migrations`, `storage`). No se ejecutaron escrituras, migraciones ni despliegues. **No se leyeron filas de datos clínicos ni personales**; los conteos de filas son estimaciones del catálogo.

> Este documento es una fotografía del 19/11/2026. Antes de basar una implementación en él, vuelve a comprobar el objeto concreto en Supabase: puede haber cambiado.

---

## 0. Resumen y hallazgos prioritarios

| # | Severidad | Hallazgo | Evidencia |
|---|---|---|---|
| H1 | **Alta (seguridad)** | La Edge Function `manage-employees` genera la "contraseña temporal" con `temporaryEmployeePassword()`, que **devuelve siempre la misma constante literal** para todas las altas (el valor no se reproduce aquí). El contrato anuncia `unique-temporary-password`, pero eso no se cumple. Cualquier empleado creado que no haya cambiado la clave comparte credencial. | `validation.ts` de la versión 8 desplegada. |
| H2 | **Alta (contradice una decisión vigente)** | `public.register_patient(text,text,text)` **se puede ejecutar como `authenticated`**. AGENTS.md exige que no lo sea. La migración `20261119052813 walkin_patient_registration` volvió a conceder `GRANT EXECUTE ... TO authenticated` después de que `20261113165229 disable_patient_self_enrollment` lo revocara. La función exige rol `paciente` y correo confirmado; como `mailer_autoconfirm=true`, cualquier cuenta paciente con nombre y fecha de nacimiento en su perfil puede **crear su propio paciente y expediente**, saltándose a Recepción. | `proacl`: `authenticated=X/postgres`; `statements` de ambas migraciones. |
| H3 | Media | **Deriva sin migración** en `public.doctor_native_workspace`: el cuerpo desplegado no coincide con el de la migración registrada `20261113204024` ni con `supabase/doctor-ios.sql`. Lo más probable es que se modificara con SQL directo fuera del historial. | Hashes normalizados distintos en los tres casos (§11). |
| H4 | Media | `anon` tiene privilegios `SELECT/INSERT/UPDATE/DELETE` sobre `hospital_settings`, `lab_result_drafts`, `laboratory_authorizations` y `panel_preferences`. Hoy los bloquea RLS (no hay políticas para `anon`), pero dependen de una sola barrera. | `has_table_privilege` (§5.2). |
| H5 | Media | `private.lab_permission()` **solo comprueba el rol `admin`**. La tabla `laboratory_authorizations` (process/validate/publish) existe, pero **no participa** en la autorización, y `authorize_laboratory_staff` está deshabilitada (lanza siempre una excepción). Laboratorio es exclusivo del ADMIN. | Cuerpos de `lab_permission` y `authorize_laboratory_staff`. |
| H6 | Baja | Supabase Auth tiene desactivada la protección contra contraseñas filtradas (`auth_leaked_password_protection`). | Advisor de seguridad. |
| H7 | Info | **Realtime** tiene la publicación `supabase_realtime` **sin ninguna tabla**, y **Storage** tiene **0 buckets, 0 objetos y 0 políticas**. `lab_result_files.storage_path` existe, pero no hay almacenamiento que lo respalde. | §10. |
| H8 | Info | 46 de las 52 tablas de `public` se crearon **fuera** del historial de migraciones (base previa). Solo 9 de las 31 migraciones tienen un archivo local equivalente. Desde los archivos locales no se puede reconstruir el esquema. | §9 y §11. |
| H9 | Rendimiento | 63 FK sin índice de cobertura, 13 políticas con `auth.uid()` sin envolver en `(select …)` e índices sin uso (`patients_name_idx`, `ambulance_requests_status_idx`). Con el volumen actual (≤121 filas) no hay impacto. | Advisor de performance. |

**No se pudo consultar:** la configuración de Auth (proveedores, `mailer_autoconfirm`, plantillas, expiración de JWT); no la expone ninguna de las herramientas MCP disponibles. El valor `mailer_autoconfirm=true` procede de la verificación HTTPS registrada el 13/11, no de esta auditoría. Tampoco se consultaron los secretos ni las variables de entorno de las Edge Functions (no se deben leer), ni los logs (`query_logs`, que no formaba parte del alcance), ni la configuración de Realtime a nivel de proyecto (límites, broadcast, presence): solo la publicación. `search_docs`, `get_publishable_keys` y `generate_typescript_types` no se usaron porque no aportan nada a la estructura que no se obtenga del catálogo. Los conteos de filas son estimaciones de `pg_class`.

---

## 1. Módulos y modelo de autorización

| Módulo | Cliente | Rol `hospital_role` | Vía de acceso principal |
|---|---|---|---|
| **ADMIN** | Panel web externo (no es `web-preview`) | `admin` | RPC `save_*`, `set_*`, planificación, laboratorio, transporte; Edge `manage-employees`; DML directo en catálogos permitido por RLS |
| **Recepción** | Panel web externo | `recepcionista` | RPC `reception_*`, `schedule_appointment`, `*_attention_*`, camas e ingresos |
| **Paciente iOS** (+ réplica `web-preview`) | SwiftUI | `paciente` (UI: `patient`) | RPC `my_*` y `submit_my_attention_request`; lectura RLS de sus filas mediante `patients.profile_id` |
| **Médico iOS** (+ réplica `web-preview`) | SwiftUI | `doctor` + `staff.active` + `staff.category='doctor'` | RPC `doctor_native_*` (todas pasan por `private.native_doctor_id()`) |

Existe también el rol `enfermera`, con la función `private.cares_for` y la tabla `care_team_assignments`. Ningún módulo actual lo usa.

### 1.1 Helpers de autorización (`private`, SECURITY DEFINER, `search_path=""`)

| Función | Lógica desplegada |
|---|---|
| `has_role(p_role)` | Existe `user_roles(user_id=auth.uid(), role, active)`. **No lee JWT ni `user_metadata`.** |
| `my_staff_id()` | `staff.id` activo del `auth.uid()`. |
| `my_patient(p_id)` | `patients.id=p_id AND profile_id=auth.uid()`. |
| `treats_patient(p_id)` | Rol `doctor` y además alguna de estas condiciones: una cita (programada/confirmada/en_atencion/completada), un encuentro o una asignación vigente de equipo con ese paciente. |
| `cares_for(p_id)` | Rol `enfermera` y asignación vigente en `care_team_assignments`. |
| `can_read_patient(p_id)` | `my_patient OR treats_patient OR cares_for OR admin OR recepcionista`. |
| `owns_clinical_note(enc)` | Rol `doctor` y además médico autor del encuentro, con `staff` activo de `category='doctor'`. |
| `encounter_doctor(enc)` | El encuentro pertenece a `my_staff_id()` y el usuario tiene rol `doctor`. |
| `encounter_patient(enc)` | Paciente del encuentro (a través de `medical_records`). |
| `native_doctor_id()` | Lanza `42501` si no tiene rol `doctor` o si no hay `staff` activo con `category='doctor'`. |
| `native_doctor_encounter(enc, open)` | Encuentro propio del médico nativo (y, opcionalmente, todavía abierto). |
| `lab_permission(p)` | **Solo `admin`** (ver H5). |
| `transport_operator(dispatch)` | **Solo `admin`.** |

El esquema `private` tiene `USAGE` para `authenticated` y no para `anon`.

### 1.2 Alta de cuentas (trigger `on_auth_user_created` en `auth.users`)

`private.auth_new_user()` inserta `profiles` (nombre, apellido, teléfono, fecha de nacimiento y ciudad tomados de `raw_user_meta_data`) y **siempre** asigna `user_roles(role='paciente')`. Los metadatos se usan solo para el perfil, **nunca para el rol**. Las cuentas de personal se crean desde la Edge Function `manage-employees`.

---

## 2. Tipos enumerados (`public`)

| Tipo | Valores |
|---|---|
| `hospital_role` | admin, doctor, recepcionista, enfermera, paciente |
| `request_state` | pendiente, en_revision, agendada, rechazada, cancelada |
| `appointment_state` | programada, confirmada, en_atencion, completada, cancelada, no_asistio |
| `admission_state` | solicitado, asignado, hospitalizado, alta_medica, cerrado, cancelado |
| `bed_state` | disponible, ocupada, limpieza, mantenimiento |
| `room_kind` | vip, semiprivada |
| `lab_state` | pendiente, en_proceso, completado |
| `dispatch_state` | pendiente, autorizada, despachada, finalizada, rechazada, cancelada |
| `ambulance_state` | disponible, en_servicio, en_mantenimiento |

Extensiones instaladas: `pgcrypto`, `uuid-ossp` y `pg_stat_statements` (en `extensions`), `btree_gist` (en **`public`**; el advisor lo marca), `supabase_vault` y `plpgsql`. **No** están instaladas `pg_cron`, `pg_net`, `pgmq` ni `pg_graphql`.

---

## 3. Diccionario de tablas

Notación: **NN** = NOT NULL · `=` = valor predeterminado · `gen()` = `gen_random_uuid()` · `ident` = columna identity · `→` = FK. La columna "Módulos" indica quién lee o escribe la tabla (A = ADMIN, R = Recepción, P = Paciente iOS, M = Médico iOS). "Filas" es una estimación del catálogo.

### 3.1 Identidad y personal

#### `profiles` — perfil 1:1 con `auth.users` · ~10 filas · A R P M
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid NN | PK · → `auth.users(id)` ON DELETE RESTRICT |
| first_name, last_name | text NN | `=''` |
| phone, city | text | |
| birth_date | date | |
| created_at, updated_at | timestamptz NN | `=now()` |

Trigger `protect_profile`: el rol `authenticated` no puede cambiar nombre, apellido ni fecha de nacimiento, y la función actualiza `updated_at`. Grants a `authenticated`: SELECT y UPDATE solo de las columnas (`phone`, `city`). RLS: `profile_read` (propio o admin), `profile_contact` (UPDATE propio) y `profile_admin_update`.

#### `user_roles` · ~17 filas · A (escribe por RPC/Edge), todos leen el propio
| user_id uuid NN → profiles ON DELETE CASCADE | role hospital_role NN | active boolean NN `=true` |
|---|---|---|

PK (`user_id`, `role`). RLS `role_read`: propio o admin. Solo se escribe con `set_employee_role` (admin) y con el trigger de alta. Lleva `planning_guard` y `planning_lock`.

#### `staff` · ~6 filas · A (Edge), R M (lectura)
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid NN `gen()` | PK |
| profile_id | uuid | UNIQUE · → profiles |
| employee_code | text NN | UNIQUE (la Edge Function asigna 001–999) |
| category | text NN | se usan 'doctor' y 'recepcionista'; **sin CHECK** |
| active | boolean NN `=true` | |
| ambulance_driver_authorized | boolean NN `=false` | |

RLS `staff_read`: `true` para cualquier `authenticated`, de modo que cualquier usuario autenticado ve el directorio completo de `staff`.

#### `specialties` (~7) · `symptom_catalog` (~11) · A escribe, todos leen
`id bigint ident PK`, `name text NN UNIQUE`, `active boolean NN =true`. RLS de lectura para `anon` y `authenticated` cuando `active`; INSERT, UPDATE y DELETE solo para admin.

#### `doctor_specialties` (~6) · A, M
PK (`doctor_id` → staff ON DELETE CASCADE, `specialty_id` → specialties). Lectura `true`; escritura admin.

#### `panel_preferences` · 0 filas · A R
`user_id uuid PK → profiles CASCADE`, `attention`, `admissions`, `ambulance` y `laboratory` (boolean NN `=true`), `poll_seconds int NN =60`, con CHECK ∈ {30, 60, 120}. Lectura propia para admin, recepcionista o laboratorio; se escribe con `my_panel_preferences`.

#### `hospital_settings` · 0 filas · A (escribe), R (lee)
Tabla de una sola fila (`id boolean PK =true`, CHECK `id`). Columnas `name`, `about`, `affiliation`, `email`, `phone` y `address` con límites de longitud; `latitude` y `longitude` numeric dentro de rango y ambas nulas o ambas presentes; `updated_at NN`; `updated_by` → profiles. Se escribe con `save_hospital_settings`.

### 3.2 Planificación laboral

#### `staff_shifts` · ~30 · A
`id`, `staff_id NN → staff`, `starts_at` y `ends_at` timestamptz NN (CHECK fin > inicio), `shift_type text NN ='ordinario'`, `status text NN ='programado'`. EXCLUDE gist: sin solapes por `staff_id` cuando `status<>'cancelado'`. RLS: admin o el propio empleado.

#### `staff_absences` · ~25 · A
`id`, `staff_id NN`, `starts_at` y `ends_at` NN, `reason`, `active NN =true`. EXCLUDE `planning_absence_overlap` (si `active`). RLS: admin o el propio empleado.

#### `doctor_schedules` · ~12 · A, R (lectura), M (propio)
`id`, `doctor_id NN → staff`, `weekday smallint NN` (0–6), `start_time` y `end_time` time NN (fin > inicio), `valid_from date NN =CURRENT_DATE`, `valid_until`, `active NN =true`, `consulting_assignment_id` → `doctor_consulting_rooms` ON DELETE RESTRICT. CHECK `planning_finite_schedule`: si está activo, `valid_until` es obligatorio y el rango no supera 366 días.

#### `doctor_consulting_rooms` · ~12 · A, R, M (propio)
`id`, `doctor_id NN`, `consulting_room_id NN`, `starts_at` y `ends_at` NN, `active NN`, `slot_minutes int NN =30` (5–180). EXCLUDE: sin solapes por médico ni por consultorio cuando `active`.

#### `staff_recurring_journeys` · ~8 · A (solo por RPC; **sin grants ni políticas** para clientes)
| Columna | Tipo / restricción |
|---|---|
| id | uuid NN PK (sin valor predeterminado) |
| staff_id | uuid NN → staff RESTRICT |
| staff_role | text NN ∈ {doctor, recepcionista} |
| weekdays | smallint[] NN, cardinalidad 1–7, valores ⊆ {0..6} |
| start_time, end_time | time NN, distintos (se admite que crucen la medianoche) |
| shift_type | text NN ∈ {ordinario, guardia} |
| breaks, consultations | jsonb NN `='[]'` (deben ser arrays) |
| consulting_room_id | uuid → consulting_rooms RESTRICT |
| specialty_id | bigint → specialties RESTRICT |
| valid_from NN, valid_until, closed_on | date (CHECK de orden) |
| active | boolean NN; CHECK `active = (closed_on IS NULL)` |
| effective_period | daterange · weekday_set int4multirange |
| supersedes | uuid → self RESTRICT |
| request_values NN, last_change_values | jsonb · last_change_key uuid |
| created_at NN `=now()`, created_by NN → profiles | |

CHECK de rol: un doctor requiere consultorio, especialidad y consultas no vacías; un recepcionista no lleva ninguno de los tres. EXCLUDE diferidos: sin solape de días y periodo por empleado, y el consultorio fijo no se comparte entre empleados en periodos que se solapen.

### 3.3 Infraestructura física

| Tabla | Columnas | Claves y reglas | Filas | Módulos |
|---|---|---|---|---|
| `hospital_floors` | id smallint PK, name NN | lectura anon/auth | 2 | A R |
| `consulting_rooms` | id uuid, code NN UNIQUE, floor_id → floors, active NN | lectura auth; escritura admin; planning triggers | 20 | A R M |
| `rooms` | id, code NN UNIQUE, floor_id NN, kind room_kind NN, active NN | lectura anon/auth si `active` | 11 | A R |
| `beds` | id, room_id NN → rooms, code NN UNIQUE, state bed_state NN ='disponible', active NN, operational_reason | lectura anon/auth `true`; trigger de auditoría de inventario | 17 | A R |
| `bed_status_history` | id bigint ident, bed_id NN, old_state, new_state NN, actor_id, changed_at NN | lectura admin/recep | 1 | A R |

### 3.4 Pacientes, atención y citas

#### `patients` · ~8 · R (alta), A, P (propio), M (los que trata)
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid NN `gen()` | PK |
| profile_id | uuid | UNIQUE · → profiles ON DELETE SET NULL (**opcional**: hay pacientes presenciales sin cuenta) |
| patient_code | text NN | `='PAC-'+12 hex` UNIQUE |
| first_name, last_name | text NN | índice `lower(last_name), lower(first_name)` |
| dui | text | UNIQUE · CHECK `^[0-9]{8}-[0-9]$` |
| phone, city, email | text | email con CHECK de formato y ≤254 |
| birth_date | date | |
| registration_source | text NN `='presencial'` | ∈ {ios, presencial} |
| created_at NN, created_by → profiles | | |

RLS: `patients_read` = `can_read_patient(id)`; `patient_admin_update` (admin o recepcionista, solo las columnas `first_name`, `last_name`, `dui`, `phone`, `birth_date` y `city`). Sin INSERT directo: se insertan con `create_walkin_patient`, `create_attention_patient` y `register_patient` (ver H2).

#### `medical_records` · ~8 · R (creación vía RPC), A, P, M
`id`, `patient_id NN UNIQUE → patients` (un expediente por paciente), `record_code NN ='EXP-…' UNIQUE`, `opened_at NN`, `opened_by` → profiles. RLS: `can_read_patient`. Trigger `clinical_record_identity_guard` (bloquea el cambio de `patient_id`).

#### `medical_history` · 0 · M (también enfermería)
`id`, `record_id NN → medical_records`, `history_type NN`, `description NN`, `recorded_by` → profiles, `created_at`. INSERT: `recorded_by=auth.uid()` y además `treats_patient` o `cares_for`. Lectura: `can_read_patient`.

#### `appointment_requests` (solicitudes de atención) · ~9 · P (crea), R A (gestionan), M (lee las de sus pacientes)
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid `gen()` | PK |
| patient_id | uuid | → patients (**nullable** hasta que Recepción lo vincula) |
| requester_id | uuid | → profiles (cuenta solicitante) |
| specialty_id | bigint NN | → specialties |
| preferred_period | text NN | ∈ {manana, tarde, indiferente} |
| reason | text NN | |
| status | request_state NN `='pendiente'` | |
| applicant_data | jsonb NN `='{}'` | datos de contacto que faltan en el perfil |
| other_symptoms | text | ≤1000 |
| closure_reason | text | |
| reviewed_by | uuid → profiles | |
| created_at | timestamptz NN | |

CHECK `attention_owner_required`: `patient_id` o `requester_id` no nulo. Triggers: `attention_request_owner` (BEFORE INSERT: impone `requester_id=auth.uid()` al paciente y valida que `patient_id` sea propio) y `panel_attention_notice` (aviso al panel). RLS: `attention_account_read` (paciente solicitante), `req_read` (propietario del paciente, recepción, admin o médico tratante), `req_insert` (solo si `my_patient(patient_id)`, estado pendiente y sin revisor). iOS usa la RPC `submit_my_attention_request`.

#### `appointment_request_symptoms` · ~9 · P, R
PK (`request_id` → requests ON DELETE CASCADE, `symptom_id` → symptom_catalog).

#### `appointments` · ~8 · R A (crean), M (atienden), P (lee las propias)
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid | PK |
| request_id | uuid | UNIQUE · → appointment_requests |
| patient_id | uuid NN | → patients |
| doctor_id | uuid NN | → staff |
| consulting_room_id | uuid NN | → consulting_rooms |
| starts_at, ends_at | timestamptz NN | fin > inicio |
| status | appointment_state NN `='programada'` | |
| queue_number | int NN (>0) | UNIQUE (`doctor_id`, `queue_date`, `queue_number`) |
| queue_date | date NN | |
| created_by, cancelled_by → profiles; cancellation_reason; cancelled_at | | |

EXCLUDE gist: no se solapan el médico, el consultorio ni el paciente mientras la cita esté en programada, confirmada o en_atencion. Triggers: `appointment_queue_assignment` (asigna el turno con `private.appointment_queue_counters`), `clinical_appointment_identity_guard`, `doctor_appointment_notice` (aviso al médico), `native_complete_guard` (solo completa si el encuentro está cerrado), `planning_lock` y `planning_guard` (diferido: el horario debe ser válido). RLS de lectura: paciente propio, médico tratante, recepción o admin. Sin DML directo de clientes.

#### `appointment_status_history` · ~8 · lectura vía RLS de `appointments`
`id bigint ident`, `appointment_id NN`, `old_status`, `new_status NN`, `actor_id`, `changed_at`.

### 3.5 Clínica

#### `clinical_encounters` (consulta) · 0 · M (autor), P (propio, tras el cierre)
| Columna | Tipo | Restricciones |
|---|---|---|
| id | uuid | PK |
| record_id | uuid NN | → medical_records (índice) |
| appointment_id | uuid | UNIQUE · → appointments |
| doctor_id | uuid NN | → staff |
| started_at NN `=now()`, ended_at | timestamptz | |
| subjective, objective, assessment, plan | text | ≤10000 cada una |
| version | int NN `=0` | concurrencia optimista |
| last_save_key | uuid | idempotencia |

RLS `encounters_read`: `owns_clinical_note(id)` o el paciente propietario cuando `ended_at IS NOT NULL` (decisión del 19/11). INSERT por política: médico tratante. En la práctica se escribe con `doctor_native_start`, `doctor_native_save` y `doctor_native_finish`. Trigger `clinical_encounter_identity_guard`.

#### `diagnoses` · 0 · M, P
`id`, `encounter_id NN`, `diagnosis_code`, `description NN`, `notes`, `created_at`. Lectura: el autor, o el paciente cuando la consulta está cerrada. INSERT: `encounter_doctor`.

#### `vital_signs` · 0 · M (también enfermería)
`id`, `encounter_id NN`, `weight_kg` (>0) y `height_cm` (>0) numeric, `systolic`, `diastolic`, `heart_rate` smallint, `temperature_c` numeric, `recorded_by NN`, `recorded_at`. Trigger `clinical_vitals_write_guard`. Lectura: paciente propio, médico tratante o enfermería asignada.

#### `care_team_assignments` · 0 · R (crea vía RPC de valoración), M, enfermería
`id`, `patient_id NN`, `staff_id NN`, `starts_at NN =now()`, `ends_at` (> inicio). Lectura: admin, médico tratante o enfermería asignada.

#### `admission_assessments` (valoración de ingreso presencial) · 0 · R (solicita), M (decide). **Solo por RPC**: sin grants ni políticas.
`id` NN (sin valor predeterminado), `patient_id`, `doctor_id` → staff, `team_assignment_id` UNIQUE → care_team, `requested_by` → profiles, `requested_at`, `reason` (1–2000), `priority` ∈ {normal, urgente}, `status` ∈ {pending, approved, rejected, expired} `='pending'`, `assessment` text ≤10000 `=''`, `version int =0`, `decided_by`, `decided_at`, `admission_id` UNIQUE → hospital_admissions. Un CHECK compuesto mantiene la coherencia entre estado y decisión. Índice único: una sola valoración pendiente por paciente.

### 3.6 Hospitalización

#### `hospital_admissions` · ~1 · M (solicita), R A (gestionan), P (lee)
`id`, `patient_id NN`, `ordered_by NN → staff`, `encounter_id` → encounters, `requested_kind room_kind NN`, `medical_reason NN`, `clinical_instructions`, `priority` ∈ {normal, urgente}, `status admission_state NN ='solicitado'`, `ordered_at`, `request_key uuid` (UNIQUE parcial con `ordered_by`), `decision` ∈ {rechazada, cancelada}, `decision_reason` ≤10000, `decided_at/by`, `reviewed_at/by`, `medically_discharged_at/by`, `discharge_notes`, `closed_at/by`. UNIQUE (`id`, `patient_id`), con soporte a FK compuesta. Índice único: un solo ingreso activo por paciente. Triggers `native_admission_audit` y `panel_admission_notice`.

#### `bed_assignments` · ~1 · R A
`id`, `admission_id NN`, `patient_id NN`, FK compuesta (`admission_id`, `patient_id`), `bed_id NN`, `assigned_by NN`, `assigned_at`, `released_at` (≥ asignación). Índices únicos: una cama activa por paciente y un paciente activo por cama.

### 3.7 Laboratorio (exclusivo ADMIN; M solicita; P lee lo publicado)

| Tabla | Columnas clave | Reglas | Filas |
|---|---|---|---|
| `lab_test_types` | id bigint ident, name UNIQUE, code `='EXAM-…'` UNIQUE, description, category, active, result_schema jsonb `'[]'`, schema_validated_by/at | trigger `protect_laboratory_schema`; lectura anon/auth si `active`; escritura admin | 11 |
| `lab_orders` | id, order_code `='LAB-…'` UNIQUE, encounter_id NN, test_type_id NN, reason NN, weight_kg/height_cm (>0), status lab_state `='pendiente'`, ordered_at, request_group uuid | UNIQUE parcial (`encounter`, `request_group`, `test`); triggers de aviso y de historial de estado | 0 |
| `lab_results` | id, order_id UNIQUE, summary NN, result_values jsonb, parameter_schema jsonb, validated_by/at, completed_at, published_at/by, published_to_patient_at, published_revision int | lectura: laboratorio, o publicado y validado para el médico tratante y, si está liberado, para el paciente | 0 |
| `lab_result_drafts` | id → lab_results (PK compartida), order_id UNIQUE, draft_summary, draft_values, draft_schema, workflow_stage ∈ {draft, review, validated, published}, version, prepared_by, draft_validated_by/at, correction_reason, updated_at | lectura solo laboratorio; ⚠ grants a anon (H4) | 0 |
| `lab_result_files` | id, result_id NN, storage_path UNIQUE, mime_type | **no existe bucket en Storage** (H7) | 0 |
| `lab_delivery_events` | id bigint ident, order_id, sender_id NN, recipient_id, delivery_type ∈ {a_recepcion, a_paciente}, sent_at | lectura: remitente, destinatario, admin o recepción | 0 |
| `laboratory_authorizations` | staff_id PK, can_process, can_validate, can_publish, active, authorized_by NN, authorized_at | **no se usa en la autorización** (H5); ⚠ grants a anon | 0 |

### 3.8 Farmacia (backend presente; sin módulo cliente activo identificado)

| Tabla | Columnas clave | Reglas | Filas |
|---|---|---|---|
| `medications` | id, name NN, presentation, strength, stock ≥0, minimum_stock ≥0, active | lectura auth; INSERT/UPDATE admin (sin columna `stock`) | 0 |
| `prescriptions` | id, prescription_code `='REC-…'` UNIQUE, encounter_id NN, issued_at, status ∈ {pendiente, parcial, entregada, anulada} | INSERT `encounter_doctor`; lectura: paciente, médico tratante o admin | 0 |
| `prescription_items` | id, prescription_id NN, medication_id NN, dose >0, dose_unit NN, frequency_hours >0, route ∈ {oral, inyectable}, quantity >0, duration_days 1–365, observations | INSERT médico si la receta está pendiente | 0 |
| `prescription_dispenses` | id, prescription_item_id NN, quantity >0, dispensed_by NN, dispensed_at | solo RPC `dispense_item` (admin) | 0 |
| `inventory_movements` | id bigint ident, medication_id NN, quantity_delta ≠0, reason NN, actor_id NN, created_at | **sin grants ni políticas**; solo RPC | 0 |

### 3.9 Transporte sanitario (ADMIN opera; R, M y P solicitan o leen)

| Tabla | Columnas clave | Reglas | Filas |
|---|---|---|---|
| `ambulances` | id smallint (secuencia `ambulance_panel_id_seq`), code UNIQUE, plate (UNIQUE `lower`), status ambulance_state, active, operational_notes | lectura auth; trigger `panel_fleet_audit` | 1 |
| `ambulance_requests` | id, patient_id, requester_id, contact_name NN, contact_phone NN, pickup_location NN, destination, reason NN, priority ∈ {normal, urgente}, status dispatch_state `='pendiente'`, requested_at, request_key (UNIQUE con requester), decision_reason | INSERT: paciente propio, recepción, admin o médico tratante; trigger `panel_transport_audit` | 0 |
| `ambulance_dispatches` | id, request_id UNIQUE, ambulance_id NN, assigned_staff_id, dispatched_at, departed_at, arrived_at, controls_checked_at, completed_at/by, completion_notes | un despacho activo por ambulancia y por conductor | 0 |
| `ambulance_status_history` | id ident, ambulance_id, old/new_status, actor_id, changed_at | lectura admin | 0 |
| `emergency_logs` | id ident, request_id NN, event_type NN, description, actor_id, occurred_at | lectura admin/recep | 0 |

### 3.10 Comunicación y auditoría

| Tabla | Columnas clave | Reglas | Filas | Módulos |
|---|---|---|---|---|
| `notifications` | id, recipient_id NN → profiles, title, body, kind NN, read_at, created_at, entity_type, entity_id, event_key | UNIQUE parcial (recipient, event_key); RLS propio; UPDATE solo de `read_at` | 16 | A R M |
| `announcements` | id, title, content, published_at, expires_at, is_public, created_by | lectura anon/auth si es pública y vigente; escritura admin | 0 | A (P potencial) |
| `audit_logs` | id ident, actor_id, action NN, entity_type NN, entity_id, metadata jsonb, occurred_at | lectura admin; se escribe desde RPC y la Edge Function | 121 | A |

### 3.11 Esquema `private`

`private.appointment_queue_counters(doctor_id uuid, queue_date date, last_number int)`: RLS activado y sin políticas (correcto, uso interno del trigger de turnos).

---

## 4. Índices no derivados de constraints

| Tabla | Índice | Definición |
|---|---|---|
| admission_assessments | admission_assessment_doctor_queue | (doctor_id, requested_at) WHERE pending |
| admission_assessments | one_pending_admission_assessment | UNIQUE (patient_id) WHERE pending |
| ambulance_dispatches | one_active_transport_per_driver | UNIQUE (assigned_staff_id) WHERE abierto |
| ambulance_dispatches | only_one_active_dispatch | UNIQUE (ambulance_id) WHERE completed_at IS NULL |
| ambulance_requests | ambulance_request_retry | UNIQUE (requester_id, request_key) |
| ambulance_requests | ambulance_requests_status_idx | (status, requested_at); sin uso |
| ambulances | ambulance_plate_unique | UNIQUE lower(plate) |
| appointment_requests | …_requester_created_idx / …_status_idx | (requester_id, created_at DESC) / (status, created_at) |
| appointments | appointments_doctor_start_idx / …_patient_start_idx | (doctor_id, starts_at) / (patient_id, starts_at) |
| bed_assignments | one_active_bed_patient / one_active_patient_bed | UNIQUE bed / patient WHERE released_at IS NULL |
| clinical_encounters | clinical_encounters_record_idx | (record_id) |
| doctor_schedules | planning_schedule_assignment_idx / planning_schedule_doctor_idx | assignment / (doctor, vigencia) WHERE active |
| hospital_admissions | admission_request_retry / hospital_admissions_status_idx / one_active_admission_per_patient | UNIQUE (ordered_by, request_key) / (status, ordered_at) / UNIQUE patient WHERE estado activo |
| lab_orders | lab_orders_encounter_idx / lab_request_group_exam | (encounter_id) / UNIQUE (encounter, group, test) |
| notifications | notification_event_once / notifications_recipient_time / notifications_unread_recipient | UNIQUE (recipient, event_key) / (recipient, created_at DESC) / (recipient) WHERE no leído |
| patients | patients_name_idx | lower(apellido, nombre); sin uso |

Además, cada PK y UNIQUE tiene su índice, y cada EXCLUDE su índice GiST (§3).

---

## 5. RLS y privilegios

### 5.1 Estado de RLS

Las **52 tablas de `public` tienen RLS activado** y ninguna lo fuerza (`FORCE`). Hay **tres tablas con RLS y sin políticas**, accesibles solo por RPC: `admission_assessments`, `staff_recurring_journeys` e `inventory_movements`. Todas las políticas son `PERMISSIVE`. La lista completa por tabla figura en §3; estas son las reglas transversales:

- **Catálogos** (specialties, symptom_catalog, lab_test_types, rooms, hospital_floors, beds y announcements públicos): lectura `anon` y `authenticated`, filtrada por `active` cuando procede; escritura solo admin.
- **Planificación** (staff_shifts, staff_absences, doctor_schedules, doctor_consulting_rooms): CRUD admin; lectura del propio empleado; recepción lee horarios y consultorios.
- **Datos clínicos**: se apoyan en `can_read_patient`, `treats_patient`, `owns_clinical_note` y `encounter_doctor`; las notas y los diagnósticos son visibles para el paciente **solo tras el cierre** de la consulta.
- **Laboratorio**: `lab_permission('any')` (solo admin) o publicación validada.
- **Notificaciones**: solo el destinatario.

### 5.2 Privilegios de tabla para `anon` y `authenticated` (S=SELECT, I=INSERT, U=UPDATE, D=DELETE)

| Tabla | anon | authenticated |
|---|---|---|
| announcements, consulting_rooms, doctor_consulting_rooms, doctor_schedules, doctor_specialties, lab_test_types, specialties, staff_absences, staff_shifts, symptom_catalog | S en catálogos públicos / — | S,I,U,D (limitado por RLS a admin) |
| **hospital_settings, lab_result_drafts, laboratory_authorizations, panel_preferences** | **S,I,U,D** ⚠ | S,I,U,D |
| ambulance_requests, appointment_request_symptoms, appointment_requests, medical_history, vital_signs | — | S,I |
| medications | — | S,I + UPDATE de columnas (name, presentation, strength, minimum_stock, active) |
| notifications | — | S + UPDATE(read_at) |
| patients | — | S + UPDATE(first_name, last_name, dui, phone, birth_date, city) |
| profiles | — | S + UPDATE(phone, city) |
| beds, rooms, hospital_floors | S | S |
| admission_assessments, inventory_movements, staff_recurring_journeys | — | **ninguno** |
| resto | — | S |

---

## 6. Funciones RPC (`public`)

**Comunes a todas**: `SECURITY DEFINER`, `search_path=""`, `EXECUTE` para `authenticated` y `service_role`, **sin `EXECUTE` para `anon`** (comprobado en las 89 funciones del advisor). Por eso todas aparecen en el aviso `authenticated_security_definer_function_executable`, que es intencionado porque cada función valida rol o vínculo por dentro. Excepción: `delete_staff_consulting_room`, `save_staff_planning` y `save_staff_planning_set` son `SECURITY INVOKER`.

Columnas: **Guarda** = control interno detectado en el cuerpo. **Escribe** = tablas afectadas por INSERT, UPDATE o DELETE directo (los efectos de triggers no se listan).

### 6.1 Paciente iOS (rol `paciente`)
| Función | Argumentos → retorno | Guarda | Escribe |
|---|---|---|---|
| my_attention_context | () → jsonb | paciente | — |
| submit_my_attention_request | (p_key uuid, p_specialty bigint, p_period text, p_reason text, p_symptoms bigint[], p_other text, p_missing jsonb) → uuid | paciente | appointment_requests, appointment_request_symptoms, profiles |
| my_attention_requests | () → jsonb | paciente | — |
| my_consultation_history | (p_from, p_to timestamptz, p_cursor jsonb) → jsonb | paciente + expediente propio | — |
| **register_patient** | (p_dui, p_phone, p_city text) → uuid | paciente + correo confirmado | patients, medical_records, audit_logs. **⚠ H2: debería estar revocada** |

### 6.2 Médico iOS (`native_doctor_id()` / `native_doctor_encounter()`: rol doctor + staff activo con `category='doctor'`)
| Función | Argumentos → retorno | Escribe |
|---|---|---|
| doctor_native_workspace | (p_from, p_to timestamptz) → jsonb | — (⚠ H3: deriva) |
| doctor_native_alerts | (p_offset int) → jsonb | notifications (marca leídas) |
| doctor_native_patients | (p_query text, p_offset int) → jsonb | — |
| doctor_native_chart | (p_patient uuid, p_from, p_to timestamptz, p_query text) → jsonb | — |
| doctor_native_start | (p_appointment uuid, p_key uuid) → uuid | clinical_encounters |
| doctor_native_save | (p_encounter uuid, p_version int, p_key uuid, p_values jsonb) → int | clinical_encounters, diagnoses, vital_signs |
| doctor_native_finish | (p_encounter uuid, p_version int) → void | clinical_encounters, audit_logs |
| doctor_native_prescribe | (p_encounter uuid, p_key uuid, p_lines jsonb) → uuid | prescriptions, prescription_items |
| doctor_native_lab | (p_encounter uuid, p_test bigint, p_reason text, p_key uuid) → uuid | lab_orders |
| doctor_native_labs | (p_encounter uuid, p_tests bigint[], p_reason text, p_key uuid) → jsonb | lab_orders |
| doctor_native_lab_catalog | () → jsonb | — |
| doctor_native_lab_orders | (p_offset int) → jsonb | — |
| doctor_native_patient_labs | (p_patient uuid, p_offset int) → jsonb | — |
| doctor_native_admission_request | (p_patient uuid, p_kind room_kind, p_reason, p_instructions, p_priority text, p_encounter uuid, p_key uuid) → uuid | hospital_admissions |
| doctor_native_admissions | (p_offset int) → jsonb | — |
| doctor_save_admission_assessment | (p_assessment uuid, p_version int, p_notes text) → int | admission_assessments, audit_logs |
| doctor_decide_admission_assessment | (p_assessment uuid, p_version int, p_decision text, p_notes text, p_kind room_kind, p_instructions text) → jsonb | admission_assessments, care_team_assignments, notifications, audit_logs |
| admission_assessment_context | (p_patient uuid, p_offset int) → jsonb | — (también admin y recepción) |
| medical_discharge | (p_admission uuid, p_notes text) → void | hospital_admissions |
| request_admission | (p_patient uuid, p_kind room_kind, p_reason, p_instructions text, p_encounter uuid) → uuid | hospital_admissions (variante anterior sin idempotencia) |
| request_medical_transport | (p_patient uuid, p_contact, p_phone, p_origin, p_destination, p_reason, p_priority text, p_key uuid) → uuid | ambulance_requests (también recepción y admin) |
| update_appointment_status | (p_id uuid, p_state appointment_state) → void | appointments, appointment_status_history (también recepción y admin) |
| get_medical_availability | (p_from, p_until timestamptz, p_doctor, p_room uuid) → TABLE | — (admin, doctor, recepción) |

### 6.3 Recepción (rol `recepcionista`; admin también)
| Función | Argumentos → retorno | Escribe |
|---|---|---|
| reception_agenda | (p_day date) → TABLE(id, request_id, patient_id, starts_at, ends_at, status, consulting_room_id, doctor_id, patient_name, doctor_name, room_code) | — |
| reception_doctor_day | (p_doctor uuid, p_day date) → jsonb | — |
| review_attention_request | (p_request uuid, p_status request_state) → void | appointment_requests |
| close_attention_request | (p_request uuid, p_status request_state, p_reason text) → void | appointment_requests |
| link_attention_patient | (p_request, p_patient uuid, p_identity_confirmed bool) → void | appointment_requests, patients |
| create_attention_patient | (p_request uuid, p_identity_confirmed bool) → uuid | patients/expediente (vía lógica interna) |
| create_walkin_patient | (p_first, p_last, p_dui, p_phone text, p_birth date, p_city text) → uuid · **sobrecarga** con `p_email text` | patients (+ medical_records y audit_logs en la versión con email) |
| reception_walkin_attention | (p_patient uuid, p_key uuid, p_values jsonb) → jsonb | appointment_requests, hospital_admissions, audit_logs |
| schedule_appointment | (p_patient, p_doctor, p_room uuid, p_start, p_end timestamptz, p_request uuid) → uuid | appointments, appointment_status_history, appointment_requests |
| cancel_appointment | (p_id uuid, p_reason text) → void | appointments, appointment_status_history |
| reception_admissions | (p_offset int, p_status text) → jsonb | — |
| reception_admission_availability | (p_admission uuid) → jsonb | — |
| reception_hospital_detail | (p_admission uuid) → jsonb | — |
| reception_hospital_inventory | () → jsonb | — |
| reception_review_admission | (p_admission uuid) → void | hospital_admissions, audit_logs |
| reception_resolve_admission | (p_admission uuid, p_action text, p_reason text, p_bed uuid) → void | hospital_admissions |
| reception_request_admission_assessment | (p_patient, p_doctor uuid, p_reason, p_priority text, p_key uuid) → uuid | admission_assessments, care_team_assignments, notifications, audit_logs |
| assign_bed | (p_admission, p_bed uuid) → uuid | bed_assignments, beds, bed_status_history, hospital_admissions |
| release_bed | (p_admission uuid) → void | ídem |
| complete_hospital_bed_cleaning | (p_bed uuid) → void | beds, bed_status_history |
| panel_transport_data | (p_offset int, p_status text, p_request uuid) → jsonb | — |
| my_panel_profile / save_my_panel_profile | () → jsonb / (p_phone, p_city, p_version, p_first, p_last text, p_birth date) → void | profiles, audit_logs |
| my_panel_notifications / read_panel_notification | (p_offset int) → jsonb / (p_id uuid) → void | notifications |
| my_panel_preferences | (p_values jsonb) → jsonb | panel_preferences |
| panel_institution | () → jsonb | — |
| reception_release_lab | (p_order uuid) → void | lab_results, lab_result_drafts, lab_delivery_events. **Guarda real: `lab_permission`, solo admin** |

### 6.4 ADMIN (rol `admin`)
| Ámbito | Funciones |
|---|---|
| Personal y roles | `set_employee_role(p_user, p_role, p_active)`, `upsert_staff(p_profile, p_code, p_category)` → staff. Las invoca la Edge Function `manage-employees` |
| Planificación | `read_staff_planning(p_from, p_until)`, `save_staff_planning(p_kind, p_values, p_id, p_version)`, `save_staff_planning_set(p_role, p_kind, p_values, p_originals)`, `delete_staff_consulting_room(p_id, p_version)`, `save_recurring_journey(p_values, p_id, p_version, p_key)`, `save_recurring_journey_scope(…, p_weekday, p_originals, p_preview)` |
| Infraestructura | `save_hospital_room`, `save_hospital_bed`, `set_bed_state`, `save_hospital_settings` |
| Laboratorio (`lab_permission`) | `laboratory_panel`, `laboratory_order_detail`, `my_laboratory_access`, `configure_laboratory_test`, `start_laboratory_order`, `save_laboratory_draft`, `submit_laboratory_validation`, `validate_laboratory_result`, `complete_laboratory_exam`, `publish_laboratory_order`, `publish_lab_result`, `correct_laboratory_result` |
| Transporte | `review_medical_transport`, `assign_medical_transport`, `dispatch_ambulance`, `progress_medical_transport`, `finish_medical_transport`, `complete_dispatch`, `save_panel_ambulance` |
| Farmacia | `add_inventory`, `dispense_item` |
| Deshabilitadas (lanzan 42501 siempre) | `authorize_laboratory_staff`, `authorize_panel_driver` |

### 6.5 Funciones internas (`private`, sin EXECUTE para clientes salvo los helpers de RLS)

Triggers: `auth_new_user`, `protect_profile`, `attention_request_owner`, `assign_appointment_queue`, `clinical_*_guard`, `native_complete_guard`, `doctor_appointment_notice`, `panel_clinical_notice`, `panel_fleet_audit`, `panel_transport_audit`, `native_admission_audit`, `hospital_inventory_audit`, `laboratory_notifications`, `audit_laboratory_order_state`, `lab_result_audit`, `protect_laboratory_schema`, `planning_lock` y `planning_guard`.

Utilidades: `assert_staff_planning`, `planning_valid_slot`, `planning_medical_coverage`, `recurring_*` (windows, work, offset, instant, legacy_*), `journey_weekday_set`, `lab_check_payload`, `lab_render_summary`, `validate_lab_schema`, `emit_panel_notice`, `native_admission_rows`, `native_mobile_lab_page` y `attention_specialty_available`.

`auth_new_user`, `protect_profile` y `journey_weekday_set` conservan `EXECUTE` para PUBLIC. Como `anon` no tiene USAGE sobre `private` y las dos primeras son funciones de trigger, el riesgo es bajo.

---

## 7. Triggers

| Tabla | Trigger | Momento | Función |
|---|---|---|---|
| auth.users | on_auth_user_created | AFTER INSERT | private.auth_new_user |
| profiles | protect_profile | BEFORE UPDATE | private.protect_profile |
| appointment_requests | attention_request_owner | BEFORE INSERT | attention_request_owner |
| appointment_requests | panel_attention_notice | AFTER INSERT | panel_clinical_notice |
| appointments | appointment_queue_assignment | BEFORE INSERT/UPDATE OF doctor_id, starts_at, queue_* | assign_appointment_queue |
| appointments | clinical_appointment_identity_guard | BEFORE UPDATE OF patient_id, doctor_id | clinical_parent_identity_guard |
| appointments | doctor_appointment_notice | AFTER INSERT/UPDATE OF doctor_id, starts_at, status | doctor_appointment_notice |
| appointments | native_complete_guard | BEFORE UPDATE OF status → completada | native_complete_guard |
| medical_records | clinical_record_identity_guard | BEFORE UPDATE OF patient_id | clinical_parent_identity_guard |
| clinical_encounters | clinical_encounter_identity_guard | BEFORE INSERT/UPDATE OF record_id, doctor_id, appointment_id | clinical_encounter_identity_guard |
| vital_signs | clinical_vitals_write_guard | BEFORE INSERT/UPDATE | clinical_vitals_write_guard |
| hospital_admissions | native_admission_audit · panel_admission_notice | AFTER INSERT/UPDATE OF status | native_admission_audit · panel_clinical_notice |
| beds · rooms | hospital_*_inventory_audit | AFTER INSERT/UPDATE | hospital_inventory_audit |
| lab_orders | laboratory_new_order_notice · laboratory_state_history | AFTER INSERT · AFTER INSERT/UPDATE OF status | laboratory_notifications · audit_laboratory_order_state |
| lab_results | laboratory_published_notice · laboratory_result_audit | AFTER INSERT/UPDATE | laboratory_notifications · lab_result_audit |
| lab_result_drafts | laboratory_draft_audit | AFTER INSERT/UPDATE | lab_result_audit |
| lab_test_types | laboratory_schema_guard | BEFORE INSERT/UPDATE | protect_laboratory_schema |
| ambulances · ambulance_requests | panel_fleet_audit · panel_transport_audit | AFTER INSERT/UPDATE | ídem |
| appointments, consulting_rooms, doctor_consulting_rooms, doctor_schedules, staff, staff_absences, staff_shifts, user_roles, staff_recurring_journeys | planning_lock (BEFORE, por sentencia) + planning_guard / recurring_journey_guard (CONSTRAINT AFTER, DEFERRABLE INITIALLY DEFERRED, por fila) | | planning_lock · planning_guard |

Todos están habilitados (`tgenabled='O'`). Los triggers de `storage.*` y `realtime.subscription` son los propios de la plataforma.

---

## 8. Edge Functions

| Slug | Estado | Versión | verify_jwt | Módulo |
|---|---|---|---|---|
| `manage-employees` | ACTIVE | 8 (contrato `employees-2026-11-registration-v4`) | **false** (valida el Bearer manualmente con `auth.getUser`) | ADMIN |

- **Acciones:** `contract`, `catalogs`, `pending`, `list`, `detail`, `create`, `recover`, `update` y `state`. `delete` está retirada (410).
- **Autorización:** `user_roles(role='admin', active)`. Se vuelve a comprobar con `FOR SHARE` dentro de la transacción. No permite modificar administradores ni al propio usuario.
- **Alta:** `auth.admin.createUser` con `email_confirm:true` y la cuenta bloqueada (`ban_duration` de 100 años, `employee_pending`). En una transacción SQL: `profiles`, `set_employee_role`, `upsert_staff`, `doctor_specialties`, más una lectura de verificación. Después desbloquea la cuenta. Recuperación idempotente mediante `recover`.
- **Desactivar:** comprueba el impacto (citas, pacientes y encuentros abiertos) y pide confirmación. Bloquea Auth, guarda los roles previos en `app_metadata` y desactiva los roles laborales (no `paciente`).
- **Secretos usados:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `SUPABASE_DB_URL` (conexión `postgres` directa). Los valores no se consultaron.
- **CORS:** `Access-Control-Allow-Origin: *`.
- **⚠ H1:** la contraseña inicial es constante. Se devuelve en la respuesta como `credentials.password`.

---

## 9. Migraciones registradas (`supabase_migrations.schema_migrations`)

| Versión | Nombre | Archivo local equivalente |
|---|---|---|
| 20261113083916 | staff_planning_and_consulting_availability | — |
| 20261113091001 | fix_staff_planning_days_roles_and_room_management | — |
| 20261113091725 | preserve_saved_dates_when_editing_staff_planning | — |
| 20261113165229 | disable_patient_self_enrollment | — (revoca `register_patient`) |
| 20261113181043 | account_owned_attention_requests | `supabase/attention-account.sql` (hash coincidente) |
| 20261113181429 | attention_owner_validation | `supabase/attention-validation.sql` (hash coincidente) |
| 20261113185224 | appointment_queue_by_doctor_day | — |
| 20261113190740 | reception_attention_workflow | — |
| 20261113190914 | reception_operational_context | — |
| 20261113204024 | doctor_native_clinical_flow_v1 | `supabase/doctor-ios.sql` (⚠ `doctor_native_workspace` difiere) |
| 20261113210758 | doctor_patient_directory_v1 | `supabase/doctor-patient-directory.sql` |
| 20261113234931 | doctor_admission_requests_v1 | `supabase/doctor-admissions.sql` (dos funciones sustituidas después) |
| 20261114000935 | hospitalization_reception_control | — (redefine `reception_admissions` y `reception_admission_availability`) |
| 20261114024046 | panel_settings_profiles_notifications | — (crea `hospital_settings` y `panel_preferences`) |
| 20261114024313 | panel_ambulance_operations | — |
| 20261114032541 | laboratory_clinical_workflow | — (crea `lab_result_drafts` y `laboratory_authorizations`) |
| 20261114032545 | laboratory_panel_ios_visibility | — |
| 20261114042355 | doctor_laboratory_multiple_v1 | `supabase/doctor-laboratory-multiple.sql` |
| 20261114044858 | laboratory_guided_completion | — |
| 20261114050734 | admin_laboratory_transport | — (redefine `lab_permission` como solo admin) |
| 20261114051025 | admin_laboratory_notifications | — |
| 20261114061016 | clinical_write_integrity_v1 | `supabase/clinical-write-integrity.sql` (hash coincidente) |
| 20261114062258 | reception_walkin_attention | — |
| 20261114073527 | reception_walkin_contact | — |
| 20261114075102 | presential_admission_assessment | — (crea `admission_assessments`) |
| 20261119020326 | recurring_staff_journeys | — (crea `staff_recurring_journeys`) |
| 20261119042607 | recurring_weekday_editing | — |
| 20261119052813 | walkin_patient_registration | — (**vuelve a conceder `register_patient` a authenticated**, H2) |
| 20261119055931 | walkin_adult_locality_validation | — |
| 20261119182927 | doctor_consultation_experience_v1 | `supabase/doctor-consultation-experience.sql` (hash coincidente) |
| 20261119183231 | patient_completed_consultation_history_v1 | `supabase/patient-consultation-history.sql` (hash coincidente) |

Las 46 tablas restantes de `public` (profiles, patients, appointments, etc.) **no se crean en ninguna migración registrada**: forman parte del esquema base previo a la primera migración. Las 6 tablas creadas por migraciones son `hospital_settings`, `panel_preferences`, `lab_result_drafts`, `laboratory_authorizations`, `admission_assessments` y `staff_recurring_journeys`.

---

## 10. Realtime y Storage

- **Realtime:** la publicación `supabase_realtime` existe (insert, update y delete activos, `alltables=false`) con **0 tablas**, y hay **0 políticas** en `realtime.*`. Los clientes actualizan por **sondeo**: `panel_preferences.poll_seconds` (30, 60 o 120) en los paneles y 30 s para los avisos del médico. No conviene presentar ningún cambio como "en tiempo real" sin añadir antes tablas a la publicación.
- **Storage:** **0 buckets, 0 objetos y 0 políticas** en `storage.objects`. No hay adjuntos de laboratorio ni imágenes de perfil almacenados.

---

## 11. Diferencias entre lo desplegado y los SQL locales

Método: MD5 del cuerpo de cada función eliminando todos los espacios. Se comparan los 9 archivos de `supabase/` que no son pruebas con `pg_proc.prosrc`.

| Objeto | Local | Desplegado | Conclusión |
|---|---|---|---|
| 37 de 42 definiciones locales: attention-account (7/7), attention-validation (2/2), clinical-write-integrity (3/3), doctor-admissions (6/8), doctor-ios (8/10), doctor-laboratory-multiple (5/5), doctor-patient-directory (2/3), doctor-consultation-experience (3/3) y patient-consultation-history (1/1) | = | = | **Coinciden** |
| `public.doctor_native_chart` | `doctor-ios.sql` ≠ | = `doctor-patient-directory.sql` | Sustituida por un archivo posterior: correcto |
| `public.doctor_native_patient_labs` | `doctor-patient-directory.sql` ≠ | = `doctor-laboratory-multiple.sql` | Sustituida por un archivo posterior: correcto |
| `public.reception_admissions`, `public.reception_admission_availability` | `doctor-admissions.sql` ≠ | redefinidas por la migración 20261114000935 | El archivo local está **desactualizado**; no hay copia local de la versión vigente |
| **`public.doctor_native_workspace`** | `doctor-ios.sql` (cab01a2f…) | 8cdfedb0…; migración 20261113204024: 27c2fc20… | **Las tres versiones difieren** → cambio fuera del historial de migraciones (H3). Revisar antes de tocarla |
| `register_patient` (grants) | sin archivo local | `GRANT` a authenticated (20261119052813) | Contradice AGENTS.md (H2) |
| Tablas base, políticas RLS, enums y la mayoría de las RPC de ADMIN y Recepción | **sin archivo local** | desplegadas | La fuente de verdad es Supabase y este diccionario |

Los archivos `supabase/test-*-rollback.sql` son pruebas con `ROLLBACK` y no definen objetos persistentes. `.local/` contiene SQL históricos que **no deben aplicarse** (AGENTS.md).

---

## 12. Recomendaciones (sin aplicar; requieren autorización expresa)

1. **H1:** generar en `manage-employees` una contraseña aleatoria criptográfica por alta (`crypto.getRandomValues`), obligar a cambiarla en el primer acceso y rotar las credenciales de los empleados creados con la constante.
2. **H2:** decidir si `register_patient` debe volver a revocarse (`REVOKE EXECUTE … FROM authenticated`) según la decisión vigente, o actualizar AGENTS.md si el cambio del 19/11 fue intencionado. No se modificó nada.
3. **H3:** exportar el cuerpo vigente de `doctor_native_workspace` a un archivo local versionado antes de cualquier cambio.
4. **H4:** `REVOKE ALL … FROM anon` en las cuatro tablas señaladas.
5. **H5:** documentar que laboratorio es solo ADMIN, o conectar `laboratory_authorizations` si se va a delegar.
6. **H6:** activar la protección contra contraseñas filtradas en Auth.
7. **H9:** índices de FK y `(select auth.uid())` en las políticas cuando crezca el volumen.
