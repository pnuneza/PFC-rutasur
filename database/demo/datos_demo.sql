-- ==========================================================
-- RutaSur v1.0 — datos_demo.sql
--
-- ⚠ DATOS DE DEMOSTRACIÓN — SOLO PARA DESARROLLO Y PRUEBAS ⚠
-- Los trazados son líneas simplificadas y los paraderos son ficticios.
-- NO representan el recorrido real de la línea LB. Los datos reales
-- se cargan desde la ficha de coordenadas y los recorridos grabados
-- con GPS (P06, carga inicial).
--
-- Contraseña de todas las cuentas demo: rutasur-demo
-- ==========================================================

BEGIN;

-- ----------------------------------------------------------
-- Paraderos (8): 4 del tramo común + 2 por ramal
-- ----------------------------------------------------------
INSERT INTO paradero (codigo, nombre, referencia, ubicacion, en_tramo_comun) VALUES
  ('stp_001', 'Centro (2 de Mayo)',     'Paradero inicial',         ST_SetSRID(ST_MakePoint(-71.5358, -16.4002), 4326), true),
  ('stp_002', 'Avenida Demo 1',         'Frente al grifo',          ST_SetSRID(ST_MakePoint(-71.5202, -16.4178), 4326), true),
  ('stp_003', 'Avenida Demo 2',         'Esquina del mercado',      ST_SetSRID(ST_MakePoint(-71.5048, -16.4402), 4326), true),
  ('stp_004', 'Plaza Characato',        'Frente a la iglesia',      ST_SetSRID(ST_MakePoint(-71.4902, -16.4688), 4326), true),
  ('stp_005', 'Mollebaya Demo 1',       'Frente a la posta',        ST_SetSRID(ST_MakePoint(-71.4801, -16.4798), 4326), false),
  ('stp_006', 'Mollebaya (final)',      'Paradero final del ramal', ST_SetSRID(ST_MakePoint(-71.4702, -16.4918), 4326), false),
  ('stp_007', 'Cerrillos Demo 1',       'Junto al colegio',         ST_SetSRID(ST_MakePoint(-71.4978, -16.4832), 4326), false),
  ('stp_008', 'Cerrillos (final)',      'Paradero final del ramal', ST_SetSRID(ST_MakePoint(-71.5048, -16.4948), 4326), false);


-- ----------------------------------------------------------
-- Variantes (4): VUELTA = Centro → ramal · IDA = ramal → Centro
-- longitud_m la calcula el trigger trg_variante_longitud
-- ----------------------------------------------------------
INSERT INTO variante (linea_id, ramal, sentido, destino, trazado)
SELECT l.id, v.ramal::ramal_t, v.sentido::sentido_t, v.destino, ST_GeomFromText(v.wkt, 4326)
  FROM linea l
 CROSS JOIN (VALUES
   ('MOLLEBAYA', 'VUELTA', 'Mollebaya',
    'LINESTRING(-71.5360 -16.4000, -71.5200 -16.4180, -71.5050 -16.4400, -71.4900 -16.4690, -71.4800 -16.4800, -71.4700 -16.4920)'),
   ('MOLLEBAYA', 'IDA',    'Centro (2 de Mayo)',
    'LINESTRING(-71.4700 -16.4920, -71.4800 -16.4800, -71.4900 -16.4690, -71.5050 -16.4400, -71.5200 -16.4180, -71.5360 -16.4000)'),
   ('CERRILLO',  'VUELTA', 'Cerrillos',
    'LINESTRING(-71.5360 -16.4000, -71.5200 -16.4180, -71.5050 -16.4400, -71.4900 -16.4690, -71.4980 -16.4830, -71.5050 -16.4950)'),
   ('CERRILLO',  'IDA',    'Centro (2 de Mayo)',
    'LINESTRING(-71.5050 -16.4950, -71.4980 -16.4830, -71.4900 -16.4690, -71.5050 -16.4400, -71.5200 -16.4180, -71.5360 -16.4000)')
 ) AS v(ramal, sentido, destino, wkt)
 WHERE l.codigo = 'LB';


-- ----------------------------------------------------------
-- Paraderos de cada variante: el orden y la distancia los calcula
-- fn_asignar_paraderos_variante a partir del trazado
-- ----------------------------------------------------------
SELECT fn_asignar_paraderos_variante(v.id,
         CASE v.ramal
           WHEN 'MOLLEBAYA' THEN ARRAY['stp_001','stp_002','stp_003','stp_004','stp_005','stp_006']::varchar[]
           ELSE                  ARRAY['stp_001','stp_002','stp_003','stp_004','stp_007','stp_008']::varchar[]
         END) AS paraderos_asignados,
       v.ramal, v.sentido
  FROM variante v;


-- ----------------------------------------------------------
-- Unidades y cuentas (hash bcrypt de "rutasur-demo")
-- ----------------------------------------------------------
INSERT INTO unidad (etiqueta) VALUES ('07'), ('12');

INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
SELECT id, 'unidad' || etiqueta, '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u'
  FROM unidad;

INSERT INTO cuenta_administrativa (usuario, hash_contrasena, rol) VALUES
  ('admin.demo', '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u', 'ADMINISTRADOR'),
  ('moderador.demo', '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u', 'MODERADOR');


-- ----------------------------------------------------------
-- Una sesión activa: la unidad 07 viaja de Mollebaya al Centro
-- ----------------------------------------------------------
INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id, inicio)
SELECT u.id, c.id, v.id, now() - interval '10 minutes'
  FROM unidad u
  JOIN cuenta_conductor c ON c.unidad_id = u.id
  JOIN variante v ON v.ramal = 'MOLLEBAYA' AND v.sentido = 'IDA'
 WHERE u.etiqueta = '07';

-- Cinco posiciones válidas cada 5 segundos, avanzando por el trazado
INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m,
                      capturada_en, valida)
SELECT gen_random_uuid(),
       s.id,
       ST_LineInterpolatePoint(v.trazado, 0.30 + n * 0.002),
       32.0, 315, 8.0,
       now() - make_interval(secs => (5 - n) * 5),
       true
  FROM sesion_emision s
  JOIN variante v ON v.id = s.variante_id
 CROSS JOIN generate_series(1, 5) AS n
 WHERE s.estado = 'ACTIVA';

-- Una posición descartada por baja precisión
INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m,
                      capturada_en, valida, motivo_descarte)
SELECT gen_random_uuid(), s.id, ST_LineInterpolatePoint(v.trazado, 0.31),
       30.0, 315, 85.0, now(), false, 'PRECISION_INSUFICIENTE'
  FROM sesion_emision s
  JOIN variante v ON v.id = s.variante_id
 WHERE s.estado = 'ACTIVA';

-- Copia de la última posición válida (lo hará el validador del backend)
UPDATE sesion_emision s
   SET (ultima_posicion_en, ultima_ubicacion, ultimo_rumbo,
        ultima_velocidad_kmh, ultima_distancia_m) =
       (SELECT p.capturada_en, p.coordenada, p.rumbo, p.velocidad_kmh,
               round(ST_Length(
                   ST_LineSubstring(v.trazado, 0,
                     ST_LineLocatePoint(v.trazado, p.coordenada))::geography)::numeric, 1)
          FROM posicion p
          JOIN variante v ON v.id = s.variante_id
         WHERE p.sesion_id = s.id AND p.valida
         ORDER BY p.capturada_en DESC
         LIMIT 1)
 WHERE s.estado = 'ACTIVA';

INSERT INTO registro_evento (tipo, origen, codigo_http, detalle)
VALUES ('POSICION_DESCARTADA', 'POST /api/v1/positions', 207,
        '{"motivo": "PRECISION_INSUFICIENTE", "precision_m": 85.0}');

COMMIT;
