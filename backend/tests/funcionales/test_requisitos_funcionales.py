"""Pruebas funcionales de caja negra: cada requisito se prueba solo por la API.

No miran el código ni la base: envían peticiones HTTP como lo haría la app del
pasajero y comparan la respuesta con lo que pide el requisito (P04, Tabla de RF).
"""

from datetime import datetime

import pytest

pytestmark = [pytest.mark.funcional, pytest.mark.integracion]


# --- RF-001: ver la línea, sus variantes y paraderos ---------------------
def test_rf001_cada_variante_tiene_ramal_sentido_y_destino(cliente):
    for v in cliente.get("/api/v1/routes/lb").json()["data"]["variants"]:
        assert v["branch"] in {"MOLLEBAYA", "CERRILLO"}
        assert v["direction"] in {"IDA", "VUELTA"}
        assert v["destination"]


def test_rf001_trazado_en_coordenadas_de_arequipa(cliente):
    for v in cliente.get("/api/v1/routes/lb").json()["data"]["variants"]:
        for punto in v["shape"]:
            lat, lon = punto  # [lat, lon], el orden que usa flutter_map
            assert -17 < lat < -16 and -72 < lon < -71


def test_rf001_cada_paradero_tiene_codigo_nombre_y_posicion(cliente):
    for v in cliente.get("/api/v1/routes/lb").json()["data"]["variants"]:
        assert v["stops"], "toda variante debe tener paraderos"
        for p in v["stops"]:
            assert p["code"].startswith("stp_")
            assert p["name"]
            assert -17 < p["lat"] < -16 and -72 < p["lon"] < -71


def test_rf001_primer_paradero_esta_al_inicio_del_recorrido(cliente):
    for v in cliente.get("/api/v1/routes/lb").json()["data"]["variants"]:
        assert v["stops"][0]["distance_from_start_m"] == pytest.approx(0, abs=200)


# --- RF-002 / RF-003: unidades en el mapa --------------------------------
def test_rf002_lista_de_unidades_con_meta_count(cliente):
    cuerpo = cliente.get("/api/v1/vehicles").json()
    assert cuerpo["meta"]["count"] == len(cuerpo["data"]) > 0


def test_rf002_cada_unidad_trae_lo_que_la_app_muestra(cliente):
    campos = {"vehicle_label", "branch", "destination", "lat", "lon", "freshness"}
    for u in cliente.get("/api/v1/vehicles").json()["data"]:
        assert campos <= set(u)


@pytest.mark.parametrize("ramal", ["MOLLEBAYA", "CERRILLO"])
def test_rf003_filtro_por_ramal_solo_devuelve_ese_ramal(cliente, ramal):
    unidades = cliente.get("/api/v1/vehicles", params={"branch": ramal}).json()["data"]
    assert all(u["branch"] == ramal for u in unidades)


def test_rf003_ramal_desconocido_es_400(cliente):
    r = cliente.get("/api/v1/vehicles", params={"branch": "YURA"})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


# --- RF-005: buscar paraderos ---------------------------------------------
def test_rf005_busqueda_devuelve_como_maximo_20(cliente):
    assert len(cliente.get("/api/v1/stops", params={"q": "av"}).json()["data"]) <= 20


def test_rf005_busqueda_sin_coincidencias_es_lista_vacia_y_no_error(cliente):
    r = cliente.get("/api/v1/stops", params={"q": "zzzzzz"})
    assert r.status_code == 200
    assert r.json()["data"] == []


def test_rf005_texto_con_espacios_alrededor_se_encuentra(cliente):
    codigos = [
        p["code"] for p in cliente.get("/api/v1/stops", params={"q": " plaza "}).json()["data"]
    ]
    assert "stp_004" in codigos


def test_rf005_sin_parametro_q_es_400(cliente):
    assert cliente.get("/api/v1/stops").status_code == 400


@pytest.mark.parametrize("texto", ["ab", "x" * 40])
def test_rf005_limites_de_longitud_aceptados(cliente, texto):
    assert cliente.get("/api/v1/stops", params={"q": texto}).status_code == 200


# --- RF-018: llegadas y tiempo estimado -----------------------------------
def test_rf018_llegadas_ordenadas_por_tiempo(cliente):
    llegadas = cliente.get("/api/v1/stops/stp_001/arrivals").json()["data"]
    tiempos = [e["eta_seconds"] for e in llegadas]
    assert tiempos == sorted(tiempos)


def test_rf018_ninguna_llegada_supera_60_minutos(cliente):
    """RN-007."""
    for e in cliente.get("/api/v1/stops/stp_001/arrivals").json()["data"]:
        assert 0 < e["eta_seconds"] <= 3600


def test_rf018_cada_llegada_indica_si_es_confiable(cliente):
    for e in cliente.get("/api/v1/stops/stp_001/arrivals").json()["data"]:
        assert isinstance(e["reliable"], bool)


# --- RF-008 / RN-005: frescura del dato -------------------------------------
def test_rf008_frescura_es_uno_de_los_tres_estados(cliente):
    for u in cliente.get("/api/v1/vehicles").json()["data"]:
        assert u["freshness"] in {"VIGENTE", "DEMORADA", "NO_CONFIABLE"}


# --- Contrato general -------------------------------------------------------
@pytest.mark.parametrize(
    "ruta",
    ["/api/v1/health", "/api/v1/routes/lb", "/api/v1/vehicles", "/api/v1/stops/stp_001/arrivals"],
)
def test_toda_respuesta_exitosa_tiene_hora_iso_8601_en_utc(cliente, ruta):
    marca = cliente.get(ruta).json()["meta"]["timestamp"]
    assert datetime.fromisoformat(marca).utcoffset().total_seconds() == 0


def test_ruta_inexistente_responde_con_el_formato_de_error(cliente):
    r = cliente.get("/api/v1/no-existe")
    assert r.status_code == 404
    assert set(r.json()) == {"error"}
