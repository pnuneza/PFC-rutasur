-- ==========================================================
-- RutaSur v1.0 — 02_prueba_rendimiento.sql
-- Prueba de carga y rendimiento con el volumen estimado en P06 (Tabla 65):
--   5 unidades × 720 posiciones/hora × 16 h × 30 días = 1 728 000 posiciones
--
-- Mide:
--   1. Tiempo de carga del volumen completo
--   2. Espacio real ocupado vs. estimado (≈ 390 MB para posicion)
--   3. Tiempo de las consultas frecuentes y si usan los índices de la Tabla 62
--
-- Todo se deshace al final (ROLLBACK). Tarda 1–3 minutos.
--
-- Ejecutar (Docker):
--   docker compose exec db psql -U rutasur_owner -d rutasur \
--       -f /rutasur/database/pruebas/02_prueba_rendimiento.sql
-- Con menos filas (prueba rápida):
--   ... -v filas=200000 -f ...
-- ==========================================================
\set ON_ERROR_STOP on
\pset footer off
SET client_min_messages = warning;

\if :{?filas}
\else
    \set filas 1728000
\endif

\echo
\echo '=== Preparando datos: 5 unidades, 1 sesión por unidad y día ==='

BEGIN;

INSERT INTO linea (codigo, nombre, hora_inicio, hora_fin)
VALUES ('PERF', 'Línea de prueba de rendimiento', '05:00', '21:00');

-- Trazado de unos 12 km con varios quiebres
INSERT INTO variante (linea_id, ramal, sentido, destino, trazado)
SELECT id, 'MOLLEBAYA', 'IDA', 'Centro (prueba)',
       ST_GeomFromText('LINESTRING(-71.47 -16.49, -71.48 -16.48, -71.49 -16.469, -71.505 -16.44, -71.52 -16.418, -71.536 -16.40)', 4326)
  FROM linea WHERE codigo = 'PERF';

INSERT INTO unidad (etiqueta) SELECT 'P' || n FROM generate_series(1, 5) n;
INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
SELECT id, 'perf.' || lower(etiqueta), '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u'
  FROM unidad WHERE etiqueta LIKE 'P_';

-- Una sesión por unidad y día; la del último día queda abierta.
-- Los días van de hace 30 días a ayer: parte del primer día supera la
-- retención y debe ser eliminada por la depuración (prueba 3d).
CREATE TEMP TABLE mapa_sesion AS
WITH dias AS (
    SELECT generate_series(0, ceil(:filas / 5.0 / 11520)::int - 1) AS dia
)
SELECT u.n AS unidad_n,
       d.dia,
       gen_random_uuid() AS sesion_id,
       date_trunc('day', now()) - make_interval(days => ceil(:filas / 5.0 / 11520)::int - d.dia)
           + interval '5 hours' AS inicio,
       d.dia = max(d.dia) OVER () AS es_ultimo
  FROM (SELECT row_number() OVER (ORDER BY etiqueta) - 1 AS n, id FROM unidad WHERE etiqueta LIKE 'P_') u
 CROSS JOIN dias d;

INSERT INTO sesion_emision (id, unidad_id, cuenta_conductor_id, variante_id, estado, inicio, fin)
SELECT m.sesion_id, u.id, c.id, v.id,
       CASE WHEN m.es_ultimo THEN 'ACTIVA' ELSE 'CERRADA_AUTOMATICAMENTE' END::estado_sesion_t,
       m.inicio,
       CASE WHEN m.es_ultimo THEN NULL ELSE m.inicio + interval '16 hours' END
  FROM mapa_sesion m
  JOIN (SELECT row_number() OVER (ORDER BY etiqueta) - 1 AS n, id FROM unidad WHERE etiqueta LIKE 'P_') u
       ON u.n = m.unidad_n
  JOIN cuenta_conductor c ON c.unidad_id = u.id
 CROSS JOIN (SELECT v.id FROM variante v JOIN linea l ON l.id = v.linea_id WHERE l.codigo = 'PERF') v;

SELECT count(*) AS "Sesiones creadas" FROM sesion_emision s
  JOIN unidad u ON u.id = s.unidad_id WHERE u.etiqueta LIKE 'P_';

\echo
\echo '=== 1. Carga de posiciones (una cada 5 s, 16 h por día) ==='
\timing on
INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m,
                      capturada_en, recibida_en, valida, motivo_descarte)
SELECT gen_random_uuid(),
       m.sesion_id,
       ST_LineInterpolatePoint(v.trazado, ((g / 5) % 11520) / 11520.0),
       round((15 + random() * 30)::numeric, 1),
       (random() * 359)::int,
       round((3 + random() * 12)::numeric, 1),
       m.inicio + make_interval(secs => ((g / 5) % 11520) * 5),
       m.inicio + make_interval(secs => ((g / 5) % 11520) * 5 + 1),
       (g % 50 <> 0),                                   -- 2 % descartadas
       CASE WHEN g % 50 = 0 THEN 'PRECISION_INSUFICIENTE'::motivo_descarte_t END
  FROM generate_series(0, :filas - 1) AS g
  JOIN mapa_sesion m ON m.unidad_n = g % 5 AND m.dia = (g / 5) / 11520
 CROSS JOIN (SELECT v.id, v.trazado FROM variante v JOIN linea l ON l.id = v.linea_id
              WHERE l.codigo = 'PERF') v;
\timing off

-- Copia de la última posición válida en las sesiones abiertas
UPDATE sesion_emision s
   SET (ultima_posicion_en, ultima_ubicacion, ultimo_rumbo, ultima_velocidad_kmh) =
       (SELECT p.capturada_en, p.coordenada, p.rumbo, p.velocidad_kmh
          FROM posicion p
         WHERE p.sesion_id = s.id AND p.valida
         ORDER BY p.capturada_en DESC
         LIMIT 1)
 WHERE s.estado = 'ACTIVA';

-- En producción el mantenimiento automático resume los bloques del índice BRIN
-- (autosummarize). Dentro de esta transacción de prueba se hace a mano.
SELECT brin_summarize_new_values('ix_posicion_recibida') AS "Rangos BRIN resumidos";
ANALYZE posicion;
ANALYZE sesion_emision;

\echo
\echo '=== 2. Espacio ocupado vs. estimación de P06 (Tabla 65) ==='
SELECT to_char(count(*), 'FM9G999G999')                                AS "Filas en posicion",
       pg_size_pretty(pg_relation_size('posicion'))                    AS "Datos",
       pg_size_pretty(pg_indexes_size('posicion'))                     AS "Índices",
       pg_size_pretty(pg_total_relation_size('posicion'))              AS "Total real",
       '≈ 390 MB'                                                      AS "Estimado en P06",
       round(pg_total_relation_size('posicion')::numeric / count(*), 0) AS "Bytes por fila"
  FROM posicion;

\echo
\echo '=== 3a. Últimas 4 posiciones válidas de una sesión (estimar velocidad) ==='
\echo '        Esperado: Index Scan sobre ix_posicion_sesion_tiempo'
SELECT sesion_id AS sesion_prueba FROM mapa_sesion WHERE es_ultimo LIMIT 1 \gset
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT capturada_en, coordenada, velocidad_kmh
  FROM posicion
 WHERE sesion_id = :'sesion_prueba' AND valida
 ORDER BY capturada_en DESC
 LIMIT 4;

\echo
\echo '=== 3b. Unidades activas para el mapa (GET /vehicles) ==='
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT * FROM v_unidades_activas;

\echo
\echo '=== 3c. Validación de corredor: ¿la posición está a menos de 150 m del trazado? (RN-003) ==='
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT ST_DWithin(v.trazado::geography,
                  ST_SetSRID(ST_MakePoint(-71.5051, -16.4401), 4326)::geography, 150)
  FROM variante v
 WHERE v.id = (SELECT v2.id FROM variante v2 JOIN linea l ON l.id = v2.linea_id WHERE l.codigo = 'PERF');

\echo
\echo '=== 3d. Depuración diaria de datos de más de 30 días (RN-012) ==='
\echo '        Esperado: uso del índice BRIN ix_posicion_recibida'
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
DELETE FROM posicion WHERE recibida_en < now() - interval '30 days';

\echo
\echo '=== 3e. Inserción de un lote de 200 posiciones (máximo por petición, P06) ==='
\timing on
INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m, capturada_en, valida)
SELECT gen_random_uuid(), :'sesion_prueba',
       ST_SetSRID(ST_MakePoint(-71.50 + n * 0.00001, -16.45), 4326), 30, 180, 8,
       now() + make_interval(secs => n), true
  FROM generate_series(1, 200) n;
\timing off

ROLLBACK;
\echo
\echo 'Prueba terminada: todos los datos de prueba se deshicieron (ROLLBACK).'
