-- ==========================================================
-- RutaSur v1.0 — datos_demo.sql
--
-- ⚠ DATOS DE DEMOSTRACIÓN — SOLO PARA DESARROLLO Y PRUEBAS ⚠
-- Unidades, cuentas y una sesión simulada. La ruta (trazados y paraderos)
-- NO está aquí: es la real y se carga antes con
-- database/datos_reales/ruta_lb.sql.
--
-- Contraseña de todas las cuentas demo: rutasur-demo
-- ==========================================================

BEGIN;

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
