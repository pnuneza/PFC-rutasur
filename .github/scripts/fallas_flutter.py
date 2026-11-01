"""Publica cada prueba fallida de `flutter test --reporter json` como anotación de GitHub.

Así el fallo se lee en el PR sin abrir el registro completo del trabajo.
"""

import json
import sys

nombres, errores = {}, {}
with open(sys.argv[1], encoding="utf-8") as archivo:
    for linea in archivo:
        try:
            evento = json.loads(linea)
        except ValueError:
            continue
        tipo = evento.get("type")
        if tipo == "testStart":
            nombres[evento["test"]["id"]] = evento["test"]["name"]
        elif tipo == "error":
            errores.setdefault(evento["testID"], []).append(evento["error"])


def escapar(texto: str) -> str:
    return texto.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


for prueba, mensajes in errores.items():
    nombre = nombres.get(prueba, f"prueba {prueba}")
    detalle = "\n".join(mensajes)[:1500]
    print(f"::error title={escapar(nombre)[:200]}::{escapar(detalle)}")
print(f"{len(errores)} pruebas con errores")
