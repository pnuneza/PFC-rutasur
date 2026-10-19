"""Convierte el recorrido real de un ramal (GPX de ida y vuelta) en un script SQL.

El GPX se dibujó en BRouter-Web siguiendo las calles: empieza en el paradero final
del ramal, llega al Centro y regresa. El script lo parte en el punto más alejado
del inicio (el Centro):

    1.ª mitad  →  IDA    (ramal → Centro)
    2.ª mitad  →  VUELTA (Centro → ramal)

y genera `trazado_<ramal>.sql`, que reemplaza en la base los trazados de
demostración por los reales. Solo usa la biblioteca estándar de Python.

Uso (desde la carpeta database/datos_reales):
    py gpx_a_sql.py RutaMollebaya.gpx --ramal MOLLEBAYA
"""

import argparse
import math
import xml.etree.ElementTree as ET  # noqa: S405  (archivo propio, no de terceros)
from pathlib import Path


def leer_puntos(gpx: Path) -> list[tuple[float, float]]:
    """Puntos (lon, lat) del track, sin repetidos consecutivos."""
    arbol = ET.parse(gpx)  # noqa: S314
    puntos: list[tuple[float, float]] = []
    for nodo in arbol.iter():
        if nodo.tag.endswith("trkpt") or nodo.tag.endswith("rtept"):
            p = (float(nodo.attrib["lon"]), float(nodo.attrib["lat"]))
            if not puntos or puntos[-1] != p:
                puntos.append(p)
    if len(puntos) < 10:
        raise SystemExit(f"{gpx.name}: el GPX tiene muy pocos puntos ({len(puntos)}).")
    return puntos


def distancia_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lon1, lat1, lon2, lat2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


def longitud_m(puntos: list[tuple[float, float]]) -> float:
    return sum(distancia_m(a, b) for a, b in zip(puntos, puntos[1:], strict=False))


def wkt(puntos: list[tuple[float, float]]) -> str:
    return "LINESTRING(" + ", ".join(f"{lon:.6f} {lat:.6f}" for lon, lat in puntos) + ")"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("gpx", type=Path)
    parser.add_argument("--ramal", required=True, choices=["MOLLEBAYA"])
    args = parser.parse_args()

    puntos = leer_puntos(args.gpx)
    giro = max(range(len(puntos)), key=lambda i: distancia_m(puntos[0], puntos[i]))
    ida, vuelta = puntos[: giro + 1], puntos[giro:]

    cierre = distancia_m(puntos[0], puntos[-1])
    if cierre > 300:
        print(f"Aviso: el recorrido no vuelve al inicio (termina a {cierre:.0f} m).")

    sql = (
        Path(__file__)
        .with_name(f"plantilla_{args.ramal.lower()}.sql")
        .read_text(encoding="utf-8")
        .replace("{{RAMAL}}", args.ramal)
        .replace("{{ORIGEN}}", args.gpx.name)
        .replace("{{WKT_IDA}}", wkt(ida))
        .replace("{{WKT_VUELTA}}", wkt(vuelta))
    )
    salida = Path(__file__).with_name(f"trazado_{args.ramal.lower()}.sql")
    salida.write_text(sql, encoding="utf-8", newline="\n")

    print(f"Puntos: {len(puntos)}  ·  giro en el punto {giro} {puntos[giro][::-1]}")
    print(f"IDA:    {len(ida)} puntos, {longitud_m(ida) / 1000:.2f} km")
    print(f"VUELTA: {len(vuelta)} puntos, {longitud_m(vuelta) / 1000:.2f} km")
    print(f"Listo: {salida.name}")


if __name__ == "__main__":
    main()
