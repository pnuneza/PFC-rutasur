"""Servicio de flota: unidades en servicio y frescura del dato (RF-002, RF-003, RF-008)."""

from dataclasses import dataclass
from datetime import datetime

from app.domain.modelos import Frescura, Ramal, UnidadEnServicio
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.repositories.interfaces import RepositorioFlota


@dataclass(frozen=True, slots=True)
class UnidadConFrescura:
    unidad: UnidadEnServicio
    antiguedad_s: int
    frescura: Frescura


def clasificar_frescura(antiguedad_s: int, umbrales: Umbrales = UMBRALES_POR_DEFECTO) -> Frescura:
    """Regla RN-005: VIGENTE hasta 30 s, DEMORADA hasta 90 s y NO_CONFIABLE después."""
    if antiguedad_s <= umbrales.frescura_vigente_s:
        return Frescura.VIGENTE
    if antiguedad_s <= umbrales.frescura_demorada_s:
        return Frescura.DEMORADA
    return Frescura.NO_CONFIABLE


class ServicioFlota:
    def __init__(
        self, repositorio: RepositorioFlota, umbrales: Umbrales = UMBRALES_POR_DEFECTO
    ) -> None:
        self._repo = repositorio
        self._u = umbrales

    def unidades_en_servicio(
        self, ahora: datetime, ramal: Ramal | None = None
    ) -> list[UnidadConFrescura]:
        """Unidades con sesión abierta y su frescura. Sin unidades, lista vacía (RNF-04)."""
        resultado = []
        for unidad in self._repo.listar_unidades_en_servicio(ramal):
            antiguedad = max(int((ahora - unidad.ultima_posicion_en).total_seconds()), 0)
            resultado.append(
                UnidadConFrescura(unidad, antiguedad, clasificar_frescura(antiguedad, self._u))
            )
        return resultado
