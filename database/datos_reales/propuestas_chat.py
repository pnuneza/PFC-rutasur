"""Aplica a paraderos.json los lugares que usa la gente según el chat de la ruta (01/11/2026).

Fuente: exportación del grupo de WhatsApp de la línea (13/02 al 31/10/2026, ~27 000
mensajes, analizados sin nombres ni números). Ubicaciones de OpenStreetMap (Overpass y
Nominatim) proyectadas sobre los trazados. Para cada lugar:
- si ya hay un paradero elegido a 80 m o menos en esa variante, se le cambia el nombre;
- si no, se elige el punto candidato (Yandex o de apoyo) más cercano al lugar.

Uso:  py propuestas_chat.py [paraderos_anterior.json]
      Modifica paraderos.json y muestra qué hizo. Si se da el archivo anterior, no toca
      los paraderos que el autor agregó o renombró desde entonces.
"""

import json
import sys
from pathlib import Path

AQUI = Path(__file__).parent
sys.path.insert(0, str(AQUI / "yandex"))
from preparar_editor import acumulado, dist, proyectar  # noqa: E402

EDITOR = AQUI / "yandex" / "datos_editor.json"
EXPORTADO = AQUI / "paraderos.json"
SEPARACION_MINIMA_M = 150  # no dos paraderos del mismo sentido más cerca que esto
JUNTOS_M = 120  # dos paraderos del mismo sentido más cerca que esto sobran
CONSERVAR_M = SEPARACION_MINIMA_M  # un paradero con nombre de lugar conocido tan cerca no se toca
LUGAR_CONOCIDO = ("óvalo", "grifo", "plaza", "unsa", "parque", "politécnico", "coliseo",
                  "restaurante", "club", "quinta", "puente", "cementerio", "picantería",
                  "urb.", "colegio", "santa ana", "cruce", "molino", "municipalidad")


def es_solo_calle(nombre):
    """«Av. Pizarro», «Carr. Moquegua con…»: nombres de calle que conviene reemplazar."""
    n = nombre.lower()
    return not any(x in n for x in LUGAR_CONOCIDO) and n.startswith(
        ("av.", "avenida", "calle", "carr.", "carretera", "prolongación", "circunvalación")
    )
MAXIMO_M = 200

# nombre que usa la gente: (lat, lon, principal, variantes donde aplica)
LUGARES = {
    "Yanayaco": (-16.48013, -71.45780, True, ["CERRILLO-IDA", "CERRILLO-VUELTA"]),
    "Cerrillo": (-16.47248, -71.46802, True, ["CERRILLO-IDA", "CERRILLO-VUELTA"]),
    "La Huaylla": (-16.47397, -71.47747, False, ["MOLLEBAYA-IDA", "MOLLEBAYA-VUELTA"]),
    "Reservorio de Guardia Civil": (-16.42554, -71.51523, True, None),
    "Tottus Mall Aventura": (-16.41603, -71.51416, True, None),
    "Feria del Altiplano (Av. Venezuela)": (-16.40180, -71.51720, True, None),
    "El Tablón (Av. Independencia)": (-16.39925, -71.52158, False, None),
    "Goyeneche": (-16.40199, -71.52866, False, ["MOLLEBAYA-VUELTA", "CERRILLO-VUELTA"]),
    "Víctor Lira": (-16.40494, -71.53250, True, None),
}


def punto(ed, clave):
    p = ed["paradas"][clave]
    return (p["lon"], p["lat"])


def separacion_cerrillo(ed):
    """Dónde el Cerrillo se separa de Mollebaya al bajar (y se junta al subir): Don Abdón."""
    v = {x["id"]: x for x in ed["variantes"]}
    resultado = {}
    for ramal_c, ramal_m in (("CERRILLO-IDA", "MOLLEBAYA-IDA"), ("CERRILLO-VUELTA", "MOLLEBAYA-VUELTA")):
        tc = [tuple(p) for p in v[ramal_c]["trazado"]]
        tm = [tuple(p) for p in v[ramal_m]["trazado"]]
        acc_m = acumulado(tm)
        fuera = [proyectar(p, tm, acc_m)[2] > 40 for p in tc]
        if ramal_c.endswith("IDA"):  # primer punto que se aleja de Mollebaya
            i = next(i for i, f in enumerate(fuera) if f and i > 5)
            resultado[ramal_m] = tc[i - 1]
        else:  # último punto lejos de Mollebaya antes de juntarse
            i = max(i for i, f in enumerate(fuera) if f)
            resultado[ramal_m] = tc[i + 1]
    return resultado


def aplicar(anterior=None):
    """anterior: paraderos.json previo; lo que el autor agregó o renombró desde él no se toca."""
    ed = json.loads(EDITOR.read_text(encoding="utf-8"))
    ex = json.loads(EXPORTADO.read_text(encoding="utf-8"))
    protegidos = set()
    if anterior:
        previo = {p["clave"]: p["nombre"] for p in json.loads(Path(anterior).read_text(encoding="utf-8"))["paraderos"]}
        protegidos = {p["clave"] for p in ex["paraderos"] if previo.get(p["clave"]) != p["nombre"]}
    nombres = {p["clave"]: p["nombre"] for p in ex["paraderos"]}
    principales = {p["clave"] for p in ex["paraderos"] if p.get("principal")}
    variantes = {v["id"]: v for v in ed["variantes"]}
    # Como el editor: se descartan los puntos que ya no están en el trazado
    validos = {vid: {k for k, _ in v["paradas"]} for vid, v in variantes.items()}
    elegidos = {v["id"]: [k for k in v["paraderos"] if k in validos[v["id"]]] for v in ex["variantes"]}
    cambios = []

    def ubicar(nombre, lon, lat, principal, ids):
        for vid in ids or variantes:
            v = variantes[vid]
            tr = [tuple(p) for p in v["trazado"]]
            if proyectar((lon, lat), tr, acumulado(tr))[2] > MAXIMO_M:
                continue  # esta variante no pasa por ahí
            # Punto candidato más cercano al lugar, y paradero ya elegido más cercano a ese punto
            d, candidato = min((dist(punto(ed, k), (lon, lat)), k) for k, _ in v["paradas"])
            if d > MAXIMO_M:
                continue
            cerca = min(
                ((dist(punto(ed, k), punto(ed, candidato)), k) for k in elegidos[vid]),
                default=(1e9, None),
            )
            actual = nombres.get(cerca[1], "") if cerca[1] else ""
            propio = cerca[1] in protegidos
            if cerca[0] <= SEPARACION_MINIMA_M and (actual == nombre or (es_solo_calle(actual) and not propio)):
                # Ya hay un paradero ahí con nombre de calle: se le pone el que usa la gente
                clave = cerca[1]
                accion = f"renombra «{actual}»"
            elif cerca[0] <= CONSERVAR_M:
                # Ya hay un paradero con nombre de lugar conocido muy cerca: se respeta
                cambios.append(f"{vid:17} {nombre:38} se deja «{actual}» (a {round(cerca[0])} m)")
                continue
            else:
                clave = candidato
                elegidos[vid].append(clave)
                accion = f"agrega un punto a {round(d)} m del lugar"
            nombres[clave] = nombre
            if principal:
                principales.add(clave)
            cambios.append(f"{vid:17} {nombre:38} {accion}")

    for nombre, (lat, lon, principal, ids) in LUGARES.items():
        ubicar(nombre, lon, lat, principal, ids)
    for vid, (lon, lat) in separacion_cerrillo(ed).items():
        ubicar("Don Abdón", lon, lat, True, [vid, vid.replace("MOLLEBAYA", "CERRILLO")])
        cambios.append(f"{'':17} (Don Abdón calculado donde el Cerrillo se separa de Mollebaya)")

    # Limpieza: un paradero con solo nombre de calle a menos de 120 m de otro con nombre de
    # lugar (del mismo sentido) sobra; queda el que la gente reconoce.
    for vid, lista in elegidos.items():
        for k in list(lista):
            if k in protegidos or not es_solo_calle(nombres.get(k, "")):
                continue
            vecino = min(
                ((dist(punto(ed, k), punto(ed, o)), o) for o in lista
                 if o != k and not es_solo_calle(nombres.get(o, ""))),
                default=(1e9, None),
            )
            if vecino[0] < JUNTOS_M:
                lista.remove(k)
                cambios.append(f"{vid:17} quita «{nombres.get(k)}» (a {round(vecino[0])} m de «{nombres.get(vecino[1])}»)")

    # Se guarda en el formato del editor, en el orden del trazado
    usados = {k for lista in elegidos.values() for k in lista}
    orden = {vid: {k: d for k, d in variantes[vid]["paradas"]} for vid in variantes}
    for v in ex["variantes"]:
        v["paraderos"] = sorted(set(elegidos[v["id"]]), key=lambda k: orden[v["id"]][k])
    previos = {p["clave"]: p for p in ex["paraderos"]}
    ex["paraderos"] = [
        {
            "clave": k,
            "nombre": nombres.get(k) or ed["paradas"][k]["nombre"],
            "lon": ed["paradas"][k]["lon"],
            "lat": ed["paradas"][k]["lat"],
            "nombre_yandex": previos.get(k, ed["paradas"][k]).get("nombre_yandex", ""),
            "principal": k in principales,
        }
        for k in sorted(usados)
    ]
    EXPORTADO.write_text(json.dumps(ex, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("\n".join(cambios))


if __name__ == "__main__":
    aplicar(sys.argv[1] if len(sys.argv) > 1 else None)
