"""Punto de entrada del servicio RutaSur.

Ejecutar en desarrollo:
    uvicorn app.main:app --reload
Documentación interactiva (contrato OpenAPI 3): http://localhost:8000/docs
"""

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import RequestResponseEndpoint

from app import __version__
from app.api.v1 import publica
from app.core.config import obtener_configuracion
from app.core.errores import registrar_manejadores

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


def crear_app() -> FastAPI:
    config = obtener_configuracion()
    app = FastAPI(
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

    produccion = config.entorno == "produccion"

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
    return app


app = crear_app()
