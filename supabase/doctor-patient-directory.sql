-- All authorized patients, independent of the day selected in the appointment calendar.
CREATE FUNCTION public.doctor_native_patients(p_query text DEFAULT '',p_offset integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); rows jsonb; total bigint; q text=lower(trim(coalesce(p_query,'')));
BEGIN
 IF length(q)>120 OR p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Búsqueda inválida' USING ERRCODE='22023'; END IF;
 WITH authorized AS MATERIALIZED (
  SELECT p.id,concat_ws(' ',p.first_name,p.last_name) full_name,m.record_code record_number,p.dui,u.email,p.phone,p.birth_date,
   extract(year FROM age((now() AT TIME ZONE 'America/Guatemala')::date,p.birth_date))::int age,
   (SELECT e.id FROM public.clinical_encounters e JOIN public.appointments a ON a.id=e.appointment_id
    WHERE e.record_id=m.id AND e.doctor_id=d AND e.ended_at IS NULL AND a.status='en_atencion'
    ORDER BY e.started_at DESC,e.id LIMIT 1) active_encounter_id
  FROM public.patients p LEFT JOIN public.medical_records m ON m.patient_id=p.id
  LEFT JOIN auth.users u ON u.id=p.profile_id WHERE private.treats_patient(p.id)
 ), matches AS MATERIALIZED (
  SELECT * FROM authorized a WHERE q='' OR strpos(lower(a.full_name),q)>0 OR strpos(lower(coalesce(a.email,'')),q)>0
   OR strpos(coalesce(a.dui,''),q)>0 OR strpos(lower(coalesce(a.record_number,'')),q)>0
   OR (q ~ '^[0-9 -]+$' AND regexp_replace(q,'[^0-9]','','g')<>''
     AND strpos(regexp_replace(coalesce(a.dui,''),'[^0-9]','','g'),regexp_replace(q,'[^0-9]','','g'))>0)
 ), page AS (SELECT * FROM matches ORDER BY lower(full_name),id LIMIT 50 OFFSET p_offset)
 SELECT (SELECT count(*) FROM matches),coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY lower(p.full_name),p.id) FROM page p),'[]') INTO total,rows;
 RETURN jsonb_build_object('patients',rows,'total',total,'has_more',p_offset+jsonb_array_length(rows)<total,
  'next_offset',CASE WHEN p_offset+jsonb_array_length(rows)<total THEN p_offset+jsonb_array_length(rows) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.doctor_native_patients(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_patients(text,integer) TO authenticated;

CREATE FUNCTION public.doctor_native_patient_labs(p_patient uuid,p_offset integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); rows jsonb; total bigint;
BEGIN
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no asignado' USING ERRCODE='42501'; END IF;
 IF p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 WITH authorized AS MATERIALIZED (
  SELECT o.id,t.name test_name,o.reason,o.status::text status,o.ordered_at,r.summary result_summary,r.completed_at
  FROM public.lab_orders o JOIN public.clinical_encounters e ON e.id=o.encounter_id
  JOIN public.medical_records m ON m.id=e.record_id JOIN public.lab_test_types t ON t.id=o.test_type_id
  LEFT JOIN public.lab_results r ON r.order_id=o.id WHERE m.patient_id=p_patient
 ), page AS (SELECT * FROM authorized ORDER BY ordered_at DESC,id DESC LIMIT 25 OFFSET p_offset)
 SELECT (SELECT count(*) FROM authorized),coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.ordered_at DESC,p.id DESC) FROM page p),'[]') INTO total,rows;
 RETURN jsonb_build_object('items',rows,'total',total,'has_more',p_offset+jsonb_array_length(rows)<total,
  'next_offset',CASE WHEN p_offset+jsonb_array_length(rows)<total THEN p_offset+jsonb_array_length(rows) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.doctor_native_patient_labs(uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_patient_labs(uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.doctor_native_chart(p_patient uuid,p_from timestamptz DEFAULT NULL,p_to timestamptz DEFAULT NULL,p_query text DEFAULT '') RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); v_record uuid; v_patient jsonb; v_history jsonb;
BEGIN
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no asignado' USING ERRCODE='42501'; END IF;
 IF length(p_query)>120 OR (p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to) THEN RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='22023'; END IF;
 SELECT m.id,jsonb_build_object('id',p.id,'full_name',concat_ws(' ',p.first_name,p.last_name),'record_number',m.record_code,
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
END $$;
NOTIFY pgrst,'reload schema';
