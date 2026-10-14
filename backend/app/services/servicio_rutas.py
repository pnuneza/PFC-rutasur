"""Servicio de rutas: línea, variantes, trazados y paraderos (RF-001, RF-005)."""

from app.domain.excepciones import ErrorDeNegocio, RecursoNoEncontrado
from app.domain.modelos import LineaRuta, ParaderoEncontrado
from app.repositories.interfaces import RepositorioRutas

CODIGO_LINEA = "LB"
LONGITUD_MINIMA_BUSQUEDA = 2
LONGITUD_MAXIMA_BUSQUEDA = 40
MAXIMO_RESULTADOS = 20


class ServicioRutas:
    def __init__(self, repositorio: RepositorioRutas) -> None:
        self._repo = repositorio

    def obtener_linea(self) -> LineaRuta:
        """Línea LB con sus variantes activas, trazados y paraderos ordenados."""
        linea = self._repo.obtener_linea(CODIGO_LINEA)
        if linea is None:
            raise RecursoNoEncontrado("La línea LB no está configurada")
        return linea

    def buscar_paraderos(self, texto: str) -> list[ParaderoEncontrado]:
        """Paraderos cuyo nombre contiene el texto, sin distinguir mayúsculas ni tildes."""
        limpio = " ".join(texto.split())
        if not LONGITUD_MINIMA_BUSQUEDA <= len(limpio) <= LONGITUD_MAXIMA_BUSQUEDA:
            raise ErrorDeNegocio(
                f"El texto de búsqueda debe tener entre {LONGITUD_MINIMA_BUSQUEDA} "
                f"y {LONGITUD_MAXIMA_BUSQUEDA} caracteres"
            )
        return self._repo.buscar_paraderos(limpio, MAXIMO_RESULTADOS)
