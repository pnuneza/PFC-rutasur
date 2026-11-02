"""Excepciones del negocio.

Los servicios lanzan estas excepciones sin saber nada de HTTP; la capa de
servicios web (core/errores.py) las traduce a los códigos de la Tabla 55 de P06.
"""


class ErrorDeNegocio(Exception):
    """Una regla de negocio rechazó la operación."""


class RecursoNoEncontrado(ErrorDeNegocio):
    """El paradero, la sesión o el recurso pedido no existe o está inactivo (404)."""


class SesionNoActiva(ErrorDeNegocio):
    """Se enviaron posiciones a una sesión cerrada (409 SESSION_NOT_ACTIVE)."""


class UnidadInactiva(ErrorDeNegocio):
    """Se intentó abrir una sesión en una unidad deshabilitada (409 UNIT_INACTIVE)."""


class AccesoDenegado(ErrorDeNegocio):
    """La sesión pertenece a otra unidad (403 FORBIDDEN)."""


class CredencialesInvalidas(ErrorDeNegocio):
    """Usuario o contraseña incorrectos, o cuenta deshabilitada (401 INVALID_CREDENTIALS).

    El mensaje es el mismo en todos los casos para no revelar qué usuarios existen.
    """


class CuentaBloqueada(ErrorDeNegocio):
    """Cinco intentos fallidos: la cuenta espera 15 minutos (403 ACCOUNT_LOCKED)."""

    def __init__(self, mensaje: str, reintentar_en_s: int) -> None:
        super().__init__(mensaje)
        self.reintentar_en_s = reintentar_en_s


class TokenInvalido(ErrorDeNegocio):
    """Falta el token, venció o no es auténtico (401 TOKEN_MISSING_OR_EXPIRED)."""


class LimiteExcedido(ErrorDeNegocio):
    """Se superó el límite de peticiones (429 RATE_LIMITED)."""

    def __init__(self, mensaje: str, reintentar_en_s: int) -> None:
        super().__init__(mensaje)
        self.reintentar_en_s = reintentar_en_s


class Conflicto(ErrorDeNegocio):
    """El dato ya existe o choca con otro: usuario repetido, unidad con cuenta (409 CONFLICT)."""


class FueraDelCorredor(ErrorDeNegocio):
    """El paradero queda a más de 150 m del trazado (RN-003, 422 OUT_OF_CORRIDOR)."""
