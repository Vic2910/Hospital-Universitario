-- Notificaciones sin duplicados: un evento → un aviso por destinatario — 20 de noviembre de 2026.
-- PREPARADO, NO APLICADO en Hospital Móviles. Probado en un PostgreSQL 17 local desechable (scripts/test-notifications-sql.mjs).
--
-- Causa del duplicado «Resultados de laboratorio disponibles» (13:50 y 13:52 del 20/11) [Supabase, solo lectura]:
--   * El panel de laboratorio llamó dos veces a publish_lab_result para la MISMA orden (lab_delivery_events 9 y 10, mismo
--     remitente, 95 s de diferencia). Cada llamada incrementa lab_results.published_revision (1 → 2).
--   * El disparador private.laboratory_notifications incluía la revisión en event_key ('lab:<orden>:<revisión>:patient'),
--     así que el índice único notification_event_once (recipient_id, event_key) no lo reconocía como el mismo evento.
--   * No hay Edge Functions que creen avisos (la única, manage-employees, no toca notifications), Realtime solo publica
--     planning_revision y los clientes únicamente leen o marcan como leídos: el origen es solo ese disparador.
--
-- Corrección (sin tocar publish_lab_result ni el panel de laboratorio):
--   1. Identidad estable del evento «resultado disponible»: orden + destinatario + tipo → 'lab:<orden>:result:<doctor|patient>'.
--   2. Volver a publicar el MISMO resultado no crea otro aviso (ON CONFLICT … DO NOTHING).
--   3. Si al volver a publicar cambió el contenido (resumen, valores o parámetros), se ACTUALIZA el aviso existente
--      («Resultados de laboratorio actualizados», no leído) en lugar de crear otro.
--   4. Un resultado de OTRA orden es otro evento: genera su propio aviso.
--   5. Los avisos existentes con clave por revisión se normalizan: el más reciente de cada grupo adopta la clave estable para
--      que una nueva publicación no lo duplique. No se borra nada (limpieza aparte: notificaciones-duplicadas-limpieza.sql).
-- Concurrencia: publish_lab_result actualiza la fila de lab_results (bloqueo de fila) y el índice único existente garantiza
-- una sola fila por (destinatario, clave) aunque dos transacciones lleguen a la vez.
BEGIN;

-- 5. Normalización de claves existentes (idempotente: solo cambia filas que aún tienen la clave por revisión).
WITH legacy AS (
  SELECT n.id, n.recipient_id, m[1] AS order_id, m[2] AS audience,
         row_number() OVER (PARTITION BY n.recipient_id, m[1], m[2] ORDER BY n.created_at DESC, n.id DESC) AS rank
  FROM public.notifications n
  CROSS JOIN LATERAL regexp_match(n.event_key, '^lab:([0-9a-f-]{36}):[0-9]+:(doctor|patient)$') AS m
  WHERE n.event_key ~ '^lab:[0-9a-f-]{36}:[0-9]+:(doctor|patient)$')
UPDATE public.notifications n SET event_key = 'lab:' || l.order_id || ':result:' || l.audience
FROM legacy l
WHERE n.id = l.id AND l.rank = 1
  AND NOT EXISTS (SELECT 1 FROM public.notifications x WHERE x.recipient_id = l.recipient_id AND x.event_key = 'lab:' || l.order_id || ':result:' || l.audience);

CREATE OR REPLACE FUNCTION private.laboratory_notifications()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE patient_user uuid; doctor_user uuid; changed boolean := false; doctor_key text; patient_key text;
BEGIN
 IF TG_TABLE_NAME = 'lab_orders' THEN
  -- Sin cambios: aviso de nueva orden para administración/laboratorio, una vez por orden.
  INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
  SELECT DISTINCT r.user_id,'Nueva orden de laboratorio','Hay un examen pendiente de procesamiento.','laboratorio','lab_orders',NEW.id::text,'lab:'||NEW.id::text||':new'
  FROM public.user_roles r LEFT JOIN public.panel_preferences pref ON pref.user_id=r.user_id
  WHERE r.role='admin' AND r.active AND coalesce(pref.laboratory,true) AND r.user_id IS DISTINCT FROM auth.uid()
  ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO NOTHING;
  RETURN NEW;
 END IF;
 IF NEW.published_at IS NULL OR NEW.validated_by IS NULL OR NEW.validated_at IS NULL THEN RETURN NEW; END IF;
 -- Solo una publicación (nueva o repetida) puede avisar; otras actualizaciones de la fila no.
 IF TG_OP = 'UPDATE' AND NEW.published_revision IS NOT DISTINCT FROM OLD.published_revision
    AND (OLD.published_to_patient_at IS NOT NULL OR NEW.published_to_patient_at IS NULL) THEN RETURN NEW; END IF;
 -- ¿Cambió lo que el destinatario ya pudo ver? (republicación con otro contenido)
 IF TG_OP = 'UPDATE' AND OLD.published_at IS NOT NULL THEN
  changed := OLD.summary IS DISTINCT FROM NEW.summary OR OLD.result_values IS DISTINCT FROM NEW.result_values
             OR OLD.parameter_schema IS DISTINCT FROM NEW.parameter_schema;
 END IF;
 SELECT s.profile_id,p.profile_id INTO doctor_user,patient_user FROM public.lab_orders o JOIN public.clinical_encounters e ON e.id=o.encounter_id
  JOIN public.staff s ON s.id=e.doctor_id JOIN public.medical_records m ON m.id=e.record_id JOIN public.patients p ON p.id=m.patient_id WHERE o.id=NEW.order_id;
 doctor_key := 'lab:'||NEW.order_id::text||':result:doctor';
 patient_key := 'lab:'||NEW.order_id::text||':result:patient';
 IF TG_OP = 'INSERT' OR NEW.published_revision IS DISTINCT FROM OLD.published_revision THEN
  INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
  SELECT doctor_user,'Resultados de laboratorio disponibles','Una orden tiene resultados validados y publicados.','laboratorio','lab_orders',NEW.order_id::text,doctor_key
  WHERE doctor_user IS NOT NULL AND EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=doctor_user AND role='doctor' AND active)
  ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO UPDATE
   SET title='Resultados de laboratorio actualizados', body='Se actualizaron los resultados validados de una orden.', read_at=NULL, created_at=now()
   WHERE changed;
 END IF;
 IF NEW.published_to_patient_at IS NOT NULL THEN
  INSERT INTO public.notifications(recipient_id,title,body,kind,entity_type,entity_id,event_key)
  SELECT patient_user,'Resultados de laboratorio disponibles','Ya puedes consultar los resultados autorizados en Laboratorios.','laboratorio','lab_orders',NEW.order_id::text,patient_key
  WHERE patient_user IS NOT NULL AND EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=patient_user AND role='paciente' AND active)
  ON CONFLICT(recipient_id,event_key) WHERE event_key IS NOT NULL DO UPDATE
   SET title='Resultados de laboratorio actualizados', body='Se actualizaron tus resultados autorizados. Revísalos en Laboratorios.', read_at=NULL, created_at=now()
   WHERE changed AND TG_OP = 'UPDATE' AND OLD.published_to_patient_at IS NOT NULL;
 END IF;
 RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION private.laboratory_notifications() FROM PUBLIC, anon, authenticated;
-- Los disparadores existentes (laboratory_new_order_notice y laboratory_published_notice) siguen apuntando a esta función.

COMMIT;

-- Comprobación (solo lectura): no debe haber dos avisos del mismo evento para el mismo destinatario.
--   SELECT recipient_id, event_key, count(*) FROM public.notifications WHERE event_key IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1;  -- vacío
--   SELECT recipient_id, entity_id, count(*) FROM public.notifications WHERE event_key ~ '^lab:.*:(doctor|patient)$' GROUP BY 1,2 HAVING count(*) > 1;
