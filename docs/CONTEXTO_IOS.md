# Contexto confirmado para el avance iOS

**Estado consolidado de la sesión:** consultar [SESION_2026-10-23.md](SESION_2026-10-23.md). El nombre vigente solicitado por el usuario es **Hospital Universitario**. Las secciones siguientes conservan la evolución histórica de las decisiones; el trabajo futuro debe registrarse conforme a `../AGENTS.md`.

Revisión: 23 de octubre de 2026. Este documento incorpora los tres archivos aportados por el usuario. No cambia el alcance de los tres bloques solicitados ni da por ejecutadas las instrucciones generales de los adjuntos.

## Fuentes y prioridad

1. La solicitud del usuario determina el avance: autenticación por roles Médico/Paciente, maquetación SwiftUI y modelos/servicios de habitaciones y turnos; vista previa web local para Windows.
2. `PROYECTO FINAL DAMA.pdf` contiene los requisitos académicos del sistema completo. Se revisaron sus cinco páginas. Su semana 2 coincide con el avance solicitado; los módulos clínicos, ambulancia, inventario, CRUD y demás plataformas se planifican para otras entregas y no se incorporan automáticamente ahora.
3. `Hospital Universitario.zip` contiene 21 capturas PNG iOS, todas de 393 × 852: 11 de Paciente y 10 de Médico. Se extrajeron sin alterar y se preservó el nombre original en `design-reference/inventory.json`.
4. `Informe_Hospital_Universitario.md` conserva el trabajo anterior de backend. Es evidencia histórica, no una autorización para ejecutar nuevas migraciones ni una garantía del estado actual. Las consultas del turno anterior confirmaron el proyecto Supabase, las tablas, las RPC y la ausencia de usuarios Auth.

El informe se conserva en `design-reference/Informe_Hospital_Universitario.md`. El texto del PDF está en `design-reference/requirements.txt`. Las hojas de contacto permiten revisar las fuentes visualmente.

## Inventario iOS recibido

| Rol | Archivo local | Pantalla |
|---|---|---|
| Paciente | screen-01.png | Inicio |
| Paciente | screen-02.png | Mis citas |
| Paciente | screen-03.png | Solicitar atención |
| Paciente | screen-04.png | Mi turno |
| Paciente | screen-05.png | Expediente |
| Paciente | screen-06.png | Historial médico |
| Paciente | screen-07.png | Mis recetas |
| Paciente | screen-08.png | Laboratorio |
| Paciente | screen-09.png | Información pública |
| Paciente | screen-10.png | Notificaciones |
| Paciente | screen-11.png | Perfil |
| Médico | screen-12.png | Inicio |
| Médico | screen-13.png | Mis pacientes |
| Médico | screen-14.png | Mis citas |
| Médico | screen-15.png | Consultas |
| Médico | screen-16.png | Expedientes |
| Médico | screen-17.png | Recetas |
| Médico | screen-18.png | Laboratorio |
| Médico | screen-19.png | Mi horario |
| Médico | screen-20.png | Notificaciones |
| Médico | screen-21.png | Perfil |

Todos los archivos están en `docs/design-reference/`. No se utilizan capturas completas como fondo de una implementación: son referencias visuales.

## Consecuencias para el código existente

- El diseño real usa encabezados color vino, fondo gris muy claro, tarjetas blancas, búsqueda superpuesta al borde inferior del encabezado y navegación inferior por rol. El scaffold actual verde azulado no reproduce este diseño y debe reemplazarse.
- El inicio tras autenticación debe ser **Inicio** del rol, no una lista de habitaciones como pantalla principal.
- Paciente tiene `Inicio / Mis citas / Salud / Perfil / Más`; Médico tiene `Inicio / Pacientes / Mis citas / Consultas / Más`. Las áreas clínicas pueden maquetarse sin implementar sus operaciones fuera del avance.
- **Mi horario** del médico corresponde a `staff_shifts`: próxima jornada y agenda semanal. **Mi turno** del paciente corresponde a `queue_tickets` y la RPC `my_queue_status`: número propio, estado, personas anteriores y consultorio autorizado. No se deben confundir estos recursos ni deducir la posición contando datos de otros pacientes en el cliente.
- El PDF define expresamente los turnos del personal para el bloque de estructura de datos. El diseño añade el turno de atención del paciente; se conserva como recurso distinto, como ya hacen los modelos actuales.
- No hay captura de **login iOS** ni de **habitaciones iOS** en este ZIP. El informe solo inventaría login Android y habitaciones para Recepción/Enfermería. Se puede adaptar la identidad visual al login, pero no presentarlo como una pantalla iOS observada. El servicio/modelo de habitaciones no exige inventar una pestaña principal en los roles Médico/Paciente.
- El PDF fija cinco habitaciones VIP individuales y seis semiprivadas dobles: **11 habitaciones y 17 camas**. Una habitación `active` no equivale a una cama libre; la ocupación se obtiene de asignaciones/proyecciones del servidor.
- Las cifras, nombres, recetas y diagnósticos que aparecen en las capturas son ejemplos de diseño. No deben convertirse en registros reales ni cifras permanentes en la app.
- El informe confirma perfiles `pending` al crear Auth, activación administrativa y vínculos a persona/paciente/personal; no propone registro libre con autoasignación de rol. Las funciones clínicas pueden requerir MFA; no se debe reducir esa protección para facilitar la maquetación.

## Alcance que se conserva

Se mantiene la integración con las funciones existentes, sin recrear el esquema, crear cuentas ficticias ni implementar operaciones clínicas por el solo hecho de aparecer en el ZIP. Las instrucciones de registro, CRUD y entrega multiplataforma del PDF describen el proyecto global y no sustituyen la restricción del usuario para este avance.

Los PNG eliminan el bloqueo para revisar visualmente estas 21 pantallas. No aportan el árbol de capas, fuentes originales, componentes exportables ni conexiones de navegación del archivo editable de Figma; esas propiedades no se dan por verificadas a partir de una imagen.

## Estado después de la revisión de contexto

Se incorporaron y clasificaron las referencias. En esta revisión no se modificó el código de la app ni Supabase. Sigue pendiente trasladar la composición observada a SwiftUI y a la web, completar la proyección de Mi turno y comprobar el resultado en navegador y Xcode. Los resultados de pruebas del backend descritos en el informe pertenecen a la conversación anterior y no se anuncian como pruebas de la app actual.

## Implementación posterior del avance del 24 de octubre

El usuario confirmó que el desarrollo continúa limitado a iOS y la vista previa web. Ya se sustituyó el scaffold inicial por la composición del prototipo y el catálogo compartido de las 21 pantallas. Se añadieron el Inicio por rol, TOTP para factores inscritos, la proyección `my_queue_status`, perfil, resumen autorizado e información pública. La vista previa incorpora un modo de diseño aislado, sin consultas a Supabase, para recorrer las pantallas con los ejemplos de las capturas. Los formularios clínicos permanecen sin operaciones de escritura. El estado y las verificaciones actuales están en `README.md`; la sección anterior conserva el resultado de la revisión documental inicial, no el estado final del código.

## Cuentas Auth de demostración autorizadas después

El usuario pidió expresamente crear dos cuentas de prueba, Médico y Paciente. Ya existen `medico.demo@hospital.test` y `paciente.demo@hospital.test`, con perfiles activos, roles y vínculos propios. Las contraseñas están solo en `.local/`, excluido de Git. Se probaron los logins reales por HTTPS, permisos, perfiles, habitaciones, consulta de turnos, refresh y revocación. El informe público de resultados está en `docs/login-verification.json`. No se inscribieron factores TOTP: esa acción adicional fue rechazada por la revisión automática hasta recibir autorización expresa. Las reglas MFA del servidor permanecen intactas.
