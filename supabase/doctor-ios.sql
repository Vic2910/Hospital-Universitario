-- Hospital Móviles: portable v1 clinical API for native clients.
ALTER TABLE public.clinical_encounters
 ADD COLUMN subjective text, ADD COLUMN objective text, ADD COLUMN assessment text, ADD COLUMN plan text,
 ADD COLUMN version integer NOT NULL DEFAULT 0, ADD COLUMN last_save_key uuid;
ALTER TABLE public.clinical_encounters ADD CONSTRAINT clinical_note_lengths
 CHECK(length(subjective)<=10000 AND length(objective)<=10000 AND length(assessment)<=10000 AND length(plan)<=10000);
ALTER TABLE public.prescription_items ADD COLUMN duration_days integer CHECK(duration_days BETWEEN 1 AND 365);

CREATE FUNCTION private.native_doctor_id() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_role('doctor') THEN RAISE EXCEPTION 'Se requiere rol doctor activo' USING ERRCODE='42501'; END IF;
 SELECT id INTO v FROM public.staff WHERE profile_id=auth.uid() AND active AND category='doctor';
 IF v IS NULL THEN RAISE EXCEPTION 'No existe vínculo médico activo' USING ERRCODE='42501'; END IF;
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION private.native_doctor_id() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.native_doctor_encounter(p_encounter uuid,p_open boolean DEFAULT true)
 RETURNS public.clinical_encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters; d uuid=private.native_doctor_id(); a public.appointments;
BEGIN
 SELECT * INTO e FROM public.clinical_encounters WHERE id=p_encounter AND doctor_id=d;
 IF NOT FOUND THEN RAISE EXCEPTION 'Consulta no autorizada' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=e.appointment_id AND doctor_id=d FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.medical_records WHERE id=e.record_id AND patient_id=a.patient_id) THEN
   RAISE EXCEPTION 'Cita o expediente no autorizado' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.clinical_encounters WHERE id=p_encounter FOR UPDATE;
 IF p_open AND (e.ended_at IS NOT NULL OR a.status<>'en_atencion') THEN
   RAISE EXCEPTION 'La consulta no está abierta para edición' USING ERRCODE='22023'; END IF;
 RETURN e;
END $$;
REVOKE ALL ON FUNCTION private.native_doctor_encounter(uuid,boolean) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.doctor_native_workspace(p_from timestamptz,p_to timestamptz) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); v_name text; v_appointments jsonb; v_orders jsonb;
BEGIN
 IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>interval '32 days' THEN
   RAISE EXCEPTION 'Intervalo inválido (máximo 32 días)' USING ERRCODE='22023'; END IF;
 SELECT concat_ws(' ',first_name,last_name) INTO v_name FROM public.profiles WHERE id=auth.uid();
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.period),'[]') INTO v_appointments FROM (
  SELECT a.id,a.patient_id,concat_ws(' ',p.first_name,p.last_name) patient_name,m.record_code record_number,p.phone,
   a.queue_number::text ticket_number,tstzrange(a.starts_at,a.ends_at,'[)')::text period,
   CASE a.status WHEN 'programada' THEN 'scheduled' WHEN 'confirmada' THEN 'confirmed' WHEN 'en_atencion' THEN 'in_progress'
    WHEN 'completada' THEN 'completed' WHEN 'cancelada' THEN 'cancelled' ELSE 'no_show' END status,
   e.id encounter_id,extract(year from age(current_date,p.birth_date))::int age,r.reason,
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
  JOIN public.patients p ON p.id=m.patient_id JOIN public.lab_test_types t ON t.id=o.test_type_id LEFT JOIN public.lab_results lr ON lr.order_id=o.id
  WHERE e.doctor_id=d AND o.ordered_at>=p_from AND o.ordered_at<p_to) x;
 RETURN jsonb_build_object('doctor_name',coalesce(v_name,''),'facility_name','Hospital Universitario','appointments',v_appointments,
  'orders',v_orders,'tests',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'code',id::text,'name',name) ORDER BY name),'[]') FROM public.lab_test_types WHERE active),
  'medications',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'strength',strength,'presentation',presentation) ORDER BY name),'[]') FROM public.medications WHERE active),
  'notifications','[]'::jsonb,'stats',jsonb_build_object('consultations',jsonb_array_length(v_appointments),
   'completed_consultations',(SELECT count(*) FROM jsonb_array_elements(v_appointments) x WHERE x->>'status'='completed'),
   'issued_orders',jsonb_array_length(v_orders),'pending_orders',(SELECT count(*) FROM jsonb_array_elements(v_orders) x WHERE x->>'status'='pendiente')));
END $$;

CREATE FUNCTION public.doctor_native_chart(p_patient uuid,p_from timestamptz DEFAULT NULL,p_to timestamptz DEFAULT NULL,p_query text DEFAULT '') RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); v_record uuid; v_patient jsonb; v_history jsonb;
BEGIN
 IF p_patient IS NULL OR NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no asignado' USING ERRCODE='42501'; END IF;
 IF length(p_query)>120 OR (p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to) THEN RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='22023'; END IF;
 SELECT m.id,jsonb_build_object('id',p.id,'full_name',concat_ws(' ',p.first_name,p.last_name),'record_number',m.record_code,
  'birth_date',p.birth_date,'sex',NULL,'phone',p.phone,'email',NULL,'address',p.city,'identification',NULL)
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

CREATE FUNCTION public.doctor_native_start(p_appointment uuid,p_key uuid) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); a public.appointments; e public.clinical_encounters; r uuid;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=p_appointment AND doctor_id=d FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cita no asignada' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.clinical_encounters WHERE appointment_id=a.id;
 IF FOUND THEN
  IF e.doctor_id<>d THEN RAISE EXCEPTION 'Consulta no autorizada' USING ERRCODE='42501'; END IF;
  RETURN e.id;
 END IF;
 IF a.status NOT IN ('programada','confirmada','en_atencion') OR a.starts_at>now()+interval '30 minutes' THEN
  RAISE EXCEPTION 'La cita todavía no puede iniciarse o ya finalizó' USING ERRCODE='22023'; END IF;
 SELECT id INTO r FROM public.medical_records WHERE patient_id=a.patient_id;
 IF r IS NULL THEN RAISE EXCEPTION 'Recepción debe vincular el expediente' USING ERRCODE='22023'; END IF;
 INSERT INTO public.clinical_encounters(id,record_id,appointment_id,doctor_id) VALUES(p_key,r,a.id,d);
 IF a.status<>'en_atencion' THEN PERFORM public.update_appointment_status(a.id,'en_atencion'); END IF;
 RETURN p_key;
END $$;

CREATE FUNCTION public.doctor_native_save(p_encounter uuid,p_version integer,p_key uuid,p_values jsonb) RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters=private.native_doctor_encounter(p_encounter); v uuid; dg uuid; x jsonb=coalesce(p_values->'vitals','{}');
 w numeric; h numeric; t numeric; sy integer; di integer; hr integer;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 IF e.last_save_key=p_key THEN RETURN e.version; END IF;
 IF e.version IS DISTINCT FROM p_version THEN RAISE EXCEPTION 'El borrador cambió. Actualiza antes de guardar' USING ERRCODE='40001'; END IF;
 IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_each_text(p_values) f WHERE f.key IN ('subjective','objective','assessment','plan') AND length(f.value)>10000)
  OR coalesce(length(p_values->>'diagnosis_code'),0)>50 THEN RAISE EXCEPTION 'Evaluación inválida' USING ERRCODE='22023'; END IF;
 w=nullif(x->>'weight_kg','')::numeric; h=nullif(x->>'height_cm','')::numeric; t=nullif(x->>'temperature_c','')::numeric;
 sy=nullif(x->>'systolic','')::integer; di=nullif(x->>'diastolic','')::integer; hr=nullif(x->>'heart_rate','')::integer;
 IF w<=0 OR w>1000 OR h<=0 OR h>300 OR t<25 OR t>50 OR sy<20 OR sy>350 OR di<10 OR di>250 OR hr<10 OR hr>350
  OR (sy IS NOT NULL AND di IS NOT NULL AND sy<=di) THEN RAISE EXCEPTION 'Signos vitales fuera de rango' USING ERRCODE='22023'; END IF;
 UPDATE public.clinical_encounters SET subjective=p_values->>'subjective',objective=p_values->>'objective',
  assessment=p_values->>'assessment',plan=p_values->>'plan',version=version+1,last_save_key=p_key WHERE id=e.id;
 SELECT id INTO v FROM public.vital_signs WHERE encounter_id=e.id AND recorded_by=auth.uid() ORDER BY recorded_at DESC,id LIMIT 1;
 IF v IS NULL AND num_nonnulls(w,h,t,sy,di,hr)>0 THEN
  INSERT INTO public.vital_signs(encounter_id,weight_kg,height_cm,temperature_c,systolic,diastolic,heart_rate,recorded_by)
   VALUES(e.id,w,h,t,sy,di,hr,auth.uid());
 ELSIF v IS NOT NULL THEN
  UPDATE public.vital_signs SET weight_kg=w,height_cm=h,temperature_c=t,systolic=sy,diastolic=di,heart_rate=hr,recorded_at=now(),recorded_by=auth.uid() WHERE id=v;
 END IF;
 SELECT id INTO dg FROM public.diagnoses WHERE encounter_id=e.id ORDER BY created_at,id LIMIT 1;
 IF nullif(trim(p_values->>'assessment'),'') IS NOT NULL THEN
  IF dg IS NULL THEN INSERT INTO public.diagnoses(encounter_id,diagnosis_code,description) VALUES(e.id,nullif(trim(p_values->>'diagnosis_code'),''),p_values->>'assessment');
  ELSE UPDATE public.diagnoses SET diagnosis_code=nullif(trim(p_values->>'diagnosis_code'),''),description=p_values->>'assessment' WHERE id=dg; END IF;
 END IF;
 RETURN e.version+1;
END $$;

CREATE FUNCTION public.doctor_native_lab(p_encounter uuid,p_test bigint,p_reason text,p_key uuid) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters=private.native_doctor_encounter(p_encounter); v uuid;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 SELECT id INTO v FROM public.lab_orders WHERE id=p_key AND encounter_id=e.id;
 IF FOUND THEN RETURN v; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lab_test_types WHERE id=p_test AND active) OR nullif(trim(p_reason),'') IS NULL OR length(p_reason)>10000 THEN
  RAISE EXCEPTION 'Selecciona examen activo y escribe el motivo' USING ERRCODE='22023'; END IF;
 INSERT INTO public.lab_orders(id,encounter_id,test_type_id,reason) VALUES(p_key,e.id,p_test,trim(p_reason));
 RETURN p_key;
END $$;

CREATE FUNCTION public.doctor_native_prescribe(p_encounter uuid,p_key uuid,p_lines jsonb) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters=private.native_doctor_encounter(p_encounter); v uuid; item jsonb;
BEGIN
 IF p_key IS NULL THEN RAISE EXCEPTION 'Identificador requerido' USING ERRCODE='22023'; END IF;
 SELECT id INTO v FROM public.prescriptions WHERE id=p_key AND encounter_id=e.id;
 IF FOUND THEN RETURN v; END IF;
 IF jsonb_typeof(p_lines) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND 30 THEN
  RAISE EXCEPTION 'La receta requiere de 1 a 30 medicamentos' USING ERRCODE='22023'; END IF;
 INSERT INTO public.prescriptions(id,encounter_id) VALUES(p_key,e.id);
 FOR item IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.medications WHERE id=(item->>'medication_id')::uuid AND active)
   OR (item->>'dose')::numeric IS NULL OR (item->>'dose')::numeric<=0 OR (item->>'dose')::numeric>100000
   OR nullif(trim(item->>'dose_unit'),'') IS NULL OR length(item->>'dose_unit')>40
   OR (item->>'frequency_hours')::integer IS NULL OR (item->>'frequency_hours')::integer NOT BETWEEN 1 AND 720
   OR (item->>'quantity')::integer IS NULL OR (item->>'quantity')::integer NOT BETWEEN 1 AND 10000
   OR (item->>'duration_days')::integer IS NULL OR (item->>'duration_days')::integer NOT BETWEEN 1 AND 365
   OR (item->>'route') IS NULL OR (item->>'route') NOT IN ('oral','inyectable')
   OR nullif(trim(item->>'observations'),'') IS NULL OR length(item->>'observations')>2000 THEN
    RAISE EXCEPTION 'Revisa medicamento, dosis, vía, duración e indicaciones' USING ERRCODE='22023'; END IF;
  INSERT INTO public.prescription_items(prescription_id,medication_id,dose,dose_unit,frequency_hours,route,quantity,duration_days,observations)
   VALUES(p_key,(item->>'medication_id')::uuid,(item->>'dose')::numeric,trim(item->>'dose_unit'),(item->>'frequency_hours')::integer,
    item->>'route',(item->>'quantity')::integer,(item->>'duration_days')::integer,trim(item->>'observations'));
 END LOOP;
 RETURN p_key;
END $$;

CREATE FUNCTION public.doctor_native_finish(p_encounter uuid,p_version integer) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.clinical_encounters=private.native_doctor_encounter(p_encounter,false);
BEGIN
 IF e.ended_at IS NOT NULL THEN RETURN; END IF;
 IF e.version IS DISTINCT FROM p_version OR e.version=0 THEN RAISE EXCEPTION 'Actualiza y guarda antes de finalizar' USING ERRCODE='40001'; END IF;
 IF nullif(trim(e.subjective),'') IS NULL OR nullif(trim(e.objective),'') IS NULL OR nullif(trim(e.assessment),'') IS NULL OR nullif(trim(e.plan),'') IS NULL THEN
  RAISE EXCEPTION 'Completa motivo, exploración, diagnóstico y tratamiento' USING ERRCODE='22023'; END IF;
 UPDATE public.clinical_encounters SET ended_at=now(),version=version+1 WHERE id=e.id;
 PERFORM public.update_appointment_status(e.appointment_id,'completada');
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id) VALUES(auth.uid(),'finalizar_consulta','clinical_encounters',e.id::text);
END $$;

CREATE FUNCTION private.native_complete_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF private.has_role('doctor') AND NOT(private.has_role('admin') OR private.has_role('recepcionista'))
  AND NOT EXISTS(SELECT 1 FROM public.clinical_encounters e WHERE e.appointment_id=NEW.id
   AND e.doctor_id=private.native_doctor_id() AND e.ended_at IS NOT NULL AND e.version>0
   AND nullif(trim(e.subjective),'') IS NOT NULL AND nullif(trim(e.objective),'') IS NOT NULL
   AND nullif(trim(e.assessment),'') IS NOT NULL AND nullif(trim(e.plan),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'Finaliza y firma la consulta antes de marcar la cita atendida' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.native_complete_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER native_complete_guard BEFORE UPDATE OF status ON public.appointments
 FOR EACH ROW WHEN (NEW.status='completada' AND OLD.status IS DISTINCT FROM NEW.status)
 EXECUTE FUNCTION private.native_complete_guard();

REVOKE ALL ON FUNCTION public.doctor_native_workspace(timestamptz,timestamptz),public.doctor_native_chart(uuid,timestamptz,timestamptz,text),
 public.doctor_native_start(uuid,uuid),public.doctor_native_save(uuid,integer,uuid,jsonb),public.doctor_native_lab(uuid,bigint,text,uuid),
 public.doctor_native_prescribe(uuid,uuid,jsonb),public.doctor_native_finish(uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_workspace(timestamptz,timestamptz),public.doctor_native_chart(uuid,timestamptz,timestamptz,text),
 public.doctor_native_start(uuid,uuid),public.doctor_native_save(uuid,integer,uuid,jsonb),public.doctor_native_lab(uuid,bigint,text,uuid),
 public.doctor_native_prescribe(uuid,uuid,jsonb),public.doctor_native_finish(uuid,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
