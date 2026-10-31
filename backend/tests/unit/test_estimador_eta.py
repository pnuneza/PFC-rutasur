"""Pruebas del EstimadorDirecto (RF-018, P05 §2.7.2)."""

from datetime import timedelta

import pytest

from app.domain.modelos import CandidatoLlegada, Ramal, Sentido
from app.services.estimador_eta import EstimadorDirecto
from tests.fakes import T0


def candidato(
    recorrido_m: float = 0,
    paradero_m: float = 1000,
    velocidades: list[float | None] | None = None,
    antiguedad_s: int = 10,
) -> CandidatoLlegada:
    return CandidatoLlegada(
        etiqueta="07",
        ramal=Ramal.MOLLEBAYA,
        sentido=Sentido.IDA,
        destino="Centro (2 de Mayo)",
        distancia_recorrida_m=recorrido_m,
        distancia_paradero_m=paradero_m,
        ultima_posicion_en=T0 - timedelta(seconds=antiguedad_s),
        velocidades_recientes_kmh=[36.0] if velocidades is None else velocidades,
    )


estimador = EstimadorDirecto()


def test_eta_es_distancia_restante_entre_velocidad():
    # 1000 m a 36 km/h (10 m/s) = 100 s
    e = estimador.estimar(candidato(paradero_m=1000, velocidades=[36.0]), T0)
    assert e.eta_s == 100
    assert e.distancia_m == 1000


def test_la_distancia_restante_descuenta_lo_ya_recorrido():
    e = estimador.estimar(candidato(recorrido_m=4000, paradero_m=5000, velocidades=[36.0]), T0)
    assert e.distancia_m == 1000
    assert e.eta_s == 100


def test_la_velocidad_es_el_promedio_de_las_lecturas_recientes():
    assert estimador.velocidad_estimada_kmh([30.0, 40.0, 50.0, 40.0]) == pytest.approx(40.0)


def test_ignora_lecturas_sin_velocidad():
    assert estimador.velocidad_estimada_kmh([30.0, None, 50.0, None]) == pytest.approx(40.0)


@pytest.mark.parametrize("velocidades", [[0.0, 0.0, 0.0, 0.0], [], [None, None]])
def test_unidad_detenida_usa_la_velocidad_minima_de_5_kmh(velocidades):
    # Sin el mínimo, una unidad detenida en un semáforo daría una división entre cero
    assert estimador.velocidad_estimada_kmh(velocidades) == 5.0
    e = estimador.estimar(candidato(paradero_m=1000, velocidades=velocidades), T0)
    assert e.eta_s == 720  # 1000 m a 5 km/h


@pytest.mark.parametrize(
    ("antiguedad_s", "confiable"), [(0, True), (89, True), (90, True), (91, False), (600, False)]
)
def test_el_dato_deja_de_ser_confiable_despues_de_90_segundos(antiguedad_s, confiable):
    e = estimador.estimar(candidato(antiguedad_s=antiguedad_s), T0)
    assert e.antiguedad_s == antiguedad_s
    assert e.confiable is confiable


def test_nunca_devuelve_distancias_negativas():
    e = estimador.estimar(candidato(recorrido_m=1200, paradero_m=1000), T0)
    assert e.distancia_m == 0
    assert e.eta_s == 0
