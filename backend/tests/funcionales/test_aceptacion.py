"""Escenarios de aceptación de las historias del pasajero (Dado / Cuando / Entonces)."""

import pytest

pytestmark = [pytest.mark.aceptacion, pytest.mark.integracion]


def test_pasajero_busca_su_paradero_y_ve_que_bus_llega_primero(cliente):
    # Dado un pasajero en la Plaza de Characato
    # Cuando busca "plaza" y abre las llegadas del primer resultado
    paradero = cliente.get("/api/v1/stops", params={"q": "plaza"}).json()["data"][0]
    llegadas = cliente.get(f"/api/v1/stops/{paradero['code']}/arrivals").json()["data"]
    # Entonces ve las unidades ordenadas, la primera con el menor tiempo estimado
    if llegadas:
        assert llegadas[0]["eta_seconds"] == min(e["eta_seconds"] for e in llegadas)


def test_pasajero_de_cerrillo_solo_ve_unidades_de_su_ramal(cliente):
    # Dado un pasajero que va a Cerrillo
    # Cuando filtra el mapa por su ramal
    unidades = cliente.get("/api/v1/vehicles", params={"branch": "CERRILLO"}).json()["data"]
    # Entonces no aparece ninguna unidad de Mollebaya
    assert all(u["branch"] == "CERRILLO" for u in unidades)


def test_pasajero_escribe_mal_el_codigo_y_recibe_un_mensaje_claro(cliente):
    # Dado un enlace con un código de paradero equivocado
    # Cuando la app consulta sus llegadas
    r = cliente.get("/api/v1/stops/paradero4/arrivals")
    # Entonces recibe un error 400 con un mensaje legible, no una falla del servidor
    assert r.status_code == 400
    assert r.json()["error"]["message"]
