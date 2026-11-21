-- Médicos de turno como información pública (requisito del enunciado: «Información pública: ... médicos de turno»).
-- Devuelve SOLO nombre y especialidades de los médicos que trabajan en este momento: jornada recurrente vigente
-- (private.recurring_work) o turno puntual no cancelado (staff_shifts), excluyendo ausencias activas.
-- No expone horarios completos, consultorios, códigos de empleado ni datos personales. Sin tablas nuevas ni cambios de RLS.
BEGIN;

CREATE OR REPLACE FUNCTION public.public_on_duty()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 WITH working AS (
   SELECT w.staff_id FROM private.recurring_work(now(), now() + interval '1 second') w
   UNION
   SELECT s.staff_id FROM public.staff_shifts s WHERE s.status <> 'cancelado' AND s.starts_at <= now() AND s.ends_at > now()
 ), doctors AS (
   SELECT st.id, concat_ws(' ', pr.first_name, pr.last_name) AS name
   FROM working w
   JOIN public.staff st ON st.id = w.staff_id AND st.active AND st.category = 'doctor'
   JOIN public.profiles pr ON pr.id = st.profile_id
   WHERE NOT EXISTS (SELECT 1 FROM public.staff_absences a
                     WHERE a.staff_id = st.id AND a.active AND a.starts_at <= now() AND a.ends_at > now())
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('name', d.name,
          'specialty', coalesce((SELECT string_agg(sp.name, ', ' ORDER BY sp.name)
                                 FROM public.doctor_specialties ds JOIN public.specialties sp ON sp.id = ds.specialty_id AND sp.active
                                 WHERE ds.doctor_id = d.id), 'Medicina general'))
          ORDER BY d.name), '[]'::jsonb)
 FROM doctors d
$function$;
REVOKE ALL ON FUNCTION public.public_on_duty() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_on_duty() TO anon, authenticated;

COMMIT;
