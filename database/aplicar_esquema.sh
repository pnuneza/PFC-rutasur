#!/usr/bin/env bash
# ==========================================================
# RutaSur v1.0 — aplicar_esquema.sh
# Crea el esquema completo en una base vacía, en UNA sola transacción:
# si algún script falla, no queda nada a medias.
#
# Uso:
#   DATABASE_URL='postgresql://usuario:clave@host/rutasur' \
#   RUTASUR_APP_PASSWORD='********' \
#   bash database/aplicar_esquema.sh
#
# Dentro del contenedor Docker se ejecuta solo, la primera vez.
# ==========================================================
set -euo pipefail

: "${RUTASUR_APP_PASSWORD:?Defina RUTASUR_APP_PASSWORD (contraseña del rol rutasur_app)}"

# Sin DATABASE_URL, se usa la conexión local del contenedor
DATABASE_URL="${DATABASE_URL:-dbname=${POSTGRES_DB:-rutasur} user=${POSTGRES_USER:-postgres}}"

SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql"

echo "RutaSur: aplicando el esquema de base de datos..."

psql "$DATABASE_URL" \
    -v ON_ERROR_STOP=1 \
    -v app_password="$RUTASUR_APP_PASSWORD" \
    --single-transaction \
    -f "$SQL_DIR/01_extensiones.sql" \
    -f "$SQL_DIR/02_tipos.sql" \
    -f "$SQL_DIR/03_tablas.sql" \
    -f "$SQL_DIR/04_indices.sql" \
    -f "$SQL_DIR/05_funciones.sql" \
    -f "$SQL_DIR/06_roles.sql" \
    -f "$SQL_DIR/07_semilla.sql"

echo "RutaSur: esquema creado correctamente."
