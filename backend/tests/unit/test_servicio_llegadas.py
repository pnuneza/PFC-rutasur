"""Pruebas del servicio de llegadas (CU-01) con repositorios en memoria."""

from datetime import timedelta

import pytest

from app.domain.excepciones import RecursoNoEncontrado
from app.domain.modelos import CandidatoLlegada, EstimacionLlegada, Ramal, Sentido
from app.services.estimador_eta import EstimadorDirecto
from app.services.servicio_llegadas import ServicioLlegadas
from tests.fakes import T0, FlotaEnMemoria, RutasEnMemoria


def candidato(etiqueta: str, restante_m: float, velocidad: float = 36.0) -> CandidatoLlegada:
    return CandidatoLlegada(
        etiqueta=etiqueta,
        ramal=Ramal.CERRILLO,
        sentido=Sentido.IDA,
        destino="Centro (2 de Mayo)",
        distancia_recorrida_m=0,
        distancia_paradero_m=restante_m,
        ultima_posicion_en=T0 - timedelta(seconds=5),
        velocidades_recientes_kmh=[velocidad],
    )


def servicio(candidatos: list[CandidatoLlegada], estimador=None) -> ServicioLlegadas:
    return ServicioLlegadas(
        rutas=RutasEnMemoria({"stp_004"}),
        flota=FlotaEnMemoria(candidatos=candidatos),
        estimador=estimador or EstimadorDirecto(),
    )


def test_paradero_inexistente_o_inactivo_es_404():
    with pytest.raises(RecursoNoEncontrado):
        servicio([]).proximas_llegadas("stp_999", T0)


def test_sin_unidades_devuelve_lista_vacia_y_no_error():
    assert servicio([]).proximas_llegadas("stp_004", T0) == []


def test_ordena_las_llegadas_de_menor_a_mayor_eta():
    llegadas = servicio(
        [candidato("12", 3000), candidato("07", 600), candidato("03", 1500)]
    ).proximas_llegadas("stp_004", T0)
    assert [e.etiqueta for e in llegadas] == ["07", "03", "12"]


def test_excluye_llegadas_de_mas_de_60_minutos():
    # A 36 km/h: 36 000 m = 3600 s (se muestra); 36 010 m > 3600 s (RN-007, no se muestra)
    llegadas = servicio([candidato("07", 36_000), candidato("12", 36_010)]).proximas_llegadas(
        "stp_004", T0
    )
    assert [e.etiqueta for e in llegadas] == ["07"]


def test_el_estimador_es_intercambiable_patron_estrategia():
    """El servicio funciona con cualquier objeto que cumpla la interfaz EstimadorETA."""

    class EstimadorFijo:
        def estimar(self, c: CandidatoLlegada, ahora) -> EstimacionLlegada:
            return EstimacionLlegada(c.etiqueta, c.ramal, c.destino, 42, 0, 0, True)

    llegadas = servicio([candidato("07", 9999)], EstimadorFijo()).proximas_llegadas("stp_004", T0)
    assert llegadas[0].eta_s == 42
