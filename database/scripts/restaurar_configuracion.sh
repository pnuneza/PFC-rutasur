#!/usr/bin/env bash
# ==========================================================
# RutaSur v1.0 — restaurar_configuracion.sh
# Procedimiento de restauración (P06, Tabla 63):
#   1. Crear una base vacía con el esquema (aplicar_esquema.sh).
#   2. Importar la última copia de configuración con pg_restore.
#
# La base destino debe tener el esquema creado y SIN datos de
# configuración (la semilla de la línea se reemplaza por la del respaldo).
#
# Uso:
#   bash restaurar_configuracion.sh /rutasur/respaldos/config_AAAAMMDD_HHMMSS.dump
# ==========================================================
set -euo pipefail

ARCHIVO="${1:?Indique el archivo .dump a restaurar}"
DATABASE_URL="${DATABASE_URL:-dbname=${POSTGRES_DB:-rutasur} user=${POSTGRES_USER:-postgres}}"

[ -f "$ARCHIVO" ] || { echo "No existe el archivo $ARCHIVO" >&2; exit 1; }

echo "Restaurando configuración desde $ARCHIVO ..."

# Se elimina la semilla para no duplicar la línea LB (todo en una transacción)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "
    DELETE FROM linea
     WHERE NOT EXISTS (SELECT 1 FROM variante WHERE variante.linea_id = linea.id);"

pg_restore --dbname="$DATABASE_URL" \
           --data-only \
           --single-transaction \
           --exit-on-error \
           "$ARCHIVO"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    SELECT 'linea' AS tabla, count(*) AS filas FROM linea
    UNION ALL SELECT 'variante',          count(*) FROM variante
    UNION ALL SELECT 'paradero',          count(*) FROM paradero
    UNION ALL SELECT 'paradero_variante', count(*) FROM paradero_variante
    UNION ALL SELECT 'unidad',            count(*) FROM unidad
    UNION ALL SELECT 'cuenta_conductor',  count(*) FROM cuenta_conductor
    UNION ALL SELECT 'cuenta_administrativa', count(*) FROM cuenta_administrativa;"

echo "Restauración terminada."
