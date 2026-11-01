#!/usr/bin/env bash
# ==========================================================
# Compila el panel administrativo (Flutter Web) para publicarlo.
# Lo usa Render al desplegar el sitio estático «rutasur-panel» (render.yaml): su
# máquina de compilación no trae Flutter, así que se descarga la versión estable.
#
#   bash tool/construir_panel_web.sh            (desde la carpeta app)
#   API_URL=http://localhost:8000 bash tool/construir_panel_web.sh
# ==========================================================
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
    echo "Descargando Flutter (estable)…"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

flutter --version
flutter config --no-analytics >/dev/null
flutter pub get
flutter build web --release \
  -t lib/entrypoints/main_panel.dart \
  --dart-define=API_URL="${API_URL:-https://rutasur-api.onrender.com}"
echo "Panel listo en app/build/web"
