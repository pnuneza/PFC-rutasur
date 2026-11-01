"""Pruebas de la API pública contra PostgreSQL + PostGIS con los datos demo."""

import unicodedata

import pytest

from tests.conftest import paraderos_de

pytestmark = pytest.mark.integracion


def test_health_informa_servicio_y_base_de_datos(cliente):
    r = cliente.get("/api/v1/health")
    assert r.status_code == 200
    assert r.json()["data"]["status"] == "ok"
    assert r.json()["data"]["database"] == "ok"


def test_respuesta_exitosa_tiene_data_y_meta(cliente):
    cuerpo = cliente.get("/api/v1/vehicles").json()
    assert set(cuerpo) == {"data", "meta"}
    assert cuerpo["meta"]["timestamp"].endswith("Z")  # hora universal, ISO 8601
    assert cuerpo["meta"]["count"] == len(cuerpo["data"])


# --- obtenerLinea --------------------------------------------------------
def test_linea_lb_tiene_cuatro_variantes_con_trazado_y_paraderos(cliente):
    linea = cliente.get("/api/v1/routes/lb").json()["data"]
    assert linea["code"] == "LB"
    assert {(v["branch"], v["direction"]) for v in linea["variants"]} == {
        ("MOLLEBAYA", "IDA"),
        ("MOLLEBAYA", "VUELTA"),
        ("CERRILLO", "IDA"),
        ("CERRILLO", "VUELTA"),
    }
    for v in linea["variants"]:
        assert len(v["shape"]) >= 2
        distancias = [p["distance_from_start_m"] for p in v["stops"]]
        assert distancias == sorted(distancias), "los paraderos deben ir en orden de recorrido"


def test_paradero_del_tramo_comun_esta_en_ambos_ramales(linea):
    ramales_de = {}
    for v in linea["variants"]:
        for p in v["stops"]:
            ramales_de.setdefault(p["code"], set()).add(v["branch"])
    for v in linea["variants"]:
        for p in v["stops"]:
            assert p["shared_trunk"] == (ramales_de[p["code"]] == {"MOLLEBAYA", "CERRILLO"}), p[
                "name"
            ]


def test_terminal_de_mollebaya_es_el_mismo_paradero_en_ida_y_vuelta(linea):
    """La unidad termina la subida y empieza la bajada en el mismo lugar (Santa Ana)."""
    ida = paraderos_de(linea, "MOLLEBAYA", "IDA")
    vuelta = paraderos_de(linea, "MOLLEBAYA", "VUELTA")
    assert ida[0]["code"] == vuelta[-1]["code"]


# --- buscarParaderos -----------------------------------------------------
def _sin_tildes(texto):
    return unicodedata.normalize("NFD", texto).encode("ascii", "ignore").decode()


def test_busqueda_sin_distinguir_mayusculas_ni_tildes(cliente, linea):
    # Un paradero real cuyo nombre lleva tilde; se busca sin tilde y en mayúsculas
    con_tilde = next(
        p for v in linea["variants"] for p in v["stops"] if _sin_tildes(p["name"]) != p["name"]
    )
    palabra = next(w for w in con_tilde["name"].split() if _sin_tildes(w) != w and len(w) >= 3)
    for texto in (palabra, palabra.upper(), _sin_tildes(palabra), _sin_tildes(palabra).upper()):
        codigos = [
            p["code"] for p in cliente.get("/api/v1/stops", params={"q": texto}).json()["data"]
        ]
        assert con_tilde["code"] in codigos, texto


def test_busqueda_indica_los_ramales_de_cada_paradero(cliente, linea):
    comun = next(p for v in linea["variants"] for p in v["stops"] if p["shared_trunk"])
    resultado = cliente.get("/api/v1/stops", params={"q": comun["name"][:40]}).json()["data"]
    encontrado = next(p for p in resultado if p["code"] == comun["code"])
    assert sorted(encontrado["branches"]) == ["CERRILLO", "MOLLEBAYA"]


@pytest.mark.parametrize("texto", ["%%", "__", "%_"])
def test_comodines_escritos_por_el_usuario_no_devuelven_todo(cliente, texto):
    assert cliente.get("/api/v1/stops", params={"q": texto}).json()["data"] == []


@pytest.mark.parametrize("texto", ["a", "x" * 41])
def test_busqueda_con_texto_de_longitud_invalida_es_400(cliente, texto):
    r = cliente.get("/api/v1/stops", params={"q": texto})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


# --- listarUnidadesActivas ----------------------------------------------
def test_unidades_activas_con_posicion_destino_y_frescura(cliente):
    unidades = cliente.get("/api/v1/vehicles").json()["data"]
    u07 = next(u for u in unidades if u["vehicle_label"] == "07")
    assert u07["branch"] == "MOLLEBAYA"
    assert u07["destination"] == "Centro (2 de Mayo)"
    assert u07["freshness"] in {"VIGENTE", "DEMORADA", "NO_CONFIABLE"}
    assert -17 < u07["lat"] < -16 and -72 < u07["lon"] < -71


def test_filtro_por_ramal(cliente):
    unidades = cliente.get("/api/v1/vehicles", params={"branch": "CERRILLO"}).json()["data"]
    assert all(u["branch"] == "CERRILLO" for u in unidades)


# --- consultarLlegadas ---------------------------------------------------
def test_llegadas_a_un_paradero_por_delante_de_la_unidad(cliente, paradero_destino_07):
    llegadas = cliente.get(f"/api/v1/stops/{paradero_destino_07}/arrivals").json()["data"]
    u07 = next(e for e in llegadas if e["vehicle_label"] == "07")
    assert u07["destination"] == "Centro (2 de Mayo)"
    assert u07["distance_m"] > 0
    assert u07["eta_seconds"] > 0


def test_paradero_que_la_unidad_ya_paso_no_la_muestra(cliente, paradero_ya_pasado_por_07):
    # La unidad 07 va de Mollebaya al Centro y ya salió del terminal de Mollebaya
    llegadas = cliente.get(f"/api/v1/stops/{paradero_ya_pasado_por_07}/arrivals").json()["data"]
    assert all(e["vehicle_label"] != "07" for e in llegadas)


def test_paradero_inexistente_es_404(cliente):
    r = cliente.get("/api/v1/stops/stp_999/arrivals")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


@pytest.mark.parametrize("codigo", ["004", "stp_4", "stp_0001", "STP_004"])
def test_codigo_de_paradero_mal_formado_es_400(cliente, codigo):
    r = cliente.get(f"/api/v1/stops/{codigo}/arrivals")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_cada_variante_tiene_paraderos_principales_y_empieza_en_uno(cliente):
    """0.6.1: con el mapa alejado la app solo muestra los principales (plazas, cruces...)."""
    linea = cliente.get("/api/v1/routes/lb").json()["data"]
    for v in linea["variants"]:
        principales = [p for p in v["stops"] if p["main"]]
        assert len(principales) >= 2, (v["branch"], v["direction"])
        assert v["stops"][0]["main"] and v["stops"][-1]["main"]  # los terminales
        assert len(principales) < len(v["stops"]) / 2
