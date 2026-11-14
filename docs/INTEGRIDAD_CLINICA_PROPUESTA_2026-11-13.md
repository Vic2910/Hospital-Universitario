# Integridad clínica — propuesta pendiente de autorización

**Actualización 2026-11-14:** desplegada con autorización como `clinical_write_integrity_v1`. Preflight aprobado y respaldo local recuperable. Verificación dinámica pendiente: el ejecutor JavaScript de pruebas falló por sintaxis antes de enviar SQL; se detuvo sin reintentos. Los apartados siguientes documentan la propuesta revisada. Fuente: `supabase/clinical-write-integrity.sql`. Solo backend; interfaces y datos clínicos existentes sin modificaciones.

## Decisión basada en dependencias reales

- Revocar INSERT/UPDATE/DELETE directos de PUBLIC/anon/authenticated en clinical_encounters, diagnoses, lab_orders, prescriptions y prescription_items, incluidos privilegios de columna. Mantener SELECT/RLS y ejecución de RPC.
- Conservar INSERT de vital_signs: la política vitals_insert autoriza al médico y a enfermería asignada mediante private.cares_for. Un trigger privado comprobará actor, consulta abierta, coherencia y los mismos límites admitidos por doctor_native_save; rechaza suplantación y traslado entre consultas.
- Impedir asociaciones inconsistentes al crear consultas y la reasignación posterior de sus vínculos. Proteger cambios de paciente/médico en citas con consulta y de paciente en expedientes con consultas.
- Preservar procesamiento/publicación de laboratorio y dispensación tras el cierre: son actualizaciones administrativas autorizadas, no nuevas prescripciones ni evaluaciones clínicas. No se aplicará un bloqueo genérico de toda escritura después del cierre.

Verificados GRANT por tabla/columna, RLS, triggers y cuerpos/propietarios de las funciones actuales. Los escritores médicos, de laboratorio y dispensación inspeccionados son SECURITY DEFINER propiedad de postgres. iOS/web-preview utilizan RPC para la creación clínica; no se encontró INSERT directo de cliente en esas cinco tablas. La función de signos vitales reutiliza la autorización de enfermería existente, sin ampliar permisos.

Preflight: firmas de definición de trece dependencias, propietario/modo de ejecución, RLS y coherencia existente; aborta ante deriva o datos incompatibles. Comprobación posterior de privilegios incluida en la misma transacción. Lectura actual: cero consultas inconsistentes y cero sin cita. No se hizo saneamiento de datos.

## Operaciones que requieren atención antes de desplegar

1. Un cliente externo que inserte directamente en las cinco tablas perderá esa vía. No hay acceso al código del panel independiente para certificar que no existe tal consumidor. Las RPC inspeccionadas conservarán sus privilegios.
2. Enfermería podrá registrar mediciones en consulta abierta y asignada. Después del cierre necesitará el episodio asistencial abierto que corresponda; no se permitirá añadir mediciones a una consulta finalizada.
3. No se permitirá mover un expediente con consultas a otro paciente ni reasignar una consulta existente. Una futura fusión/corrección de identidades requerirá un flujo específico auditado; no se identificó una RPC actual que realice esa operación.
4. Se requieren bloqueos breves de esquema al instalar triggers/revocar permisos. Desplegar en una transacción y con verificación controlada posterior. No se alteran firmas públicas ni datos clínicos.

## Pruebas posteriores a la autorización

Con fixtures temporales, sin pacientes reales y reversión completa:

- Doctor autorizado: iniciar, guardar signos/diagnóstico, laboratorio individual/múltiple, receta y cierre; repetir solicitudes con claves estables.
- INSERT directo rechazado en las cinco tablas, antes y después del cierre; verificar permisos residuales y separación paciente/recepción/doctor ajeno.
- Enfermería asignada: INSERT de signos vitales aceptado con consulta abierta; rechazo sin asignación, con otro actor, valores fuera de validación y después del cierre.
- Rechazo de vínculos cita–doctor–expediente incompatibles y de cambios posteriores que rompan la asociación.
- Consulta cerrada: RPC de guardar, nueva receta y nuevo examen rechazadas; laboratorio conserva procesamiento/validación/publicación y dispensación autorizada sigue funcionando.
- Lecturas RLS existentes y ausencia de datos temporales persistentes.

Los scripts existentes `test-doctor-rollback.sql` y `test-laboratory-rollback.sql` servirán como regresión del contrato, ampliando los casos directos/enfermería. **Estas pruebas de BD aún no se ejecutan:** la migración espera autorización. Tampoco se afirma validación del parser/ejecución PostgreSQL del borrador.
