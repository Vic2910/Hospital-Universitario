BEGIN;
CREATE OR REPLACE FUNCTION public.my_consultation_history(p_from timestamptz DEFAULT NULL,p_to timestamptz DEFAULT NULL,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('paciente') THEN RAISE EXCEPTION 'Se requiere una cuenta paciente activa' USING ERRCODE='42501'; END IF;
 IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to THEN RAISE EXCEPTION 'Intervalo inválido' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.started_at DESC,x.id DESC),'[]') INTO result FROM (
 SELECT e.id,e.started_at,e.ended_at,e.subjective,e.objective,e.assessment,e.plan,
 concat_ws(' ',pr.first_name,pr.last_name) doctor_name,sp.name specialty,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('diagnosis_code',dg.diagnosis_code,'description',dg.description)),'[]') FROM public.diagnoses dg WHERE dg.encounter_id=e.id) diagnoses,
 (SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]') FROM (SELECT weight_kg,height_cm,systolic,diastolic,temperature_c,heart_rate,recorded_at FROM public.vital_signs WHERE encounter_id=e.id ORDER BY recorded_at DESC,id LIMIT 1)v) vital_signs
 FROM public.clinical_encounters e JOIN public.medical_records m ON m.id=e.record_id JOIN public.patients p ON p.id=m.patient_id
 JOIN public.staff s ON s.id=e.doctor_id JOIN public.profiles pr ON pr.id=s.profile_id
 LEFT JOIN public.appointments a ON a.id=e.appointment_id LEFT JOIN public.appointment_requests ar ON ar.id=a.request_id LEFT JOIN public.specialties sp ON sp.id=ar.specialty_id
 WHERE p.profile_id=auth.uid() AND e.ended_at IS NOT NULL
 AND (p_from IS NULL OR e.started_at>=p_from) AND (p_to IS NULL OR e.started_at<=p_to)
 AND (p_cursor IS NULL OR (e.started_at,e.id)<((p_cursor->>'value')::timestamptz,(p_cursor->>'id')::uuid))
 ORDER BY e.started_at DESC,e.id DESC LIMIT 26)x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.my_consultation_history(timestamptz,timestamptz,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_consultation_history(timestamptz,timestamptz,jsonb) TO authenticated;
COMMIT;