-- Hospital Móviles: requests reuse hospital_admissions; no duplicate hospitalization tables.
ALTER TABLE public.hospital_admissions
 ADD COLUMN request_key uuid,
 ADD COLUMN decision text CHECK (decision IN ('rechazada','cancelada')),
 ADD COLUMN decision_reason text CHECK (length(decision_reason)<=10000),
 ADD COLUMN decided_at timestamptz,
 ADD COLUMN decided_by uuid REFERENCES public.profiles(id);
CREATE UNIQUE INDEX admission_request_retry ON public.hospital_admissions(ordered_by,request_key) WHERE request_key IS NOT NULL;

CREATE FUNCTION private.native_admission_audit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  VALUES(auth.uid(),'estado_ingreso','hospital_admissions',NEW.id::text,
   jsonb_build_object('status',NEW.status,'previous_status',CASE WHEN TG_OP='UPDATE' THEN OLD.status END,
    'decision',NEW.decision,'reason',NEW.decision_reason));
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.native_admission_audit() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER native_admission_audit AFTER INSERT OR UPDATE OF status ON public.hospital_admissions
 FOR EACH ROW EXECUTE FUNCTION private.native_admission_audit();

-- Keep the existing reception integration signature and enforce the active medical link.
CREATE OR REPLACE FUNCTION public.request_admission(p_patient uuid,p_kind public.room_kind,p_reason text,
 p_instructions text DEFAULT NULL,p_encounter uuid DEFAULT NULL) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); v uuid;
BEGIN
 IF NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no autorizado' USING ERRCODE='42501'; END IF;
 IF p_kind IS NULL OR nullif(trim(p_reason),'') IS NULL OR length(p_reason)>10000 OR length(p_instructions)>10000 THEN
  RAISE EXCEPTION 'Completa categoría y motivo clínico (máximo 10000 caracteres)' USING ERRCODE='22023'; END IF;
 IF p_encounter IS NOT NULL AND (private.encounter_patient(p_encounter) IS DISTINCT FROM p_patient OR NOT private.encounter_doctor(p_encounter)) THEN
  RAISE EXCEPTION 'Atención inválida' USING ERRCODE='42501'; END IF;
 INSERT INTO public.hospital_admissions(patient_id,ordered_by,encounter_id,requested_kind,medical_reason,clinical_instructions)
 VALUES(p_patient,d,p_encounter,p_kind,trim(p_reason),nullif(trim(p_instructions),'')) RETURNING id INTO v;
 RETURN v;
END $$;

CREATE FUNCTION public.doctor_native_admission_request(p_patient uuid,p_kind public.room_kind,p_reason text,
 p_instructions text,p_priority text,p_encounter uuid,p_key uuid) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); a public.hospital_admissions; v uuid;
BEGIN
 IF NOT private.treats_patient(p_patient) THEN RAISE EXCEPTION 'Paciente no autorizado' USING ERRCODE='42501'; END IF;
 IF p_key IS NULL OR p_priority IS NULL OR p_priority NOT IN ('normal','urgente') THEN
  RAISE EXCEPTION 'Prioridad o clave inválida' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(d::text||p_key::text,0));
 SELECT * INTO a FROM public.hospital_admissions WHERE ordered_by=d AND request_key=p_key;
 IF FOUND THEN
  IF a.patient_id IS DISTINCT FROM p_patient OR a.requested_kind IS DISTINCT FROM p_kind OR a.priority IS DISTINCT FROM p_priority
   OR a.medical_reason IS DISTINCT FROM trim(p_reason) OR a.clinical_instructions IS DISTINCT FROM nullif(trim(p_instructions),'')
   OR a.encounter_id IS DISTINCT FROM p_encounter THEN RAISE EXCEPTION 'La solicitud enviada cambió; actualiza el seguimiento' USING ERRCODE='22023'; END IF;
  RETURN a.id;
 END IF;
 v=public.request_admission(p_patient,p_kind,p_reason,p_instructions,p_encounter);
 UPDATE public.hospital_admissions SET priority=p_priority,request_key=p_key WHERE id=v;
 RETURN v;
END $$;

CREATE FUNCTION private.native_admission_rows(p_doctor uuid,p_offset integer,p_status text DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH permitted AS (
  SELECT a.*,concat_ws(' ',p.first_name,p.last_name) patient_name,m.record_code record_number,
   concat_ws(' ',pr.first_name,pr.last_name) doctor_name
  FROM public.hospital_admissions a JOIN public.patients p ON p.id=a.patient_id
  LEFT JOIN public.medical_records m ON m.patient_id=p.id JOIN public.staff s ON s.id=a.ordered_by
  JOIN public.profiles pr ON pr.id=s.profile_id
  WHERE (p_doctor IS NULL OR (a.ordered_by=p_doctor AND private.treats_patient(a.patient_id)))
   AND (p_status IS NULL OR a.status::text=p_status)
 ), paged AS (SELECT * FROM permitted ORDER BY ordered_at DESC,id DESC LIMIT 25 OFFSET p_offset), rows AS (
  SELECT a.id,a.patient_id,a.patient_name,a.record_number,a.doctor_name,a.requested_kind::text category,
   a.medical_reason reason,a.clinical_instructions observations,a.priority,a.status::text status,
   a.ordered_at,a.encounter_id,a.decision,a.decision_reason,a.decided_at,
   (SELECT jsonb_build_object('room',r.code,'bed',b.code,'floor',f.name,'assigned_at',ba.assigned_at,'released_at',ba.released_at)
    FROM public.bed_assignments ba JOIN public.beds b ON b.id=ba.bed_id JOIN public.rooms r ON r.id=b.room_id
    JOIN public.hospital_floors f ON f.id=r.floor_id WHERE ba.admission_id=a.id ORDER BY ba.assigned_at DESC LIMIT 1) assignment,
   coalesce((SELECT jsonb_agg(jsonb_build_object('status',h.metadata->>'status','decision',h.metadata->>'decision',
    'reason',h.metadata->>'reason','at',h.occurred_at) ORDER BY h.occurred_at,h.id) FROM public.audit_logs h
    WHERE h.entity_type='hospital_admissions' AND h.entity_id=a.id::text AND h.action='estado_ingreso'),'[]') history
  FROM paged a
 ) SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(to_jsonb(rows) ORDER BY ordered_at DESC,id DESC) FROM rows),'[]'),
  'total',(SELECT count(*) FROM permitted),'has_more',(SELECT count(*) FROM permitted)>p_offset+25,
  'next_offset',CASE WHEN (SELECT count(*) FROM permitted)>p_offset+25 THEN p_offset+25 END);
$$;
REVOKE ALL ON FUNCTION private.native_admission_rows(uuid,integer,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.doctor_native_admissions(p_offset integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid=private.native_doctor_id(); v jsonb;
BEGIN
 IF p_offset IS NULL OR p_offset<0 THEN RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 v=private.native_admission_rows(d,p_offset);
 RETURN v||jsonb_build_object('doctor_name',(SELECT concat_ws(' ',first_name,last_name) FROM public.profiles WHERE id=auth.uid()),
  'categories',(SELECT jsonb_agg(k::text) FROM unnest(enum_range(NULL::public.room_kind)) k),
  'priorities',jsonb_build_array('normal','urgente'));
END $$;

CREATE FUNCTION public.reception_admissions(p_offset integer DEFAULT 0,p_status text DEFAULT NULL) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT (private.has_role('recepcionista') OR private.has_role('admin')) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 IF p_offset IS NULL OR p_offset<0 OR (p_status IS NOT NULL AND NOT EXISTS(SELECT 1 FROM unnest(enum_range(NULL::public.admission_state)) s WHERE s::text=p_status)) THEN
  RAISE EXCEPTION 'Filtro inválido' USING ERRCODE='22023'; END IF;
 RETURN private.native_admission_rows(NULL,p_offset,p_status);
END $$;

CREATE FUNCTION public.reception_admission_availability(p_admission uuid) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.hospital_admissions; v jsonb;
BEGIN
 IF NOT (private.has_role('recepcionista') OR private.has_role('admin')) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM public.hospital_admissions WHERE id=p_admission;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('bed_id',b.id,'bed',b.code,'room_id',r.id,'room',r.code,'category',r.kind,
  'floor',f.name) ORDER BY r.code,b.code),'[]') INTO v
 FROM public.beds b JOIN public.rooms r ON r.id=b.room_id JOIN public.hospital_floors f ON f.id=r.floor_id
 WHERE r.active AND r.kind=a.requested_kind AND b.state='disponible'
  AND NOT EXISTS(SELECT 1 FROM public.bed_assignments ba WHERE ba.bed_id=b.id AND ba.released_at IS NULL);
 RETURN jsonb_build_object('beds',v,'checked_at',now(),'reservation',false);
END $$;

CREATE FUNCTION public.reception_resolve_admission(p_admission uuid,p_action text,p_reason text DEFAULT NULL,p_bed uuid DEFAULT NULL) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.hospital_admissions;
BEGIN
 IF NOT (private.has_role('recepcionista') OR private.has_role('admin')) THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM public.hospital_admissions WHERE id=p_admission FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente' USING ERRCODE='22023'; END IF;
 IF p_action='asignar' THEN
  IF a.status='hospitalizado' AND EXISTS(SELECT 1 FROM public.bed_assignments WHERE admission_id=a.id AND bed_id=p_bed AND released_at IS NULL) THEN RETURN; END IF;
  PERFORM public.assign_bed(p_admission,p_bed); RETURN;
 END IF;
 IF p_action IS NULL OR p_action NOT IN ('rechazar','cancelar') OR nullif(trim(p_reason),'') IS NULL OR length(p_reason)>10000 OR p_bed IS NOT NULL THEN
  RAISE EXCEPTION 'Indica rechazo/cancelación y justificación' USING ERRCODE='22023'; END IF;
 IF a.status='cancelado' AND a.decision=(CASE p_action WHEN 'rechazar' THEN 'rechazada' ELSE 'cancelada' END) AND a.decision_reason=trim(p_reason) THEN RETURN; END IF;
 IF a.status<>'solicitado' THEN RAISE EXCEPTION 'Solo puede rechazarse o cancelarse una solicitud pendiente sin cama' USING ERRCODE='22023'; END IF;
 UPDATE public.hospital_admissions SET status='cancelado',decision=CASE p_action WHEN 'rechazar' THEN 'rechazada' ELSE 'cancelada' END,
  decision_reason=trim(p_reason),decided_by=auth.uid(),decided_at=now() WHERE id=a.id;
END $$;

REVOKE ALL ON FUNCTION public.doctor_native_admission_request(uuid,public.room_kind,text,text,text,uuid,uuid),
 public.doctor_native_admissions(integer),public.reception_admissions(integer,text),
 public.reception_admission_availability(uuid),public.reception_resolve_admission(uuid,text,text,uuid),
 public.request_admission(uuid,public.room_kind,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_admission_request(uuid,public.room_kind,text,text,text,uuid,uuid),
 public.doctor_native_admissions(integer),public.reception_admissions(integer,text),
 public.reception_admission_availability(uuid),public.reception_resolve_admission(uuid,text,text,uuid),
 public.request_admission(uuid,public.room_kind,text,text,uuid) TO authenticated;
