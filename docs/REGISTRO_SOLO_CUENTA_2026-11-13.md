# Registro exclusivo de cuenta — 13 de noviembre de 2026

## Decisión y comportamiento vigente

Por instrucción expresa del usuario, registrarse solo crea la cuenta Auth, su perfil y el rol paciente asignado por el trigger existente. No crea fila de paciente, expediente ni cita. Los metadatos del usuario nunca autorizan roles ni vinculan expedientes. Se conservan los campos personales del formulario; el DUI es una declaración en metadatos editables, no identidad clínica verificada.

iOS y web dejan de llamar a `register_patient`. Cuando Auth devuelve sesión, consultan el acceso y muestran **Cuenta registrada** si no existe vínculo clínico. La pantalla explica que recepción registra o vincula el expediente y ofrece actualizar estado/cerrar sesión. No contiene formulario para crear expediente. Al volver a iniciar sesión mantiene ese estado. Los pacientes previamente vinculados conservan los módulos actuales y pueden enviar solicitudes de atención; recepción programa las citas.

No se implementó un mecanismo nuevo para vincular cuentas desde recepción. Se conserva `create_walkin_patient`, que crea paciente/expediente para personal autorizado; la vinculación de ese paciente a una cuenta debe resolverse con el flujo autorizado de recepción. No se vincula por correo ni DUI automáticamente. No se modificó la aplicación de recepción.

## Cambio remoto aplicado

En Hospital Móviles (`uvebpsbbwofthucghccc`) se aplicó la migración `disable_patient_self_enrollment` mediante el conector Supabase:

```sql
REVOKE EXECUTE ON FUNCTION public.register_patient(text,text,text)
FROM PUBLIC, anon, authenticated;
```

La consulta real posterior con `has_function_privilege` devuelve false para anon/authenticated y true para service_role. Se mantienen ejecutables las RPC de recepción `create_walkin_patient` y `schedule_appointment`, cuyos cuerpos verificados exigen recepcionista/admin. Las tablas patients, medical_records y appointments solo conceden SELECT a authenticated: no permiten inserciones directas del cliente. No se alteraron RLS, datos clínicos ni cuentas existentes.

## Correo

La petición HTTPS real a `/auth/v1/settings` devolvió `disable_signup=false` y **`mailer_autoconfirm=true`** en esta intervención. Por tanto, la configuración remota actual no exige confirmación de correo. No se atribuye este ajuste al conector: sus herramientas disponibles no ofrecen edición de Auth y no se envió una solicitud administrativa para cambiarlo. Se verificó el estado efectivo, que difiere del observado en la revisión anterior.

Si Auth volviera a devolver signup sin sesión, los clientes informan de la discrepancia y no simulan acceso. No se confirman cuentas antiguas por SQL ni se alteran masivamente usuarios. Un fallo de lectura tras signup permite recuperar el acceso por login, sin duplicar cuentas.

Documentación oficial consultada: [configuración de Auth](https://supabase.com/docs/guides/auth/general-configuration) y [API administrativa de configuración](https://supabase.com/docs/reference/api/v1-update-auth-service-config).

## Rutas y verificación

- iOS: `Auth/RegisterView.swift`, `ContentView.swift`, `Core/HospitalStore.swift`, `Core/HospitalAPI.swift`, núcleo compartido y prueba nativa de rechazo del alta clínica.
- Web: `app.js`, `api.js`; transporte de pruebas deja de simular creación de paciente.
- Regresión: `test-core`, `test-preview` y `test-patient-registration` aprobados con transporte simulado. Registro sin confirmación, doble envío, cuenta sin expediente, restauración por login, actualización, cero escrituras REST clínicas, recuperación de fallo de lectura, configuración discrepante y solicitudes de pacientes vinculados. Durante la adaptación se corrigieron selectores/eventos del test de solicitudes; la repetición final pasó.
- `check-project.py` aprobado: estructura portable y correspondencia de configuración; no compila Swift. Prueba nativa añadida, pendiente de Xcode.
- Sintaxis JS de app.js/api.js y `git diff --check` aprobados.
- HTTPS real aprobado: Auth y rechazo anónimo 401 de perfiles/pacientes/roles. Sin altas de prueba en producción.
- Asesores de seguridad consultados: avisos existentes de SECURITY DEFINER en 18 RPC, extensión btree_gist en public, protección de contraseñas filtradas deshabilitada y RLS sin política en inventory_movements. No se ampliaron permisos ni se modificaron esos módulos.

Pendientes: compilar/probar SwiftUI en Mac, revisión visual, recorrido con una identidad autorizada y validación operativa de recepción/vinculación. No se ejecutó un registro completo real ni se crearon cuentas/pacientes/citas para comprobarlo.
