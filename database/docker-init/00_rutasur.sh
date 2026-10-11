#!/usr/bin/env bash
# ==========================================================
# RutaSur v1.0 — inicialización del contenedor
# Docker ejecuta este archivo UNA sola vez: cuando el volumen de
# datos está vacío (primer `docker compose up`).
# Para volver a ejecutarlo: docker compose down -v && docker compose up -d
# ==========================================================

bash /rutasur/database/aplicar_esquema.sh

if [ "${RUTASUR_CARGAR_DEMO:-no}" = "si" ]; then
    echo "RutaSur: cargando datos de demostración..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
         -f /rutasur/database/demo/datos_demo.sql
fi
