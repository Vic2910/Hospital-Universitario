# Registro de pacientes conectado a Supabase (DUI y teléfono)

**Fecha:** 2026-10-31 · **Solicitud:** el formulario de crear cuenta mostraba «Formulario de demostración: no se envía a la base de datos» y el campo DUI estaba mal implementado; se pidió que el registro **sí** se enviara a la base y se corrigiera el DUI.

## Decisiones del usuario

1. **Auto-registro completo:** el formulario crea la cuenta (correo + contraseña) y envía la solicitud de registro a la base; reutiliza el flujo real de Supabase.
2. **Añadir columna de DUI/teléfono al esquema:** autorizado explícitamente, aunque el esquema previo no tenía dónde guardarlos.
3. **Campo «Fecha de nacimiento»:** sustituye a «Edad», porque `hospital.persons.birth_date` es una fecha y la RPC la exige.

## Qué había antes

`Auth/RegisterView.swift` (iOS) y `renderRegister` (web) eran solo presentación: validaban en el cliente y mostraban un aviso de demostración, sin tocar Supabase. El DUI usaba el formato `0000-00000` (4-5 dígitos), cuando el DUI salvadoreño real es **`00000000-0`** (8 dígitos + dígito verificador). El formulario pedía «Edad» pero la RPC necesita `birth_date`, no capturaba el sexo administrativo (obligatorio) y no había dónde guardar DUI ni teléfono.

## Flujo real (reutiliza `public.submit_patient_registration`)

1. **`signUp(correo, contraseña)`** crea la cuenta; el trigger `hospital_auth_profile_created` deja el perfil en estado `pending`. La confirmación de correo está **desactivada en el proyecto** (decisión del usuario el 2026-10-31; se quitó en Supabase Dashboard → Authentication → Sign In / Providers → Email → «Confirm email»), por lo que el signUp ya entrega una sesión usable y no hay paso intermedio.
2. Si el signUp no entregara sesión, el formulario intenta **iniciar sesión una vez como respaldo** antes de enviar (y mostraría el error del servidor, p. ej. si la confirmación volviera a activarse).
3. Con la sesión y el perfil todavía `pending`, se envía la solicitud de registro (nombres, apellidos, fecha de nacimiento, sexo, **DUI** y **teléfono**) a la base vía `submit_patient_registration`.
4. El hospital revisa y aprueba con `review_patient_registration`; recién entonces la cuenta se activa, se crea la persona/expediente (con DUI y teléfono) y se vincula el rol `patient`.

## Cambios en Supabase (autorizados)

Migración aplicada y guardada en [`sql/registration-dui-phone-migration.sql`](sql/registration-dui-phone-migration.sql):

- `hospital.persons` y `hospital.registration_requests` reciben las columnas `dui text` y `phone text` (anulables) con CHECK de formato:
  - DUI: `^[0-9]{8}-[0-9]$` (`00000000-0`).
  - Teléfono: `^[0-9]{4}-[0-9]{4}$` (`0000-0000`).
- `private/public.submit_patient_registration` ampliadas con `p_dui text` y `p_phone text` (DEFAULT NULL; validan el formato si se envían y los almacenan en la solicitud). Se conserva la idempotencia y los códigos `PT409`/`PT422` de los envoltorios públicos.
- `private.review_patient_registration`: al aprobar, copia `dui` y `phone` de la solicitud a la nueva `hospital.persons`.

## Cambios de cliente (por duplicado: iOS fuente de verdad + réplica web)

- **iOS:** `Core/HospitalAPI.swift` (nuevos `signUp` y `submitPatientRegistration`, struct `RegistrationDraft` con la sede CENTRAL); `Core/HospitalStore.swift` (métodos `signUpForRegistration`, `signInForRegistration`, `submitRegistration`, `endRegistrationSession`, sin tocar el `busy` principal); `Auth/RegisterView.swift` (formulario con fecha de nacimiento, sexo, DUI `00000000-0`, teléfono `0000-0000`; registro en un solo paso, sin fase de confirmación desde el 2026-10-31); `ContentView.swift` (inyecta el store en `RegisterView`).
- **Web:** `web-preview/api.js` (nuevos `signUp` y `submitPatientRegistration`; mensajes claros para `email_not_confirmed` y cuenta ya existente); `web-preview/app.js` (`renderRegister`/`registerProblem` con los campos nuevos, máscaras y registro en un solo paso —sin fase de confirmación desde el 2026-10-31—, sin re-render que borre el formulario); `web-preview/style.css` (estilo del `select` de sexo en el contexto de auth).

## Verificaciones realmente ejecutadas

- **Supabase:** migración aplicada; verificación transaccional con `ROLLBACK` ([`sql/test-registration-dui-phone.sql`](sql/test-registration-dui-phone.sql)) que confirma: DUI/teléfono almacenados en el envío, idempotencia, rechazo de datos distintos (`PT409`), rechazo de formatos inválidos (`PT422`) y que la aprobación copia DUI/teléfono a `hospital.persons`. Sin datos temporales residuales (todo en `ROLLBACK`).
- **Locales:** `node --preserve-symlinks --preserve-symlinks-main scripts/test-preview.mjs` (8 recorridos + 20 pantallas + agendar cita + **2 pruebas nuevas del registro**: renderizado con máscaras y sin aviso de demostración, y envío de `submit_patient_registration` con DUI/teléfono/fecha/sexo); `python scripts/check-project.py`; `git diff --check`; suites `test-core`, `test-modules`, `test-profile`, `test-patient-appointments`, `test-patient-chart` y `test-doctor-patients` en verde.

## Supuestos y límites

- **Confirmación de correo (actualización del 2026-10-31):** el usuario pidió eliminarla y decidió desactivarla en el panel de Supabase (Authentication → Sign In / Providers → Email → «Confirm email»). El formulario ya no muestra ninguna fase de confirmación: `signUp` envía la solicitud directamente, con un respaldo de `signIn` si el signUp no entrega sesión. Mientras la desactivación no esté hecha en el panel, el servidor rechazará el envío con `email_not_confirmed` y el formulario mostrará ese mensaje. **Verificación pendiente:** repetir un registro real contra Supabase tras la desactivación (el intento de sondeo del 31 de octubre devolvió límite de envío de correos, lo que indicaba que la confirmación seguía activa en ese momento).
- **DUI/teléfono solo en el registro:** la columna y la RPC se actualizaron para el registro. El formulario de **agendar cita** muestra un DUI decorativo (`0000-00000`) que no se envía a la base (`request_appointment` no lo admite); no se tocó por estar fuera del reporte y depender de él `test-preview.mjs`.
- **Sede:** se usa la única sede activa (`hospital.facilities`, código CENTRAL) como constante en el cliente, ya que no hay una RPC pública para listarla antes de autenticar.
- La app Swift **no se compiló** en esta sesión (requiere Mac); la réplica web sí está verificada. La aprobación final y la activación de la cuenta siguen siendo una acción del hospital con permiso `patients.write` (administrator/receptionist).
