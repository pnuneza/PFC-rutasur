#!/usr/bin/env bash
# ==========================================================
# RutaSur v1.0 — respaldo_configuracion.sh
# Política de respaldo (P06, Tabla 63): exportación lógica de los
# datos de CONFIGURACIÓN. Las posiciones, sesiones y eventos no se
# respaldan porque son temporales (RN-012).
#
# Uso local (Docker):
#   docker compose exec db bash /rutasur/database/scripts/respaldo_configuracion.sh
# Uso contra Neon:
#   DATABASE_URL='postgresql://...' bash database/scripts/respaldo_configuracion.sh
# ==========================================================
set -euo pipefail

DATABASE_URL="${DATABASE_URL:-dbname=${POSTGRES_DB:-rutasur} user=${POSTGRES_USER:-postgres}}"
DESTINO="${RESPALDO_DIR:-/rutasur/respaldos}"
CONSERVAR="${RESPALDO_CONSERVAR:-8}"          # últimas 8 copias

mkdir -p "$DESTINO"
ARCHIVO="$DESTINO/config_$(date -u +%Y%m%d_%H%M%S).dump"

pg_dump "$DATABASE_URL" \
    --format=custom \
    --data-only \
    --table=linea \
    --table=variante \
    --table=paradero \
    --table=paradero_variante \
    --table=unidad \
    --table=cuenta_conductor \
    --table=cuenta_administrativa \
    --file="$ARCHIVO"

echo "Respaldo creado: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"

# Rotación: se conservan solo las últimas N copias
ls -1t "$DESTINO"/config_*.dump 2>/dev/null | tail -n +"$((CONSERVAR + 1))" | while read -r viejo; do
    rm -f "$viejo"
    echo "Copia antigua eliminada: $viejo"
done
