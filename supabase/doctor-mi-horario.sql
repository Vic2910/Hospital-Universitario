-- Mi horario del médico: lectura de su propia jornada recurrente con descansos y almuerzo — 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO.
--
-- Hallazgo: la jornada recurrente real está en public.staff_recurring_journeys (weekdays, start_time, end_time, shift_type,
-- breaks jsonb con {reason, start_time, end_time}, p. ej. reason 'Almuerzo'). Tiene RLS sin políticas y authenticated no
-- tiene SELECT; la única lectura es read_staff_schedule, exclusiva de administración. Esta RPC da al médico SOLO su propia
-- jornada (native_doctor_id) reutilizando private.recurring_work y private.recurring_instant, igual que read_staff_schedule.
-- No cambia tablas, RLS ni datos. No duplica read_staff_schedule: aquella es de administración y para cualquier empleado.
BEGIN;
CREATE OR REPLACE FUNCTION public.doctor_native_schedule(p_from timestamp with time zone, p_until timestamp with time zone)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE d uuid = private.native_doctor_id(); work jsonb = '[]'; pauses jsonb = '[]'; w record; j public.staff_recurring_journeys%ROWTYPE; b jsonb;
BEGIN
 IF p_from IS NULL OR p_until IS NULL OR p_until <= p_from OR p_until - p_from > interval '32 days' THEN
   RAISE EXCEPTION 'Rango inválido (máximo 32 días)' USING ERRCODE = '22023'; END IF;
 FOR w IN SELECT * FROM private.recurring_work(p_from, p_until, d) LOOP
  SELECT * INTO j FROM public.staff_recurring_journeys WHERE id = w.journey_id;
  work = work || jsonb_build_array(jsonb_build_object('starts_at', w.starts_at, 'ends_at', w.ends_at, 'shift_type', j.shift_type));
  FOR b IN SELECT value FROM jsonb_array_elements(coalesce(j.breaks, '[]')) LOOP
   pauses = pauses || jsonb_build_array(jsonb_build_object(
     'starts_at', private.recurring_instant(w.work_day, (b->>'start_time')::time, j.start_time),
     'ends_at', private.recurring_instant(w.work_day, (b->>'end_time')::time, j.start_time),
     'reason', coalesce(nullif(trim(b->>'reason'), ''), 'Descanso')));
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('work', work, 'breaks', pauses,
  'shifts', (SELECT coalesce(jsonb_agg(jsonb_build_object('starts_at', s.starts_at, 'ends_at', s.ends_at, 'shift_type', s.shift_type, 'status', s.status) ORDER BY s.starts_at), '[]')
     FROM public.staff_shifts s WHERE s.staff_id = d AND s.starts_at < p_until AND s.ends_at > p_from),
  'absences', (SELECT coalesce(jsonb_agg(jsonb_build_object('starts_at', a.starts_at, 'ends_at', a.ends_at, 'reason', a.reason, 'active', a.active) ORDER BY a.starts_at), '[]')
     FROM public.staff_absences a WHERE a.staff_id = d AND a.active AND a.starts_at < p_until AND a.ends_at > p_from));
END $function$;
REVOKE ALL ON FUNCTION public.doctor_native_schedule(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.doctor_native_schedule(timestamptz, timestamptz) TO authenticated;
COMMIT;
