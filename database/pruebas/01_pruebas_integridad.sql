-- ==========================================================
-- RutaSur v1.0 — 01_pruebas_integridad.sql
-- Pruebas de integridad, reglas de negocio y seguridad de la base.
--
-- Verifica que cada restricción de la Tabla 61 (P06) y cada regla
-- programada en la base RECHACE los datos incorrectos y ACEPTE los
-- correctos. Todo ocurre dentro de una transacción que se deshace al
-- final: la base queda exactamente como estaba.
--
-- Ejecutar (Docker):
--   docker compose exec db psql -U rutasur_owner -d rutasur \
--       -f /rutasur/database/pruebas/01_pruebas_integridad.sql
-- ==========================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET client_min_messages = warning;

BEGIN;

-- La salida de cada prueba se oculta; al final se muestra la tabla de resultados
\o /dev/null

-- ----------------------------------------------------------
-- Mini marco de pruebas
-- ----------------------------------------------------------
CREATE TEMP TABLE resultado (
    n          serial,
    grupo      text,
    prueba     text,
    regla      text,
    resultado  text,
    detalle    text
);

-- Ejecuta una sentencia que DEBE fallar con el código de error indicado.
-- Si la sentencia tiene éxito, se deshace igualmente y se marca FALLO.
CREATE FUNCTION pg_temp.debe_fallar(p_grupo text, p_prueba text, p_regla text,
                                    p_sql text, p_sqlstate text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'aceptado' USING ERRCODE = 'RS999';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'RS999' THEN
            INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
            VALUES (p_grupo, p_prueba, p_regla, 'FALLO', 'La base ACEPTÓ un dato que debía rechazar');
        ELSIF SQLSTATE = p_sqlstate THEN
            INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
            VALUES (p_grupo, p_prueba, p_regla, 'OK', 'Rechazado: ' || left(SQLERRM, 90));
        ELSE
            INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
            VALUES (p_grupo, p_prueba, p_regla, 'FALLO',
                    format('Error inesperado %s: %s', SQLSTATE, left(SQLERRM, 80)));
        END IF;
    END;
END;
$$;

-- Ejecuta una sentencia que DEBE funcionar (sus cambios se conservan).
CREATE FUNCTION pg_temp.debe_funcionar(p_grupo text, p_prueba text, p_regla text, p_sql text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
    VALUES (p_grupo, p_prueba, p_regla, 'OK', 'Aceptado');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
    VALUES (p_grupo, p_prueba, p_regla, 'FALLO', format('%s: %s', SQLSTATE, left(SQLERRM, 80)));
END;
$$;

-- Comprueba una condición.
CREATE FUNCTION pg_temp.verificar(p_grupo text, p_prueba text, p_regla text,
                                  p_condicion boolean, p_detalle text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO resultado (grupo, prueba, regla, resultado, detalle)
    VALUES (p_grupo, p_prueba, p_regla,
            CASE WHEN p_condicion THEN 'OK' ELSE 'FALLO' END, p_detalle);
$$;

-- Atajos para obtener identificadores de los datos de prueba
CREATE FUNCTION pg_temp.v() RETURNS uuid LANGUAGE sql AS
  $$ SELECT v.id FROM variante v JOIN linea l ON l.id = v.linea_id WHERE l.codigo = 'TST' $$;
CREATE FUNCTION pg_temp.u(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM unidad WHERE etiqueta = p $$;
CREATE FUNCTION pg_temp.c(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM cuenta_conductor WHERE usuario = p $$;
CREATE FUNCTION pg_temp.p(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT id FROM paradero WHERE codigo = p $$;
CREATE FUNCTION pg_temp.s(p text) RETURNS uuid LANGUAGE sql AS
  $$ SELECT s.id FROM sesion_emision s JOIN unidad u ON u.id = s.unidad_id
      WHERE u.etiqueta = p ORDER BY s.inicio DESC LIMIT 1 $$;


-- ----------------------------------------------------------
-- Datos de prueba (propios; no dependen de los datos demo)
-- Trazado recto norte-sur de unos 2,2 km
-- ----------------------------------------------------------
INSERT INTO linea (codigo, nombre, hora_inicio, hora_fin)
VALUES ('TST', 'Línea de prueba', '05:00', '21:00');

INSERT INTO variante (linea_id, ramal, sentido, destino, trazado)
SELECT id, 'MOLLEBAYA', 'IDA', 'Destino de prueba',
       ST_GeomFromText('LINESTRING(-71.5 -16.45, -71.5 -16.46, -71.5 -16.47)', 4326)
  FROM linea WHERE codigo = 'TST';

INSERT INTO paradero (codigo, nombre, ubicacion) VALUES
  ('stp_901', 'Prueba inicio',  ST_SetSRID(ST_MakePoint(-71.5001, -16.4500), 4326)),
  ('stp_902', 'Prueba medio',   ST_SetSRID(ST_MakePoint(-71.4999, -16.4600), 4326)),
  ('stp_903', 'Prueba final',   ST_SetSRID(ST_MakePoint(-71.5002, -16.4700), 4326)),
  ('stp_904', 'Prueba lejana',  ST_SetSRID(ST_MakePoint(-71.4900, -16.4600), 4326));  -- ~1 km fuera

INSERT INTO unidad (etiqueta, activa) VALUES ('T1', true), ('T2', true), ('T3', false), ('TBORRAR', true);

INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
SELECT id, 'prueba.' || lower(etiqueta), '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u'
  FROM unidad WHERE etiqueta IN ('T1', 'T2', 'T3');


-- ==========================================================
-- A. CÁLCULOS AUTOMÁTICOS
-- ==========================================================
SELECT pg_temp.verificar('A. Cálculos', 'Longitud del trazado calculada sola', 'trg_variante_longitud',
       (SELECT longitud_m BETWEEN 2150 AND 2280 FROM variante WHERE id = pg_temp.v()),
       (SELECT 'longitud_m = ' || longitud_m || ' m' FROM variante WHERE id = pg_temp.v()));

-- Se envían los paraderos DESORDENADOS: la base debe ordenarlos según el trazado
SELECT pg_temp.debe_funcionar('A. Cálculos', 'Asignar paraderos de una variante', 'fn_asignar_paraderos_variante',
       $q$ SELECT fn_asignar_paraderos_variante(pg_temp.v(), ARRAY['stp_903','stp_901','stp_902']::varchar[]) $q$);

SELECT pg_temp.verificar('A. Cálculos', 'Orden obtenido del trazado', 'RN-006',
       (SELECT string_agg(p.codigo, ',' ORDER BY pv.orden) = 'stp_901,stp_902,stp_903'
          FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
         WHERE pv.variante_id = pg_temp.v()),
       (SELECT string_agg(p.codigo || '=' || pv.distancia_desde_inicio_m || 'm', '  ' ORDER BY pv.orden)
          FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
         WHERE pv.variante_id = pg_temp.v()));

SELECT pg_temp.verificar('A. Cálculos', 'Distancia acumulada del último paradero ≈ longitud', 'RN-006',
       (SELECT abs(pv.distancia_desde_inicio_m - v.longitud_m) < 5
          FROM paradero_variante pv JOIN variante v ON v.id = pv.variante_id
         WHERE pv.variante_id = pg_temp.v() AND pv.paradero_id = pg_temp.p('stp_903')),
       'Diferencia menor a 5 m');

SELECT pg_temp.debe_fallar('A. Cálculos', 'Paradero a más de 150 m del trazado', 'Carga inicial (P06)',
       $q$ SELECT fn_asignar_paraderos_variante(pg_temp.v(), ARRAY['stp_901','stp_904']::varchar[]) $q$,
       '23514');

SELECT pg_temp.debe_fallar('A. Cálculos', 'Lista con un paradero inexistente', 'fn_asignar_paraderos_variante',
       $q$ SELECT fn_asignar_paraderos_variante(pg_temp.v(), ARRAY['stp_901','stp_999']::varchar[]) $q$,
       '23503');

-- Mover un paradero 550 m más adelante debe recalcular su distancia
SELECT pg_temp.debe_funcionar('A. Cálculos', 'Mover un paradero', 'trg_paradero_recalcular',
       $q$ UPDATE paradero SET ubicacion = ST_SetSRID(ST_MakePoint(-71.4999, -16.4650), 4326)
            WHERE codigo = 'stp_902' $q$);

SELECT pg_temp.verificar('A. Cálculos', 'Distancia recalculada al mover el paradero', 'trg_paradero_recalcular',
       (SELECT distancia_desde_inicio_m BETWEEN 1600 AND 1700 FROM paradero_variante
         WHERE variante_id = pg_temp.v() AND paradero_id = pg_temp.p('stp_902')),
       (SELECT 'stp_902 ahora a ' || distancia_desde_inicio_m || ' m' FROM paradero_variante
         WHERE variante_id = pg_temp.v() AND paradero_id = pg_temp.p('stp_902')));

UPDATE linea SET actualizado_en = '2020-01-01' WHERE codigo = 'TST';
UPDATE paradero SET referencia = 'Frente a la posta' WHERE codigo = 'stp_901';
SELECT pg_temp.verificar('A. Cálculos', 'Cambio en la ruta marca linea.actualizado_en', 'Caché del pasajero (Tabla 58)',
       (SELECT actualizado_en > '2020-01-01' FROM linea WHERE codigo = 'TST'),
       'La app sabrá que debe renovar su caché');


-- ==========================================================
-- B. CONFIGURACIÓN: línea, variantes, paraderos, cuentas
-- ==========================================================
SELECT pg_temp.debe_fallar('B. Configuración', 'Horario con fin antes del inicio', 'ck_horario (RN-009)',
       $q$ INSERT INTO linea (codigo, nombre, hora_inicio, hora_fin) VALUES ('X1', 'Mala', '21:00', '05:00') $q$, '23514');

SELECT pg_temp.debe_fallar('B. Configuración', 'Variante repetida (mismo ramal y sentido)', 'uq_variante_ramal_sentido',
       $q$ INSERT INTO variante (linea_id, ramal, sentido, destino, trazado)
           SELECT linea_id, ramal, sentido, destino, trazado FROM variante WHERE id = pg_temp.v() $q$, '23505');

SELECT pg_temp.debe_fallar('B. Configuración', 'Ramal que no existe', 'ramal_t (Tabla 59)',
       $q$ INSERT INTO variante (linea_id, ramal, sentido, destino, trazado)
           SELECT linea_id, 'TAXI', 'IDA', 'Ninguno', trazado FROM variante WHERE id = pg_temp.v() $q$, '22P02');

SELECT pg_temp.debe_fallar('B. Configuración', 'Código de paradero con formato incorrecto', 'ck_paradero_codigo',
       $q$ INSERT INTO paradero (codigo, nombre, ubicacion) VALUES ('P-1', 'Paradero', ST_SetSRID(ST_MakePoint(-71.5, -16.45), 4326)) $q$, '23514');

SELECT pg_temp.debe_fallar('B. Configuración', 'Nombre de paradero de menos de 3 letras', 'ck_paradero_nombre',
       $q$ INSERT INTO paradero (codigo, nombre, ubicacion) VALUES ('stp_950', 'ab', ST_SetSRID(ST_MakePoint(-71.5, -16.45), 4326)) $q$, '23514');

SELECT pg_temp.debe_fallar('B. Configuración', 'Mismo paradero dos veces en una variante', 'pk_paradero_variante (RF-015)',
       $q$ INSERT INTO paradero_variante VALUES (pg_temp.v(), pg_temp.p('stp_901'), 99, 0) $q$, '23505');

SELECT pg_temp.debe_fallar('B. Configuración', 'Dos paraderos en la misma posición', 'uq_variante_orden (RF-015)',
       $q$ INSERT INTO paradero_variante VALUES (pg_temp.v(), pg_temp.p('stp_904'), 1, 0) $q$, '23505');

SELECT pg_temp.debe_fallar('B. Configuración', 'Segunda cuenta para la misma unidad', 'uq_cuenta_unidad (RN-001)',
       $q$ INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
           VALUES (pg_temp.u('T1'), 'otra.cuenta', '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u') $q$, '23505');

SELECT pg_temp.debe_fallar('B. Configuración', 'Usuario con espacios y mayúsculas', 'ck_cuenta_conductor_usuario',
       $q$ INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
           VALUES (pg_temp.u('TBORRAR'), 'Unidad 07', '$2b$12$nfL5pFmDVzxbqsFNIF3uTOIr2og46/CkipNZrwJUnerW.kiWwBa6u') $q$, '23514');

SELECT pg_temp.debe_fallar('B. Configuración', 'Contraseña guardada en texto plano', 'ck_cuenta_conductor_hash (RNF-15)',
       $q$ INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
           VALUES (pg_temp.u('TBORRAR'), 'unidad99', rpad('micontrasena123', 60)) $q$, '23514');

SELECT pg_temp.debe_fallar('B. Configuración', 'Más de 5 intentos fallidos', 'ck_cuenta_conductor_intentos (RN-011)',
       $q$ UPDATE cuenta_conductor SET intentos_fallidos = 6 WHERE usuario = 'prueba.t1' $q$, '23514');

SELECT pg_temp.verificar('B. Configuración', 'Cuenta de conductor sin columnas de datos personales', 'RNF-15 / Ley 29733',
       NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'cuenta_conductor'
                      AND column_name ~ '(nombre|dni|documento|telefono|correo|email)'),
       'No existe dónde guardar nombre, DNI, teléfono ni correo');


-- ==========================================================
-- C. SESIONES DE EMISIÓN
-- ==========================================================
SELECT pg_temp.debe_funcionar('C. Sesiones', 'Abrir sesión de la unidad T1', 'RF-013',
       $q$ INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id)
           VALUES (pg_temp.u('T1'), pg_temp.c('prueba.t1'), pg_temp.v()) $q$);

SELECT pg_temp.debe_fallar('C. Sesiones', 'Segunda sesión abierta para la misma unidad', 'uq_sesion_abierta_unidad (RN-002)',
       $q$ INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id)
           VALUES (pg_temp.u('T1'), pg_temp.c('prueba.t1'), pg_temp.v()) $q$, '23505');

SELECT pg_temp.debe_fallar('C. Sesiones', 'Unidad inactiva intenta abrir sesión', 'trg_sesion_validar_apertura',
       $q$ INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id)
           VALUES (pg_temp.u('T3'), pg_temp.c('prueba.t3'), pg_temp.v()) $q$, '23514');

SELECT pg_temp.debe_fallar('C. Sesiones', 'Cuenta de otra unidad abre sesión', 'trg_sesion_validar_apertura (RN-001)',
       $q$ INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id)
           VALUES (pg_temp.u('T1'), pg_temp.c('prueba.t2'), pg_temp.v()) $q$, '23514');

SELECT pg_temp.debe_fallar('C. Sesiones', 'Sesión cerrada sin fecha de fin', 'ck_sesion_cierre',
       $q$ UPDATE sesion_emision SET estado = 'CERRADA_POR_CONDUCTOR' WHERE id = pg_temp.s('T1') $q$, '23514');

SELECT pg_temp.debe_fallar('C. Sesiones', 'Sesión que termina antes de empezar', 'ck_sesion_fin',
       $q$ UPDATE sesion_emision SET estado = 'CERRADA_POR_CONDUCTOR', fin = inicio - interval '1 hour'
            WHERE id = pg_temp.s('T1') $q$, '23514');

SELECT pg_temp.verificar('C. Sesiones', 'La unidad aparece en la vista de unidades activas', 'v_unidades_activas (GET /vehicles)',
       EXISTS (SELECT 1 FROM v_unidades_activas WHERE etiqueta = 'T1'),
       'T1 visible con su variante y destino');


-- ==========================================================
-- D. POSICIONES
-- ==========================================================
SELECT pg_temp.debe_funcionar('D. Posiciones', 'Registrar una posición válida', 'POST /positions',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m, capturada_en, valida)
           VALUES ('11111111-1111-4111-8111-111111111111', pg_temp.s('T1'),
                   ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 30, 180, 8, now(), true) $q$);

SELECT pg_temp.debe_fallar('D. Posiciones', 'Lote reenviado: misma posición dos veces', 'pk_posicion (idempotencia)',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m, capturada_en, valida)
           VALUES ('11111111-1111-4111-8111-111111111111', pg_temp.s('T1'),
                   ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 30, 180, 8, now(), true) $q$, '23505');

DO $$
DECLARE
    v_filas integer;
BEGIN
    -- Así insertará el backend: un lote reenviado no duplica ni produce error
    INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida)
    VALUES ('11111111-1111-4111-8111-111111111111', pg_temp.s('T1'),
            ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 8, now(), true)
    ON CONFLICT (id) DO NOTHING;
    GET DIAGNOSTICS v_filas = ROW_COUNT;

    PERFORM pg_temp.verificar('D. Posiciones', 'Reenvío con ON CONFLICT no duplica ni falla',
                              'Idempotencia (P06, decisión 3)', v_filas = 0,
                              v_filas || ' filas insertadas, sin error');
END
$$;

SELECT pg_temp.debe_fallar('D. Posiciones', 'Posición descartada sin motivo', 'ck_motivo_descarte (RF-019)',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), pg_temp.s('T1'), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 8, now(), false) $q$, '23514');

SELECT pg_temp.debe_fallar('D. Posiciones', 'Posición válida con motivo de descarte', 'ck_motivo_descarte (RF-019)',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida, motivo_descarte)
           VALUES (gen_random_uuid(), pg_temp.s('T1'), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 8, now(), true, 'DUPLICADA') $q$, '23514');

SELECT pg_temp.debe_fallar('D. Posiciones', 'Rumbo de 400 grados', 'ck_rumbo',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, rumbo, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), pg_temp.s('T1'), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 400, 8, now(), true) $q$, '23514');

SELECT pg_temp.debe_fallar('D. Posiciones', 'Velocidad de 250 km/h', 'ck_velocidad',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), pg_temp.s('T1'), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 250, 8, now(), true) $q$, '23514');

SELECT pg_temp.debe_fallar('D. Posiciones', 'Precisión negativa', 'ck_precision',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), pg_temp.s('T1'), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), -1, now(), true) $q$, '23514');

SELECT pg_temp.debe_fallar('D. Posiciones', 'Posición de una sesión que no existe', 'fk_posicion_sesion',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), gen_random_uuid(), ST_SetSRID(ST_MakePoint(-71.5, -16.455), 4326), 8, now(), true) $q$, '23503');

-- Error realista: coordenadas en UTM zona 19S (usado en mapas del Perú) en vez de WGS 84
SELECT pg_temp.debe_fallar('D. Posiciones', 'Coordenada en UTM 19S en lugar de WGS 84', 'GEOMETRY(Point, 4326)',
       $q$ INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, valida)
           VALUES (gen_random_uuid(), pg_temp.s('T1'),
                   ST_SetSRID(ST_MakePoint(231500, 8178600), 32719), 8, now(), true) $q$, '22023');


-- ==========================================================
-- E. AUDITORÍA, ELIMINACIONES Y RETENCIÓN
-- ==========================================================
SELECT pg_temp.debe_fallar('E. Auditoría y retención', 'Código HTTP inexistente', 'ck_evento_codigo_http',
       $q$ INSERT INTO registro_evento (tipo, origen, codigo_http) VALUES ('ERROR', 'prueba', 700) $q$, '23514');

SELECT pg_temp.debe_fallar('E. Auditoría y retención', 'Borrar una unidad que tiene cuenta', 'fk_cuenta_unidad',
       $q$ DELETE FROM unidad WHERE etiqueta = 'T2' $q$, '23503');

INSERT INTO registro_evento (tipo, origen, unidad_id) VALUES ('SEGURIDAD', 'prueba', pg_temp.u('TBORRAR'));
DELETE FROM unidad WHERE etiqueta = 'TBORRAR';
SELECT pg_temp.verificar('E. Auditoría y retención', 'La auditoría sobrevive al borrar la unidad', 'fk_evento_unidad ON DELETE SET NULL',
       EXISTS (SELECT 1 FROM registro_evento WHERE origen = 'prueba' AND tipo = 'SEGURIDAD' AND unidad_id IS NULL),
       'El evento se conserva con unidad_id = NULL');

-- Sesión cerrada de hace 40 días, con una posición y un evento antiguos
INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id, estado, inicio, fin)
VALUES (pg_temp.u('T2'), pg_temp.c('prueba.t2'), pg_temp.v(), 'CERRADA_AUTOMATICAMENTE',
        now() - interval '40 days', now() - interval '40 days' + interval '2 hours');
INSERT INTO posicion (id, sesion_id, coordenada, precision_m, capturada_en, recibida_en, valida)
VALUES (gen_random_uuid(), pg_temp.s('T2'), ST_SetSRID(ST_MakePoint(-71.5, -16.46), 4326), 8,
        now() - interval '40 days', now() - interval '40 days', true);
INSERT INTO registro_evento (tipo, origen, fecha) VALUES ('PETICION', 'prueba_antigua', now() - interval '40 days');

SELECT pg_temp.verificar('E. Auditoría y retención', 'Depuración elimina solo lo de más de 30 días', 'fn_depurar_datos_operativos (RN-012)',
       (SELECT d.sesiones_eliminadas >= 1 AND d.posiciones_eliminadas >= 1 AND d.eventos_eliminados >= 1
          FROM fn_depurar_datos_operativos(30) d)
       AND EXISTS (SELECT 1 FROM posicion WHERE id = '11111111-1111-4111-8111-111111111111')
       AND EXISTS (SELECT 1 FROM sesion_emision WHERE id = pg_temp.s('T1')),
       'Datos antiguos eliminados; la sesión y posición recientes se conservan');

SELECT pg_temp.verificar('E. Auditoría y retención', 'La depuración queda registrada', 'RF-020',
       EXISTS (SELECT 1 FROM registro_evento WHERE tipo = 'TAREA' AND origen = 'depuracion_diaria'),
       'Evento TAREA con el número de filas eliminadas');

DELETE FROM sesion_emision WHERE id = pg_temp.s('T1');
SELECT pg_temp.verificar('E. Auditoría y retención', 'Al borrar una sesión se borran sus posiciones', 'fk_posicion_sesion ON DELETE CASCADE',
       NOT EXISTS (SELECT 1 FROM posicion WHERE id = '11111111-1111-4111-8111-111111111111'),
       'Sin posiciones huérfanas');


-- ==========================================================
-- F. SEGURIDAD: permisos del rol de la aplicación
-- ==========================================================
GRANT INSERT ON resultado TO rutasur_app;
GRANT USAGE ON SEQUENCE resultado_n_seq TO rutasur_app;

SET ROLE rutasur_app;

SELECT pg_temp.debe_funcionar('F. Seguridad (rol rutasur_app)', 'La app puede leer la ruta y las unidades', 'Menor privilegio',
       $q$ SELECT count(*) FROM paradero_variante JOIN variante ON variante.id = paradero_variante.variante_id $q$);

SELECT pg_temp.debe_fallar('F. Seguridad (rol rutasur_app)', 'La app intenta borrar un paradero', 'Menor privilegio',
       $q$ DELETE FROM paradero WHERE codigo = 'stp_901' $q$, '42501');

SELECT pg_temp.debe_fallar('F. Seguridad (rol rutasur_app)', 'La app intenta borrar posiciones directamente', 'Menor privilegio',
       $q$ DELETE FROM posicion $q$, '42501');

SELECT pg_temp.debe_fallar('F. Seguridad (rol rutasur_app)', 'La app intenta alterar la auditoría', 'Menor privilegio',
       $q$ UPDATE registro_evento SET origen = 'alterado' $q$, '42501');

SELECT pg_temp.debe_fallar('F. Seguridad (rol rutasur_app)', 'La app intenta eliminar una tabla', 'Menor privilegio',
       $q$ DROP TABLE posicion $q$, '42501');

SELECT pg_temp.debe_fallar('F. Seguridad (rol rutasur_app)', 'La app intenta crear una tabla', 'Menor privilegio',
       $q$ CREATE TABLE public.intrusa (id int) $q$, '42501');

SELECT pg_temp.debe_funcionar('F. Seguridad (rol rutasur_app)', 'La app sí puede ejecutar la depuración', 'SECURITY DEFINER',
       $q$ SELECT * FROM fn_depurar_datos_operativos(30) $q$);

RESET ROLE;


-- ----------------------------------------------------------
-- Resultado
-- ----------------------------------------------------------
\o
\echo
\echo '================  RESULTADO DE LAS PRUEBAS DE INTEGRIDAD  ================'
SELECT n AS "N.°", grupo AS "Grupo", prueba AS "Prueba", regla AS "Regla verificada",
       resultado AS "Resultado", detalle AS "Detalle"
  FROM resultado ORDER BY n;

SELECT count(*) FILTER (WHERE resultado = 'OK')    AS "Pruebas OK",
       count(*) FILTER (WHERE resultado = 'FALLO') AS "Pruebas con FALLO",
       count(*)                                    AS "Total"
  FROM resultado;

-- Si hubo algún fallo, el script termina con error (útil en GitHub Actions)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM resultado WHERE resultado = 'FALLO') THEN
        RAISE EXCEPTION 'Hay pruebas con FALLO';
    END IF;
END
$$;

-- Se deshacen todos los datos de prueba
ROLLBACK;
