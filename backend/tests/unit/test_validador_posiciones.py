"""Pruebas del ValidadorPosiciones (RF-019, P05 Figura 25)."""

from datetime import timedelta
from uuid import uuid4

import pytest

from app.domain.modelos import (
    Coordenada,
    MedicionTrazado,
    MotivoDescarte,
    PosicionEntrante,
    ReferenciaPosicion,
)
from app.services.validador_posiciones import ValidadorPosiciones
from tests.fakes import T0

ORIGEN = Coordenada(-16.4500, -71.5000)
METRO_EN_GRADOS_LAT = 1 / 111_195  # aproximación suficiente para las pruebas

validador = ValidadorPosiciones()


def posicion(
    metros_al_norte: float = 0, segundos: float = 0, precision_m: float = 8
) -> PosicionEntrante:
    return PosicionEntrante(
        id=uuid4(),
        ubicacion=Coordenada(ORIGEN.lat + metros_al_norte * METRO_EN_GRADOS_LAT, ORIGEN.lon),
        velocidad_kmh=30,
        rumbo=0,
        precision_m=precision_m,
        capturada_en=T0 + timedelta(seconds=segundos),
    )


def medicion(al_trazado_m: float = 10) -> MedicionTrazado:
    return MedicionTrazado(distancia_al_trazado_m=al_trazado_m, distancia_recorrida_m=0)


ANTERIOR = ReferenciaPosicion(ORIGEN, T0)


def test_primera_posicion_correcta_es_valida():
    r = validador.validar(posicion(), medicion(), anterior=None)
    assert r.valida
    assert r.motivo is None


@pytest.mark.parametrize(
    ("precision", "valida"), [(8, True), (50, True), (50.1, False), (85, False)]
)
def test_descarta_precision_peor_que_50_m(precision, valida):
    r = validador.validar(posicion(precision_m=precision), medicion(), None)
    assert r.valida is valida
    if not valida:
        assert r.motivo == MotivoDescarte.PRECISION_INSUFICIENTE


@pytest.mark.parametrize(
    ("al_trazado", "valida"), [(0, True), (150, True), (150.1, False), (600, False)]
)
def test_descarta_posiciones_a_mas_de_150_m_del_trazado(al_trazado, valida):
    r = validador.validar(posicion(), medicion(al_trazado), None)
    assert r.valida is valida
    if not valida:
        assert r.motivo == MotivoDescarte.FUERA_DE_CORREDOR


@pytest.mark.parametrize("segundos", [0, -5])
def test_misma_hora_o_anterior_a_la_ultima_valida_es_duplicada(segundos):
    r = validador.validar(posicion(metros_al_norte=20, segundos=segundos), medicion(), ANTERIOR)
    assert not r.valida
    assert r.motivo == MotivoDescarte.DUPLICADA


def test_velocidad_implicita_de_un_salto():
    # 100 m en 5 s = 72 km/h
    v = validador.velocidad_implicita_kmh(ANTERIOR, posicion(metros_al_norte=100, segundos=5))
    assert v == pytest.approx(72, abs=0.5)


@pytest.mark.parametrize(
    ("metros", "valida"),
    [
        (100, True),  # 72 km/h: posible
        (124, True),  # ≈ 89 km/h: todavía posible
        (130, False),  # ≈ 94 km/h: imposible para un bus urbano
        (500, False),  # 360 km/h: salto del GPS
    ],
)
def test_descarta_velocidad_implicita_mayor_a_90_kmh(metros, valida):
    r = validador.validar(posicion(metros_al_norte=metros, segundos=5), medicion(), ANTERIOR)
    assert r.valida is valida
    if not valida:
        assert r.motivo == MotivoDescarte.VELOCIDAD_IMPOSIBLE


def test_la_regla_mas_barata_se_evalua_primero():
    # Imprecisa Y fuera del corredor: el motivo registrado es el primero que falla
    r = validador.validar(posicion(precision_m=90), medicion(al_trazado_m=900), ANTERIOR)
    assert r.motivo == MotivoDescarte.PRECISION_INSUFICIENTE
