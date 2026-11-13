# Revisión funcional del frontend — 12 de noviembre de 2026

## Punto de partida y alcance

El solicitante ya tenía reglas compartidas, registro de demostración, datos personales, inicio, formulario y lista local. Los ejemplos rechazado/cancelado y el script visual también estaban en el árbol de trabajo al comenzar esta revisión. Se conservaron los cambios previos. No se modificaron Supabase, SQL, migraciones, permisos, transportes ni configuración de Auth.

## Hallazgos y correcciones de esta revisión

- El registro válido terminaba en un aviso sin continuidad. Ahora ofrece **Continuar con datos de ejemplo** en SwiftUI y web; abre **Completa tus datos** y no crea cuenta ni sesión. Se vuelven a introducir los datos en esa pantalla; no se transfieren contraseñas.
- Completar datos no ofrecía salida dentro de la vista iOS: se añadió **Salir de la demostración** en ambas plataformas antes de guardar.
- Se explicitó `@MainActor` en RegisterView y ApplicantDemoView, y `Combine` en el store observable. El acceso a `ApplicantRules.shared` del registro es calculado, evitando inicializarlo como propiedad almacenada fuera del actor.
- El puente Swift podía devolver validación exitosa si faltaba el recurso JavaScript o una función no estaba disponible. Ahora muestra error y bloquea el envío en ese caso.
- La tarjeta SwiftUI colocaba especialidad y badge en una misma fila: ahora se apilan para admitir texto largo y tamaños pequeños. Web incorpora ajuste de texto, controles de formulario con ancho limitado y botones de navegación/preferencia de al menos 44 px. Las etiquetas Especialidad/Motivo están vinculadas a sus controles.
- Los ejemplos de rechazada/cancelada ya presentes se comprobaron: ambos muestran motivo, estado y aviso de ejemplo/no cita. El avance hasta Cita programada sigue siendo exclusivamente una simulación identificada.
- El script visual tenía un error secundario al no encontrar DevTools y saltaba del registro mediante el botón externo. Ahora informa el bloqueo y usa la continuación del registro. Se separó además su caso de DUI inválido del caso de nacimiento futuro.

## Pruebas ejecutadas en esta intervención

Todas las pruebas siguientes terminaron con código 0. Se ejecutaron con Node y los flags `--preserve-symlinks --preserve-symlinks-main`:

| Script | Cobertura |
|---|---|
| `scripts/test-applicant.mjs` | Formato DUI, edad, fechas inexistentes/futuras, datos vacíos, DUI/teléfono incorrectos, correo, longitud/confirmación de contraseña; completar datos → inicio → solicitar → lista; preferencia obligatoria, todos los estados, motivos, salida y limpieza local. |
| `scripts/test-preview.mjs` | Ocho recorridos y veinte pantallas; login doctor/patient/doble rol, rechazo de suspendidos, navegación, sesión, resumen protegido y diseño sin API. |
| `scripts/test-core.mjs` | Once pruebas de roles, contratos, intervalos, transporte Auth simulado, renovación, credenciales inválidas y logout. |
| `scripts/test-modules.mjs` | Siete recorridos de módulos: solicitud, cancelación, notificaciones, consulta, receta y cierre con transporte simulado. |
| `test-patient-appointments`, `test-patient-chart`, `test-patient-history`, `test-patient-prescriptions`, `test-profile` | Regresión de citas, expediente, historial, recetas, perfil e información general. |
| `test-doctor-dashboard`, `test-doctor-patients`, `test-doctor-consultations`, `test-clinical-labs` | Regresión de agenda, pacientes, consultas y laboratorios. |

También pasaron `python scripts/check-project.py`, `node --check` de `web-preview/app.js`, `web-preview/applicant.js` y `scripts/visual-applicant.mjs`, y `git diff --check` (aviso informativo CRLF en RegisterView).

El servidor ya ocupaba el puerto 4173; el intento de arranque respondió EADDRINUSE. Se reutilizó el servidor existente y se comprobaron HTTP 200 en `/` y `/applicant.js`.

**Límites de la evidencia:** son pruebas de reglas/DOM/transporte simulado. No se ejecutó un registro real, login real ni operación clínica contra Supabase. El enlace nuevo Registro → Completar datos se revisó en código; su ejecución en un navegador sigue pendiente.

## Revisión Swift y visual pendiente

La revisión estática comprobó la llamada `TextField("Describe tu motivo", text: $draft.reason, axis: .vertical)`: corresponde a la variante multilínea y el target declara iOS 18.2. No se detectó una incompatibilidad por versión en esa llamada. Se revisaron el aislamiento de ApplicantRules, DatePicker limitado hasta hoy y los recursos con el comprobador portable.

**No se ejecutó Xcode, xcodebuild ni ApplicantRulesTests. No se acredita compilación Swift.** En Mac: abrir `HospitalUniversitario/HospitalUniversitario.xcodeproj`, esquema HospitalUniversitario, simulador iOS 18.2+, compilar y ejecutar pruebas. Revisar además teclado, VoiceOver, tamaño de texto grande y dispositivos de 320/375/393/430 puntos.

Se intentó `node scripts/visual-applicant.mjs docs/visual-applicant-review` con Edge headless. No expuso una página DevTools en el puerto 9333 y el script original falló antes de navegar. **No se generaron capturas ni resultados visuales válidos.** Por tanto no se certifica ausencia de cortes, superposiciones o controles inaccesibles: los ajustes de adaptabilidad requieren revisión real. El script corregido se validó sintácticamente; no se repitió el lanzamiento del navegador.

## Recorrido manual exacto en Windows

1. Desde la raíz ejecutar `node --preserve-symlinks --preserve-symlinks-main web-preview/server.mjs` si no hay servidor activo. Si aparece EADDRINUSE, usar el servidor existente. Abrir `http://127.0.0.1:4173/` y recargar con Ctrl+F5.
2. Abrir DevTools (F12), activar dispositivo (Ctrl+Shift+M). Probar 320×640, 375×667, 393×852 y 430×932. Mantener zoom 100%; después repetir con texto/zoom aumentado. Recorrer **todas** las pantallas y desplazar hasta el final: controles y salida deben ser alcanzables, sin scroll horizontal, texto cortado ni superposición. Repetir en horizontal y, para teclado real, en iPhone.
3. Pulsar **Regístrate**. Enviar vacío: debe impedirse el envío. Introducir datos ficticios: Ana / Prueba, DUI `012345678` (se formatea `0123-45678`), nacimiento `1995-03-10`, teléfono `7000-1111`, correo `ana@correo.test`, contraseña y confirmación iguales de al menos ocho caracteres. No usar datos personales reales.
4. Cambiar solo DUI a `1234` y enviar: error de nueve dígitos. Restaurarlo. Cambiar nacimiento a una fecha futura y enviar: error de nacimiento. Restaurarlo. Cambiar teléfono a `abc`: error de teléfono. Restaurarlo. Cambiar confirmación: error de coincidencia. Restaurarla y enviar: aviso de demostración, sin cuenta creada.
5. Pulsar **Continuar con datos de ejemplo** → **Completa tus datos**. Repetir vacío/DUI/futuro/teléfono y guardar los datos ficticios válidos. Debe aparecer **Inicio**, saludo y aviso de ausencia de expediente. La salida debe estar disponible incluso antes de guardar.
6. Pulsar **Solicitar atención**. Comprobar especialidad/motivo vacíos, fecha pasada y preferencia sin elegir: no debe generarse una solicitud. Elegir especialidad, motivo, fecha futura y Mañana o Tarde; cambiar entre ambas y comprobar selección exclusiva. Enviar: debe abrir **Mis solicitudes**, estado **Pendiente**, sin cita real.
7. Pulsar **Mostrar ejemplos de rechazada y cancelada**. Ver ambos estados con sus motivos. Repetir el botón: no debe duplicarlos. En la solicitud pendiente pulsar **Simular avance de recepción (ejemplo)** tres veces: En revisión → Aceptada → Cita programada; conservar el aviso de cita de ejemplo. Ningún ejemplo debe aparecer como cita real en otro módulo.
8. Recorrer Inicio/Solicitar/Mis solicitudes; salir y volver a entrar: no deben quedar datos locales anteriores. Volver al login con **Login real**. No introducir credenciales reales para esta revisión. Usar Médico/Paciente de diseño para verificar navegación y pantallas existentes.
9. En Network, comprobar que los pasos de registro y solicitante no envían peticiones a Supabase. Las pruebas reales de autenticación quedan fuera de esta intervención.

## Pendientes antes de conectar

- Ejecutar el recorrido completo y la revisión de adaptabilidad en navegador, incluyendo la nueva continuación desde registro.
- Compilar y probar en Xcode, incluyendo ApplicantRulesTests y la carga del bundle JavaScript.
- Revisar visualmente iPhone con teclado, áreas seguras, texto grande y accesibilidad.
- La conexión y persistencia real siguen pendientes; esta revisión no autoriza cambios de backend.
