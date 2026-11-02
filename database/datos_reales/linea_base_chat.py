"""Línea base de operación de la línea LB a partir del chat de WhatsApp del grupo.

Lee la exportación del chat (.txt, formato «[m/d/aa, h:mm:ss AM] Autor: texto»), se
queda solo con los avisos de salida que publica el despachador y calcula:

- salidas por día y por ramal (lunes a viernes, sábado, domingo);
- primera y última salida del día;
- intervalo entre salidas del mismo ramal;
- tiempo entre puntos de control (Santa Ana → Yanayaco → Cerrillo, etc.).

El autor de cada mensaje se descarta al leer y nada del chat se guarda: el script
solo imprime cifras agregadas. La exportación del chat NO se sube al repositorio.

Uso:
    python linea_base_chat.py chat.txt [desde AAAA-MM-DD] [hasta AAAA-MM-DD]
"""

from __future__ import annotations

import datetime as dt
import re
import statistics as st
import sys
import unicodedata
from collections import Counter, defaultdict
from itertools import pairwise

CABECERA = re.compile(r"^\[(\d+)/(\d+)/(\d+), (\d+):(\d+):\d+ ([AP]M)\] [^:]+: (.*)$")
PUNTO = re.compile(r"\s*([A-ZÁÉÍÓÚÑ .]+?)\s*:?\s*(\d{1,2})\s*[:.]\s*(\d{2})")
SINONIMOS = {
    "STA ANA": "SANTA ANA",
    "STA. ANA": "SANTA ANA",
    "DON ABDÓN": "ABDÓN",
    "MACHAHUAYA": "MACHAHUAY",
    "PLAZA": "PLAZA CHARACATO",
}
DIAS = {"lunes a viernes": range(0, 5), "sábado": [5], "domingo": [6]}


def leer_avisos(ruta: str) -> list[dict]:
    """Mensajes del chat sin autor: fecha, minuto del día y texto."""
    mensajes: list[dict] = []
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            linea = linea.rstrip("\n").replace("‎", "")
            m = CABECERA.match(linea)
            if m:
                mes, dia, anio, h, mi, ampm, texto = m.groups()
                hora = int(h) % 12 + (12 if ampm == "PM" else 0)
                mensajes.append(
                    {
                        "fecha": dt.date(2000 + int(anio), int(mes), int(dia)),
                        "minuto": hora * 60 + int(mi),
                        "texto": texto,
                    }
                )
            elif mensajes:
                mensajes[-1]["texto"] += "\n" + linea
    return mensajes


def salidas(mensajes: list[dict]) -> list[dict]:
    """Avisos «SALIDA: …» con su ramal y la hora en cada punto de control."""
    resultado = []
    for m in mensajes:
        texto = m["texto"].upper()
        if not texto.startswith("SALIDA"):
            continue
        primera = texto.split("\n")[0]
        ramal = next((r for r in ("CERRILLO", "MOLLEBAYA") if r in primera), None)
        if ramal is None:
            continue
        puntos = {}
        for linea in texto.split("\n")[1:]:
            p = PUNTO.match(linea)
            if not p:
                continue
            nombre = SINONIMOS.get(p.group(1).strip(), p.group(1).strip())
            h, mi = int(p.group(2)), int(p.group(3))
            # Escriben «01.11» por «13:11»: se toma la lectura más cercana a la del mensaje
            minuto = min((h * 60 + mi, (h % 12 + 12) * 60 + mi), key=lambda x: abs(x - m["minuto"]))
            if abs(minuto - m["minuto"]) <= 60:
                puntos[nombre] = minuto
        resultado.append(
            {
                "fecha": m["fecha"],
                "ramal": ramal,
                "hora": puntos.get("SANTA ANA", m["minuto"]),
                "puntos": puntos,
            }
        )
    return resultado


PREGUNTA = re.compile(
    r"(por\s*donde|donde\s+(esta|se\s+encuentra|va|viene)|a\s*q(ue)?\s*hora|aque\s*hora|k\s*ora|a\s*k\s*hora)"
)


def es_pregunta_de_ubicacion(texto: str) -> bool:
    """«¿Por dónde está la combi?», «¿A qué hora baja?» (sin tildes ni mayúsculas)."""
    plano = unicodedata.normalize("NFD", texto.lower()).encode("ascii", "ignore").decode()
    return not plano.startswith("salida") and PREGUNTA.search(plano) is not None


def hhmm(minuto: float) -> str:
    return f"{int(minuto) // 60:02d}:{int(minuto) % 60:02d}"


def cuartiles(valores: list[float]) -> tuple[float, float, float]:
    q = st.quantiles(valores, n=4)
    return q[0], st.median(valores), q[2]


def imprimir_preguntas(mensajes: list[dict]) -> None:
    preguntas = Counter(m["fecha"] for m in mensajes if es_pregunta_de_ubicacion(m["texto"]))
    habiles = sorted({m["fecha"] for m in mensajes if m["fecha"].weekday() < 5})
    if len(habiles) > 1:
        q1, me, q3 = cuartiles([preguntas.get(f, 0) for f in habiles])
        print(
            f"Preguntas «¿por dónde está?» o «¿a qué hora sale?» por día hábil: {me:g} "
            f"({q1:.0f}–{q3:.0f}), {sum(preguntas.values())} en total"
        )


def imprimir_salidas(lista: list[dict]) -> None:
    por_dia: dict[tuple, list[int]] = defaultdict(list)
    for s in lista:
        por_dia[(s["fecha"], s["ramal"])].append(s["hora"])
    print(
        "\n| Ramal | Días | Salidas/día (L-V) | Sábado | Domingo "
        "| Primera salida | Última salida | Intervalo |"
    )
    print("|---|---|---|---|---|---|---|---|")
    for ramal in ("MOLLEBAYA", "CERRILLO"):
        dias = {f: sorted(h) for (f, r), h in por_dia.items() if r == ramal}
        conteo = {}
        for nombre, semana in DIAS.items():
            n = [len(h) for f, h in dias.items() if f.weekday() in semana]
            conteo[nombre] = f"{st.median(n):g} ({len(n)} d)" if n else "sin avisos"
        p1, m1, p3 = cuartiles([h[0] for h in dias.values()])
        u1, mu, u3 = cuartiles([h[-1] for h in dias.values()])
        i1, mi, i3 = cuartiles(
            [b - a for h in dias.values() for a, b in pairwise(h) if 0 < b - a < 300]
        )
        print(
            f"| {ramal.title()} | {len(dias)} | {conteo['lunes a viernes']} | {conteo['sábado']} "
            f"| {conteo['domingo']} | {hhmm(m1)} ({hhmm(p1)}–{hhmm(p3)}) "
            f"| {hhmm(mu)} ({hhmm(u1)}–{hhmm(u3)}) | {mi:g} min ({i1:.0f}–{i3:.0f}) |"
        )


def imprimir_tramos(lista: list[dict]) -> None:
    tramos: dict[tuple, list[int]] = defaultdict(list)
    for s in lista:
        orden = sorted(s["puntos"].items(), key=lambda kv: kv[1])
        for (a, ta), (b, tb) in pairwise(orden):
            if 0 < tb - ta < 90:
                tramos[(s["ramal"], a, b)].append(tb - ta)
    print("\n| Ramal | Tramo | Casos | Mediana | Cuartiles |")
    print("|---|---|---|---|---|")
    for (ramal, a, b), v in sorted(tramos.items(), key=lambda kv: -len(kv[1])):
        if len(v) >= 5:
            q1, me, q3 = cuartiles(v)
            tramo = f"{a.title()} → {b.title()}"
            print(f"| {ramal.title()} | {tramo} | {len(v)} | {me:g} min | {q1:.0f}–{q3:.0f} |")


def main() -> None:
    ruta = sys.argv[1]
    desde = dt.date.fromisoformat(sys.argv[2]) if len(sys.argv) > 2 else dt.date.min
    hasta = dt.date.fromisoformat(sys.argv[3]) if len(sys.argv) > 3 else dt.date.max
    mensajes = [m for m in leer_avisos(ruta) if desde <= m["fecha"] <= hasta]
    lista = salidas(mensajes)
    print(f"Avisos de salida: {len(lista)}", dict(Counter(s["ramal"] for s in lista)))
    imprimir_preguntas(mensajes)
    imprimir_salidas(lista)
    imprimir_tramos(lista)


if __name__ == "__main__":
    main()
