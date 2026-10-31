"""Pruebas de la frescura del dato (RN-005, P05 Figura 26) y del servicio de flota."""

from datetime import timedelta

import pytest

from app.domain.modelos import Coordenada, Frescura, Ramal, Sentido, UnidadEnServicio
from app.services.servicio_flota import ServicioFlota, clasificar_frescura
from tests.fakes import T0, FlotaEnMemoria


@pytest.mark.parametrize(
    ("antiguedad_s", "esperada"),
    [
        (0, Frescura.VIGENTE),
        (30, Frescura.VIGENTE),
        (31, Frescura.DEMORADA),
        (90, Frescura.DEMORADA),
        (91, Frescura.NO_CONFIABLE),
        (3600, Frescura.NO_CONFIABLE),
    ],
)
def test_clasificacion_de_frescura(antiguedad_s, esperada):
    assert clasificar_frescura(antiguedad_s) == esperada


def unidad(etiqueta: str, ramal: Ramal, hace_s: int) -> UnidadEnServicio:
    return UnidadEnServicio(
        etiqueta,
        ramal,
        Sentido.IDA,
        "Centro (2 de Mayo)",
        Coordenada(-16.45, -71.5),
        315,
        T0 - timedelta(seconds=hace_s),
    )


def test_calcula_antiguedad_y_frescura_de_cada_unidad():
    flota = FlotaEnMemoria(
        unidades=[unidad("07", Ramal.MOLLEBAYA, 12), unidad("12", Ramal.CERRILLO, 95)]
    )
    resultado = ServicioFlota(flota).unidades_en_servicio(T0)
    assert [(u.unidad.etiqueta, u.antiguedad_s, u.frescura) for u in resultado] == [
        ("07", 12, Frescura.VIGENTE),
        ("12", 95, Frescura.NO_CONFIABLE),
    ]


def test_filtra_por_ramal():
    flota = FlotaEnMemoria(
        unidades=[unidad("07", Ramal.MOLLEBAYA, 5), unidad("12", Ramal.CERRILLO, 5)]
    )
    resultado = ServicioFlota(flota).unidades_en_servicio(T0, Ramal.CERRILLO)
    assert [u.unidad.etiqueta for u in resultado] == ["12"]


def test_sin_unidades_en_servicio_devuelve_lista_vacia():
    assert ServicioFlota(FlotaEnMemoria()).unidades_en_servicio(T0) == []
