-- ==========================================================
-- RutaSur v1.0 — 04_indices.sql
-- Estrategia de indexación (P06, Tabla 62)
-- Solo se indexan las consultas que realmente se repiten.
-- Los índices de PK y UNIQUE los crea PostgreSQL automáticamente.
-- ==========================================================

-- Validación de la distancia de cada posición al trazado (RN-003)
CREATE INDEX ix_variante_trazado
    ON variante USING gist (trazado);

-- Paraderos cercanos en el panel y validación de ubicación (A-03a)
CREATE INDEX ix_paradero_ubicacion
    ON paradero USING gist (ubicacion);

-- Búsqueda por parte del nombre, sin mayúsculas ni tildes (GET /stops?q=)
CREATE INDEX ix_paradero_nombre_trgm
    ON paradero USING gin (lower(f_unaccent(nombre)) gin_trgm_ops);

-- Variantes que incluyen un paradero: primer paso del cálculo de llegadas (RN-006)
CREATE INDEX ix_pv_paradero
    ON paradero_variante (paradero_id);

-- RN-002: una sola sesión abierta por unidad.
-- Además de proteger la regla, acelera la lista de unidades activas (GET /vehicles).
CREATE UNIQUE INDEX uq_sesion_abierta_unidad
    ON sesion_emision (unidad_id)
    WHERE estado IN ('ACTIVA', 'SIN_SENAL');

-- Últimas cuatro posiciones válidas de una sesión, para estimar la velocidad
CREATE INDEX ix_posicion_sesion_tiempo
    ON posicion (sesion_id, capturada_en DESC);

-- Depuración diaria de posiciones de más de 30 días.
-- BRIN ocupa muy poco espacio porque las filas llegan en orden de tiempo.
-- autosummarize: el mantenimiento automático resume cada bloque nuevo apenas
-- se llena; sin esto, los bloques recientes se revisarían completos.
CREATE INDEX ix_posicion_recibida
    ON posicion USING brin (recibida_en)
    WITH (autosummarize = on);

-- Depuración y filtros por rango de fechas en A-05
CREATE INDEX ix_evento_fecha
    ON registro_evento USING brin (fecha)
    WITH (autosummarize = on);

-- Filtro por tipo de evento en A-05
CREATE INDEX ix_evento_tipo_fecha
    ON registro_evento (tipo, fecha);
