-- Extend the existing laboratory contract; one lab_orders row per exam remains unchanged for the panel.
ALTER TABLE public.lab_test_types
 ADD COLUMN code text NOT NULL DEFAULT ('EXAM-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16))),
 ADD COLUMN category text;
ALTER TABLE public.lab_test_types ADD CONSTRAINT lab_test_types_code_key UNIQUE(code);
ALTER TABLE public.lab_orders ADD COLUMN request_group uuid;
CREATE UNIQUE INDEX lab_request_group_exam ON public.lab_orders(encounter_id,request_group,test_type_id) WHERE request_group IS NOT NULL;

-- Existing glucose is the same basic exam; a lipid panel does not duplicate the individual cholesterol/triglyceride tests.
UPDATE public.lab_test_types SET category='Sangre' WHERE lower(name) IN ('hemograma completo','glucosa','perfil lipídico');
UPDATE public.lab_test_types SET category='Orina' WHERE lower(name)='examen general de orina';
DO $$
DECLARE x record;
BEGIN
 FOR x IN SELECT * FROM (VALUES
  ('Examen general de heces','HECES-GENERAL','Heces'),('Colesterol total','COLESTEROL-TOTAL','Sangre'),
  ('Triglicéridos','TRIGLICERIDOS','Sangre'),('Creatinina','CREATININA','Sangre'),
  ('Urea','UREA','Sangre'),('Ácido úrico','ACIDO-URICO','Sangre')) v(name,code,category)
 LOOP
  IF NOT EXISTS(SELECT 1 FROM public.lab_test_types WHERE translate(lower(trim(name)),'áéíóú','aeiou')=translate(lower(x.name),'áéíóú','aeiou')) THEN
   INSERT INTO public.lab_test_types(name,code,category) VALUES(x.name,x.code,x.category);
  END IF;
 END LOOP;
END $$;

CREATE FUNCTION public.doctor_native_lab_catalog() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.native_doctor_id();
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'category',category) ORDER BY name),'[]')
  FROM public.lab_test_types WHERE active);
END $$;

CREATE FUNCTION public.doctor_native_labs(p_encounter uuid,p_tests bigint[],p_reason text,p_key uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters=private.native_doctor_encounter(p_encounter,false); tests bigint[]; existing bigint[]; t bigint; oid uuid; ids uuid[]='{}';
BEGIN
 IF p_key IS NULL OR p_tests IS NULL OR cardinality(p_tests) NOT BETWEEN 1 AND 30 OR array_position(p_tests,NULL) IS NOT NULL
  OR nullif(trim(p_reason),'') IS NULL OR length(p_reason)>10000 THEN RAISE EXCEPTION 'Selecciona de 1 a 30 exámenes e indica el motivo clínico' USING ERRCODE='22023'; END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO tests FROM unnest(p_tests) x;
 IF cardinality(tests)<>cardinality(p_tests) THEN RAISE EXCEPTION 'No repitas exámenes en la selección' USING ERRCODE='22023'; END IF;
 SELECT array_agg(test_type_id ORDER BY test_type_id),array_agg(id ORDER BY test_type_id) INTO existing,ids
  FROM public.lab_orders WHERE encounter_id=e.id AND request_group=p_key;
 IF existing IS NOT NULL THEN
  IF existing IS DISTINCT FROM tests OR EXISTS(SELECT 1 FROM public.lab_orders WHERE encounter_id=e.id AND request_group=p_key AND reason IS DISTINCT FROM trim(p_reason)) THEN
   RAISE EXCEPTION 'El envío ya existe con otro contenido; actualiza las órdenes' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('order_ids',ids,'count',cardinality(ids));
 END IF;
 IF e.ended_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM public.appointments WHERE id=e.appointment_id AND status='en_atencion') THEN
  RAISE EXCEPTION 'Se requiere una consulta propia abierta' USING ERRCODE='22023'; END IF;
 IF (SELECT count(*) FROM public.lab_test_types WHERE id=ANY(tests) AND active)<>cardinality(tests) THEN
  RAISE EXCEPTION 'Uno de los exámenes ya no está activo; actualiza el catálogo' USING ERRCODE='22023'; END IF;
 ids='{}';
 FOREACH t IN ARRAY tests LOOP
  oid=md5(e.id::text||':'||p_key::text||':'||t::text)::uuid;
  PERFORM public.doctor_native_lab(e.id,t,trim(p_reason),oid);
  UPDATE public.lab_orders SET request_group=p_key WHERE id=oid AND encounter_id=e.id;
  ids=array_append(ids,oid);
 END LOOP;
 RETURN jsonb_build_object('order_ids',ids,'count',cardinality(ids));
END $$;

CREATE FUNCTION private.native_mobile_lab_page(p_patient uuid,p_doctor uuid,p_offset integer) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH permitted AS MATERIALIZED (
  SELECT o.id,o.encounter_id,o.test_type_id,o.reason,o.status::text status,o.ordered_at,o.request_group,
   t.name test_name,t.category,m.patient_id,m.record_code record_number,concat_ws(' ',p.first_name,p.last_name) patient_name,
   r.summary result_summary,r.completed_at,r.published_at,
   coalesce((SELECT jsonb_agg(jsonb_build_object('label',s->>'label','value',r.result_values->(s->>'key')->>'value',
    'unit',s->>'unit','reference',s->>'reference','observation',r.result_values->(s->>'key')->>'observation') ORDER BY n)
    FROM jsonb_array_elements(coalesce(r.parameter_schema,'[]')) WITH ORDINALITY a(s,n)),'[]') parameters
  FROM public.lab_orders o JOIN public.clinical_encounters e ON e.id=o.encounter_id
  JOIN public.medical_records m ON m.id=e.record_id JOIN public.patients p ON p.id=m.patient_id
  JOIN public.lab_test_types t ON t.id=o.test_type_id
  LEFT JOIN public.lab_results r ON r.order_id=o.id AND r.published_at IS NOT NULL AND r.validated_at IS NOT NULL AND r.validated_by IS NOT NULL
  WHERE (p_patient IS NOT NULL AND m.patient_id=p_patient) OR
   (p_doctor IS NOT NULL AND e.doctor_id=p_doctor AND private.treats_patient(m.patient_id))
 ), page AS (SELECT * FROM permitted ORDER BY ordered_at DESC,id DESC LIMIT 25 OFFSET p_offset)
 SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY ordered_at DESC,id DESC) FROM page x),'[]'),
  'total',(SELECT count(*) FROM permitted),'has_more',(SELECT count(*) FROM permitted)>p_offset+25,
  'next_offset',CASE WHEN (SELECT count(*) FROM permitted)>p_offset+25 THEN p_offset+25 END);
$$;
REVOKE ALL ON FUNCTION private.native_mobile_lab_page(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.doctor_native_patient_labs(p_patient uuid,p_offset integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.native_doctor_id();
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no asignado' USING ERRCODE='42501'; END IF;
 IF p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 RETURN private.native_mobile_lab_page(p_patient,NULL,p_offset);
END $$;

CREATE FUNCTION public.doctor_native_lab_orders(p_offset integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id();
BEGIN
 IF p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 RETURN private.native_mobile_lab_page(NULL,d,p_offset);
END $$;
REVOKE ALL ON FUNCTION public.doctor_native_lab_catalog(),public.doctor_native_labs(uuid,bigint[],text,uuid),
 public.doctor_native_lab_orders(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_lab_catalog(),public.doctor_native_labs(uuid,bigint[],text,uuid),
 public.doctor_native_lab_orders(integer) TO authenticated;
NOTIFY pgrst,'reload schema';
