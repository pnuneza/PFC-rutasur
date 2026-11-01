"""Da un nombre propio a los paraderos que repetían el nombre de su calle (01/11/2026).

Pierre lo dejó a criterio del autor del software. Para cada paradero repetido en un mismo
sentido se usa el lugar conocido más cercano (OpenStreetMap, a 150 m o menos), con la
calle entre paréntesis: «Colegio de Arquitectos (Calle Colón)». Se prefieren pueblos,
colegios, mercados, restaurantes y grifos sobre urbanizaciones. Si no hay ninguno, se
agrega el kilómetro del recorrido.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

AQUI = Path(__file__).parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI / "yandex"))
import paraderos_a_sql as g  # noqa: E402
from preparar_editor import dist  # noqa: E402

PRIORIDAD = {"village": 0, "school": 1, "marketplace": 1, "restaurant": 2, "fuel": 2,
             "office": 2, "venue": 2, "landmark": 2, "place": 3, "neighbourhood": 4}
RADIO_M = 150


def renombrar(lugares):
    ed, nombres, elegidos = g.leer_entradas()
    por_variante = g.paraderos_por_variante(ed, elegidos)
    ex = json.loads(g.EXPORTADO.read_text(encoding="utf-8"))
    actuales = {p["clave"]: p["nombre"] for p in ex["paraderos"]}
    usados_por_variante = {vid: {actuales.get(k) for k in ks} for vid, ks in por_variante.items()}
    repetidos = set()
    for vid, ks in por_variante.items():
        cuenta = defaultdict(list)
        for k in ks:
            cuenta[actuales.get(k)].append(k)
        repetidos |= {k for lista in cuenta.values() if len(lista) > 1 for k in lista}

    for clave in sorted(repetidos):
        p = ed["paradas"][clave]
        calle = actuales[clave]
        candidatos = sorted(
            (PRIORIDAD.get(tipo, 5), dist((p["lon"], p["lat"]), (lon, lat)), nombre)
            for nombre, tipo, lat, lon in lugares
            if dist((p["lon"], p["lat"]), (lon, lat)) <= RADIO_M
        )
        variantes = [vid for vid, ks in por_variante.items() if clave in ks]
        nuevo = None
        # Un lugar que ya da nombre a otro paradero no se repite
        otros = [n.lower() for k, n in actuales.items() if k != clave and n]
        for _, _, lugar in candidatos:
            if any(lugar.lower()[:18] in n for n in otros):
                continue
            propuesto = f"{lugar} ({calle})"
            if all(propuesto not in usados_por_variante[v] for v in variantes):
                nuevo = propuesto
                break
        if nuevo is None:
            km = dict(next(v for v in ed["variantes"] if v["id"] == variantes[0])["paradas"])[clave]
            nuevo = f"{calle} (km {km / 1000:.1f})".replace(".", ",").replace("Carr, ", "Carr. ")
        for v in variantes:
            usados_por_variante[v].add(nuevo)
        actuales[clave] = nuevo
        print(f"{calle:16} → {nuevo:45} {', '.join(variantes)}")

    for p in ex["paraderos"]:
        p["nombre"] = actuales[p["clave"]]
    g.EXPORTADO.write_text(json.dumps(ex, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    renombrar(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
