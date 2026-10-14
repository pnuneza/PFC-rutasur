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
