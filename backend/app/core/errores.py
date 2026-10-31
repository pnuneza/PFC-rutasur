"""Respuesta de error única del servicio (P06, Tabla 55).

Todo error devuelve la misma forma, con un código estable que la aplicación
interpreta sin depender del texto:

    { "error": { "code": "NOT_FOUND", "message": "..." } }

Los errores internos nunca exponen detalles al cliente (OWASP A05); se
registran en el log del servidor.
"""

import logging

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.domain.excepciones import (
    AccesoDenegado,
    CredencialesInvalidas,
    CuentaBloqueada,
    ErrorDeNegocio,
    LimiteExcedido,
    RecursoNoEncontrado,
    SesionNoActiva,
    TokenInvalido,
    UnidadInactiva,
)

registro = logging.getLogger("rutasur")

# Excepción del negocio → (estado HTTP, código estable de la Tabla 55).
# Agregar un error nuevo es agregar una fila, no un manejador más.
ERRORES_DE_NEGOCIO: dict[type[ErrorDeNegocio], tuple[int, str]] = {
    RecursoNoEncontrado: (status.HTTP_404_NOT_FOUND, "NOT_FOUND"),
    SesionNoActiva: (status.HTTP_409_CONFLICT, "SESSION_NOT_ACTIVE"),
    UnidadInactiva: (status.HTTP_409_CONFLICT, "UNIT_INACTIVE"),
    AccesoDenegado: (status.HTTP_403_FORBIDDEN, "FORBIDDEN"),
    CredencialesInvalidas: (status.HTTP_401_UNAUTHORIZED, "INVALID_CREDENTIALS"),
    TokenInvalido: (status.HTTP_401_UNAUTHORIZED, "TOKEN_MISSING_OR_EXPIRED"),
    CuentaBloqueada: (status.HTTP_403_FORBIDDEN, "ACCOUNT_LOCKED"),
    LimiteExcedido: (status.HTTP_429_TOO_MANY_REQUESTS, "RATE_LIMITED"),
    ErrorDeNegocio: (status.HTTP_400_BAD_REQUEST, "VALIDATION_ERROR"),
}


def respuesta_error(
    estado: int, codigo: str, mensaje: str, reintentar_en_s: int | None = None
) -> JSONResponse:
    contenido: dict = {"error": {"code": codigo, "message": mensaje}}
    cabeceras = {}
    if reintentar_en_s is not None:
        # Cuenta bloqueada o límite superado: la app sabe cuánto esperar (P06 Tabla 52)
        contenido["meta"] = {"retry_after_s": reintentar_en_s}
        cabeceras["Retry-After"] = str(reintentar_en_s)
    if estado == status.HTTP_401_UNAUTHORIZED:
        cabeceras["WWW-Authenticate"] = "Bearer"
    return JSONResponse(status_code=estado, content=contenido, headers=cabeceras)


def _mensaje_de_validacion(exc: RequestValidationError) -> str:
    primero = exc.errors()[0] if exc.errors() else {}
    ubicacion = primero.get("loc", [])
    campo = ".".join(str(p) for p in ubicacion if p not in ("body", "query", "path"))
    return f"Dato inválido en '{campo}': {primero.get('msg', 'formato incorrecto')}"


async def _error_de_validacion(_: Request, exc: RequestValidationError) -> JSONResponse:
    # El contrato fija 400 para datos mal formados (FastAPI usa 422 por defecto)
    return respuesta_error(
        status.HTTP_400_BAD_REQUEST, "VALIDATION_ERROR", _mensaje_de_validacion(exc)
    )


async def _error_de_negocio(_: Request, exc: Exception) -> JSONResponse:
    # Se busca la clase más específica de la tabla (por ejemplo, SesionNoActiva antes
    # que su clase base ErrorDeNegocio)
    for clase in type(exc).__mro__:
        if clase in ERRORES_DE_NEGOCIO:
            estado, codigo = ERRORES_DE_NEGOCIO[clase]
            return respuesta_error(estado, codigo, str(exc), getattr(exc, "reintentar_en_s", None))
    return await _error_inesperado(_, exc)


async def _error_http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    codigo = "NOT_FOUND" if exc.status_code == status.HTTP_404_NOT_FOUND else "HTTP_ERROR"
    return respuesta_error(exc.status_code, codigo, str(exc.detail))


async def _error_inesperado(request: Request, exc: Exception) -> JSONResponse:
    registro.error("Error inesperado en %s %s", request.method, request.url.path, exc_info=exc)
    return respuesta_error(
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        "INTERNAL_ERROR",
        "Ocurrió un error inesperado. Intente nuevamente.",
    )


def registrar_manejadores(app: FastAPI) -> None:
    """Conecta las excepciones con la respuesta de error estándar."""
    app.add_exception_handler(RequestValidationError, _error_de_validacion)
    app.add_exception_handler(ErrorDeNegocio, _error_de_negocio)
    app.add_exception_handler(StarletteHTTPException, _error_http)
    app.add_exception_handler(Exception, _error_inesperado)
