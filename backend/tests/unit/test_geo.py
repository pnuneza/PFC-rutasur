"""Pruebas del cálculo de distancias."""

import pytest

from app.domain.geo import distancia_m
from app.domain.modelos import Coordenada


def test_un_milesimo_de_grado_de_latitud_mide_unos_111_m():
    a = Coordenada(-16.4500, -71.5000)
    b = Coordenada(-16.4510, -71.5000)
    assert distancia_m(a, b) == pytest.approx(111.2, abs=0.2)


def test_distancia_entre_un_punto_y_si_mismo_es_cero():
    p = Coordenada(-16.4688, -71.4902)
    assert distancia_m(p, p) == 0


def test_distancia_plaza_characato_a_2_de_mayo_es_del_orden_de_8_km():
    # Referencia gruesa en línea recta (coordenadas demo)
    assert (
        7_000 < distancia_m(Coordenada(-16.4688, -71.4902), Coordenada(-16.4002, -71.5358)) < 10_000
    )
