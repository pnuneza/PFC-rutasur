-- ==========================================================
-- RutaSur v1.0 — 03_tablas.sql
-- Tablas del modelo lógico (P06, Figura 47 y Tabla 60)
-- Restricciones con nombre propio según la Tabla 61.
--
-- Convenciones:
--   pk_  clave primaria      fk_  clave foránea
--   uq_  valor único         ck_  regla de verificación
--   Fechas en hora universal (TIMESTAMPTZ).
--   Coordenadas en WGS 84 (SRID 4326), igual que el GPS del teléfono.
-- ==========================================================


-- ----------------------------------------------------------
-- DATOS DE CONFIGURACIÓN (pocos, cambian rara vez, no se pierden)
-- ----------------------------------------------------------

-- Línea de transporte (una fila: LB)
CREATE TABLE linea (
    id              UUID         NOT NULL DEFAULT gen_random_uuid(),
    codigo          VARCHAR(10)  NOT NULL,
    nombre          VARCHAR(80)  NOT NULL,
    hora_inicio     TIME         NOT NULL,
    hora_fin        TIME         NOT NULL,
    actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_linea          PRIMARY KEY (id),
    CONSTRAINT uq_linea_codigo   UNIQUE (codigo),
    CONSTRAINT ck_horario        CHECK (hora_fin > hora_inicio)          -- RN-009
);


-- Variante: un ramal en un sentido (cuatro filas)
CREATE TABLE variante (
    id          UUID                    NOT NULL DEFAULT gen_random_uuid(),
    linea_id    UUID                    NOT NULL,
    ramal       ramal_t                 NOT NULL,
    sentido     sentido_t               NOT NULL,
    destino     VARCHAR(60)             NOT NULL,
    trazado     GEOMETRY(LineString, 4326) NOT NULL,
    longitud_m  NUMERIC(8,1)            NOT NULL,   -- la calcula un trigger
    activa      BOOLEAN                 NOT NULL DEFAULT true,

    CONSTRAINT pk_variante                PRIMARY KEY (id),
    CONSTRAINT fk_variante_linea          FOREIGN KEY (linea_id) REFERENCES linea (id),
    CONSTRAINT uq_variante_ramal_sentido  UNIQUE (linea_id, ramal, sentido),
    CONSTRAINT ck_variante_longitud       CHECK (longitud_m > 0),
    CONSTRAINT ck_variante_destino        CHECK (char_length(btrim(destino)) >= 3),
    CONSTRAINT ck_variante_trazado        CHECK (ST_IsValid(trazado) AND ST_NPoints(trazado) >= 2)
);


-- Paradero: punto de parada
CREATE TABLE paradero (
    id              UUID                  NOT NULL DEFAULT gen_random_uuid(),
    codigo          VARCHAR(12)           NOT NULL,
    nombre          VARCHAR(80)           NOT NULL,
    referencia      VARCHAR(120),
    ubicacion       GEOMETRY(Point, 4326) NOT NULL,
    en_tramo_comun  BOOLEAN               NOT NULL DEFAULT false,
    activo          BOOLEAN               NOT NULL DEFAULT true,

    CONSTRAINT pk_paradero          PRIMARY KEY (id),
    CONSTRAINT uq_paradero_codigo   UNIQUE (codigo),
    CONSTRAINT ck_paradero_codigo   CHECK (codigo ~ '^stp_[0-9]{3}$'),
    CONSTRAINT ck_paradero_nombre   CHECK (char_length(btrim(nombre)) >= 3)
);


-- Paradero_variante: orden de los paraderos en cada variante (relación N:M)
CREATE TABLE paradero_variante (
    variante_id               UUID          NOT NULL,
    paradero_id               UUID          NOT NULL,
    orden                     SMALLINT      NOT NULL,
    distancia_desde_inicio_m  NUMERIC(8,1)  NOT NULL,

    CONSTRAINT pk_paradero_variante  PRIMARY KEY (variante_id, paradero_id),
    CONSTRAINT fk_pv_variante        FOREIGN KEY (variante_id) REFERENCES variante (id),
    CONSTRAINT fk_pv_paradero        FOREIGN KEY (paradero_id) REFERENCES paradero (id),
    -- DEFERRABLE: permite reordenar paraderos dentro de una transacción
    -- (PUT /admin/variants/{id}/stops) sin chocar con el orden temporal.
    CONSTRAINT uq_variante_orden     UNIQUE (variante_id, orden)
                                     DEFERRABLE INITIALLY IMMEDIATE,
    CONSTRAINT ck_pv_orden           CHECK (orden > 0),
    CONSTRAINT ck_pv_distancia       CHECK (distancia_desde_inicio_m >= 0)
);


-- Unidad: vehículo de la flota
CREATE TABLE unidad (
    id         UUID         NOT NULL DEFAULT gen_random_uuid(),
    etiqueta   VARCHAR(20)  NOT NULL,
    activa     BOOLEAN      NOT NULL DEFAULT true,
    creada_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_unidad           PRIMARY KEY (id),
    CONSTRAINT uq_unidad_etiqueta  UNIQUE (etiqueta)
);


-- Cuenta del conductor: acceso a la app del conductor.
-- Sin datos personales: no existe columna para nombre, DNI ni teléfono (RNF-15).
CREATE TABLE cuenta_conductor (
    id                 UUID         NOT NULL DEFAULT gen_random_uuid(),
    unidad_id          UUID         NOT NULL,
    usuario            VARCHAR(30)  NOT NULL,
    hash_contrasena    CHAR(60)     NOT NULL,
    activa             BOOLEAN      NOT NULL DEFAULT true,
    intentos_fallidos  SMALLINT     NOT NULL DEFAULT 0,
    bloqueada_hasta    TIMESTAMPTZ,

    CONSTRAINT pk_cuenta_conductor           PRIMARY KEY (id),
    CONSTRAINT fk_cuenta_unidad              FOREIGN KEY (unidad_id) REFERENCES unidad (id),
    CONSTRAINT uq_cuenta_unidad              UNIQUE (unidad_id),          -- RN-001
    CONSTRAINT uq_cuenta_conductor_usuario   UNIQUE (usuario),
    CONSTRAINT ck_cuenta_conductor_usuario   CHECK (usuario ~ '^[a-z0-9._]{4,30}$'),
    CONSTRAINT ck_cuenta_conductor_intentos  CHECK (intentos_fallidos BETWEEN 0 AND 5),  -- RN-011
    -- Solo se acepta un hash bcrypt: impide guardar una contraseña en texto plano.
    CONSTRAINT ck_cuenta_conductor_hash      CHECK (hash_contrasena ~ '^\$2[aby]\$[0-9]{2}\$')
);


-- Cuenta administrativa: acceso al panel
CREATE TABLE cuenta_administrativa (
    id                 UUID         NOT NULL DEFAULT gen_random_uuid(),
    usuario            VARCHAR(30)  NOT NULL,
    hash_contrasena    CHAR(60)     NOT NULL,
    rol                rol_t        NOT NULL,
    activa             BOOLEAN      NOT NULL DEFAULT true,
    intentos_fallidos  SMALLINT     NOT NULL DEFAULT 0,
    bloqueada_hasta    TIMESTAMPTZ,

    CONSTRAINT pk_cuenta_administrativa           PRIMARY KEY (id),
    CONSTRAINT uq_cuenta_administrativa_usuario   UNIQUE (usuario),
    CONSTRAINT ck_cuenta_administrativa_usuario   CHECK (usuario ~ '^[a-z0-9._]{4,30}$'),
    CONSTRAINT ck_cuenta_administrativa_intentos  CHECK (intentos_fallidos BETWEEN 0 AND 5),
    CONSTRAINT ck_cuenta_administrativa_hash      CHECK (hash_contrasena ~ '^\$2[aby]\$[0-9]{2}\$')
);


-- ----------------------------------------------------------
-- DATOS OPERATIVOS (se escriben continuamente; se conservan 30 días, RN-012)
-- ----------------------------------------------------------

-- Sesión de emisión: periodo en que una unidad transmite su posición
CREATE TABLE sesion_emision (
    id                    UUID                  NOT NULL DEFAULT gen_random_uuid(),
    unidad_id             UUID                  NOT NULL,
    cuenta_conductor_id   UUID                  NOT NULL,
    variante_id           UUID                  NOT NULL,
    estado                estado_sesion_t       NOT NULL DEFAULT 'ACTIVA',
    inicio                TIMESTAMPTZ           NOT NULL DEFAULT now(),
    fin                   TIMESTAMPTZ,
    -- Copia de la última posición válida (desnormalización justificada, RNF-06):
    -- responde GET /vehicles sin recorrer la tabla posicion.
    ultima_posicion_en    TIMESTAMPTZ,
    ultima_ubicacion      GEOMETRY(Point, 4326),
    ultimo_rumbo          SMALLINT,
    ultima_velocidad_kmh  NUMERIC(5,1),
    ultima_distancia_m    NUMERIC(8,1),

    CONSTRAINT pk_sesion_emision        PRIMARY KEY (id),
    CONSTRAINT fk_sesion_unidad         FOREIGN KEY (unidad_id) REFERENCES unidad (id),
    CONSTRAINT fk_sesion_cuenta         FOREIGN KEY (cuenta_conductor_id) REFERENCES cuenta_conductor (id),
    CONSTRAINT fk_sesion_variante       FOREIGN KEY (variante_id) REFERENCES variante (id),
    -- Una sesión abierta no tiene fin; una cerrada siempre lo tiene.
    CONSTRAINT ck_sesion_cierre         CHECK ((estado IN ('ACTIVA', 'SIN_SENAL')) = (fin IS NULL)),
    CONSTRAINT ck_sesion_fin            CHECK (fin IS NULL OR fin > inicio),
    CONSTRAINT ck_sesion_ultimo_rumbo   CHECK (ultimo_rumbo BETWEEN 0 AND 359),
    CONSTRAINT ck_sesion_ultima_vel     CHECK (ultima_velocidad_kmh BETWEEN 0 AND 200),
    CONSTRAINT ck_sesion_ultima_dist    CHECK (ultima_distancia_m >= 0)
);


-- Posición: lectura GPS enviada por el conductor
CREATE TABLE posicion (
    id               UUID                  NOT NULL,          -- generado en el teléfono (idempotencia)
    sesion_id        UUID                  NOT NULL,
    coordenada       GEOMETRY(Point, 4326) NOT NULL,
    velocidad_kmh    NUMERIC(5,1),
    rumbo            SMALLINT,
    precision_m      NUMERIC(6,1)          NOT NULL,
    capturada_en     TIMESTAMPTZ           NOT NULL,
    recibida_en      TIMESTAMPTZ           NOT NULL DEFAULT now(),
    valida           BOOLEAN               NOT NULL,
    motivo_descarte  motivo_descarte_t,

    CONSTRAINT pk_posicion           PRIMARY KEY (id),
    -- Al depurar una sesión antigua se eliminan sus posiciones (RN-012).
    CONSTRAINT fk_posicion_sesion    FOREIGN KEY (sesion_id) REFERENCES sesion_emision (id)
                                     ON DELETE CASCADE,
    -- Toda posición descartada tiene su motivo, y una válida no tiene ninguno (RF-019).
    CONSTRAINT ck_motivo_descarte    CHECK (valida = (motivo_descarte IS NULL)),
    CONSTRAINT ck_rumbo              CHECK (rumbo BETWEEN 0 AND 359),
    CONSTRAINT ck_velocidad          CHECK (velocidad_kmh BETWEEN 0 AND 200),
    CONSTRAINT ck_precision          CHECK (precision_m >= 0)
);


-- ----------------------------------------------------------
-- DATOS DE AUDITORÍA (se conservan 30 días)
-- ----------------------------------------------------------

-- Registro de eventos (RF-020). No guarda direcciones IP (Ley N.° 29733).
CREATE TABLE registro_evento (
    id                        BIGINT         GENERATED ALWAYS AS IDENTITY,
    fecha                     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    tipo                      tipo_evento_t  NOT NULL,
    origen                    VARCHAR(80)    NOT NULL,
    unidad_id                 UUID,
    cuenta_administrativa_id  UUID,
    codigo_http               SMALLINT,
    detalle                   JSONB,

    CONSTRAINT pk_registro_evento     PRIMARY KEY (id),
    -- La auditoría se conserva aunque se elimine la unidad o la cuenta.
    CONSTRAINT fk_evento_unidad       FOREIGN KEY (unidad_id) REFERENCES unidad (id)
                                      ON DELETE SET NULL,
    CONSTRAINT fk_evento_cuenta_admin FOREIGN KEY (cuenta_administrativa_id)
                                      REFERENCES cuenta_administrativa (id)
                                      ON DELETE SET NULL,
    CONSTRAINT ck_evento_codigo_http  CHECK (codigo_http BETWEEN 100 AND 599)
);


-- ----------------------------------------------------------
-- Documentación dentro de la base (visible en DBeaver / pgAdmin)
-- ----------------------------------------------------------
COMMENT ON TABLE linea              IS 'Línea de transporte (una fila: LB). Horario referencial RN-009.';
COMMENT ON TABLE variante           IS 'Un ramal en un sentido. Cuatro filas: Mollebaya/Cerrillo × Ida/Vuelta.';
COMMENT ON TABLE paradero           IS 'Punto de parada. Se desactiva en lugar de borrarse.';
COMMENT ON TABLE paradero_variante  IS 'Orden y distancia acumulada de cada paradero dentro de una variante. Base del ETA (RN-006).';
COMMENT ON TABLE unidad             IS 'Vehículo de la flota. Solo las unidades activas pueden abrir sesiones.';
COMMENT ON TABLE cuenta_conductor   IS 'Acceso a la app del conductor. Una cuenta por unidad (RN-001). Sin datos personales.';
COMMENT ON TABLE cuenta_administrativa IS 'Acceso al panel administrativo.';
COMMENT ON TABLE sesion_emision     IS 'Periodo en que una unidad transmite. Una sola sesión abierta por unidad (RN-002).';
COMMENT ON TABLE posicion           IS 'Lectura GPS enviada por el conductor. Se conserva 30 días (RN-012).';
COMMENT ON TABLE registro_evento    IS 'Auditoría (RF-020). Sin direcciones IP. Se conserva 30 días.';

COMMENT ON COLUMN variante.longitud_m IS 'Longitud del trazado en metros; la calcula el trigger trg_variante_longitud.';
COMMENT ON COLUMN paradero_variante.distancia_desde_inicio_m IS 'Distancia sobre el trazado desde el inicio de la variante; la calcula fn_recalcular_paraderos_variante().';
COMMENT ON COLUMN posicion.id IS 'UUID generado en el teléfono: si un lote se reenvía, la posición no se duplica.';
COMMENT ON COLUMN cuenta_conductor.hash_contrasena IS 'Hash bcrypt. Nunca se guarda la contraseña.';
