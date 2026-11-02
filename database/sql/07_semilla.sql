-- ==========================================================
-- RutaSur v1.0 — 07_semilla.sql
-- Datos mínimos para que el sistema arranque.
--
-- Los paraderos y trazados REALES se cargan desde la ficha de registro
-- de coordenadas y los recorridos grabados con GPS (P06, carga inicial).
-- Para desarrollo, use database/demo/datos_demo.sql.
-- ==========================================================

-- Horario referencial según la operación real (chat del grupo, jul–oct 2026): no hay
-- combis de noche. Se puede ajustar desde el panel (A-03).
INSERT INTO linea (codigo, nombre, hora_inicio, hora_fin)
VALUES ('LB', 'Línea LB — Characato', '05:00', '19:30')
ON CONFLICT (codigo) DO NOTHING;
