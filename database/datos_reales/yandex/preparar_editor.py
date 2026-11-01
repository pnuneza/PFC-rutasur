"""Prepara los datos del editor de paraderos a partir de las rutas de Yandex Maps.

Entrada: T1/T0 (LB Mollebaya, ida/vuelta) y C1/C0 (LB Cerrillos, ida/vuelta), extraídos
de Yandex Maps el 26/10/2026. Cada archivo trae las paradas en orden y el trazado.

Actualización 31/10/2026: el ramal Mollebaya de VUELTA (Centro → Mollebaya) de Yandex
está desactualizado (iba por Av. Mariscal Castilla, María Nieves y Bustamante, Av. Argentina
y Av. Kennedy). Se reemplaza su trazado por el GPX trazado en BRouter por el autor
(../Centro_Mollebaya_2026-10-31.gpx), que va por el Óvalo Carvajal y la Av. Jesús. Sus
paradas candidatas son las de Yandex (Mollebaya y Cerrillos de vuelta) que quedan a 25 m
o menos del trazado nuevo, ordenadas a lo largo de él.

Actualización 01/11/2026: el ramal Cerrillo también usa trazados propios en los dos
sentidos. Ya no sale de la Calle Grau: sale del terminal Santa Ana (el mismo de Mollebaya),
pasa por Yanayaco y Cerrillo, y sigue al Centro; de vuelta hace lo inverso. Donde Yandex no
tiene paradas (el tramo nuevo), se agregan puntos de apoyo cada 100 m para que el autor
marque y nombre los paraderos en el editor.

Salida: datos_editor.json y editor_paraderos.html con, por variante, el trazado, todas las paradas de Yandex y
una preselección de paraderos principales (cada 300–700 m, priorizando lugares de
referencia). Los paraderos del tramo común se comparten entre ramales porque Yandex
usa exactamente las mismas coordenadas.
"""

import hashlib
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


# Variantes cuyo trazado viene de un GPX propio: (archivo GPX, variantes de Yandex del
# mismo sentido de las que se toman paradas candidatas, origen del trazado)
TRAZADO_PROPIO = {
    ("MOLLEBAYA", "VUELTA"): (AQUI.parent / "Centro_Mollebaya_2026-10-31.gpx", ["T0", "C0"],
                              "GPX propio (BRouter, 31/10/2026)"),
    ("CERRILLO", "IDA"): (AQUI.parent / "Cerrillo_Centro_2026-11-01.gpx", ["C1", "T1"],
                          "GPX propio (BRouter y gpx.studio, 01/11/2026)"),
    ("CERRILLO", "VUELTA"): (AQUI.parent / "Centro_Cerrillo_2026-11-01.gpx", ["C0", "T0"],
                             "GPX propio (BRouter, 01/11/2026)"),
}
# Terminal de Mollebaya: donde termina el GPX de vuelta. El bus se queda ahí y de ahí
# sale de bajada; Yandex seguía unos 100 m más por la Calle La Unión (confirmado por
# el autor el 31/10/2026). Ambos sentidos del ramal empiezan o terminan en este punto.
# En el despacho y en el chat de la ruta este punto se llama «Santa Ana».
# Desde el 01/11/2026 el ramal Cerrillo sale y llega al mismo terminal: es un solo paradero.
TERMINALES = {"MOLLEBAYA": "Santa Ana", "CERRILLO": "Santa Ana"}
GPX_DEL_TERMINAL = AQUI.parent / "Centro_Mollebaya_2026-10-31.gpx"
RADIO_CANDIDATA_M = 25
DUPLICADO_M = 8
# Lo último exportado del editor: de ahí salen los paraderos ya elegidos
EXPORTADO = AQUI.parent / "paraderos.json"
# Variantes con trazado nuevo: su preselección sale de lo ya elegido (ver seleccion_renovada)
RENOVADAS = {("CERRILLO", "IDA"), ("CERRILLO", "VUELTA")}
CERCA_M = 80
# Paraderos principales sugeridos (los que la app muestra con el mapa alejado, 0.6.1):
# terminales y lugares que todos conocen. El autor los corrige con la estrella del editor.
PRINCIPALES_SUGERIDOS = re.compile(r"plaza|cruce|óvalo|unsa|santa ana", re.IGNORECASE)
# Tramos sin paradas de Yandex: puntos de apoyo para elegir paraderos en el editor
HUECO_M = 400
PASO_APOYO_M = 100


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


def punto_en(trazado, acc, d):
    """Punto del trazado a d metros del inicio."""
    for i in range(1, len(trazado)):
        if acc[i] >= d:
            t = 0 if acc[i] == acc[i - 1] else (d - acc[i - 1]) / (acc[i] - acc[i - 1])
            a, b = trazado[i - 1], trazado[i]
            return (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
    return trazado[-1]


def con_puntos_de_apoyo(trazado, paradas):
    """Rellena cada tramo de más de 400 m sin paradas de Yandex con un punto cada 100 m.

    No tienen nombre de Yandex: el autor elige cuáles son paraderos y los nombra.
    """
    acc = acumulado(trazado)
    bordes = [0.0] + [p["d_trazado"] for p in paradas] + [acc[-1]]
    nuevas = []
    for a, b in zip(bordes, bordes[1:], strict=False):
        if b - a <= HUECO_M:
            continue
        n = int((b - a) // PASO_APOYO_M)
        for k in range(1, n):
            d = a + k * (b - a) / n
            lon, lat = punto_en(trazado, acc, d)
            nuevas.append({"nombre": "", "lon": round(lon, 6), "lat": round(lat, 6),
                           "d_trazado": d, "apoyo": True})
    return sorted(paradas + nuevas, key=lambda p: p["d_trazado"])


def punto_terminal(ramal):
    """El terminal es el final del GPX de subida a Mollebaya (compartido por los dos ramales)."""
    lon, lat = leer_gpx(GPX_DEL_TERMINAL)[-1]
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


def seleccion_renovada(ramal, sentido, paradas, obligatorias):
    """Preselección de una variante cuyo trazado cambió, a partir de lo ya exportado.

    Se conservan sus paraderos que siguen sobre el trazado y se agregan los de Mollebaya
    del mismo sentido que también quedan sobre él (donde los dos ramales van por el mismo
    camino). Si uno propio está a menos de 80 m de uno de Mollebaya, queda el de
    Mollebaya, que es el compartido.
    """
    if not EXPORTADO.exists():
        return None
    elegidos = {v["id"]: set(v["paraderos"]) for v in json.loads(EXPORTADO.read_text(encoding="utf-8"))["variantes"]}
    d = {p["clave"]: p["d"] for p in paradas}
    propios = elegidos.get(f"{ramal}-{sentido}", set()) & d.keys()
    compartidos = elegidos.get(f"MOLLEBAYA-{sentido}", set()) & d.keys()
    propios = {k for k in propios if k in compartidos or all(abs(d[k] - d[m]) >= CERCA_M for m in compartidos)}
    marcadas = propios | compartidos | set(obligatorias)
    return {i for i, p in enumerate(paradas) if p["clave"] in marcadas}


def principales_sugeridos(variantes):
    """Lo ya marcado en paraderos.json o, si nunca se marcó, la sugerencia por nombre."""
    if EXPORTADO.exists():
        exportado = json.loads(EXPORTADO.read_text(encoding="utf-8"))
        if any("principal" in p for p in exportado["paraderos"]):
            return sorted(p["clave"] for p in exportado["paraderos"] if p.get("principal"))
        nombres = {p["clave"]: p["nombre"] for p in exportado["paraderos"]}
        elegidos = {v["id"]: v["paraderos"] for v in exportado["variantes"]}
    else:
        nombres, elegidos = {}, {}
    sugeridos = set()
    for v in variantes:
        lista = elegidos.get(v["id"], v["elegidas"])
        if not lista:
            continue
        sugeridos |= {lista[0], lista[-1]}  # terminales de cada variante
        sugeridos |= {k for k in lista if PRINCIPALES_SUGERIDOS.search(nombres.get(k, ""))}
    return sorted(sugeridos)


def estado_guardado():
    """El último paraderos.json del repositorio, para que el editor lo abra tal cual.

    La versión cambia si cambia el archivo: así, cuando se combinan en el repositorio
    cambios hechos fuera del editor (por ejemplo, los lugares del chat de la ruta), el
    editor los carga en lugar de lo que tenía guardado el navegador.
    """
    if not EXPORTADO.exists():
        return None
    texto = EXPORTADO.read_text(encoding="utf-8")
    ex = json.loads(texto)
    return {
        "version": hashlib.sha1(texto.encode()).hexdigest()[:10],
        "sel": {v["id"]: v["paraderos"] for v in ex["variantes"]},
        "nombres": {p["clave"]: p["nombre"] for p in ex["paraderos"]},
        "principales": [p["clave"] for p in ex["paraderos"] if p.get("principal")],
    }


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
            paradas = con_puntos_de_apoyo(trazado, candidatas_sobre(trazado, propio[1]))
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
        # Los puntos de apoyo no se preseleccionan: el autor sabe dónde para el bus
        elegidas = {i for i in elegidas if not paradas[i].get("apoyo")} | {
            i for i, p in enumerate(paradas) if p["clave"] in forzadas}
        if (ramal, sentido) in RENOVADAS:
            elegidas = seleccion_renovada(ramal, sentido, paradas, obligatorias) or elegidas
        seleccion_por_sentido[sentido] |= {paradas[i]["clave"] for i in elegidas}
        for p in paradas:
            sugerido = (f"Sin nombre (km {p['d'] / 1000:.1f})".replace(".", ",")
                        if p.get("apoyo") else nombre_sugerido(p["nombre"]))
            salida["paradas"].setdefault(p["clave"], {
                "nombre_yandex": p["nombre"], "nombre": sugerido,
                "lon": p["lon"], "lat": p["lat"]})
        salida["variantes"].append({
            "id": f"{ramal}-{sentido}",
            "fuente_trazado": propio[2] if propio else "Yandex Maps", "ramal": ramal, "sentido": sentido, "destino": destino,
            "longitud_m": round(acc[-1]),
            "trazado": [[round(x, 6), round(y, 6)] for x, y in trazado],
            "paradas": [[p["clave"], round(p["d"])] for p in paradas],
            "elegidas": sorted(paradas[i]["clave"] for i in elegidas),
            "obligatorias": obligatorias,
        })
        print(f"{ramal:9} {sentido:6} {acc[-1] / 1000:5.1f} km  paradas Yandex={len(paradas):3}  "
              f"preseleccionadas={len(elegidas):2}  máx. desvío={max(p['off'] for p in paradas):.0f} m  "
              f"puntos de apoyo={sum(1 for p in paradas if p.get('apoyo'))}")
    salida["principales"] = principales_sugeridos(salida["variantes"])
    salida["guardado"] = estado_guardado()
    datos = json.dumps(salida, ensure_ascii=False)
    (AQUI / "datos_editor.json").write_text(datos, encoding="utf-8")
    plantilla = (AQUI / "plantilla_editor.html").read_text(encoding="utf-8")
    (AQUI / "editor_paraderos.html").write_text(
        plantilla.replace("/*__DATOS__*/null", datos), encoding="utf-8")


if __name__ == "__main__":
    main()
