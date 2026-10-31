"""Prepara los datos del editor de paraderos a partir de las rutas de Yandex Maps.

Entrada: T1/T0 (LB Mollebaya, ida/vuelta) y C1/C0 (LB Cerrillos, ida/vuelta), extraídos
de Yandex Maps el 26/10/2026. Cada archivo trae las paradas en orden y el trazado.

Actualización 31/10/2026: el ramal Mollebaya de VUELTA (Centro → Mollebaya) de Yandex
está desactualizado (iba por Av. Mariscal Castilla, María Nieves y Bustamante, Av. Argentina
y Av. Kennedy). Se reemplaza su trazado por el GPX trazado en BRouter por el autor
(../Centro_Mollebaya_2026-10-31.gpx), que va por el Óvalo Carvajal y la Av. Jesús. Sus
paradas candidatas son las de Yandex (Mollebaya y Cerrillos de vuelta) que quedan a 25 m
o menos del trazado nuevo, ordenadas a lo largo de él.

Salida: datos_editor.json y editor_paraderos.html con, por variante, el trazado, todas las paradas de Yandex y
una preselección de paraderos principales (cada 300–700 m, priorizando lugares de
referencia). Los paraderos del tramo común se comparten entre ramales porque Yandex
usa exactamente las mismas coordenadas.
"""

import json
import math
import re
from pathlib import Path

AQUI = Path(__file__).parent
VARIANTES = [  # archivo, ramal, sentido, destino
    ("T1", "MOLLEBAYA", "IDA", "Centro (2 de Mayo)"),
    ("T0", "MOLLEBAYA", "VUELTA", "Mollebaya"),
    ("C1", "CERRILLO", "IDA", "Centro (2 de Mayo)"),
    ("C0", "CERRILLO", "VUELTA", "Cerrillos"),
]
REFERENCIAS = (
    "plaza", "municipalidad", "colegio", "mercado", "hospital", "unsa", "grifo", "óvalo",
    "parque", "puente", "cementerio", "cruce", "urb.", "restaurante", "picantería", "club",
    "molino", "coliseo", "politécnico", "universitario", "salón", "quinta", "bcp",
)
MIN_M, IDEAL_M, MAX_M = 300, 450, 700
# Lugares que la gente reconoce: siempre son paraderos (uno por lugar).
IMPRESCINDIBLES = ("plaza de", "unsa", "municipalidad")


def leer(clave):
    texto = (AQUI / f"{clave}.txt").read_text(encoding="utf-8")
    cabecera, geom = texto.split("\nGEOM\n")
    paradas = []
    for linea in cabecera.split("\n")[1:]:
        nombre, _, lon, lat = linea.split("|")
        paradas.append({"nombre": nombre, "lon": float(lon), "lat": float(lat)})
    trazado = [tuple(map(float, p.split(","))) for p in geom.split(";")]
    return paradas, trazado


def dist(a, b):
    lo1, la1, lo2, la2 = map(math.radians, (*a, *b))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


def acumulado(trazado):
    acc = [0.0]
    for i in range(1, len(trazado)):
        acc.append(acc[-1] + dist(trazado[i - 1], trazado[i]))
    return acc


def proyectar(p, trazado, acc, desde=0):
    """Distancia sobre el trazado hasta el punto más cercano a p (búsqueda hacia adelante)."""
    mejor, mejor_d = None, 1e18
    k = math.cos(math.radians(p[1]))
    for i in range(desde, len(trazado) - 1):
        a, b = trazado[i], trazado[i + 1]
        ax, ay = (a[0] - p[0]) * k, a[1] - p[1]
        bx, by = (b[0] - p[0]) * k, b[1] - p[1]
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        t = 0 if ll == 0 else max(0, min(1, -(ax * dx + ay * dy) / ll))
        dd = math.hypot(ax + t * dx, ay + t * dy) * 111320
        if dd < mejor_d - 0.5:
            mejor_d, mejor = dd, (i, acc[i] + t * (acc[i + 1] - acc[i]))
    return mejor[1], mejor[0], mejor_d


# Variantes cuyo trazado viene de un GPX propio: (archivo GPX, variantes de Yandex
# de las que se toman paradas candidatas, en orden de preferencia)
TRAZADO_PROPIO = {
    ("MOLLEBAYA", "VUELTA"): (AQUI.parent / "Centro_Mollebaya_2026-10-31.gpx", ["T0", "C0"]),
}
# Terminal de Mollebaya: donde termina el GPX de vuelta. El bus se queda ahí y de ahí
# sale de bajada; Yandex seguía unos 100 m más por la Calle La Unión (confirmado por
# el autor el 31/10/2026). Ambos sentidos del ramal empiezan o terminan en este punto.
# En el despacho y en el chat de la ruta este punto se llama «Santa Ana».
TERMINALES = {"MOLLEBAYA": "Santa Ana"}
RADIO_CANDIDATA_M = 25
DUPLICADO_M = 8


def leer_gpx(ruta):
    texto = Path(ruta).read_text(encoding="utf-8")
    puntos = [(float(lo), float(la)) for la, lo in re.findall(r'<trkpt lat="([-\d.]+)" lon="([-\d.]+)"', texto)]
    # BRouter deja "picos" de 2–7 m donde se fijó cada punto de paso: el trazado va
    # al punto y vuelve. Se quitan para que el trazado no retroceda.
    limpio = [puntos[0]]
    for i in range(1, len(puntos) - 1):
        if dist(puntos[i - 1], puntos[i + 1]) < 1 and dist(puntos[i - 1], puntos[i]) > 0.5:
            continue
        if dist(limpio[-1], puntos[i]) < 0.5:
            continue
        limpio.append(puntos[i])
    limpio.append(puntos[-1])
    return limpio


def candidatas_sobre(trazado, archivos):
    """Paradas de Yandex a <=25 m del trazado, sin duplicados, ordenadas a lo largo de él."""
    acc = acumulado(trazado)
    vistas = []
    for archivo in archivos:
        for p in leer(archivo)[0]:
            if any(dist((p["lon"], p["lat"]), (q["lon"], q["lat"])) < DUPLICADO_M for q in vistas):
                continue
            d, _, desvio = proyectar((p["lon"], p["lat"]), trazado, acc)
            if desvio <= RADIO_CANDIDATA_M:
                p["d_trazado"] = d
                vistas.append(p)
    return sorted(vistas, key=lambda p: p["d_trazado"])


def punto_terminal(ramal):
    """El terminal es el final del GPX de vuelta del ramal."""
    gpx = TRAZADO_PROPIO[(ramal, "VUELTA")][0]
    lon, lat = leer_gpx(gpx)[-1]
    return {"nombre": TERMINALES[ramal], "lon": round(lon, 6), "lat": round(lat, 6)}


def con_terminal(ramal, sentido, trazado, paradas):
    """Corta el trazado en el terminal y lo pone como primer (ida) o último (vuelta) paradero."""
    terminal = punto_terminal(ramal)
    t = (terminal["lon"], terminal["lat"])
    if sentido == "IDA":
        i = min(range(len(trazado)), key=lambda j: dist(trazado[j], t))
        trazado = [t] + trazado[i + 1:]
        acc = acumulado(trazado)
        paradas = [p for p in paradas if proyectar((p["lon"], p["lat"]), trazado, acc)[0] > 30]
        paradas = [dict(terminal)] + paradas
    else:
        if dist(trazado[-1], t) > 1:
            trazado = trazado + [t]
        paradas = [p for p in paradas if dist((p["lon"], p["lat"]), t) > 30] + [dict(terminal)]
    return trazado, paradas, terminal


def puntaje(nombre):
    n = nombre.lower()
    if any(r in n for r in REFERENCIAS):
        return 3
    if " y " in n and n.count("avenida") >= 2:
        return 2
    return 1 if " y " in n else 0


def nombre_sugerido(nombre):
    abre = lambda s: s.replace("Avenida ", "Av. ").replace("Carretera ", "Carr. ")
    partes = nombre.split(" y ")
    if len(partes) == 1:
        return abre(nombre)
    ref = [p for p in partes[1:] if any(r in p.lower() for r in REFERENCIAS)]
    if ref:
        return f"{ref[0]} ({abre(partes[0])})"
    return " con ".join(abre(p) for p in partes)


def clave_de(p):
    return f"{p['lon']:.6f},{p['lat']:.6f}"


def seleccionar(paradas, forzadas):
    """Siempre el primero, el último y los forzados; entre ellos, uno cada ~450 m."""
    n = len(paradas)
    fijas = {0, n - 1} | {i for i, p in enumerate(paradas) if p["clave"] in forzadas}
    for i, p in enumerate(paradas):
        if any(t in p["nombre"].lower() for t in IMPRESCINDIBLES) and all(
            abs(paradas[j]["d"] - p["d"]) > 250 for j in fijas
        ):
            fijas.add(i)
    fijas = sorted(fijas)
    elegidas = set(fijas)
    for a, b in zip(fijas, fijas[1:], strict=False):
        ultimo = paradas[a]["d"]
        while paradas[b]["d"] - ultimo > MAX_M:
            ventana = [i for i in range(a + 1, b)
                       if MIN_M <= paradas[i]["d"] - ultimo <= MAX_M and paradas[b]["d"] - paradas[i]["d"] >= MIN_M * 0.6]
            if not ventana:
                break
            i = max(ventana, key=lambda j: (puntaje(paradas[j]["nombre"]),
                                            -abs(paradas[j]["d"] - ultimo - IDEAL_M)))
            elegidas.add(i)
            ultimo, a = paradas[i]["d"], i
    return elegidas


def main():
    salida = {"fuente": "Yandex Maps, rutas «LB Mollebaya» y «LB Cerrillos», consulta del 26/10/2026",
              "variantes": [], "paradas": {}}
    seleccion_por_sentido = {"IDA": set(), "VUELTA": set()}
    for archivo, ramal, sentido, destino in VARIANTES:
        propio = TRAZADO_PROPIO.get((ramal, sentido))
        if propio:
            trazado = leer_gpx(propio[0])
            paradas = candidatas_sobre(trazado, propio[1])
        else:
            paradas, trazado = leer(archivo)
        obligatorias = []
        if ramal in TERMINALES:
            trazado, paradas, terminal = con_terminal(ramal, sentido, trazado, paradas)
            obligatorias.append(clave_de(terminal))
        acc = acumulado(trazado)
        # Distancia acumulada a lo largo de la secuencia de paradas: siempre creciente,
        # aunque el trazado se cruce consigo mismo (bucle de la Av. Kennedy).
        anterior = None
        for p in paradas:
            punto = (p["lon"], p["lat"])
            p["d"] = 0.0 if anterior is None else anterior["d"] + dist((anterior["lon"], anterior["lat"]), punto)
            p["off"] = proyectar(punto, trazado, acc)[2]
            p["clave"] = clave_de(p)
            anterior = p
        forzadas = (seleccion_por_sentido[sentido] if ramal == "CERRILLO" else set()) | set(obligatorias)
        elegidas = seleccionar(paradas, forzadas)
        seleccion_por_sentido[sentido] |= {paradas[i]["clave"] for i in elegidas}
        for p in paradas:
            salida["paradas"].setdefault(p["clave"], {
                "nombre_yandex": p["nombre"], "nombre": nombre_sugerido(p["nombre"]),
                "lon": p["lon"], "lat": p["lat"]})
        salida["variantes"].append({
            "id": f"{ramal}-{sentido}",
            "fuente_trazado": "GPX propio (BRouter, 31/10/2026)" if propio else "Yandex Maps", "ramal": ramal, "sentido": sentido, "destino": destino,
            "longitud_m": round(acc[-1]),
            "trazado": [[round(x, 6), round(y, 6)] for x, y in trazado],
            "paradas": [[p["clave"], round(p["d"])] for p in paradas],
            "elegidas": sorted(paradas[i]["clave"] for i in elegidas),
            "obligatorias": obligatorias,
        })
        print(f"{ramal:9} {sentido:6} {acc[-1] / 1000:5.1f} km  paradas Yandex={len(paradas):3}  "
              f"preseleccionadas={len(elegidas):2}  máx. desvío={max(p['off'] for p in paradas):.0f} m")
    datos = json.dumps(salida, ensure_ascii=False)
    (AQUI / "datos_editor.json").write_text(datos, encoding="utf-8")
    plantilla = (AQUI / "plantilla_editor.html").read_text(encoding="utf-8")
    (AQUI / "editor_paraderos.html").write_text(
        plantilla.replace("/*__DATOS__*/null", datos), encoding="utf-8")


if __name__ == "__main__":
    main()
