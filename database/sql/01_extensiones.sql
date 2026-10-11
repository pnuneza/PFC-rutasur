-- ==========================================================
-- RutaSur v1.0 — 01_extensiones.sql
-- Extensiones de PostgreSQL que necesita el modelo (P06, 2.16.1)
-- ==========================================================

-- PostGIS: tipos geométricos (puntos, líneas) y funciones para medir
-- distancias y proyectar un punto sobre el trazado (cálculo del ETA).
CREATE EXTENSION IF NOT EXISTS postgis;

-- pg_trgm + unaccent: búsqueda de paraderos por parte del nombre,
-- sin distinguir mayúsculas ni tildes (GET /stops?q=).
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- unaccent() no es IMMUTABLE, por eso no puede usarse directamente en un
-- índice. Esta envoltura fija el diccionario y sí puede indexarse.
CREATE OR REPLACE FUNCTION f_unaccent(texto text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$
    SELECT public.unaccent('public.unaccent'::regdictionary, texto)
$$;

COMMENT ON FUNCTION f_unaccent(text) IS
    'Quita tildes de un texto; versión inmutable de unaccent() para usar en índices.';
