-- Expedientes: búsqueda por código de paciente e historial completo por consulta — 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO. Requiere autorización expresa antes de ejecutarlo en Hospital Móviles (uvebpsbbwofthucghccc).
--
-- Solo amplía la salida de tres RPC existentes; no crea RPC, tablas ni columnas; no cambia RLS, GRANT ni datos
-- (CREATE OR REPLACE conserva los privilegios). Definiciones base leídas con pg_get_functiondef el 19-20 de noviembre.
--   1. doctor_native_patients: devuelve patients.patient_code y también busca por él. Autorización intacta: private.treats_patient.
--   2. doctor_native_chart: añade patient_code (igual que doctor-consultation-six-fields.sql; aplicar ambos en cualquier orden
--      deja el mismo resultado). En cada consulta añade ended_at, doctor_name, specialty y reason (motivo de la solicitud).
--      Cada receta incluye encounter_id. Sigue devolviendo solo consultas del médico autenticado (e.doctor_id = d).
--   3. my_consultation_history: añade reason y, por consulta, recetas y exámenes. Los resultados de laboratorio solo aparecen
--      si están validados y publicados al paciente. Sigue limitado a consultas finalizadas del propio paciente (auth.uid()).
BEGIN;

CREATE OR REPLACE FUNCTION public.doctor_native_patients(p_query text DEFAULT ''::text, p_offset integer DEFAULT 0)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE d uuid=private.native_doctor_id(); rows jsonb; total bigint; q text=lower(trim(coalesce(p_query,'')));
BEGIN
 IF length(q)>120 OR p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Búsqueda inválida' USING ERRCODE='22023'; END IF;
 WITH authorized AS MATERIALIZED (
  SELECT p.id,concat_ws(' ',p.first_name,p.last_name) full_name,m.record_code record_number,p.patient_code,p.dui,u.email,p.phone,p.birth_date,
   extract(year FROM age((now() AT TIME ZONE 'America/Guatemala')::date,p.birth_date))::int age,
   (SELECT e.id FROM public.clinical_encounters e JOIN public.appointments a ON a.id=e.appointment_id
    WHERE e.record_id=m.id AND e.doctor_id=d AND e.ended_at IS NULL AND a.status='en_atencion'
    ORDER BY e.started_at DESC,e.id LIMIT 1) active_encounter_id
  FROM public.patients p LEFT JOIN public.medical_records m ON m.patient_id=p.id
  LEFT JOIN auth.users u ON u.id=p.profile_id WHERE private.treats_patient(p.id)
 ), matches AS MATERIALIZED (
  SELECT * FROM authorized a WHERE q='' OR strpos(lower(a.full_name),q)>0 OR strpos(lower(coalesce(a.email,'')),q)>0
   OR strpos(coalesce(a.dui,''),q)>0 OR strpos(lower(coalesce(a.record_number,'')),q)>0 OR strpos(lower(coalesce(a.patient_code,'')),q)>0
   OR (q ~ '^[0-9 -]+$' AND regexp_replace(q,'[^0-9]','','g')<>''
     AND strpos(regexp_replace(coalesce(a.dui,''),'[^0-9]','','g'),regexp_replace(q,'[^0-9]','','g'))>0)
 ), page AS (SELECT * FROM matches ORDER BY lower(full_name),id LIMIT 50 OFFSET p_offset)
 SELECT (SELECT count(*) FROM matches),coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY lower(p.full_name),p.id) FROM page p),'[]') INTO total,rows;
 RETURN jsonb_build_object('patients',rows,'total',total,'has_more',p_offset+jsonb_array_length(rows)<total,
  'next_offset',CASE WHEN p_offset+jsonb_array_length(rows)<total THEN p_offset+jsonb_array_length(rows) ELSE NULL END);
END $function$;

CREATE OR REPLACE FUNCTION public.doctor_native_chart(p_patient uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_query text DEFAULT ''::text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE d uuid=private.native_doctor_id(); v_record uuid; v_patient jsonb; v_history jsonb;
BEGIN
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no asignado' USING ERRCODE='42501'; END IF;
 IF length(p_query)>120 OR (p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to) THEN RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='22023'; END IF;
 SELECT m.id,jsonb_build_object('id',p.id,'full_name',concat_ws(' ',p.first_name,p.last_name),'record_number',m.record_code,'patient_code',p.patient_code,
  'birth_date',p.birth_date,'sex',NULL,'phone',p.phone,'email',(SELECT email FROM auth.users WHERE id=p.profile_id),'address',p.city,'identification',p.dui)
 INTO v_record,v_patient FROM public.patients p JOIN public.medical_records m ON m.patient_id=p.id WHERE p.id=p_patient;
 IF v_record IS NULL THEN RAISE EXCEPTION 'Expediente no disponible' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.started_at DESC),'[]') INTO v_history FROM (
  SELECT e.id,e.started_at,e.ended_at,CASE WHEN e.ended_at IS NULL THEN 'open' ELSE 'closed' END status,
   e.subjective,e.objective,e.assessment,e.plan,CASE WHEN e.version>0 THEN e.id ELSE NULL END note_id,
   e.version note_version,e.version row_version,
   (SELECT concat_ws(' ',pr.first_name,pr.last_name) FROM public.staff s JOIN public.profiles pr ON pr.id=s.profile_id WHERE s.id=e.doctor_id) doctor_name,
   (SELECT sp.name FROM public.appointments a JOIN public.appointment_requests ar ON ar.id=a.request_id JOIN public.specialties sp ON sp.id=ar.specialty_id WHERE a.id=e.appointment_id) specialty,
   (SELECT ar.reason FROM public.appointments a JOIN public.appointment_requests ar ON ar.id=a.request_id WHERE a.id=e.appointment_id) reason,
   (SELECT dg.diagnosis_code FROM public.diagnoses dg WHERE dg.encounter_id=e.id ORDER BY dg.created_at LIMIT 1) diagnosis_code,
   coalesce((SELECT jsonb_object_agg(k,v#>>'{}') FROM public.vital_signs vs,
    LATERAL jsonb_each(to_jsonb(vs)-ARRAY['id','encounter_id','recorded_by','recorded_at']) j(k,v)
    WHERE vs.encounter_id=e.id AND vs.id=(SELECT id FROM public.vital_signs WHERE encounter_id=e.id ORDER BY recorded_at DESC,id LIMIT 1)
    AND v<>'null'::jsonb),'{}') vitals
  FROM public.clinical_encounters e WHERE e.record_id=v_record AND e.doctor_id=d
   AND (p_from IS NULL OR e.started_at>=p_from) AND (p_to IS NULL OR e.started_at<=p_to)
   AND (coalesce(p_query,'')='' OR concat_ws(' ',e.subjective,e.objective,e.assessment,e.plan) ILIKE '%'||p_query||'%')) x;
 RETURN jsonb_build_object('patient',v_patient,'history',v_history,
  'allergies',(SELECT coalesce(jsonb_agg(description),'[]') FROM public.medical_history WHERE record_id=v_record AND history_type IN ('alergia','alergias')),
  'conditions',(SELECT coalesce(jsonb_agg(description),'[]') FROM public.medical_history WHERE record_id=v_record AND history_type IN ('condicion','enfermedad')),
  'medical_history',(SELECT coalesce(jsonb_agg(history_type||': '||description ORDER BY created_at DESC),'[]') FROM public.medical_history WHERE record_id=v_record),
  'prescriptions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'encounter_id',r.encounter_id,'code',r.prescription_code,'issued_at',r.issued_at,'status',r.status,
    'lines',(SELECT coalesce(jsonb_agg(concat_ws(' ',med.name,med.strength,i.dose,i.dose_unit,'cada',i.frequency_hours,'horas',i.route,
      i.duration_days,'días',i.observations)),'[]') FROM public.prescription_items i JOIN public.medications med ON med.id=i.medication_id WHERE i.prescription_id=r.id)) ORDER BY r.issued_at DESC),'[]')
    FROM public.prescriptions r JOIN public.clinical_encounters e ON e.id=r.encounter_id WHERE e.record_id=v_record AND e.doctor_id=d));
END $function$;

CREATE OR REPLACE FUNCTION public.my_consultation_history(p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('paciente') THEN RAISE EXCEPTION 'Se requiere una cuenta paciente activa' USING ERRCODE='42501'; END IF;
 IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to THEN RAISE EXCEPTION 'Intervalo inválido' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.started_at DESC,x.id DESC),'[]') INTO result FROM (
 SELECT e.id,e.started_at,e.ended_at,e.subjective,e.objective,e.assessment,e.plan,
 concat_ws(' ',pr.first_name,pr.last_name) doctor_name,sp.name specialty,ar.reason,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('diagnosis_code',dg.diagnosis_code,'description',dg.description)),'[]') FROM public.diagnoses dg WHERE dg.encounter_id=e.id) diagnoses,
 (SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]') FROM (SELECT weight_kg,height_cm,systolic,diastolic,temperature_c,heart_rate,recorded_at FROM public.vital_signs WHERE encounter_id=e.id ORDER BY recorded_at DESC,id LIMIT 1)v) vital_signs,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('code',r.prescription_code,'issued_at',r.issued_at,'status',r.status,
   'lines',(SELECT coalesce(jsonb_agg(concat_ws(' ',med.name,med.strength,i.dose,i.dose_unit,'cada',i.frequency_hours,'horas',i.route,i.duration_days,'días',i.observations)),'[]')
    FROM public.prescription_items i JOIN public.medications med ON med.id=i.medication_id WHERE i.prescription_id=r.id)) ORDER BY r.issued_at DESC),'[]')
   FROM public.prescriptions r WHERE r.encounter_id=e.id) prescriptions,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('test_name',t.name,'status',o.status::text,'ordered_at',o.ordered_at,
   'result_summary',CASE WHEN lr.published_to_patient_at IS NOT NULL AND lr.published_at IS NOT NULL AND lr.validated_at IS NOT NULL AND lr.validated_by IS NOT NULL THEN lr.summary END) ORDER BY o.ordered_at DESC),'[]')
   FROM public.lab_orders o JOIN public.lab_test_types t ON t.id=o.test_type_id LEFT JOIN public.lab_results lr ON lr.order_id=o.id WHERE o.encounter_id=e.id) lab_orders
 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id JOIN public.patients p ON p.id=m.patient_id
 JOIN public.staff s ON s.id=e.doctor_id JOIN public.profiles pr ON pr.id=s.profile_id
 LEFT JOIN public.appointments a ON a.id=e.appointment_id LEFT JOIN public.appointment_requests ar ON ar.id=a.request_id LEFT JOIN public.specialties sp ON sp.id=ar.specialty_id
 WHERE p.profile_id=auth.uid() AND e.ended_at IS NOT NULL
 AND (p_from IS NULL OR e.started_at>=p_from) AND (p_to IS NULL OR e.started_at<=p_to)
 AND (p_cursor IS NULL OR (e.started_at,e.id)<((p_cursor->>'value')::timestamptz,(p_cursor->>'id')::uuid))
 ORDER BY e.started_at DESC,e.id DESC LIMIT 26)x;
 RETURN result;
END $function$;

COMMIT;
