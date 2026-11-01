"""Publica cada prueba fallida de `flutter test --reporter json` como anotación de GitHub.

Así el fallo se lee en el PR sin abrir el registro completo del trabajo.
"""

import json
import sys

nombres, errores, impresos = {}, {}, {}
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
        elif tipo == "print":
            # En las pruebas de widgets la excepción real se imprime antes del error
            impresos.setdefault(evento["testID"], []).append(evento["message"])


def escapar(texto: str) -> str:
    return texto.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


for prueba, mensajes in errores.items():
    nombre = nombres.get(prueba, f"prueba {prueba}")
    texto = "\n".join(impresos.get(prueba, []) + mensajes)
    # Lo útil está al principio de la excepción: se quitan las líneas de marco «═══»
    lineas = [x for x in texto.splitlines() if x.strip() and not x.startswith("══")]
    detalle = "\n".join(lineas[:25])[:3000]
    print(f"::error title={escapar(nombre)[:200]}::{escapar(detalle)}")
print(f"{len(errores)} pruebas con errores")
