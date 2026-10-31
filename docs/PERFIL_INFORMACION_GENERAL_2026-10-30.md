# Perfil del Paciente e Información general — 2026-10-30

## Implementación

Perfil del Paciente presenta un encabezado vino con iniciales/nombre y una card de información personal con nombre completo, correo electrónico y teléfono, iconos y separadores. Es de lectura: usa `my_profile.person.given_names/family_names`, `auth_email` y el contacto `kind=phone`. Los faltantes se muestran como No disponible; no se completan cuentas reales con datos de prueba. En diseño web y Preview SwiftUI se utiliza el perfil de ejemplo María López, maria.lopez@ejemplo.test, 7123-4567. La vista de Perfil del Doctor conserva nombre y apellido.

La ruta `information` se mantiene y su título pasa a Información general en el catálogo del Paciente. Presenta portada vino, ubicación de referencia del campus UNICAES en Santa Ana, botón Cómo llegar, contacto institucional, especialidades y acceso a Solicitar atención. Se conservan Consultar habitaciones y los datos publicados de ocupación, médicos y comunicados, agrupados en Avisos y actividad del hospital. Se retira el buscador de esta pantalla.

Las especialidades se toman de médicos publicados cuando `hospital_overview.on_duty` tiene registros. Sin registros, se reutilizan las seis especialidades del formulario existente y se identifican como Catálogo de demostración, con disponibilidad por confirmar. No se presentan como servicios clínicos verificados de UNICAES.

## Fuente pública

Se consultó y abrió el [directorio oficial de UNICAES](https://catolica.edu.sv/contactos-facultades-y-unidades-unidaes/) durante esta intervención. Se usaron la dirección del campus Santa Ana y los contactos de Clínica Universitaria y WhatsApp institucional, conservando sus nombres oficiales. No se inventó un número de soporte hospitalario ni disponibilidad de servicios. El enlace de mapa abre una búsqueda del campus, no coordenadas no verificadas. El enlace de fuente queda visible en Información general.

## Archivos

- Nuevo `HospitalUniversitario/HospitalUniversitario/Patient/PatientProfileInformationView.swift`: PatientProfileCardView, HospitalInformationView y constantes HospitalPublicContact; Previews locales. Entra por el grupo sincronizado del target existente.
- `HospitalUniversitario/HospitalUniversitario/ContentView.swift`: integración de perfil según rol y nueva información general, sin buscador.
- `HospitalUniversitario/HospitalUniversitario/Shared/screens.json`: título de Información general y descripción del Perfil del Paciente; IDs y rutas conservados.
- `web-preview/app.js`, `web-preview/style.css`: réplica de cards, datos propios, estados de faltantes, enlaces y especialidades; sin nuevas dependencias.
- `scripts/test-profile.mjs`: pruebas ajustadas para perfil de paciente, conservación del doctor, faltantes, datos de demostración aislados y enlaces de información.
- README.md, docs/README.md y docs/BITACORA.md: documentación vigente.

## Verificación real de esta intervención

- test-preview.mjs: recorridos de ambas cuentas y diseño, 20 pantallas y formulario de Solicitar atención desde Salud.
- test-profile.mjs: nombre, correo y teléfono de cuenta simulada; faltantes explícitos; no mezcla de perfil de ejemplo; datos del Doctor conservados; sin formulario de edición ni RPC de ajustes; ubicación y enlaces de contacto/mapa/fuente, seis especialidades de ejemplo y acceso directo a Salud.
- python scripts/check-project.py, node --check web-preview/app.js y git diff --check.
- Recursos HTTP 200/no-store en el servidor de vista previa existente; app.js y style.css entregan los componentes nuevos. Sin segundo servidor ni cambio de puerto.

Son pruebas con DOM/transporte simulado y HTTP local. No se realizaron llamadas ni mensajes a los contactos, escrituras a Supabase, revisión visual del navegador o compilación Swift/Xcode. Pendiente verificar SwiftUI en Mac y validar el catálogo clínico real cuando se publique.

Este cambio reemplaza la decisión anterior de mostrar únicamente nombre/apellido en Perfil del Paciente. No cambia la decisión correspondiente al Doctor.
