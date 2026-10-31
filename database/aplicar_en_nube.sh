#!/usr/bin/env bash
# ==========================================================
# RutaSur v1.0 — aplicar_en_nube.sh
# Prepara una base de datos vacía en la nube (Neon) para producción:
#   1. Esquema completo, extensiones y rol rutasur_app (aplicar_esquema.sh)
#   2. Ruta real de la línea LB (datos_reales/ruta_lb.sql)
# NO carga datos demo: en producción no debe haber cuentas con contraseñas conocidas.
#
# Se ejecuta desde la PC, dentro del contenedor de Docker (que ya tiene psql):
#
#   docker compose exec `
#     -e DATABASE_URL="postgresql://neondb_owner:...@ep-....neon.tech/rutasur?sslmode=require" `
#     -e RUTASUR_APP_PASSWORD="(clave nueva y larga para rutasur_app)" `
#     db bash /rutasur/database/aplicar_en_nube.sh
#
# DATABASE_URL es la del DUEÑO de la base (para crear tablas y el rol).
# El servicio en Render usará después la del rol rutasur_app.
# ==========================================================
set -euo pipefail

: "${DATABASE_URL:?Defina DATABASE_URL con la conexión del dueño de la base en Neon}"
: "${RUTASUR_APP_PASSWORD:?Defina RUTASUR_APP_PASSWORD (contraseña nueva del rol rutasur_app)}"

if [ "${#RUTASUR_APP_PASSWORD}" -lt 20 ]; then
    echo "ERROR: use una contraseña de al menos 20 caracteres para rutasur_app" >&2
    exit 1
fi

case "$DATABASE_URL" in
    *localhost*|*127.0.0.1*|*@db:*|*@db/*)
        echo "ERROR: DATABASE_URL apunta a la base local, no a la nube" >&2
        exit 1 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Una base que ya tiene el esquema no se vuelve a crear (evita borrar datos por error)
if psql "$DATABASE_URL" -tAc "SELECT to_regclass('public.linea') IS NOT NULL" | grep -q t; then
    echo "La base ya tiene el esquema de RutaSur: solo se actualiza la ruta."
else
    bash "$DIR/aplicar_esquema.sh"
fi

echo "RutaSur: cargando la ruta real de la línea LB..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$DIR/datos_reales/ruta_lb.sql"

echo
echo "RutaSur: base en la nube lista."
psql "$DATABASE_URL" -c "
SELECT v.ramal, v.sentido, v.destino, round(v.longitud_m / 1000, 1) AS km,
       count(pv.paradero_id) AS paraderos
  FROM variante v
  LEFT JOIN paradero_variante pv ON pv.variante_id = v.id
 GROUP BY v.id ORDER BY v.ramal, v.sentido;"
