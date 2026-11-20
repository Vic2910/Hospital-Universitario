-- Limpieza de avisos duplicados ya almacenados — 20 de noviembre de 2026. PREPARADO, NO APLICADO.
-- Ejecutar SOLO después de revisar el resultado del paso 1. El paso 2 termina en ROLLBACK: cambiar a COMMIT únicamente
-- cuando las filas listadas sean las esperadas.
--
-- Criterio (no se usa el título): son el mismo evento los avisos de «resultado de laboratorio disponible» del MISMO
-- destinatario, de la MISMA orden (entity_id) y para el MISMO tipo de destinatario (doctor/patient), cuya clave solo difiere
-- en la revisión de publicación ('lab:<orden>:<revisión>:<tipo>' o la clave estable 'lab:<orden>:result:<tipo>').
-- Se conserva el más reciente de cada grupo (el que se normaliza a la clave estable). Avisos de órdenes distintas nunca se agrupan.
--
-- Estado inspeccionado el 20/11 (solo lectura): 2 grupos, ambos de la orden 2150c727-638a-4069-e9ad-6c6bb69ee34d:
--   paciente 16983bd9… → ':1:patient' (13:50:30) y ':2:patient' (13:52:05)
--   médico   6e74b3ae… → ':1:doctor'  (13:50:30) y ':2:doctor'  (13:52:05)
-- Se eliminarían 2 filas (las de la revisión 1). Ningún otro evento tiene duplicados.

-- 1. Identificación (solo lectura).
WITH lab AS (
  SELECT n.id, n.recipient_id, n.entity_id, n.event_key, n.created_at, n.read_at, m[1] AS audience
  FROM public.notifications n CROSS JOIN LATERAL regexp_match(n.event_key, '^lab:[0-9a-f-]{36}:(?:[0-9]+|result):(doctor|patient)$') AS m
), ranked AS (
  SELECT lab.*, count(*) OVER w AS group_size, row_number() OVER (w ORDER BY created_at DESC, id DESC) AS rank
  FROM lab WINDOW w AS (PARTITION BY recipient_id, entity_id, audience)
)
SELECT id, recipient_id, entity_id AS order_id, audience, event_key, created_at AT TIME ZONE 'America/El_Salvador' AS created_sv, read_at,
       CASE WHEN rank = 1 THEN 'conservar' ELSE 'eliminar (duplicado)' END AS decision
FROM ranked WHERE group_size > 1 ORDER BY recipient_id, order_id, created_at;

-- 2. Eliminación revisable (termina en ROLLBACK).
BEGIN;
WITH lab AS (
  SELECT n.id, n.recipient_id, n.entity_id, n.created_at, m[1] AS audience
  FROM public.notifications n CROSS JOIN LATERAL regexp_match(n.event_key, '^lab:[0-9a-f-]{36}:(?:[0-9]+|result):(doctor|patient)$') AS m
), ranked AS (
  SELECT id, row_number() OVER (PARTITION BY recipient_id, entity_id, audience ORDER BY created_at DESC, id DESC) AS rank FROM lab
)
DELETE FROM public.notifications n USING ranked r WHERE n.id = r.id AND r.rank > 1
RETURNING n.id, n.recipient_id, n.entity_id, n.event_key, n.created_at;
ROLLBACK;  -- Cambiar a COMMIT solo tras verificar las filas devueltas.
