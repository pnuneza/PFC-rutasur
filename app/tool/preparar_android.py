"""Ajusta el AndroidManifest.xml que genera `flutter create` (se ejecuta una sola vez).

- Permiso de INTERNET: la app consulta la API.
- usesCleartextTraffic: permite HTTP sin cifrar hacia la API LOCAL de desarrollo
  (http://10.0.2.2:8000). En producción la API usa HTTPS (P05, Tabla 34) y este
  permiso se retira.
- Nombre visible de la app: «RutaSur».

Uso (desde la carpeta app):  py tool/preparar_android.py
"""

from pathlib import Path

MANIFIESTO = Path(__file__).resolve().parents[1] / "android/app/src/main/AndroidManifest.xml"

texto = MANIFIESTO.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in texto:
    texto = texto.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )
if "usesCleartextTraffic" not in texto:
    texto = texto.replace(
        "<application", '<application\n        android:usesCleartextTraffic="true"', 1
    )
texto = texto.replace('android:label="rutasur"', 'android:label="RutaSur"')

MANIFIESTO.write_text(texto, encoding="utf-8")
print(f"Listo: {MANIFIESTO}")
