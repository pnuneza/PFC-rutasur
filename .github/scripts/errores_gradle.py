"""Publica como anotación de GitHub las partes útiles de un registro de compilación fallida."""

import re
import sys

texto = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lineas = texto.splitlines()
claves = re.compile(r"(error|What went wrong|FAILURE|Exception|e: |> |Could not|unresolved|Execution failed)", re.I)
utiles = []
for i, linea in enumerate(lineas):
    if claves.search(linea):
        utiles.extend(lineas[i : i + 3])
utiles = list(dict.fromkeys(x for x in utiles if x.strip()))[:60]
detalle = "\n".join(utiles or lineas[-40:])[:6000]
print("::error title=Compilación del APK::" + detalle.replace("%", "%25").replace("\n", "%0A"))
