# Revisión de conexión — 13 de noviembre de 2026

## Resultado

La copia de trabajo ya contenía una transición extensa sin confirmar en Git. Se conservaron esos cambios. iOS y web apuntan exclusivamente a Hospital Móviles, referencia `uvebpsbbwofthucghccc`; el conector Supabase confirma el nombre y estado `ACTIVE_HEALTHY` del proyecto.

Se comprobó la configuración Xcode incluida por App.xcconfig, Info.plist y el contrato web. SharedCore.swift y api.js ahora rechazan cualquier destino distinto de la URL exacta autorizada y requieren una clave pública publicable. check-project.py comprueba la correspondencia entre URL/clave de iOS y web. La sesión utiliza almacenamiento específico del proyecto actual.

## Limpieza

Se retiraron nueve scripts de edición de un solo uso de la transición, que todavía contenían nombres de servicios o reemplazos del backend sustituido, y el JSON de diferencias del diccionario anterior. No se ejecutaron esos scripts. Sus rutas se añadieron al manifiesto de archivos retirados. Se reconstruyó el índice documental para eliminar enlaces a SQL y contratos inexistentes y destacar las instrucciones vigentes. La bitácora conserva trazabilidad histórica; sus entradas previas no son instrucciones para configurar el backend actual. Las referencias visuales locales se conservan.

## Evidencia ejecutada

- Conector Supabase: listado real de proyectos, sin modificar datos.
- `check-backend.mjs`: HTTPS real con la clave pública; Auth devuelve 200, registro habilitado y confirmación de correo requerida. REST rechaza acceso sin sesión a profiles, patients y user_roles con 401. La primera ejecución falló por EACCES de red del sandbox; la repetición con autorización pasó.
- `test-core.mjs`: aprobado, incluyendo rechazo de configuración ajena antes de acceder a la red, autorización por roles activos/vínculos, filtros propios y renovación de sesión. Transporte simulado.
- `test-preview.mjs`: aprobado, veinte pantallas y navegación de diseño aislada. Transporte/DOM simulados; no es revisión visual.
- `test-patient-registration.mjs`: aprobado, registro, confirmación de correo, fallo parcial, reintento y solicitudes sin programar citas. Transporte simulado; no se crearon cuentas reales.
- `generate-models.mjs --check` y `check-project.py`: aprobados. Verifican modelos y estructura portable de Xcode; no compilan Swift.
- `git diff --check`: aprobado con la configuración vigente y avisos de normalización LF/CRLF. Búsqueda final sin dominio ni RPC sustituidos en iOS, web y scripts.

No se cambió el esquema, RLS, permisos ni configuración Auth, ni se crearon pacientes, cuentas o datos clínicos. No se modificó ningún proyecto remoto.

## Pendientes para funcionamiento completo

En Mac: resolver dependencias fijadas, compilar y ejecutar pruebas SwiftUI en Xcode y recorrer la interfaz. Con una identidad autorizada: comprobar correo, login, registro, persistencia y aislamiento entre usuarios. Las comprobaciones sin sesión y el transporte simulado no acreditan esos recorridos.

Siguen pendientes las operaciones clínicas enumeradas en la [transición](TRANSICION_HOSPITAL_MOVILES_2026-11-13.md): iniciar/guardar/cerrar consulta, emitir recetas/órdenes, contacto de emergencia, preferencias, confirmación de jornadas, documentos y detalle de expediente del doctor. La conexión nueva responde; esto no significa que todos los módulos estén completados.
