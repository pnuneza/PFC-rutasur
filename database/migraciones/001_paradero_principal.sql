-- ==========================================================
-- RutaSur v1.0 — migración 001 (versión 0.6.1)
-- Paraderos principales: los que la app muestra con el mapa alejado.
-- Se puede aplicar varias veces. Una base nueva ya trae la columna (03_tablas.sql).
-- ==========================================================
ALTER TABLE paradero ADD COLUMN IF NOT EXISTS principal BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN paradero.principal IS
    'Lugar de referencia que la app muestra con el mapa alejado; los demás aparecen al acercarse.';
