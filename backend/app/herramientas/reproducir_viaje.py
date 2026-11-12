"""Reproducción de un viaje real grabado (demostraciones del Módulo 7).

`simular_unidad` mueve una combi a velocidad constante sobre el trazado: sirve para
probar, pero no se parece a la calle. Esta herramienta **repite un viaje real**, lectura
por lectura y con los mismos tiempos: las paradas en los paraderos, los semáforos, el
tráfico del óvalo y los tramos rápidos de la carretera. Lo que ven la app del pasajero
y el panel es lo mismo que se vio aquel día, pero ocurriendo ahora.

Dos pasos:

1. **Exportar** un viaje de la base (rol `rutasur_app`; las posiciones se conservan
   14 días, RN-012) a un archivo JSON:
       python -m app.herramientas.reproducir_viaje exportar --sesion <id> \\
           --salida viajes/bajada.json

   El archivo contiene coordenadas exactas del recorrido de una persona: se guarda en
   la PC, **no en el repositorio** (RN-011). La carpeta `viajes/` está en .gitignore.

2. **Reproducir** el viaje por la API, exactamente como la app del conductor:
       $env:RUTASUR_CLAVE = "(contraseña de la cuenta)"
       python -m app.herramientas.reproducir_viaje reproducir \\
           --api https://rutasur-api.onrender.com --usuario unidad07 \\
           --viaje viajes/bajada.json --desde-minuto 10

   Abre una sesión con el ramal y el sentido del viaje y envía cada lectura cuando le
   toca, con la hora de ahora (el servidor no acepta posiciones anteriores al inicio de
   la sesión). `--desde-minuto` empieza a mitad del viaje y `--rapidez 2` lo pasa al
   doble de rapidez (no más: con intervalos más cortos los saltos normales del GPS
   superan los 90 km/h implícitos de RN-004 y el servidor los descarta). Ctrl+C
   cierra la sesión ordenadamente.

Para que el ETA ya use la velocidad real de los últimos 10 minutos, conviene arrancar
la reproducción unos 15 minutos antes de mostrarla.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib import error as urlerror
from uuid import uuid4

from sqlalchemy import Connection, text
from sqlalchemy.orm import Session

from app.domain.modelos import Ramal, Sentido
from app.herramientas.simular_unidad import ErrorApi, SimuladorApi


# ----------------------------------------------------------------------
# El viaje grabado
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class LecturaGrabada:
    """Una posición del viaje; `t` son los segundos desde el inicio de la sesión."""

    t: float
    lat: float
    lon: float
    velocidad_kmh: float | None
    rumbo: int | None
    precision_m: float


@dataclass(frozen=True, slots=True)
class ViajeGrabado:
    ramal: Ramal
    sentido: Sentido
    fecha: str
    lecturas: tuple[LecturaGrabada, ...]
    descripcion: str = ""

    @property
    def duracion_s(self) -> float:
        return self.lecturas[-1].t - self.lecturas[0].t if self.lecturas else 0.0


def cargar_viaje(ruta: str | Path) -> ViajeGrabado:
    """Lee un viaje exportado; falla con un mensaje claro si el archivo no sirve."""
    try:
        datos = json.loads(Path(ruta).read_text(encoding="utf-8"))
        lecturas = sorted(
            (
                LecturaGrabada(
                    t=float(x["t"]),
                    lat=float(x["lat"]),
                    lon=float(x["lon"]),
                    velocidad_kmh=None if x.get("speed_kmh") is None else float(x["speed_kmh"]),
                    rumbo=None if x.get("heading") is None else int(x["heading"]),
                    precision_m=float(x["accuracy_m"]),
                )
                for x in datos["lecturas"]
            ),
            key=lambda lectura: lectura.t,
        )
        viaje = ViajeGrabado(
            ramal=Ramal(datos["ramal"]),
            sentido=Sentido(datos["sentido"]),
            fecha=str(datos.get("fecha", "")),
            lecturas=tuple(lecturas),
            descripcion=str(datos.get("descripcion", "")),
        )
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise SystemExit(f"No se pudo leer el viaje {ruta}: {e}") from e
    if not viaje.lecturas:
        raise SystemExit(f"El viaje {ruta} no tiene lecturas")
    return viaje


def viaje_a_json(viaje: ViajeGrabado) -> dict:
    return {
        "descripcion": viaje.descripcion,
        "ramal": viaje.ramal.value,
        "sentido": viaje.sentido.value,
        "fecha": viaje.fecha,
        "lecturas": [
            {
                "t": lectura.t,
                "lat": lectura.lat,
                "lon": lectura.lon,
                "speed_kmh": lectura.velocidad_kmh,
                "heading": lectura.rumbo,
                "accuracy_m": lectura.precision_m,
            }
            for lectura in viaje.lecturas
        ],
    }


def programa(
    viaje: ViajeGrabado, desde_minuto: float = 0.0, rapidez: float = 1.0
) -> list[tuple[float, LecturaGrabada]]:
    """Cuándo enviar cada lectura: segundos desde que empieza la reproducción.

    Conserva los intervalos reales entre lecturas, divididos por `rapidez`. Las
    lecturas anteriores a `desde_minuto` se omiten y la primera restante sale en 0.
    """
    if rapidez <= 0:
        raise ValueError("La rapidez debe ser mayor que cero")
    corte = viaje.lecturas[0].t + desde_minuto * 60
    restantes = [lectura for lectura in viaje.lecturas if lectura.t >= corte]
    if not restantes:
        return []
    cero = restantes[0].t
    return [((lectura.t - cero) / rapidez, lectura) for lectura in restantes]


def lectura_a_json(lectura: LecturaGrabada, capturada_en: datetime, rapidez: float = 1.0) -> dict:
    """La lectura como la envía la app del conductor, con un id nuevo y la hora indicada."""
    velocidad = lectura.velocidad_kmh
    return {
        "id": str(uuid4()),
        "lat": lectura.lat,
        "lon": lectura.lon,
        "speed_kmh": None
        if velocidad is None
        else min(round(max(0.0, velocidad) * rapidez, 1), 200.0),
        "heading": lectura.rumbo,
        "accuracy_m": lectura.precision_m,
        "captured_at": capturada_en.isoformat(),
    }


# ----------------------------------------------------------------------
# Exportar un viaje de la base
# ----------------------------------------------------------------------
_SQL_VIAJE = text(
    """
    SELECT v.ramal::text AS ramal, v.sentido::text AS sentido, s.inicio,
           extract(epoch FROM p.capturada_en - s.inicio)::float8 AS t,
           ST_Y(p.coordenada::geometry) AS lat, ST_X(p.coordenada::geometry) AS lon,
           p.velocidad_kmh::float8 AS velocidad_kmh, p.rumbo,
           p.precision_m::float8 AS precision_m
    FROM posicion p
    JOIN sesion_emision s ON s.id = p.sesion_id
    JOIN variante v ON v.id = s.variante_id
    WHERE p.sesion_id = :sesion AND p.valida
    ORDER BY p.capturada_en
    """
)


def exportar(conexion: Connection | Session, sesion_id: str) -> ViajeGrabado:
    """Lee las posiciones válidas de la sesión; no modifica la base."""
    filas = conexion.execute(_SQL_VIAJE, {"sesion": sesion_id}).mappings().all()
    if not filas:
        raise SystemExit(f"La sesión {sesion_id} no tiene posiciones válidas (¿pasaron 14 días?)")
    primera = filas[0]
    return ViajeGrabado(
        ramal=Ramal(primera["ramal"]),
        sentido=Sentido(primera["sentido"]),
        fecha=f"{primera['inicio']:%Y-%m-%d}",
        lecturas=tuple(
            LecturaGrabada(
                t=round(f["t"], 1),
                lat=round(f["lat"], 6),
                lon=round(f["lon"], 6),
                velocidad_kmh=None if f["velocidad_kmh"] is None else round(f["velocidad_kmh"], 1),
                rumbo=f["rumbo"],
                precision_m=round(f["precision_m"], 1),
            )
            for f in filas
        ),
        descripcion=f"Sesión {sesion_id}",
    )


# ----------------------------------------------------------------------
# Reproducir por la API
# ----------------------------------------------------------------------
class ReproductorViaje(SimuladorApi):
    """Hace de teléfono del conductor, pero con las lecturas de un viaje real."""

    def __init__(
        self,
        args: argparse.Namespace,
        viaje: ViajeGrabado,
        *,
        reloj: Callable[[], float] = time.monotonic,
        dormir: Callable[[float], None] = time.sleep,
        ahora: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        super().__init__(args)
        self.viaje = viaje
        self._reloj, self._dormir, self._ahora = reloj, dormir, ahora

    def ejecutar(self) -> int:
        args = self.args
        clave = os.environ.get("RUTASUR_CLAVE") or getpass.getpass(
            f"Contraseña de {args.usuario}: "
        )
        print(f"Conectando con {args.api} (si el servicio dormía, tarda ~1 min)...")
        try:
            ingreso = self._pedir(
                "POST", "/auth/login", {"username": args.usuario, "password": clave}
            )
            self.token = ingreso["data"]["access_token"]
            etiqueta = ingreso["data"]["vehicle_label"]
            sesion = self._pedir(
                "POST",
                "/sessions",
                {"branch": self.viaje.ramal.value, "direction": self.viaje.sentido.value},
            )
        except ErrorApi as e:
            print(f"No se pudo iniciar: {e}")
            return 1
        sesion_id = sesion["data"]["session_id"]
        print(
            f"Unidad {etiqueta} · {self.viaje.ramal.value} {self.viaje.sentido.value} | "
            f"sesión {sesion_id}\nReproduciendo el viaje del {self.viaje.fecha} desde el "
            f"minuto {args.desde_minuto:g} (rapidez ×{args.rapidez:g}). Ctrl+C para detener.\n"
        )
        try:
            completo = self.recorrer(sesion_id)
            if completo:
                print("\nEl viaje terminó: la unidad llegó al final del recorrido.")
        except KeyboardInterrupt:
            print("\nReproducción detenida.")
        finally:
            try:
                self._pedir("POST", f"/sessions/{sesion_id}/close")
                print("Sesión cerrada.")
            except (ErrorApi, urlerror.URLError) as e:
                print(f"No se pudo cerrar la sesión: {e}")
        return 0

    def recorrer(self, sesion_id: str) -> bool:
        """Envía las lecturas a su hora. Devuelve False si el servidor cortó la sesión."""
        args = self.args
        plan = programa(self.viaje, args.desde_minuto, args.rapidez)
        if not plan:
            print("No quedan lecturas después de ese minuto.")
            return True
        inicio_reloj, inicio_hora = self._reloj(), self._ahora()
        duracion = self.viaje.duracion_s or 1.0
        for n, (segundo, lectura) in enumerate(plan, start=1):
            espera = segundo - (self._reloj() - inicio_reloj)
            if espera > 0:
                self._dormir(espera)
            # La hora de captura respeta el intervalo real aunque un envío se demore
            capturada = inicio_hora + timedelta(seconds=segundo)
            self.cola.append(lectura_a_json(lectura, capturada, args.rapidez))
            ultima = n == len(plan)
            if (n % args.lote == 0 or ultima) and not self._enviar(
                sesion_id, (lectura.t - self.viaje.lecturas[0].t) / duracion
            ):
                return False
        if self.cola:  # lo que no se confirmó, un último intento
            self._enviar(sesion_id, 1.0)
        return True


# ----------------------------------------------------------------------
# Línea de comandos
# ----------------------------------------------------------------------
def _argumentos(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Exporta y reproduce viajes reales de RutaSur.")
    sub = p.add_subparsers(dest="accion", required=True)

    e = sub.add_parser("exportar", help="guarda en JSON un viaje de la base (rol rutasur_app)")
    e.add_argument("--sesion", required=True, help="id de la sesión de emisión")
    e.add_argument("--salida", required=True, help="archivo JSON (fuera del repositorio)")

    r = sub.add_parser("reproducir", help="repite el viaje por la API, como la app del conductor")
    r.add_argument("--api", required=True, help="URL de la API")
    r.add_argument("--usuario", required=True, help="cuenta del conductor; clave en RUTASUR_CLAVE")
    r.add_argument("--viaje", required=True, help="archivo JSON del viaje")
    r.add_argument("--desde-minuto", type=float, default=0.0, help="minuto del viaje donde empezar")
    r.add_argument(
        "--rapidez", type=float, default=1.0, help="1 = tiempo real; 2 = el doble (máx. 2)"
    )
    r.add_argument("--lote", type=int, default=3, help="lecturas por envío (3 → cada 15 s)")
    args = p.parse_args(argv)
    # Más rápido, el servidor descarta tramos por VELOCIDAD_IMPOSIBLE (RN-004, 90 km/h)
    if args.accion == "reproducir" and not (0 < args.rapidez <= 2 and args.desde_minuto >= 0):
        p.error("--rapidez va de 0 a 2 y --desde-minuto no puede ser negativo")
    return args


def main(argv: list[str] | None = None) -> int:
    args = _argumentos(argv)
    if args.accion == "exportar":
        from app.db.conexion import obtener_motor

        with obtener_motor().connect() as conexion:
            viaje = exportar(conexion, args.sesion)
        Path(args.salida).write_text(
            json.dumps(viaje_a_json(viaje), ensure_ascii=False), encoding="utf-8"
        )
        print(
            f"{len(viaje.lecturas)} lecturas ({viaje.duracion_s / 60:.0f} min, "
            f"{viaje.ramal.value} {viaje.sentido.value}) guardadas en {args.salida}"
        )
        return 0
    viaje = cargar_viaje(args.viaje)
    return ReproductorViaje(args, viaje).ejecutar()


if __name__ == "__main__":
    sys.exit(main())
