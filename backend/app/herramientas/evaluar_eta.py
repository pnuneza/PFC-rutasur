"""Evaluación del ETA con viajes reales (prueba de campo, Módulo 7).

Responde a la pregunta del indicador «nivel de error de la predicción»: cuando la app
decía «llega en N minutos», ¿cuánto tardó de verdad?

Para cada sesión de emisión (un viaje de una unidad en una variante):

1. Toma las posiciones válidas que guardó el servidor y calcula cuánto había recorrido
   la unidad sobre el trazado en cada una, con la misma fórmula que usa la API.
2. Calcula la **llegada real** a cada paradero: el instante en que lo recorrido alcanzó
   la distancia del paradero, interpolando entre las dos posiciones de cada lado.
3. **Reproduce el ETA** que la API habría dado en cada posición, con el mismo
   `EstimadorDirecto` (mismo código, mismas reglas: velocidad = avance real en los
   últimos 10 min, mínimo 5 km/h, sin llegadas de más de 60 min). Con
   `--solo-gps` reproduce el estimador de la 0.7.2 (velocidad del GPS de los últimos
   20 s), para comparar.
4. Compara: error = ETA estimado − tiempo real que faltaba. Positivo: la combi llegó
   antes de lo anunciado; negativo: llegó tarde.

Resultado: MAE y RMSE (Tabla 1 del plan de tesis), el porcentaje de estimaciones con
error de 2 minutos o menos, el error por horizonte (a 5, 10, 20… minutos de la llegada)
y la hoja de contraste en CSV para la tesis (una fila por paradero y estimación).

No modifica la base. Las posiciones se conservan 14 días (RN-012): hay que evaluar
dentro de ese plazo.

Uso (con DATABASE_URL del rol rutasur_app, la misma de Render):
    python -m app.herramientas.evaluar_eta --desde 2026-11-03 --hasta 2026-11-14 \\
        --unidad 07 --csv contraste_eta.csv
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from dataclasses import dataclass, replace
from datetime import date, datetime, time, timedelta
from statistics import fmean
from zoneinfo import ZoneInfo

from sqlalchemy import Engine, text

from app.domain.modelos import CandidatoLlegada, Ramal, Sentido
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.services.estimador_eta import EstimadorDirecto

LIMA = ZoneInfo("America/Lima")
HORIZONTES_MIN = (5, 10, 20, 40, 60)
TOLERANCIA_S = 120  # «acierta» si el error es de 2 minutos o menos
# El estimador de la 0.7.2: nunca usa la ventana, solo la velocidad del GPS
SOLO_GPS = replace(UMBRALES_POR_DEFECTO, ventana_minima_s=10**9)


# ----------------------------------------------------------------------
# Datos
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Lectura:
    """Posición válida de la unidad, ya proyectada sobre el trazado."""

    en: datetime
    recorrido_m: float
    velocidad_kmh: float | None


@dataclass(frozen=True, slots=True)
class ParaderoDeViaje:
    codigo: str
    nombre: str
    distancia_m: float
    principal: bool = False


@dataclass(frozen=True, slots=True)
class Viaje:
    sesion_id: str
    etiqueta: str
    ramal: Ramal
    sentido: Sentido
    destino: str
    paraderos: list[ParaderoDeViaje]
    lecturas: list[Lectura]


@dataclass(frozen=True, slots=True)
class Contraste:
    """Una estimación comparada con la realidad (una fila de la hoja de contraste)."""

    sesion_id: str
    etiqueta: str
    variante: str
    paradero: ParaderoDeViaje
    estimado_en: datetime
    distancia_restante_m: float
    eta_s: float
    real_s: float

    @property
    def error_s(self) -> float:
        return self.eta_s - self.real_s


# ----------------------------------------------------------------------
# Cálculo (sin base de datos: se prueba con viajes sintéticos)
# ----------------------------------------------------------------------
def llegadas_reales(
    lecturas: list[Lectura], paraderos: list[ParaderoDeViaje]
) -> dict[str, datetime]:
    """Instante en que la unidad alcanzó cada paradero, interpolando en el tiempo.

    Solo cuentan los paraderos que la unidad tenía por delante en la primera lectura y
    que alcanzó antes de la última: los demás no se pueden cronometrar.
    """
    llegadas: dict[str, datetime] = {}
    for p in paraderos:
        for antes, despues in zip(lecturas, lecturas[1:], strict=False):
            if antes.recorrido_m < p.distancia_m <= despues.recorrido_m:
                avance = despues.recorrido_m - antes.recorrido_m
                fraccion = (p.distancia_m - antes.recorrido_m) / avance
                llegadas[p.codigo] = antes.en + (despues.en - antes.en) * fraccion
                break
    return llegadas


def reproducir(
    viaje: Viaje,
    cada_s: int = 60,
    umbrales: Umbrales = UMBRALES_POR_DEFECTO,
) -> list[Contraste]:
    """ETA que la API habría mostrado, una vez por minuto, frente a la llegada real."""
    estimador = EstimadorDirecto(umbrales)
    llegadas = llegadas_reales(viaje.lecturas, viaje.paraderos)
    variante = f"{viaje.ramal}-{viaje.sentido}"
    contrastes: list[Contraste] = []
    siguiente: datetime | None = None
    for i, lectura in enumerate(viaje.lecturas):
        if siguiente is not None and lectura.en < siguiente:
            continue
        siguiente = lectura.en + timedelta(seconds=cada_s)
        desde = max(0, i + 1 - umbrales.posiciones_para_velocidad)
        recientes = [x.velocidad_kmh for x in reversed(viaje.lecturas[desde : i + 1])]
        # Igual que la API: primera lectura de la ventana reciente (D-21)
        limite = lectura.en - timedelta(seconds=umbrales.ventana_velocidad_s)
        inicio = next(x for x in viaje.lecturas[: i + 1] if x.en >= limite)
        avance_m = lectura.recorrido_m - inicio.recorrido_m
        duracion_s = (lectura.en - inicio.en).total_seconds()
        for p in viaje.paraderos:
            # RN-006: solo paraderos que la unidad todavía no pasó
            if p.codigo not in llegadas or p.distancia_m <= lectura.recorrido_m:
                continue
            real_s = (llegadas[p.codigo] - lectura.en).total_seconds()
            estimacion = estimador.estimar(
                CandidatoLlegada(
                    etiqueta=viaje.etiqueta,
                    ramal=viaje.ramal,
                    sentido=viaje.sentido,
                    destino=viaje.destino,
                    distancia_recorrida_m=lectura.recorrido_m,
                    distancia_paradero_m=p.distancia_m,
                    ultima_posicion_en=lectura.en,
                    velocidades_recientes_kmh=recientes,
                    avance_ventana_m=avance_m,
                    duracion_ventana_s=duracion_s,
                ),
                lectura.en,
            )
            if estimacion.eta_s > umbrales.eta_maximo_s:  # RN-007: la app no la muestra
                continue
            contrastes.append(
                Contraste(
                    sesion_id=viaje.sesion_id,
                    etiqueta=viaje.etiqueta,
                    variante=variante,
                    paradero=p,
                    estimado_en=lectura.en,
                    distancia_restante_m=estimacion.distancia_m,
                    eta_s=estimacion.eta_s,
                    real_s=real_s,
                )
            )
    return contrastes


@dataclass(frozen=True, slots=True)
class Resumen:
    n: int
    mae_s: float
    rmse_s: float
    sesgo_s: float  # promedio del error: + anuncia de más, − anuncia de menos
    aciertos: float  # proporción con |error| ≤ 2 min


def resumir(contrastes: list[Contraste]) -> Resumen | None:
    if not contrastes:
        return None
    errores = [c.error_s for c in contrastes]
    return Resumen(
        n=len(errores),
        mae_s=fmean(abs(e) for e in errores),
        rmse_s=math.sqrt(fmean(e * e for e in errores)),
        sesgo_s=fmean(errores),
        aciertos=sum(abs(e) <= TOLERANCIA_S for e in errores) / len(errores),
    )


def por_horizonte(contrastes: list[Contraste]) -> list[tuple[str, Resumen | None]]:
    """Error según cuánto faltaba de verdad: no es lo mismo acertar a 5 que a 40 minutos."""
    limites = [0, *HORIZONTES_MIN]
    filas = []
    for desde, hasta in zip(limites, limites[1:], strict=False):
        grupo = [c for c in contrastes if desde * 60 <= c.real_s < hasta * 60]
        filas.append((f"{desde}–{hasta} min", resumir(grupo)))
    return filas


# ----------------------------------------------------------------------
# Lectura de la base
# ----------------------------------------------------------------------
_SQL_SESIONES = text("""
    SELECT s.id::text AS id, u.etiqueta, v.id AS variante_id, v.ramal::text AS ramal,
           v.sentido::text AS sentido, v.destino
      FROM sesion_emision s
      JOIN unidad u   ON u.id = s.unidad_id
      JOIN variante v ON v.id = s.variante_id
     WHERE s.inicio >= :desde AND s.inicio < :hasta
       AND (CAST(:unidad AS text) IS NULL OR u.etiqueta = :unidad)
     ORDER BY s.inicio
""")

_SQL_PARADEROS = text("""
    SELECT p.codigo, p.nombre, pv.distancia_desde_inicio_m::float8 AS distancia, p.principal
      FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
     WHERE pv.variante_id = :variante
     ORDER BY pv.orden
""")

# Misma proyección que la API al recibir cada posición (repositorio de emisión)
_SQL_LECTURAS = text("""
    SELECT p.capturada_en, p.velocidad_kmh::float8 AS velocidad,
           ST_Length(ST_LineSubstring(v.trazado, 0,
                     ST_LineLocatePoint(v.trazado, p.coordenada))::geography) AS recorrido
      FROM posicion p
      JOIN sesion_emision s ON s.id = p.sesion_id
      JOIN variante v       ON v.id = s.variante_id
     WHERE p.sesion_id = CAST(:sesion AS uuid) AND p.valida
     ORDER BY p.capturada_en
""")


def cargar_viajes(motor: Engine, desde: date, hasta: date, unidad: str | None) -> list[Viaje]:
    """Sesiones que empezaron entre «desde» y «hasta» (días en hora de Lima, inclusive)."""
    inicio = datetime.combine(desde, time.min, LIMA)
    fin = datetime.combine(hasta + timedelta(days=1), time.min, LIMA)
    viajes = []
    with motor.connect() as c:
        sesiones = c.execute(
            _SQL_SESIONES, {"desde": inicio, "hasta": fin, "unidad": unidad}
        ).mappings()
        for s in list(sesiones):
            paraderos = [
                ParaderoDeViaje(f["codigo"], f["nombre"], f["distancia"], f["principal"])
                for f in c.execute(_SQL_PARADEROS, {"variante": s["variante_id"]}).mappings()
            ]
            lecturas = [
                Lectura(f["capturada_en"], f["recorrido"], f["velocidad"])
                for f in c.execute(_SQL_LECTURAS, {"sesion": s["id"]}).mappings()
            ]
            viajes.append(
                Viaje(
                    sesion_id=s["id"],
                    etiqueta=s["etiqueta"],
                    ramal=Ramal(s["ramal"]),
                    sentido=Sentido(s["sentido"]),
                    destino=s["destino"],
                    paraderos=paraderos,
                    lecturas=lecturas,
                )
            )
    return viajes


# ----------------------------------------------------------------------
# Salida
# ----------------------------------------------------------------------
def _min(segundos: float) -> str:
    return f"{segundos / 60:.1f}".replace(".", ",")


def _fila(nombre: str, r: Resumen | None) -> str:
    if r is None:
        return f"| {nombre} | 0 | — | — | — | — |"
    return (
        f"| {nombre} | {r.n} | {_min(r.mae_s)} | {_min(r.rmse_s)} | {_min(r.sesgo_s)} "
        f"| {r.aciertos:.0%} |"
    )


def informe(viajes: list[Viaje], contrastes: list[Contraste]) -> str:
    lineas = [
        "## Viajes",
        "",
        "| Inicio (Lima) | Unidad | Variante | Posiciones | Paraderos cronometrados |",
        "|---|---|---|---|---|",
    ]
    for v in viajes:
        inicio = v.lecturas[0].en.astimezone(LIMA).strftime("%d/%m %H:%M") if v.lecturas else "—"
        llegadas = llegadas_reales(v.lecturas, v.paraderos)
        lineas.append(
            f"| {inicio} | {v.etiqueta} | {v.ramal}-{v.sentido} | {len(v.lecturas)} "
            f"| {len(llegadas)} de {len(v.paraderos)} |"
        )
    cabecera = "| Grupo | Estimaciones | MAE (min) | RMSE (min) | Sesgo (min) | Error ≤ 2 min |"
    lineas += ["", "## Error del ETA", "", cabecera, "|---|---|---|---|---|---|"]
    lineas.append(_fila("Todas", resumir(contrastes)))
    principales = [c for c in contrastes if c.paradero.principal]
    lineas.append(_fila("Paraderos principales", resumir(principales)))
    for variante in sorted({c.variante for c in contrastes}):
        lineas.append(_fila(variante, resumir([c for c in contrastes if c.variante == variante])))
    lineas += ["", "## Error según cuánto faltaba", "", cabecera, "|---|---|---|---|---|---|"]
    for nombre, r in por_horizonte(contrastes):
        lineas.append(_fila(nombre, r))
    lineas += [
        "",
        "Sesgo positivo: la app anunció más minutos de los que tardó (la combi llegó antes).",
    ]
    return "\n".join(lineas)


def escribir_csv(ruta: str, contrastes: list[Contraste]) -> None:
    with open(ruta, "w", newline="", encoding="utf-8-sig") as f:  # se abre bien en Excel
        w = csv.writer(f, delimiter=";")
        w.writerow(
            [
                "sesion", "unidad", "variante", "paradero", "nombre", "principal",
                "estimado_en", "distancia_restante_m", "eta_min", "real_min", "error_min",
            ]
        )  # fmt: skip
        for c in contrastes:
            w.writerow(
                [
                    c.sesion_id[:8],
                    c.etiqueta,
                    c.variante,
                    c.paradero.codigo,
                    c.paradero.nombre,
                    "sí" if c.paradero.principal else "no",
                    c.estimado_en.astimezone(LIMA).strftime("%Y-%m-%d %H:%M:%S"),
                    round(c.distancia_restante_m),
                    _min(c.eta_s),
                    _min(c.real_s),
                    _min(c.error_s),
                ]
            )


def principal(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--desde", type=date.fromisoformat, required=True, help="AAAA-MM-DD")
    p.add_argument("--hasta", type=date.fromisoformat, required=True, help="AAAA-MM-DD")
    p.add_argument("--unidad", help="Etiqueta de la unidad, por ejemplo 07")
    p.add_argument("--cada", type=int, default=60, help="Segundos entre estimaciones (60)")
    p.add_argument("--csv", help="Archivo de la hoja de contraste")
    p.add_argument(
        "--solo-gps",
        action="store_true",
        help="Estimador de la 0.7.2: solo la velocidad del GPS de los últimos 20 s",
    )
    args = p.parse_args(argv)

    from app.db.conexion import obtener_motor  # solo al usarla desde la consola

    viajes = cargar_viajes(obtener_motor(), args.desde, args.hasta, args.unidad)
    if not viajes:
        print("No hay viajes en ese periodo. Las posiciones se conservan 14 días.")
        return 1
    umbrales = SOLO_GPS if args.solo_gps else UMBRALES_POR_DEFECTO
    contrastes = [c for v in viajes for c in reproducir(v, args.cada, umbrales)]
    print(informe(viajes, contrastes))
    if args.csv:
        escribir_csv(args.csv, contrastes)
        print(f"\nHoja de contraste: {args.csv} ({len(contrastes)} filas)")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
