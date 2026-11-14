# Doctor iOS — entrega funcional

Actualización: el mismo flujo está replicado en web-preview para Windows, consumiendo las siete RPC ya desplegadas. Iniciar sesión como doctor permite ver Dashboard, agenda propia, expediente, borrador/signos, laboratorio, receta y cierre; sin cambios en Supabase ni en el panel externo. test-doctor-preview-live pasó con transporte simulado; sigue pendiente revisión visual real. La regla permanente es mantener iOS y la réplica local sincronizados.

Se reutilizan DoctorModuleView, Dashboard, agenda, ticket, repositorio y modelo existentes. La sesión real deja de activar el diseño local y de sustituir agendas vacías por ejemplos. Dashboard con nombre real, fecha, pendientes/atendidas y próxima cita; accesos a Agenda, Consultas, Pacientes, Laboratorios y Recetas. Calendario, búsqueda y filtros de estado. Detalle enlaza cita, solicitud/síntomas, consultorio, especialidad y expediente; la cita directa informa que no tiene solicitud.

El acceso mantiene user_roles activos; doctor exige staff.profile_id propio, activo y category=doctor. No existe tabla separada de doctores. Varios roles mantienen elección explícita; paciente no obtiene funciones médicas. Registro, Dashboard y solicitudes del paciente se conservan. No se editaron archivos web en esta intervención; se preservan los cambios locales anteriores.

## Supabase

Migración desplegada: `doctor_native_clinical_flow_v1`, fuente `supabase/doctor-ios.sql`. Reutiliza clinical_encounters, medical_records/history, diagnoses, vital_signs, lab_orders/results, prescriptions/items, medications y appointments. Añade cuatro secciones de evaluación, versión/clave de último guardado al encuentro existente y duration_days al ítem de receta. No crea tablas clínicas paralelas ni altera las políticas RLS existentes.

Las RPC doctor_native_workspace/chart/start/save/lab/prescribe/finish obtienen el doctor desde auth.uid(). Devuelven agenda propia, expediente autorizado y catálogos reales; mutaciones bloquean cita/encuentro, comprueban autoría y estado y usan claves estables/versiones. Se reutiliza update_appointment_status; un trigger impide que un doctor marque atendida una cita antes de cerrar una consulta completa. La finalización y el cambio de cita son atómicos. No hay endpoint para que doctor publique resultados. Sin service_role en clientes ni permisos anónimos para las nuevas RPC.

El borrador admite secciones incompletas; finalizar exige las cuatro secciones guardadas. Diagnóstico en diagnoses, código opcional manual porque no existe catálogo. Medicamento/concentración desde medications, dosis/unidad/frecuencia/vía/duración/cantidad e indicaciones; vías restringidas al CHECK actual. Laboratorio usa ID bigint real del catálogo, sin identificadores UUID ficticios. Historial de consultas y recetas se limita al médico actual; antecedentes del expediente autorizado se comparten según el vínculo asistencial.

Contrato de transporte reutilizable por Android: `contracts/doctor-native-v1.json`. Recursos y rutas Xcode se mantienen en los grupos sincronizados existentes.

## Verificación y pendientes

`supabase/test-doctor-rollback.sql` pasó en Supabase real: cuenta paciente crea solicitud; recepción vincula y programa; doctor ve agenda/solicitud/síntomas/antecedentes; inicia una sola consulta; guarda borrador/vitales; emite una orden y una receta; finaliza; paciente ve su receta. Reintentos no duplican. Paciente/otro doctor rechazados, resultados protegidos, cita no finalizable prematuramente y consulta cerrada no editable. Se corrigió una aserción del test para comparar numéricamente el peso con escala Postgres, no como texto. Todas las filas temporales se revirtieron; consulta posterior confirmó cero cuentas, empleados y medicamentos de prueba persistentes. No se probó login HTTPS con credenciales ni se ejecutó iOS.

test-preview, test-core, test-patient-registration, test-attention-navigation y check-project aprobados. DoctorModuleTests adaptado y ampliado, pendiente de ejecutar en Mac. Asesores consultados: las RPC con SECURITY DEFINER tienen autorización interna y EXECUTE anónimo revocado; avisos restantes ajenos al alcance no modificados.

Pendiente: compilar con ⌘R, ejecutar ⌘U y recorrer UI/acceso multirrol, edición, laboratorio/receta y cierre en Xcode con identidad autorizada. La comprobación portable no sustituye el SDK de Apple ni una revisión visual.
