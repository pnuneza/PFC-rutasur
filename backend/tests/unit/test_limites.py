"""Límite de peticiones por ventana deslizante (429 RATE_LIMITED)."""

import pytest

from app.core.limites import LimitadorVentana
from app.domain.excepciones import LimiteExcedido


class Reloj:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


def test_permite_hasta_el_maximo_y_luego_rechaza_con_la_espera():
    reloj = Reloj()
    limite = LimitadorVentana(3, 60, reloj)
    for _ in range(3):
        limite.registrar("unidad-07")
    reloj.t += 20
    with pytest.raises(LimiteExcedido) as e:
        limite.registrar("unidad-07")
    assert e.value.reintentar_en_s == 40


def test_la_ventana_se_desliza():
    reloj = Reloj()
    limite = LimitadorVentana(2, 60, reloj)
    limite.registrar("x")
    reloj.t += 30
    limite.registrar("x")
    reloj.t += 31  # la primera ya salió de la ventana
    limite.registrar("x")


def test_cada_clave_cuenta_por_separado():
    limite = LimitadorVentana(1, 60, Reloj())
    limite.registrar("unidad-07")
    limite.registrar("unidad-12")
    with pytest.raises(LimiteExcedido):
        limite.registrar("unidad-07")


def test_las_claves_viejas_se_limpian():
    reloj = Reloj()
    limite = LimitadorVentana(5, 60, reloj)
    for i in range(10_001):
        limite.registrar(f"ip-{i}")
    reloj.t += 61
    limite.registrar("nueva")
    assert len(limite._marcas) <= 2
