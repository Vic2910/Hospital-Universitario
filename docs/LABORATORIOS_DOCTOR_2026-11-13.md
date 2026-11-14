# Laboratorios Doctor iOS / Windows

## Flujo vigente

Doctor → consulta propia abierta → **Emitir orden de laboratorio** → buscar/filtrar y seleccionar exámenes → motivo/indicaciones → revisar → confirmar. También puede abrir Laboratorios desde el Dashboard: **Mis órdenes de laboratorio** muestra sus órdenes sin depender del día de agenda; el directorio permite revisar un paciente autorizado. La orden utiliza el mismo Supabase y formato que el panel externo. Recargar Windows con Ctrl+F5 en http://127.0.0.1:4173/ e iniciar sesión real de doctor. Los ejemplos de diseño siguen siendo locales.

El esquema existente almacena un examen por fila de `lab_orders`. Una selección múltiple genera una fila por examen, atómicamente, vinculadas a la misma consulta y `request_group`. No se creó otra tabla ni una pantalla paralela; el panel sigue recibiendo las filas por su contrato actual. Doctor/paciente/expediente se resuelven mediante `clinical_encounters`, `staff` y `medical_records`. No se modificó el proyecto administrativo externo.

## Catálogo real

Existían activos: **Hemograma completo**, **Examen general de orina**, **Glucosa** (glucemia), **Perfil lipídico** y **Prueba de embarazo**.

Se agregaron los seis ausentes: **Examen general de heces**, **Colesterol total**, **Triglicéridos**, **Creatinina**, **Urea** y **Ácido úrico**. El perfil lipídico existente se conserva; no equivale a duplicar las pruebas individuales. Total posterior: once activos, cero nombres normalizados/códigos duplicados.

Se añadieron `code` único y `category` opcional a `lab_test_types`. Categorías Sangre, Orina y Heces para los exámenes identificados; embarazo permanece sin categoría por no asumir el tipo de muestra. Las nuevas inserciones del panel conservan compatibilidad gracias al código predeterminado y categoría opcional. No se borraron ni reactivaron pruebas. Los identificadores técnicos no se presentan en la selección.

## Contrato de Supabase

Migración desplegada: `doctor_laboratory_multiple_v1`; fuente `supabase/doctor-laboratory-multiple.sql`.

- `doctor_native_lab_catalog()` → exámenes activos `{id,name,code,category}`. Requiere doctor activo con vínculo staff válido.
- `doctor_native_labs(p_encounter uuid,p_tests bigint[],p_reason text,p_key uuid)` → `{order_ids,count}`. De 1 a 30 exámenes distintos activos, motivo obligatorio hasta 10000 caracteres, consulta propia abierta. Reutiliza `doctor_native_lab`; la misma clave/contenido devuelve las órdenes originales. Un examen inválido no deja inserciones parciales. Los clientes conservan payload/clave ante fallo de transporte y bloquean doble envío.
- `doctor_native_lab_orders(p_offset=0)` → página de 25 órdenes propias de pacientes autorizados, sin filtro por fecha.
- `doctor_native_patient_labs(p_patient,p_offset=0)` conserva su firma y ahora incluye paciente/expediente y parámetros publicados. Ambas páginas devuelven `items,total,has_more,next_offset`.

Se reutilizan `lab_orders`, `lab_test_types`, `lab_results`, `lab_result_drafts`, permisos, RLS y RPC del laboratorio. Sin cambios de permisos clínicos ni service_role en los clientes. El panel conserva `laboratory_panel` / `laboratory_order_detail`, procesamiento, validación y publicación existentes. No necesita adaptarse para recibir órdenes; puede aprovechar `request_group` para agrupar visualmente en el futuro.

## Resultados y límite clínico

El backend ya tenía `result_values`, `parameter_schema` y validación/publicación diferenciadas. La app muestra resumen y parámetros con unidades, referencias y observaciones **solo cuando están publicados y validados**. Para paciente se exige además `published_to_patient_at`; se mantienen sus filtros de identidad y RLS. Una orden completada aún no liberada se presenta como pendiente de publicación, sin mostrar el informe.

Los once catálogos tienen actualmente `result_schema=[]` y no cuentan con referencias clínicas validadas. Por ello funcionan informes descriptivos; el laboratorio autorizado debe configurar/validar sus parámetros, unidades y referencias con `configure_laboratory_test` antes de usar informes numéricos estandarizados. No se inventaron unidades, rangos, metodologías ni valores normales. Los clientes ya interpretan los parámetros cuando el laboratorio los publique.

## Verificación y límites

`supabase/test-laboratory-rollback.sql`: prueba SQL real aprobada de selección múltiple, formato visible desde `laboratory_panel`, borrador → validación → publicación doctor → liberación paciente. Reintento sin duplicados, examen inválido sin filas parciales y aislamiento de otro médico/paciente/borradores. Fixtures y parámetros textuales de prueba se revirtieron; consulta posterior confirmó cero cuentas de prueba y catálogos clínicos sin parámetros inventados.

JavaScript simulado aprobado: `test-doctor-laboratory` (búsqueda/categorías, selección, confirmación, reintento, seguimiento, colores, catálogo vacío y resultado propio del paciente); recorrido médico y regresiones de directorio, ingresos, registro, Dashboard paciente y atención. `test-core` valida el filtro de publicación y adaptación estructurada compartida. Comprobador portable y diff aprobados; no acreditan compilación Apple. Fuente de prueba Swift añadida a DoctorModuleTests, pendiente Mac.

Asesores consultados; las RPC SECURITY DEFINER para authenticated son intencionales con controles internos y anon revocado. Persisten avisos previos ajenos al alcance sobre extensión en public, RLS sin políticas y protección de contraseñas. [Aviso de funciones](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Pendiente: compilar/probar Swift y tamaños/accesibilidad en Xcode, revisión visual del navegador y recorrido autenticado HTTPS de los clientes. La prueba SQL verifica el backend y contrato del panel, sin afirmar que se operó la interfaz del otro proyecto.
