# Solicitante sin expediente: frontend iOS y vista previa web (2026-11-12)

**Alcance:** cambios locales de interfaz. No modifican Supabase, migraciones, configuración de Auth ni permisos. El registro y las solicitudes **no están conectados** a RPC reales. El borrador SQL permanece en `docs/sql/drafts/`, separado y pendiente de revisión del responsable del backend.

## Qué se implementó

| Requisito | Implementación |
|---|---|
| Edad → fecha de nacimiento | Registro y datos personales usan fecha de nacimiento (iOS: `DatePicker`; web: `input type=date`). La edad se calcula en el núcleo compartido. |
| Validación y formato del DUI | `HospitalCore.formatDui` y `validatePersonalData`. Formato `0000-00000` mientras se escribe. Idéntico en iOS y web porque ambos usan `hospital-core.js`. |
| Pantalla de completar datos | Nombres, apellidos, DUI, fecha de nacimiento y teléfono. iOS: `ApplicantCompleteDataView`; web: `completeForm`. |
| Navegación del solicitante | Inicio, Solicitar, Mis solicitudes y Salir. iOS: `ApplicantDemoView`; web: `applicant.js` (`nav`). |
| Formulario sin citas | Especialidad, motivo, fecha preferida y preferencia Mañana/Tarde obligatoria. Envía a estado Pendiente local y muestra «Una solicitud no es una cita». No existe ninguna ruta que genere cita. |
| Estados visuales | Pendiente, En revisión, Aceptada, Rechazada, Cita programada (ver tabla abajo). |
| Sincronía SwiftUI / web | Reglas y estados en `Shared/hospital-core.js`. Vistas paralelas. |
| Datos simulados identificados | Todo muestra «ejemplo» o «demostración». El avance de estados es un botón de ejemplo. |
| Transportes simulados | No hay llamadas de red en la vista de solicitante. |

## Estados: interfaz frente a backend

| Estado de interfaz | Clave | Valor real del backend | Notas |
|---|---|---|---|
| Pendiente | `pending` | `attention_requests.status = 'pending'` | Solicitud creada; no es cita. |
| En revisión | `review` | `status = 'identity_verified'` | Recepción verificó identidad. |
| Aceptada | `accepted` | `status = 'converted'` sin cita programada | Solicitud formal creada; falta programar cita. |
| Cita programada | `scheduled` | `status = 'converted'` **y** `appointment_requests.status = 'scheduled'` | Solo se deriva; no se guarda en la solicitud. |
| Rechazada | `rejected` | `status = 'rejected'` | Requiere motivo. |
| Cancelada | `cancelled` | `status = 'cancelled'` | Requiere motivo. |
| Estado no disponible | `unknown` | Cualquier otro valor | Aviso neutral; no inventa estado. |

Regla: una cita `pending` dentro de una solicitud `converted` se muestra como **Aceptada**, no como programada.

## Archivos modificados y creados

### Núcleo compartido
- `HospitalUniversitario/HospitalUniversitario/Shared/hospital-core.js`: `localIsoDay`, `isIsoDay`, `formatDui`, `applicantAge`, `validatePersonalData`, `validateApplicantProfile`, `validateAttentionRequest`, `applicantStateView`, catálogos de demostración (`applicantDemoSpecialties`, `applicantPeriods`).

### iOS (SwiftUI, sin compilar)
- `Applicant/ApplicantRules.swift` (nuevo): puente a `hospital-core.js` mediante JavaScriptCore; no usa `SharedCore` para no requerir configuración de Supabase.
- `Applicant/ApplicantDemoStore.swift` (nuevo): modelos y almacén en memoria; sin red.
- `Applicant/ApplicantDemoView.swift` (nuevo): vista del solicitante, datos personales, inicio, formulario y lista.
- `Auth/RegisterView.swift`: reescrito con fecha de nacimiento, DUI formateado, validación compartida y texto actualizado (sin confirmación de correo).
- `ContentView.swift`: estado `showApplicantDemo`, rama nueva en el acceso y enlace «Vista de diseño del solicitante» en el login. El flujo de login no cambia.
- `HospitalUniversitarioTests/ApplicantRulesTests.swift` (nuevo, Swift Testing): mismas reglas que las pruebas web.

### Vista previa web
- `web-preview/applicant.js` (nuevo): `HospitalApplicantDemo` con datos personales, inicio, solicitud, lista y avance de ejemplo.
- `web-preview/app.js`: registro con fecha de nacimiento y reglas compartidas; render del solicitante; botón «Solicitante (demo)»; cierre de la vista. La lógica de login no cambia.
- `web-preview/index.html`: botón `design-applicant` y script `applicant.js`.
- `web-preview/server.mjs`: recurso `/applicant.js` en la lista explícita.
- `web-preview/style.css`: `is-rejected`, `applicant-periods` y estado seleccionado de la preferencia.

### Pruebas
- `scripts/test-applicant.mjs` (nuevo): 5 bloques de aserciones sobre reglas, validaciones, estados, navegación y ausencia de cita.
- `scripts/test-preview.mjs`: añade el botón `design-applicant` y carga `applicant.js` en el arnés.

## Verificaciones ejecutadas

| Comprobación | Resultado |
|---|---|
| `node scripts/test-applicant.mjs` | **Aprobada** (5 bloques). |
| `node --check web-preview/applicant.js` y `app.js` | Sin errores de sintaxis. |
| `node scripts/test-core.mjs` | **Aprobada** (11 pruebas). |
| `test-preview`, `test-patient-appointments`, `test-modules`, `test-doctor-dashboard`, `test-doctor-consultations`, `test-doctor-patients`, `test-clinical-labs`, `test-patient-chart`, `test-patient-history`, `test-patient-prescriptions`, `test-profile`, `test-account-tools` | **Aprobadas** (exit 0). |
| `python scripts/check-project.py` | **Aprobado**. |
| `git diff --check` | Sin errores de espacios. Aviso informativo de finales de línea CRLF/LF en `RegisterView.swift`. |

## No verificado

- **Compilación SwiftUI y `ApplicantRulesTests`: no ejecutadas.** Windows no tiene el SDK de Apple. Requiere Xcode en Mac. Puntos a revisar al compilar: `private let rules = ApplicantRules.shared` en `RegisterView` (aislamiento de actores), `TextField(axis:)`, `DatePicker(in: ...Date())` y la inicialización de `JSContext` en el target de pruebas.
- **`test-account-codes`: falla por entorno.** Necesita `.local/test-accounts.json`, que no existe en esta copia del repositorio. No está relacionado con este cambio.
- **Recorrido visual en navegador y simulador: no realizado.**

## Decisiones E y F: bloqueadas

- **E. Código real del rol de recepción:** no se puede consultar desde esta sesión (sin acceso de lectura a la base). Pendiente: consultar `hospital.roles` con la sección 10 de la propuesta. El frontend no usa ningún código de rol.
- **F. Horarios de `period_bounds`:** pendiente de consultar la definición real. El frontend no muestra horas; solo muestra Mañana/Tarde. El borrador SQL conserva sus horarios como supuestos marcados.

## Pendiente antes de conectar

1. Consultar en Supabase las firmas y permisos (sección 10 de la propuesta) y el rol de recepción (decisión E).
2. Confirmar horarios AM/PM con recepción (decisión F).
3. Autorizar la migración y revisar el borrador con el responsable del backend.
4. Conectar `signUp`, `register_applicant`, `submit_attention_request` y `my_applicant_status` mediante una bandera de configuración, y la rama de solicitante del login.
5. Decisión C: `my_attention_requests()` para pacientes activos.
6. Compilar en Mac y revisar visualmente iOS y web.
