"""Punto de entrada del servicio RutaSur.

Ejecutar en desarrollo:
    uvicorn app.main:app --reload
Documentación interactiva (contrato OpenAPI 3): http://localhost:8000/docs
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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

    registrar_manejadores(app)
    app.include_router(publica.router)
    return app


app = crear_app()
