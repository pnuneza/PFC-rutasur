"""Simulador de una unidad en servicio.

Hace el papel del teléfono del conductor mientras la app móvil no existe: abre
una sesión de emisión y recorre el trazado de la variante enviando posiciones,
en lotes, al MISMO servicio de emisión que usará la API (validador incluido).
Mientras corre, GET /vehicles y GET /stops/{codigo}/arrivals cambian en vivo.

Uso (con la base de datos en marcha y el archivo .env configurado):
    python -m app.herramientas.simular_unidad --unidad 12 --ramal CERRILLO --sentido IDA
    python -m app.herramientas.simular_unidad --unidad 12 --ramal CERRILLO --sentido IDA \\
        --velocidad 35 --con-errores

Detener con Ctrl+C: la sesión se cierra ordenadamente.
"""

import argparse
import random
import sys
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from math import atan2, cos, degrees, radians, sin
from uuid import uuid4

from sqlalchemy.orm import Session

from app.db.conexion import obtener_motor
from app.domain.excepciones import ErrorDeNegocio
from app.domain.geo import distancia_m
from app.domain.modelos import Coordenada, PosicionEntrante, Ramal, Sentido
from app.repositories.sql_emision import RepositorioEmisionSQL
from app.repositories.sql_rutas import RepositorioRutasSQL
from app.services.servicio_emision import ServicioEmision
from app.services.validador_posiciones import ValidadorPosiciones

# Generador pseudoaleatorio solo para dar realismo al recorrido simulado;
# no interviene en nada relacionado con seguridad.
_azar = random.Random()  # noqa: S311  # nosec B311


@dataclass
class Recorrido:
    """Trazado de la variante con las distancias acumuladas de cada vértice."""

    puntos: list[Coordenada]
    acumulado: list[float]

    @classmethod
    def desde(cls, puntos: list[Coordenada]) -> "Recorrido":
        acumulado = [0.0]
        for a, b in zip(puntos, puntos[1:], strict=False):
            acumulado.append(acumulado[-1] + distancia_m(a, b))
        return cls(puntos, acumulado)

    @property
    def longitud_m(self) -> float:
        return self.acumulado[-1]

    def punto_a(self, metros: float) -> tuple[Coordenada, int]:
        """Punto del trazado a cierta distancia del inicio, y el rumbo del tramo."""
        metros = min(max(metros, 0.0), self.longitud_m)
        for i in range(1, len(self.acumulado)):
            if metros <= self.acumulado[i]:
                a, b = self.puntos[i - 1], self.puntos[i]
                tramo = self.acumulado[i] - self.acumulado[i - 1] or 1.0
                f = (metros - self.acumulado[i - 1]) / tramo
                punto = Coordenada(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f)
                return punto, _rumbo(a, b)
        return self.puntos[-1], 0


def _rumbo(a: Coordenada, b: Coordenada) -> int:
    """Dirección de avance en grados (0 = norte, 90 = este)."""
    lat1, lat2 = radians(a.lat), radians(b.lat)
    dlon = radians(b.lon - a.lon)
    x = sin(dlon) * cos(lat2)
    y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
    return int(degrees(atan2(x, y)) % 360)


def _con_ruido(punto: Coordenada, metros: float) -> Coordenada:
    """Desplaza el punto unos metros al azar, como el error normal de un GPS."""
    grados = metros / 111_320
    return Coordenada(
        punto.lat + _azar.uniform(-grados, grados), punto.lon + _azar.uniform(-grados, grados)
    )


def _posicion(
    punto: Coordenada, rumbo: int, velocidad: float, con_errores: bool
) -> PosicionEntrante:
    precision = round(_azar.uniform(4, 12), 1)
    ubicacion = _con_ruido(punto, 4)
    if con_errores:
        sorteo = _azar.random()
        if sorteo < 0.05:  # GPS impreciso → PRECISION_INSUFICIENTE
            precision = 85.0
        elif sorteo < 0.10:  # salto de 600 m fuera de la ruta → FUERA_DE_CORREDOR
            ubicacion = _con_ruido(Coordenada(punto.lat + 0.0055, punto.lon), 0)
    return PosicionEntrante(
        id=uuid4(),
        ubicacion=ubicacion,
        velocidad_kmh=round(velocidad + _azar.uniform(-3, 3), 1),
        rumbo=rumbo,
        precision_m=precision,
        capturada_en=datetime.now(UTC),
    )


def _argumentos() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Simula una unidad de RutaSur emitiendo su posición.")
    p.add_argument("--unidad", required=True, help="Etiqueta de la unidad, por ejemplo 12")
    p.add_argument("--ramal", required=True, choices=[r.value for r in Ramal])
    p.add_argument("--sentido", required=True, choices=[s.value for s in Sentido])
    p.add_argument("--velocidad", type=float, default=30.0, help="km/h (por defecto 30)")
    p.add_argument("--cada", type=float, default=5.0, help="segundos entre lecturas (5)")
    p.add_argument("--lote", type=int, default=3, help="lecturas por envío (3 → cada 15 s)")
    p.add_argument("--desde", type=float, default=0.0, help="metros ya recorridos al empezar")
    p.add_argument("--con-errores", action="store_true", help="mezcla lecturas defectuosas")
    return p.parse_args()


def main() -> int:
    args = _argumentos()
    ramal, sentido = Ramal(args.ramal), Sentido(args.sentido)
    motor = obtener_motor()
    validador = ValidadorPosiciones()

    # 1. Preparar: trazado de la variante, unidad y apertura de la sesión
    with Session(motor) as s:
        linea = RepositorioRutasSQL(s).obtener_linea("LB")
        variante = next(
            (
                v
                for v in (linea.variantes if linea else [])
                if (v.ramal, v.sentido) == (ramal, sentido)
            ),
            None,
        )
        ids = RepositorioEmisionSQL(s).buscar_unidad_por_etiqueta(args.unidad)
        if variante is None or ids is None:
            print("No se encontró la variante o la unidad (¿cargó los datos demo?)")
            return 1
        unidad_id, cuenta_id = ids
        try:
            sesion = ServicioEmision(RepositorioEmisionSQL(s), validador).abrir_sesion(
                unidad_id, cuenta_id, ramal, sentido, datetime.now(UTC)
            )
        except ErrorDeNegocio as e:
            print(f"No se pudo abrir la sesión: {e}")
            return 1
        s.commit()

    recorrido = Recorrido.desde(variante.trazado)
    print(f"Unidad {args.unidad} → {variante.destino} | sesión {sesion.id}")
    km = recorrido.longitud_m / 1000
    print(f"Recorrido de {km:.1f} km a {args.velocidad:.0f} km/h. Ctrl+C para detener.\n")

    # 2. Recorrer el trazado enviando lotes, como lo hará el teléfono del conductor
    recorrido_m = args.desde
    pendientes: list[PosicionEntrante] = []
    try:
        while recorrido_m < recorrido.longitud_m:
            punto, rumbo = recorrido.punto_a(recorrido_m)
            pendientes.append(_posicion(punto, rumbo, args.velocidad, args.con_errores))
            if len(pendientes) >= args.lote:
                _enviar(motor, validador, sesion.id, unidad_id, pendientes, recorrido_m, recorrido)
                pendientes = []
            time.sleep(args.cada)
            recorrido_m += args.velocidad / 3.6 * args.cada
        print("\nLa unidad llegó al final del recorrido.")
    except KeyboardInterrupt:
        print("\nSimulación detenida.")
    finally:
        with Session(motor) as s:
            ServicioEmision(RepositorioEmisionSQL(s), validador).cerrar_sesion(sesion.id, unidad_id)
            s.commit()
        print("Sesión cerrada.")
    return 0


def _enviar(motor, validador, sesion_id, unidad_id, lote, recorrido_m, recorrido) -> None:
    # Un lote rechazado no detiene la emisión: el teléfono real tampoco se cierra,
    # informa el problema y sigue con el siguiente envío.
    try:
        with Session(motor) as s:
            acuse = ServicioEmision(RepositorioEmisionSQL(s), validador).recibir_lote(
                sesion_id, unidad_id, lote, datetime.now(UTC)
            )
            s.commit()
    except ErrorDeNegocio as e:
        print(f"{datetime.now():%H:%M:%S}  lote rechazado por el servidor: {e}")
        return
    avance = recorrido_m / recorrido.longitud_m * 100
    print(
        f"{datetime.now():%H:%M:%S}  avance {avance:5.1f} %  "
        f"publicadas {acuse.publicadas}  descartadas {acuse.descartadas}  "
        f"duplicadas {acuse.duplicadas}"
    )


if __name__ == "__main__":
    sys.exit(main())
