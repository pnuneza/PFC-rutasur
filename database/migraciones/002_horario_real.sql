-- ==========================================================
-- RutaSur v1.0 — migración 002 (01/11/2026, solo datos)
-- Horario referencial real de la línea LB: de 05:00 a 19:30.
--
-- Según el chat del grupo (julio a octubre de 2026, días hábiles), la primera
-- combi sale de Santa Ana hacia las 05:40 y la última hacia las 16:45. Los
-- últimos retornos se reportan alrededor de las 18:30 (en 9 de cada 10 días,
-- antes de las 19:20). De noche no hay servicio. Ver docs/calidad/linea-base-operacion.md.
--
-- Solo cambia el horario de ejemplo de la semilla (05:00 a 21:00): si ya se
-- ajustó desde el panel, se respeta. Se puede aplicar varias veces.
-- ==========================================================
UPDATE linea
   SET hora_fin = '19:30', actualizado_en = now()
 WHERE codigo = 'LB' AND hora_inicio = '05:00' AND hora_fin = '21:00';
