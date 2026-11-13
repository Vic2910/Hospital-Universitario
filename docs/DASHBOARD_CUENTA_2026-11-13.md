# Dashboard de paciente con o sin expediente

Se reutilizan PatientDashboardView, sus componentes, ContentView y el portal web. La cuenta con rol paciente activo entra al Home sin exigir paciente clínico. El saludo usa primer nombre/apellido de profiles, nunca metadatos ni ejemplos. Los cuatro accesos son citas, atención, laboratorios y recetas; sin vínculo muestran vacíos/orientación de recepción. El núcleo evita consultas clínicas sin patient_id y mantiene los filtros propios y RLS al vincularse.

La tarjeta consulta la próxima cita futura programada/confirmada, ordenada ascendentemente y limitada a una. Muestra fecha, hora, estado y médico autorizado. Se cotejaron las FK reales appointments→staff→profiles por consulta de metadatos. La RLS de profiles puede ocultar el nombre del doctor al paciente: en ese caso se muestra su employee_code publicado por staff, o una indicación de dato no disponible. No se ampliaron políticas para obtener nombres. La fecha se presenta en español con zona local del dispositivo.

Se limpia el dato anterior al actualizar, cambiar vínculo o cerrar sesión; hay carga, error distinguible de vacío y reintento. La navegación y los recursos siguen dentro del target existente. No se modificó Supabase, registro, confirmación de correo ni permisos de empleados.

Verificación: test-preview, test-core, test-patient-registration y nueva test-patient-dashboard con transporte simulado; casos con/sin vínculo, nombre compuesto, cuatro accesos, filtros, ausencia de escrituras, error/reintento y vínculo actualizado. Prueba Swift añadida, pendiente de Mac. Check-project portable y formato se registran en bitácora. Sin registro real, compilación Apple ni revisión visual nueva.
