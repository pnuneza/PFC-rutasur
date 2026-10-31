"""Verificación del servicio desplegado (prueba de humo).

Recorre la API pública como lo hará la app del pasajero y comprueba lo mínimo que
debe cumplir un despliegue: el servicio y la base responden, la ruta real está
cargada, las cabeceras de seguridad llegan y la conexión es HTTPS. Mide además
cuánto tarda la primera respuesta, que en la capa gratuita de Render incluye el
arranque del servicio si estaba apagado.

Uso:
    python -m app.herramientas.verificar_despliegue https://rutasur-api.onrender.com

Devuelve código 0 si todo está bien y 1 si algo falla, para poder usarlo en scripts.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from urllib.parse import urlparse

TIEMPO_LIMITE_S = 120  # el arranque en frío de Render ronda un minuto


@dataclass
class Respuesta:
    estado: int
    cabeceras: dict[str, str]
    cuerpo: dict
    segundos: float


Obtener = Callable[[str], Respuesta]


@dataclass
class Resultado:
    verificaciones: list[tuple[str, bool, str]] = field(default_factory=list)

    def anotar(self, nombre: str, ok: bool, detalle: str = "") -> None:
        self.verificaciones.append((nombre, ok, detalle))

    @property
    def correcto(self) -> bool:
        return all(ok for _, ok, _ in self.verificaciones)


def obtener_por_red(base: str) -> Obtener:
    """Cliente HTTP con la librería estándar (no requiere instalar nada)."""
    # Solo HTTP(S): urllib también abriría file:// u otros esquemas
    if urlparse(base).scheme not in {"http", "https"}:
        raise ValueError("La URL debe empezar con http:// o https://")

    def obtener(ruta: str) -> Respuesta:
        inicio = time.monotonic()
        url = base.rstrip("/") + ruta
        peticion = urllib.request.Request(url, headers={"Accept": "application/json"})  # noqa: S310
        try:
            with urllib.request.urlopen(peticion, timeout=TIEMPO_LIMITE_S) as r:  # noqa: S310  # nosec B310
                estado, cabeceras, datos = r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            estado, cabeceras, datos = e.code, dict(e.headers), e.read()
        cabeceras = {k.lower(): v for k, v in cabeceras.items()}
        try:
            cuerpo = json.loads(datos or b"{}")
        except ValueError:
            cuerpo = {}
        return Respuesta(estado, cabeceras, cuerpo, time.monotonic() - inicio)

    return obtener


def verificar(obtener: Obtener, url_base: str) -> Resultado:
    res = Resultado()

    salud = obtener("/api/v1/health")
    datos = salud.cuerpo.get("data", {})
    res.anotar("Servicio en línea (GET /health)", salud.estado == 200, f"{salud.segundos:.1f} s")
    res.anotar("Base de datos conectada", datos.get("database") == "ok", str(datos.get("database")))
    res.anotar("Versión", bool(datos.get("version")), str(datos.get("version")))

    linea = obtener("/api/v1/routes/lb")
    variantes = linea.cuerpo.get("data", {}).get("variants", [])
    paraderos = {p["code"] for v in variantes for p in v.get("stops", [])}
    res.anotar("Ruta LB con 4 variantes", len(variantes) == 4, f"{len(variantes)} variantes")
    res.anotar("Paraderos reales cargados", len(paraderos) > 8, f"{len(paraderos)} paraderos")

    unidades = obtener("/api/v1/vehicles")
    res.anotar(
        "Unidades activas (GET /vehicles)",
        unidades.estado == 200,
        f"{len(unidades.cuerpo.get('data', []))} en servicio",
    )

    busqueda = obtener("/api/v1/stops?q=plaza")
    res.anotar(
        "Búsqueda de paraderos",
        busqueda.estado == 200,
        f"{len(busqueda.cuerpo.get('data', []))} resultados",
    )

    if paraderos:
        codigo = sorted(paraderos)[0]
        llegadas = obtener(f"/api/v1/stops/{codigo}/arrivals")
        res.anotar(f"Llegadas a {codigo}", llegadas.estado == 200, f"{llegadas.segundos:.2f} s")

    error = obtener("/api/v1/stops/stp_999/arrivals")
    res.anotar(
        "Errores con el formato del contrato", "error" in error.cuerpo, f"HTTP {error.estado}"
    )

    h = salud.cabeceras
    res.anotar("Cabecera X-Content-Type-Options", h.get("x-content-type-options") == "nosniff")
    res.anotar(
        "Cabecera Content-Security-Policy",
        "default-src 'none'" in h.get("content-security-policy", ""),
    )
    if urlparse(url_base).scheme == "https":
        res.anotar("HSTS (solo en producción)", "max-age" in h.get("strict-transport-security", ""))
    else:
        res.anotar("Conexión HTTPS", False, "la URL no empieza con https://")
    return res


def imprimir(res: Resultado) -> None:
    for nombre, ok, detalle in res.verificaciones:
        print(f"  {'OK   ' if ok else 'FALLA'}  {nombre}{f' — {detalle}' if detalle else ''}")
    print("\nResultado:", "despliegue correcto" if res.correcto else "HAY FALLAS")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prueba de humo del servicio desplegado")
    parser.add_argument("url", help="URL base, por ejemplo https://rutasur-api.onrender.com")
    args = parser.parse_args()
    print(
        f"Verificando {args.url} (la primera respuesta puede tardar ~1 min si el servicio dormía)\n"
    )
    resultado = verificar(obtener_por_red(args.url), args.url)
    imprimir(resultado)
    return 0 if resultado.correcto else 1


if __name__ == "__main__":
    sys.exit(main())
