-- Lecturas del médico: código de paciente, hora real de finalización y orden de la agenda — actualizado el 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO. Requiere autorización expresa antes de ejecutarlo en Hospital Móviles (uvebpsbbwofthucghccc).
--
-- Historia: este archivo relajaba doctor_native_finish y native_complete_guard para no exigir `plan`. El 20 de noviembre
-- el usuario pidió que el plan de tratamiento tenga su propio campo obligatorio, de modo que el cierre ya funciona con lo
-- desplegado y esas dos funciones se retiraron de aquí (no deben aplicarse). Queda solo:
--   * doctor_native_workspace: publica patients.patient_code y finished_at (clinical_encounters.ended_at) y ordena por
--     a.starts_at en lugar del texto del intervalo.
--   * doctor_native_chart: publica patient_code (expedientes-historial.sql contiene una versión más completa; si se
--     aplican ambos, aplicar expedientes-historial.sql después).
-- No cambia RLS, GRANT ni datos.
BEGIN;

CREATE OR REPLACE FUNCTION public.doctor_native_workspace(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE d uuid=private.native_doctor_id(); v_name text; v_appointments jsonb; v_orders jsonb;
BEGIN
 IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>interval '32 days' THEN
   RAISE EXCEPTION 'Intervalo inválido (máximo 32 días)' USING ERRCODE='22023'; END IF;
 SELECT concat_ws(' ',first_name,last_name) INTO v_name FROM public.profiles WHERE id=auth.uid();
 SELECT coalesce(jsonb_agg(to_jsonb(x)-'starts_at' ORDER BY x.starts_at,x.id),'[]') INTO v_appointments FROM (
  SELECT a.id,a.patient_id,concat_ws(' ',p.first_name,p.last_name) patient_name,m.record_code record_number,p.patient_code,p.phone,
   a.queue_number::text ticket_number,tstzrange(a.starts_at,a.ends_at,'[)')::text period,
   CASE a.status WHEN 'programada' THEN 'scheduled' WHEN 'confirmada' THEN 'confirmed' WHEN 'en_atencion' THEN 'in_progress'
    WHEN 'completada' THEN 'completed' WHEN 'cancelada' THEN 'cancelled' ELSE 'no_show' END status,
   e.id encounter_id,e.ended_at finished_at,a.starts_at,extract(year from age(current_date,p.birth_date))::int age,r.reason,
   CASE WHEN r.id IS NULL THEN NULL ELSE coalesce((SELECT jsonb_agg(s.name ORDER BY s.id)
    FROM public.appointment_request_symptoms rs JOIN public.symptom_catalog s ON s.id=rs.symptom_id WHERE rs.request_id=r.id),'[]') END symptoms,
   r.other_symptoms,sp.name specialty,cr.code room_code,extract(epoch from a.ends_at-a.starts_at)::int/60 duration_minutes
  FROM public.appointments a JOIN public.patients p ON p.id=a.patient_id JOIN public.medical_records m ON m.patient_id=p.id
  LEFT JOIN public.clinical_encounters e ON e.appointment_id=a.id LEFT JOIN public.appointment_requests r ON r.id=a.request_id
  LEFT JOIN public.specialties sp ON sp.id=r.specialty_id LEFT JOIN public.consulting_rooms cr ON cr.id=a.consulting_room_id
  WHERE a.doctor_id=d AND a.starts_at>=p_from AND a.starts_at<p_to) x;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.issued_at DESC),'[]') INTO v_orders FROM (
  SELECT o.id,m.patient_id,concat_ws(' ',p.first_name,p.last_name) patient_name,NULL::text ticket_number,p.phone,
   t.name test_name,o.ordered_at issued_at,'Hospital Universitario'::text facility_name,v_name doctor_name,o.reason instructions,
   o.status::text status,0 row_version,lr.summary result_summary
  FROM public.lab_orders o JOIN public.clinical_encounters e ON e.id=o.encounter_id JOIN public.medical_records m ON m.id=e.record_id
  JOIN public.patients p ON p.id=m.patient_id JOIN public.lab_test_types t ON t.id=o.test_type_id LEFT JOIN public.lab_results lr ON lr.order_id=o.id AND lr.published_at IS NOT NULL AND lr.validated_at IS NOT NULL AND lr.validated_by IS NOT NULL
  WHERE e.doctor_id=d AND o.ordered_at>=p_from AND o.ordered_at<p_to) x;
 RETURN jsonb_build_object('doctor_name',coalesce(v_name,''),'facility_name','Hospital Universitario','appointments',v_appointments,
  'orders',v_orders,'tests',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'code',id::text,'name',name) ORDER BY name),'[]') FROM public.lab_test_types WHERE active),
  'medications',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'strength',strength,'presentation',presentation) ORDER BY name),'[]') FROM public.medications WHERE active),
  'notifications','[]'::jsonb,'stats',jsonb_build_object('consultations',jsonb_array_length(v_appointments),
   'completed_consultations',(SELECT count(*) FROM jsonb_array_elements(v_appointments) x WHERE x->>'status'='completed'),
   'issued_orders',jsonb_array_length(v_orders),'pending_orders',(SELECT count(*) FROM jsonb_array_elements(v_orders) x WHERE x->>'status'='pendiente')));
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
  SELECT e.id,e.started_at,CASE WHEN e.ended_at IS NULL THEN 'open' ELSE 'closed' END status,
   e.subjective,e.objective,e.assessment,e.plan,CASE WHEN e.version>0 THEN e.id ELSE NULL END note_id,
   e.version note_version,e.version row_version,
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
  'prescriptions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'code',r.prescription_code,'issued_at',r.issued_at,'status',r.status,
    'lines',(SELECT coalesce(jsonb_agg(concat_ws(' ',med.name,med.strength,i.dose,i.dose_unit,'cada',i.frequency_hours,'horas',i.route,
      i.duration_days,'días',i.observations)),'[]') FROM public.prescription_items i JOIN public.medications med ON med.id=i.medication_id WHERE i.prescription_id=r.id)) ORDER BY r.issued_at DESC),'[]')
    FROM public.prescriptions r JOIN public.clinical_encounters e ON e.id=r.encounter_id WHERE e.record_id=v_record AND e.doctor_id=d));
END $function$;

COMMIT;
