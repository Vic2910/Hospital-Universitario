-- Citas no atendidas automáticas, aviso de cancelación al médico, turno único por hospital y día y avisos de jornada.
-- 20 de noviembre de 2026. PREPARADO, NO APLICADO. Requiere autorización expresa en Hospital Móviles (uvebpsbbwofthucghccc).
--
-- Base inspeccionada con el MCP en solo lectura:
--   * appointment_state: programada, confirmada, en_atencion, completada, cancelada, no_asistio.
--     update_appointment_status permite programada/confirmada → no_asistio; nada marcaba citas vencidas.
--   * appointments ya impide solapes (EXCLUDE por médico, consultorio y paciente en estados activos) y turnos <= 0.
--   * private.assign_appointment_queue numera por (doctor_id, queue_date) con private.appointment_queue_counters
--     e índice único (doctor_id, queue_date, queue_number). El 2026-11-14 hay un número repetido entre dos médicos.
--   * cancel_appointment registra cancelled_by, cancelled_at, cancellation_reason y el historial; no avisa al médico.
--   * Jornada: doctor_schedules (semanal), staff_shifts (por fecha), staff_absences y staff_recurring_journeys (breaks con
--     motivo, p. ej. «Almuerzo»; la lee el médico con doctor_native_schedule de doctor-mi-horario.sql).
--   * pg_cron está disponible pero no instalado.
-- No elimina datos, no cambia RLS ni GRANT de tablas existentes. Idempotente: se puede ejecutar de nuevo.
BEGIN;

-- 1. Citas no atendidas -------------------------------------------------------------------------------------------
-- Una cita programada o confirmada cuya hora de fin ya pasó y que nunca se abrió pasa a no_asistio.
-- Las abiertas (en_atencion), atendidas o con consulta creada nunca se tocan. Conserva todos sus datos y el turno.
CREATE OR REPLACE FUNCTION private.mark_missed_appointments()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE n integer;
BEGIN
 WITH candidates AS (
   SELECT a.id, a.status FROM public.appointments a
   WHERE a.status IN ('programada','confirmada') AND a.ends_at < now()
     AND NOT EXISTS (SELECT 1 FROM public.clinical_encounters e WHERE e.appointment_id = a.id)
   FOR UPDATE SKIP LOCKED),
 updated AS (
   UPDATE public.appointments a SET status = 'no_asistio' FROM candidates c
   WHERE a.id = c.id AND a.status = c.status RETURNING a.id, c.status AS old_status)
 INSERT INTO public.appointment_status_history(appointment_id, old_status, new_status, actor_id)
 SELECT id, old_status, 'no_asistio', NULL FROM updated;
 GET DIAGNOSTICS n = ROW_COUNT;
 RETURN n;
END $function$;
REVOKE ALL ON FUNCTION private.mark_missed_appointments() FROM PUBLIC, anon, authenticated;

-- Ejecución automática cada 5 minutos en el servidor (no depende de que alguien abra la app).
CREATE EXTENSION IF NOT EXISTS pg_cron;
DO $cron$
BEGIN
 PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'hospital-mark-missed-appointments';
 PERFORM cron.schedule('hospital-mark-missed-appointments', '*/5 * * * *', 'SELECT private.mark_missed_appointments()');
END $cron$;

-- 2. Aviso al médico cuando se cancela una cita -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.doctor_cancellation_notice()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE recipient uuid; patient_name text; patient_profile uuid; local timestamp; months text[] := ARRAY['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre']; who text; hour text;
BEGIN
 IF NEW.status <> 'cancelada' OR OLD.status NOT IN ('programada','confirmada') THEN RETURN NEW; END IF;
 SELECT s.profile_id INTO recipient FROM public.staff s WHERE s.id = NEW.doctor_id AND s.active AND s.category = 'doctor';
 IF recipient IS NULL OR NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = recipient AND r.role = 'doctor' AND r.active) THEN RETURN NEW; END IF;
 SELECT concat_ws(' ', p.first_name, p.last_name), p.profile_id INTO patient_name, patient_profile FROM public.patients p WHERE p.id = NEW.patient_id;
 local := NEW.starts_at AT TIME ZONE 'America/El_Salvador';
 hour := ltrim(to_char(local, 'HH12:MI'), '0') || CASE WHEN extract(hour FROM local) < 12 THEN ' a. m.' ELSE ' p. m.' END;
 who := CASE WHEN NEW.cancelled_by IS NOT NULL AND NEW.cancelled_by = patient_profile THEN 'El paciente ' || coalesce(nullif(patient_name, ''), 'asignado') || ' ha cancelado su cita'
             ELSE 'Se canceló la cita de ' || coalesce(nullif(patient_name, ''), 'un paciente') END;
 INSERT INTO public.notifications(recipient_id, title, body, kind, entity_type, entity_id, event_key)
 VALUES (recipient, 'Cita cancelada',
   -- La hora ya termina en «a. m.»/«p. m.»: no se añade otro punto. Motivo opcional al final.
   who || ' programada para el ' || extract(day FROM local)::int || ' de ' || months[extract(month FROM local)::int] || ' a las ' || hour
     || coalesce(' Motivo: ' || nullif(trim(NEW.cancellation_reason), '') || '.', ''),
   'cita', 'appointments', NEW.id::text, 'doctor:appointment:' || NEW.id::text || ':cancelled')
 ON CONFLICT (recipient_id, event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NEW;
END $function$;
DROP TRIGGER IF EXISTS doctor_cancellation_notice ON public.appointments;
CREATE TRIGGER doctor_cancellation_notice AFTER UPDATE OF status ON public.appointments
 FOR EACH ROW EXECUTE FUNCTION private.doctor_cancellation_notice();
REVOKE ALL ON FUNCTION private.doctor_cancellation_notice() FROM PUBLIC, anon, authenticated;

-- 3. Turno único por hospital y día ------------------------------------------------------------------------------------
-- Contador por día (America/El_Salvador), inicializado con el mayor turno ya asignado ese día para no repetir ni reciclar.
CREATE TABLE IF NOT EXISTS private.appointment_queue_day_counters (
  queue_date date PRIMARY KEY,
  last_number integer NOT NULL CHECK (last_number > 0));
INSERT INTO private.appointment_queue_day_counters(queue_date, last_number)
SELECT queue_date, max(queue_number) FROM public.appointments WHERE queue_date IS NOT NULL GROUP BY queue_date
ON CONFLICT (queue_date) DO UPDATE SET last_number = greatest(private.appointment_queue_day_counters.last_number, EXCLUDED.last_number);

-- El disparador conserva su nombre y su regla anti-edición manual. La fila del contador se bloquea en la misma
-- transacción que inserta la cita: dos recepcionistas simultáneos nunca reciben el mismo número y si la cita falla
-- no queda número huérfano (se revierte junto con el contador).
CREATE OR REPLACE FUNCTION private.assign_appointment_queue()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_day date;
BEGIN
  v_day := (NEW.starts_at AT TIME ZONE 'America/El_Salvador')::date;
  IF TG_OP = 'INSERT' OR v_day IS DISTINCT FROM OLD.queue_date THEN
    INSERT INTO private.appointment_queue_day_counters(queue_date, last_number) VALUES (v_day, 1)
      ON CONFLICT (queue_date) DO UPDATE SET last_number = private.appointment_queue_day_counters.last_number + 1
      RETURNING last_number INTO NEW.queue_number;
    NEW.queue_date := v_day;
  ELSIF NEW.queue_number IS DISTINCT FROM OLD.queue_number OR NEW.queue_date IS DISTINCT FROM OLD.queue_date THEN
    RAISE EXCEPTION 'El turno se asigna automáticamente al agendar la cita';
  END IF;
  RETURN NEW;
END $function$;
-- Unicidad hospitalaria desde el 15 de noviembre (el 14 ya contiene un número repetido de la numeración anterior).
CREATE UNIQUE INDEX IF NOT EXISTS appointments_hospital_day_queue_unique
  ON public.appointments (queue_date, queue_number) WHERE queue_date >= DATE '2026-11-15';

-- 4. Avisos de cambio de jornada al médico -----------------------------------------------------------------------------
-- Cubre las cuatro fuentes que asigna administración: doctor_schedules (semanal), staff_shifts (por fecha), staff_absences
-- y staff_recurring_journeys (jornada recurrente, donde están almuerzo y descansos en breaks).
-- Sin duplicados: la identidad del evento es la TRANSACCIÓN de administración (event_key 'schedule:<empleado>:<xid>' + índice
-- único notification_event_once). Un guardado que toca varias filas o tablas (save_staff_planning_set cierra la fila anterior
-- e inserta la nueva) produce un solo aviso; dos guardados distintos son dos modificaciones y producen dos avisos.
-- No toca la sincronización existente: planning_revision_changed sigue en las cuatro tablas y es independiente.
CREATE OR REPLACE FUNCTION private.doctor_schedule_notice()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE staff_row uuid; recipient uuid; label text;
BEGIN
 -- Se lee el campo según la tabla y la operación (NEW no existe al borrar).
 IF TG_TABLE_NAME = 'doctor_schedules' THEN
   IF TG_OP = 'DELETE' THEN staff_row := OLD.doctor_id; ELSE staff_row := NEW.doctor_id; END IF;
 ELSE
   IF TG_OP = 'DELETE' THEN staff_row := OLD.staff_id; ELSE staff_row := NEW.staff_id; END IF;
 END IF;
 SELECT s.profile_id INTO recipient FROM public.staff s WHERE s.id = staff_row AND s.active;
 IF recipient IS NULL THEN RETURN NULL; END IF;
 label := CASE TG_TABLE_NAME WHEN 'staff_absences' THEN 'Se registró o modificó una ausencia en tu jornada.'
   WHEN 'staff_recurring_journeys' THEN 'Administración actualizó tu jornada recurrente (horario, almuerzo o descansos).'
   ELSE 'Administración actualizó tu horario laboral.' END;
 INSERT INTO public.notifications(recipient_id, title, body, kind, entity_type, entity_id, event_key)
 VALUES (recipient, 'Tu jornada cambió', label || ' Revisa Mi horario.', 'jornada', TG_TABLE_NAME, staff_row::text,
   'schedule:' || staff_row::text || ':' || pg_current_xact_id()::text)
 ON CONFLICT (recipient_id, event_key) WHERE event_key IS NOT NULL DO NOTHING;
 RETURN NULL;
END $function$;
DROP TRIGGER IF EXISTS doctor_schedule_notice ON public.doctor_schedules;
CREATE TRIGGER doctor_schedule_notice AFTER INSERT OR UPDATE OR DELETE ON public.doctor_schedules FOR EACH ROW EXECUTE FUNCTION private.doctor_schedule_notice();
DROP TRIGGER IF EXISTS doctor_shift_notice ON public.staff_shifts;
CREATE TRIGGER doctor_shift_notice AFTER INSERT OR UPDATE OR DELETE ON public.staff_shifts FOR EACH ROW EXECUTE FUNCTION private.doctor_schedule_notice();
DROP TRIGGER IF EXISTS doctor_absence_notice ON public.staff_absences;
CREATE TRIGGER doctor_absence_notice AFTER INSERT OR UPDATE OR DELETE ON public.staff_absences FOR EACH ROW EXECUTE FUNCTION private.doctor_schedule_notice();
DROP TRIGGER IF EXISTS doctor_recurring_journey_notice ON public.staff_recurring_journeys;
CREATE TRIGGER doctor_recurring_journey_notice AFTER INSERT OR UPDATE OR DELETE ON public.staff_recurring_journeys FOR EACH ROW EXECUTE FUNCTION private.doctor_schedule_notice();
REVOKE ALL ON FUNCTION private.doctor_schedule_notice() FROM PUBLIC, anon, authenticated;

COMMIT;

-- Comprobaciones posteriores (solo lectura):
--   SELECT jobname, schedule FROM cron.job WHERE jobname = 'hospital-mark-missed-appointments';
--   SELECT queue_date, queue_number, count(*) FROM public.appointments WHERE queue_date >= DATE '2026-11-15' GROUP BY 1,2 HAVING count(*) > 1;  -- debe estar vacío
--   SELECT status, count(*) FROM public.appointments GROUP BY 1;
--   SELECT tgrelid::regclass, tgname FROM pg_trigger WHERE tgname LIKE 'doctor_%notice' ORDER BY 1;  -- 4 tablas de jornada + citas
