-- ==========================================================
-- RutaSur v1.0 — Trazado real del ramal MOLLEBAYA
--
-- ARCHIVO GENERADO por gpx_a_sql.py a partir de {{ORIGEN}}
-- (dibujado en BRouter-Web sobre las calles de OpenStreetMap).
-- No editar a mano: corrija el GPX y vuelva a generarlo.
--
-- Se aplica DESPUÉS de los datos demo. En una sola transacción:
--   1. Reemplaza los trazados de Mollebaya IDA y VUELTA por los reales.
--   2. Desactiva el ramal CERRILLO hasta tener su trazado real: sus
--      variantes y sus paraderos exclusivos dejan de mostrarse, y se
--      cierran sus sesiones abiertas. No se borra nada.
--   3. Coloca los paraderos demo de Mollebaya sobre la ruta real y
--      recalcula su orden y distancia (se validan los 150 m).
--   4. Reubica sobre el trazado nuevo las posiciones ya registradas.
--
-- Uso (PowerShell, en la raíz del proyecto):
--   docker compose exec db psql -U rutasur_owner -d rutasur -f /rutasur/database/datos_reales/trazado_mollebaya.sql
-- ==========================================================
\set ON_ERROR_STOP on
\pset pager off

BEGIN;

-- Trazados actuales: sirven para reubicar las posiciones al final
CREATE TEMP TABLE trazado_anterior ON COMMIT DROP AS
SELECT id, trazado FROM variante;

CREATE TEMP TABLE ruta_real ON COMMIT DROP AS
SELECT ST_GeomFromText('{{WKT_IDA}}', 4326) AS ida,
       ST_GeomFromText('{{WKT_VUELTA}}', 4326) AS vuelta;


-- 1. Se quitan las asignaciones de paraderos: se recalculan en el paso 3
DELETE FROM paradero_variante;

-- 2. Trazados reales de Mollebaya (el trigger recalcula longitud_m)
UPDATE variante v
   SET trazado = CASE v.sentido WHEN 'IDA' THEN r.ida ELSE r.vuelta END
  FROM ruta_real r
 WHERE v.ramal = 'MOLLEBAYA';

-- Cerrillo, fuera de servicio hasta tener su trazado real
UPDATE sesion_emision s
   SET estado = 'CERRADA_AUTOMATICAMENTE',
       fin    = GREATEST(clock_timestamp(), s.inicio + interval '1 millisecond')
  FROM variante v
 WHERE v.id = s.variante_id
   AND v.ramal = 'CERRILLO'
   AND s.estado IN ('ACTIVA', 'SIN_SENAL');

UPDATE variante SET activa = false WHERE ramal = 'CERRILLO';
UPDATE paradero SET activo = false WHERE codigo IN ('stp_007', 'stp_008');

-- 3. Paraderos de Mollebaya sobre la ruta real. Sin Cerrillo no hay tramo
--    común: toda la ruta se dibuja con el color de Mollebaya.
UPDATE paradero p
   SET ubicacion = CASE p.codigo
         WHEN 'stp_006' THEN ST_StartPoint(r.ida)        -- Mollebaya (final)
         WHEN 'stp_001' THEN ST_EndPoint(r.ida)          -- Centro (2 de Mayo)
         ELSE ST_ClosestPoint(r.ida, p.ubicacion)        -- stp_002 a stp_005
       END,
       en_tramo_comun = false
  FROM ruta_real r
 WHERE p.codigo IN ('stp_001', 'stp_002', 'stp_003', 'stp_004', 'stp_005', 'stp_006');

SELECT fn_asignar_paraderos_variante(v.id,
         ARRAY['stp_001','stp_002','stp_003','stp_004','stp_005','stp_006']::varchar[]
       ) AS paraderos_asignados,
       v.ramal, v.sentido
  FROM variante v
 WHERE v.ramal = 'MOLLEBAYA'
 ORDER BY v.sentido;

-- 4. Posiciones ya registradas: misma fracción del recorrido, sobre el trazado nuevo
UPDATE posicion p
   SET coordenada = ST_LineInterpolatePoint(v.trazado, ST_LineLocatePoint(a.trazado, p.coordenada))
  FROM sesion_emision s
  JOIN variante v         ON v.id = s.variante_id
  JOIN trazado_anterior a ON a.id = s.variante_id
 WHERE p.sesion_id = s.id
   AND v.ramal = 'MOLLEBAYA';

UPDATE sesion_emision s
   SET ultima_ubicacion   = ST_LineInterpolatePoint(v.trazado,
                              ST_LineLocatePoint(a.trazado, s.ultima_ubicacion)),
       ultima_distancia_m = round(ST_Length(ST_LineSubstring(v.trazado, 0,
                              ST_LineLocatePoint(a.trazado, s.ultima_ubicacion))::geography)::numeric, 1)
  FROM variante v
  JOIN trazado_anterior a ON a.id = v.id
 WHERE v.id = s.variante_id
   AND v.ramal = 'MOLLEBAYA'
   AND s.ultima_ubicacion IS NOT NULL;

-- Resumen
SELECT v.ramal, v.sentido, v.activa, ST_NPoints(v.trazado) AS puntos,
       round(v.longitud_m / 1000, 2) AS km
  FROM variante v
 ORDER BY v.ramal, v.sentido;

COMMIT;

\echo 'Trazado real de Mollebaya cargado (Cerrillo desactivado). Reinicie el simulador y recargue la app.'
