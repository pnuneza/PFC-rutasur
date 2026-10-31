"""Punto de entrada del servicio RutaSur.

Ejecutar en desarrollo:
    uvicorn app.main:app --reload
Documentación interactiva (contrato OpenAPI 3): http://localhost:8000/docs
"""

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import RequestResponseEndpoint

from app import __version__
from app.api.v1 import emision, publica
from app.core.config import obtener_configuracion
from app.core.errores import registrar_manejadores
from app.db.conexion import obtener_motor
from app.db.depuracion import depurar_periodicamente

DESCRIPCION = """
API de **RutaSur v1.0**: seguimiento en tiempo real de los buses de la línea LB
(Cono Sur de Arequipa).

Toda respuesta exitosa tiene la forma `{ "data": ..., "meta": ... }` y todo error
`{ "error": { "code": ..., "message": ... } }`. Fechas en ISO 8601 (UTC),
duraciones en segundos y distancias en metros.
"""


# Cabeceras de seguridad (OWASP A05, Práctica 08, D-09). La API solo devuelve JSON,
# así que la política de contenido más estricta posible no rompe nada; la página
# /docs sí carga scripts y estilos, por eso se exceptúa.
CABECERAS_SEGURIDAD = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-site",
}
POLITICA_CONTENIDO = "default-src 'none'; frame-ancestors 'none'"
RUTAS_DOCUMENTACION = ("/docs", "/openapi.json")
HSTS = "max-age=31536000; includeSubDomains"


def _configurar_registro() -> None:
    """Los mensajes del servicio (logger «rutasur») salen en la consola, como los de uvicorn.

    En Render es lo que se ve en la pestaña Logs.
    """
    registro = logging.getLogger("rutasur")
    if not registro.handlers:
        manejador = logging.StreamHandler()
        manejador.setFormatter(logging.Formatter("%(levelname)s:     %(name)s — %(message)s"))
        registro.addHandler(manejador)
        registro.setLevel(logging.INFO)


@contextlib.asynccontextmanager
async def ciclo_de_vida(app: FastAPI) -> AsyncIterator[None]:
    """Arranque y cierre del servicio: tareas en segundo plano (RN-012)."""
    _configurar_registro()
    config = obtener_configuracion()
    tarea = None
    if config.depurar_automaticamente:
        tarea = asyncio.create_task(depurar_periodicamente(obtener_motor(), config.retencion_dias))
    yield
    if tarea is not None:
        tarea.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await tarea


def crear_app() -> FastAPI:
    config = obtener_configuracion()
    app = FastAPI(
        lifespan=ciclo_de_vida,
        title="RutaSur API",
        version=__version__,
        description=DESCRIPCION,
        docs_url="/docs",
        redoc_url=None,
    )

    if config.cors_origenes:
        # Solo el dominio del panel puede llamar a la API desde un navegador (OWASP A05)
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.cors_origenes,
            allow_methods=["GET", "POST", "PUT", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )

    produccion = config.es_produccion

    @app.middleware("http")
    async def agregar_cabeceras_seguridad(
        request: Request, siguiente: RequestResponseEndpoint
    ) -> Response:
        respuesta = await siguiente(request)
        for nombre, valor in CABECERAS_SEGURIDAD.items():
            respuesta.headers.setdefault(nombre, valor)
        if not request.url.path.startswith(RUTAS_DOCUMENTACION):
            respuesta.headers.setdefault("Content-Security-Policy", POLITICA_CONTENIDO)
        if produccion:
            # Solo en producción: en local no hay HTTPS y el navegador recordaría la regla
            respuesta.headers.setdefault("Strict-Transport-Security", HSTS)
        return respuesta

    registrar_manejadores(app)
    app.include_router(publica.router)
    app.include_router(emision.router)
    return app


app = crear_app()
