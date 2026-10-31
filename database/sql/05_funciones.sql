-- ==========================================================
-- RutaSur v1.0 — 05_funciones.sql
-- Funciones, triggers y vistas que protegen las reglas de negocio
-- y mantienen los datos calculados (P06, 2.16.2).
--
-- Las desnormalizaciones aceptadas en P06 (longitud_m y
-- distancia_desde_inicio_m) se mantienen AQUÍ, en un único lugar,
-- para que nunca queden desactualizadas.
--
-- Seguridad: cada función fija su search_path. Así no puede ser
-- engañada con tablas falsas en otro esquema, y funciona igual
-- durante pg_restore (que ejecuta todo con search_path vacío).
-- ==========================================================


-- ----------------------------------------------------------
-- 1. Longitud del trazado: se calcula sola al guardar la variante
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_variante_longitud()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    -- geography: mide en metros sobre la superficie terrestre, no en grados
    NEW.longitud_m := round(ST_Length(NEW.trazado::geography)::numeric, 1);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_variante_longitud
    BEFORE INSERT OR UPDATE OF trazado ON variante
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_variante_longitud();


-- ----------------------------------------------------------
-- 2. Orden y distancia acumulada de los paraderos de una variante
--    Base del cálculo del ETA (RN-006). Rechaza cualquier paradero a
--    más de 150 m del trazado (validación de la carga inicial, P06).
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalcular_paraderos_variante(
    p_variante_id   uuid,
    p_tolerancia_m  numeric DEFAULT 150
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_trazado  geometry;
    v_fuera    record;
    v_filas    integer;
BEGIN
    SELECT trazado INTO v_trazado
      FROM variante
     WHERE id = p_variante_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La variante % no existe', p_variante_id
              USING ERRCODE = 'no_data_found';
    END IF;

    -- Validación: ningún paradero puede quedar fuera del corredor
    SELECT p.codigo,
           round(ST_Distance(p.ubicacion::geography, v_trazado::geography)::numeric, 1) AS distancia
      INTO v_fuera
      FROM paradero_variante pv
      JOIN paradero p ON p.id = pv.paradero_id
     WHERE pv.variante_id = p_variante_id
       AND NOT ST_DWithin(p.ubicacion::geography, v_trazado::geography, p_tolerancia_m)
     ORDER BY distancia DESC
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'El paradero % está a % m del trazado (máximo permitido: % m)',
                        v_fuera.codigo, v_fuera.distancia, p_tolerancia_m
              USING ERRCODE = 'check_violation',
                    HINT    = 'Revise la ubicación del paradero o el trazado de la variante.';
    END IF;

    -- El orden se reasigna dentro de la transacción; se difiere la unicidad
    SET CONSTRAINTS uq_variante_orden DEFERRED;

    WITH calculo AS (
        SELECT pv.paradero_id,
               -- distancia real (en metros) recorrida sobre el trazado hasta
               -- el punto del trazado más cercano al paradero
               round(ST_Length(
                   ST_LineSubstring(v_trazado, 0, ST_LineLocatePoint(v_trazado, p.ubicacion))::geography
               )::numeric, 1) AS distancia
          FROM paradero_variante pv
          JOIN paradero p ON p.id = pv.paradero_id
         WHERE pv.variante_id = p_variante_id
    ),
    ordenado AS (
        SELECT paradero_id,
               distancia,
               row_number() OVER (ORDER BY distancia, paradero_id) AS nuevo_orden
          FROM calculo
    )
    UPDATE paradero_variante pv
       SET orden                    = o.nuevo_orden,
           distancia_desde_inicio_m = o.distancia
      FROM ordenado o
     WHERE pv.variante_id = p_variante_id
       AND pv.paradero_id = o.paradero_id;

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    SET CONSTRAINTS uq_variante_orden IMMEDIATE;

    RETURN v_filas;
END;
$$;

COMMENT ON FUNCTION fn_recalcular_paraderos_variante(uuid, numeric) IS
    'Valida que los paraderos estén a menos de 150 m del trazado y recalcula su orden y distancia acumulada. Devuelve el número de paraderos procesados.';


-- ----------------------------------------------------------
-- 3. Asignar la lista de paraderos de una variante
--    Usada por PUT /admin/variants/{id}/stops y por la carga inicial.
--    El orden NO lo decide quien llama: se obtiene del propio trazado.
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_asignar_paraderos_variante(
    p_variante_id  uuid,
    p_codigos      varchar[]
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_encontrados  integer;
    v_distintos    integer;
BEGIN
    SELECT count(DISTINCT c) INTO v_distintos FROM unnest(p_codigos) AS c;

    IF v_distintos <> coalesce(array_length(p_codigos, 1), 0) THEN
        RAISE EXCEPTION 'La lista de paraderos tiene códigos repetidos'
              USING ERRCODE = 'unique_violation';
    END IF;

    SELECT count(*) INTO v_encontrados
      FROM paradero
     WHERE codigo = ANY (p_codigos)
       AND activo;

    IF v_encontrados <> v_distintos THEN
        RAISE EXCEPTION 'Algún código de paradero no existe o está inactivo (% de %)',
                        v_encontrados, v_distintos
              USING ERRCODE = 'foreign_key_violation';
    END IF;

    SET CONSTRAINTS uq_variante_orden DEFERRED;

    DELETE FROM paradero_variante WHERE variante_id = p_variante_id;

    INSERT INTO paradero_variante (variante_id, paradero_id, orden, distancia_desde_inicio_m)
    SELECT p_variante_id, p.id, c.n, 0          -- valores provisionales
      FROM unnest(p_codigos) WITH ORDINALITY AS c(codigo, n)
      JOIN paradero p ON p.codigo = c.codigo;

    RETURN fn_recalcular_paraderos_variante(p_variante_id);
END;
$$;

COMMENT ON FUNCTION fn_asignar_paraderos_variante(uuid, varchar[]) IS
    'Reemplaza los paraderos de una variante y calcula automáticamente su orden y distancia acumulada.';


-- ----------------------------------------------------------
-- 4. Recalcular automáticamente si cambia un trazado o un paradero
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_variante_trazado_cambiado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM fn_recalcular_paraderos_variante(NEW.id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_variante_recalcular
    AFTER UPDATE OF trazado ON variante
    FOR EACH ROW
    WHEN (OLD.trazado IS DISTINCT FROM NEW.trazado)
    EXECUTE FUNCTION fn_trg_variante_trazado_cambiado();


CREATE OR REPLACE FUNCTION fn_trg_paradero_ubicacion_cambiada()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_variante_id uuid;
BEGIN
    FOR v_variante_id IN
        SELECT variante_id FROM paradero_variante WHERE paradero_id = NEW.id
    LOOP
        PERFORM fn_recalcular_paraderos_variante(v_variante_id);
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_paradero_recalcular
    AFTER UPDATE OF ubicacion ON paradero
    FOR EACH ROW
    WHEN (OLD.ubicacion IS DISTINCT FROM NEW.ubicacion)
    EXECUTE FUNCTION fn_trg_paradero_ubicacion_cambiada();


-- ----------------------------------------------------------
-- 5. linea.actualizado_en: marca que la ruta cambió, para que el
--    teléfono del pasajero sepa que debe renovar su caché (Tabla 58).
--    A nivel de sentencia: se ejecuta una vez aunque se carguen
--    cientos de paraderos.
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_marcar_ruta_actualizada()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE linea SET actualizado_en = now();
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_variante_ruta_actualizada
    AFTER INSERT OR UPDATE OR DELETE ON variante
    FOR EACH STATEMENT EXECUTE FUNCTION fn_trg_marcar_ruta_actualizada();

CREATE TRIGGER trg_paradero_ruta_actualizada
    AFTER INSERT OR UPDATE OR DELETE ON paradero
    FOR EACH STATEMENT EXECUTE FUNCTION fn_trg_marcar_ruta_actualizada();

CREATE TRIGGER trg_pv_ruta_actualizada
    AFTER INSERT OR UPDATE OR DELETE ON paradero_variante
    FOR EACH STATEMENT EXECUTE FUNCTION fn_trg_marcar_ruta_actualizada();


-- ----------------------------------------------------------
-- 6. Apertura de sesión: solo unidades y cuentas activas, y la cuenta
--    debe ser la de esa unidad (RN-001: fuente única de posición).
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_sesion_validar_apertura()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_unidad_activa    boolean;
    v_cuenta_activa    boolean;
    v_cuenta_unidad    uuid;
    v_variante_activa  boolean;
BEGIN
    SELECT activa INTO v_unidad_activa FROM unidad WHERE id = NEW.unidad_id;
    IF NOT coalesce(v_unidad_activa, false) THEN
        RAISE EXCEPTION 'La unidad está inactiva y no puede abrir sesiones'
              USING ERRCODE = 'check_violation';
    END IF;

    SELECT activa, unidad_id INTO v_cuenta_activa, v_cuenta_unidad
      FROM cuenta_conductor WHERE id = NEW.cuenta_conductor_id;
    IF NOT coalesce(v_cuenta_activa, false) THEN
        RAISE EXCEPTION 'La cuenta del conductor está inactiva'
              USING ERRCODE = 'check_violation';
    END IF;
    IF v_cuenta_unidad IS DISTINCT FROM NEW.unidad_id THEN
        RAISE EXCEPTION 'La cuenta no corresponde a la unidad indicada (RN-001)'
              USING ERRCODE = 'check_violation';
    END IF;

    SELECT activa INTO v_variante_activa FROM variante WHERE id = NEW.variante_id;
    IF NOT coalesce(v_variante_activa, false) THEN
        RAISE EXCEPTION 'La variante declarada está inactiva'
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sesion_validar_apertura
    BEFORE INSERT ON sesion_emision
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_sesion_validar_apertura();


-- ----------------------------------------------------------
-- 7. Depuración de datos operativos y de auditoría (RN-012)
--    Se ejecuta una vez al día desde una tarea programada.
--    SECURITY DEFINER: el rol de la aplicación puede ejecutarla sin
--    tener permiso para borrar posiciones por su cuenta.
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_depurar_datos_operativos(p_dias integer DEFAULT 30)
RETURNS TABLE (
    posiciones_eliminadas  bigint,
    sesiones_eliminadas    bigint,
    eventos_eliminados     bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_limite timestamptz := now() - make_interval(days => p_dias);
BEGIN
    IF p_dias < 1 THEN
        RAISE EXCEPTION 'El periodo de retención debe ser de al menos 1 día';
    END IF;

    DELETE FROM posicion WHERE recibida_en < v_limite;
    GET DIAGNOSTICS posiciones_eliminadas = ROW_COUNT;

    DELETE FROM sesion_emision WHERE fin < v_limite;      -- sus posiciones caen en cascada
    GET DIAGNOSTICS sesiones_eliminadas = ROW_COUNT;

    DELETE FROM registro_evento WHERE fecha < v_limite;
    GET DIAGNOSTICS eventos_eliminados = ROW_COUNT;

    INSERT INTO registro_evento (tipo, origen, detalle)
    VALUES ('TAREA', 'depuracion_diaria',
            jsonb_build_object('dias_retencion', p_dias,
                               'posiciones', posiciones_eliminadas,
                               'sesiones', sesiones_eliminadas,
                               'eventos', eventos_eliminados));
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION fn_depurar_datos_operativos(integer) IS
    'Elimina posiciones, sesiones cerradas y eventos con más de N días (RN-012) y registra la tarea.';


-- ----------------------------------------------------------
-- 8. Vista de unidades en servicio (GET /vehicles)
--    Lee la copia de la última posición de cada sesión abierta.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW v_unidades_activas AS
SELECT s.id                            AS sesion_id,
       u.id                            AS unidad_id,
       u.etiqueta,
       v.id                            AS variante_id,
       v.ramal,
       v.sentido,
       v.destino,
       s.estado,
       s.inicio,
       s.ultima_posicion_en,
       ST_Y(s.ultima_ubicacion)        AS latitud,
       ST_X(s.ultima_ubicacion)        AS longitud,
       s.ultimo_rumbo,
       s.ultima_velocidad_kmh,
       s.ultima_distancia_m
  FROM sesion_emision s
  JOIN unidad   u ON u.id = s.unidad_id
  JOIN variante v ON v.id = s.variante_id
 WHERE s.estado IN ('ACTIVA', 'SIN_SENAL');

COMMENT ON VIEW v_unidades_activas IS
    'Unidades con sesión abierta y su última posición conocida (GET /vehicles).';
