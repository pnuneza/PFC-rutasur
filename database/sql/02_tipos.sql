-- ==========================================================
-- RutaSur v1.0 — 02_tipos.sql
-- Tipos enumerados (P06, Tabla 59)
-- Listas cerradas de valores: la base de datos impide guardar
-- un valor que no esté en la lista.
-- ==========================================================

-- Ramal de la línea LB
CREATE TYPE ramal_t AS ENUM ('MOLLEBAYA', 'CERRILLO');

-- IDA: hacia el Centro (2 de Mayo) · VUELTA: hacia el ramal
CREATE TYPE sentido_t AS ENUM ('IDA', 'VUELTA');

-- Estados de una sesión de emisión (diagrama de estados, Figura 24)
CREATE TYPE estado_sesion_t AS ENUM (
    'ACTIVA',
    'SIN_SENAL',
    'CERRADA_POR_CONDUCTOR',
    'CERRADA_AUTOMATICAMENTE'
);

-- Motivo por el que el validador descarta una posición (RF-019)
CREATE TYPE motivo_descarte_t AS ENUM (
    'FUERA_DE_CORREDOR',
    'VELOCIDAD_IMPOSIBLE',
    'DUPLICADA',
    'PRECISION_INSUFICIENTE'
);

-- Roles del panel administrativo (Tabla 35)
CREATE TYPE rol_t AS ENUM ('ADMINISTRADOR', 'MODERADOR');

-- Tipos de evento de auditoría (RF-020)
CREATE TYPE tipo_evento_t AS ENUM (
    'PETICION',
    'ERROR',
    'POSICION_DESCARTADA',
    'SEGURIDAD',
    'TAREA'
);
