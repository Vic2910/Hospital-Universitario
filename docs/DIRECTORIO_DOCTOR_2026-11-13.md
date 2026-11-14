# Pacientes y Laboratorios — 13 de noviembre de 2026

El directorio médico de iOS y `web-preview/` muestra pacientes autorizados independientemente de la fecha de agenda. Incluye búsqueda por nombre, DUI con/sin guion, correo de cuenta vinculada y expediente, con paginación. Tarjetas vino/blanco, contacto real, expediente autorizado y navegación entre paciente y laboratorios. Los datos ausentes se identifican; no se inventan correos ni expedientes.

Laboratorios selecciona primero al paciente y muestra sus órdenes y resultados autorizados, con acceso a su expediente. Emitir una orden exige una consulta propia abierta; abrir un paciente no inicia consultas ni crea datos. Al cambiar selección o cerrar sesión se descarta el contexto previo.

## Backend real

Desplegada `doctor_patient_directory_v1`, fuente `supabase/doctor-patient-directory.sql`: dos RPC de lectura `doctor_native_patients` y `doctor_native_patient_labs`; `doctor_native_chart` incorpora DUI y correo vinculado. Reutilizan `patients`, `medical_records`, `clinical_encounters`, `lab_orders`, `lab_results`, `lab_test_types`, `auth.users` y los controles existentes `private.native_doctor_id()` / `private.treats_patient()`. No se crearon tablas ni se ampliaron políticas RLS. Solo doctor activo con vínculo propio de personal y relación asistencial válida; no acceso anónimo ni identidad de médico elegida por el cliente.

## Rutas principales

- iOS: `Core/DoctorModels.swift`, `DoctorRepository.swift`, `DoctorViewModel.swift`, `HospitalAPI.swift`, `Doctor/DoctorModuleView.swift` y `ContentView.swift`.
- Réplica Windows: `web-preview/api.js`, `app.js`, `modules.js`, `style.css`. No se modificó el proyecto administrativo externo.
- Contrato reutilizable: `contracts/doctor-native-v1.json`.

## Verificación

SQL real con identidades temporales en subtransacción revertida: búsqueda nombre/DUI/correo, aislamiento frente a otro médico, datos del expediente, órdenes y recorrido clínico completo aprobados. No acredita login HTTPS del usuario. La restricción real `medical_records_patient_id_key` evita duplicar pacientes por expediente.

Pruebas JavaScript con transporte simulado: directorio sin citas hoy, paginación, búsqueda, selección/limpieza, expediente, laboratorios, errores/reintento, cierre y ausencia de escrituras clínicas al navegar; recorrido médico completo y regresiones de paciente/registro/solicitudes. Comprobador portable del proyecto aprobado; no compila Swift. Prueba nativa de directorio añadida a `DoctorModuleTests`, pendiente de Xcode.

Asesores consultados: advertencia de RPC SECURITY DEFINER ejecutables por authenticated, intencional con controles internos de rol/relación y acceso anónimo revocado; persisten avisos ajenos a esta intervención sobre extensión en public, tablas RLS sin políticas y contraseñas filtradas. [Descripción del aviso de funciones](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Para verlo: servidor local de README, Ctrl+F5, sesión real de doctor → Pacientes o Laboratorios. No se ejecutó revisión visual en navegador ni compilación Apple en Windows. Pendiente compilar/pruebas Swift y revisar tamaños/accesibilidad en simulador iOS.
