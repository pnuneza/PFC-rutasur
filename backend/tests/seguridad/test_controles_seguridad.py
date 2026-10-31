"""Controles de seguridad de la API pública (OWASP Top 10, Práctica 08: D-08 y D-09)."""

import pytest
from fastapi.testclient import TestClient

from app import main
from app.core.config import Configuracion

pytestmark = [pytest.mark.seguridad, pytest.mark.integracion]

RUTAS = ["/api/v1/health", "/api/v1/routes/lb", "/api/v1/vehicles", "/api/v1/stops?q=plaza"]


# --- A03 Inyección -----------------------------------------------------------
@pytest.mark.parametrize(
    "texto",
    ["' OR '1'='1", "plaza'; DROP TABLE paradero; --", '" OR 1=1 --', "plaza) UNION SELECT 1--"],
)
def test_inyeccion_sql_en_la_busqueda_no_devuelve_datos_ajenos(cliente, texto):
    r = cliente.get("/api/v1/stops", params={"q": texto})
    assert r.status_code == 200
    assert r.json()["data"] == []


@pytest.mark.parametrize("texto", ["pla\x00za", "plaza\n", "\x1b[31mplaza", "pla\x7fza"])
def test_caracteres_de_control_en_la_busqueda_son_400_y_no_500(cliente, texto):
    """D-08: un byte nulo llegaba a PostgreSQL y provocaba un error 500."""
    r = cliente.get("/api/v1/stops", params={"q": texto})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_inyeccion_en_el_codigo_de_paradero_es_rechazada(cliente):
    r = cliente.get("/api/v1/stops/stp_001' OR '1'='1/arrivals")
    assert r.status_code in {400, 404}
    assert "error" in r.json()


# --- A05 Configuración: cabeceras de seguridad (D-09) --------------------------
@pytest.mark.parametrize("ruta", RUTAS)
def test_respuestas_de_la_api_llevan_cabeceras_de_seguridad(cliente, ruta):
    h = cliente.get(ruta).headers
    assert h["x-content-type-options"] == "nosniff"
    assert h["x-frame-options"] == "DENY"
    assert h["referrer-policy"] == "no-referrer"
    assert h["content-security-policy"] == "default-src 'none'; frame-ancestors 'none'"


def test_los_errores_tambien_llevan_cabeceras_de_seguridad(cliente):
    h = cliente.get("/api/v1/stops/stp_999/arrivals").headers
    assert h["x-content-type-options"] == "nosniff"


def test_la_documentacion_no_recibe_la_politica_estricta(cliente):
    """/docs carga scripts y estilos: con default-src 'none' quedaría en blanco."""
    h = cliente.get("/docs").headers
    assert "content-security-policy" not in h
    assert h["x-frame-options"] == "DENY"


def test_sin_hsts_fuera_de_produccion(cliente):
    assert "strict-transport-security" not in cliente.get("/api/v1/health").headers


def test_con_hsts_en_produccion(monkeypatch):
    monkeypatch.setattr(main, "obtener_configuracion", lambda: Configuracion(entorno="produccion"))
    h = TestClient(main.crear_app()).get("/docs").headers
    assert h["strict-transport-security"].startswith("max-age=31536000")


def test_cors_cerrado_si_no_hay_origenes_configurados(cliente):
    h = cliente.get("/api/v1/health", headers={"Origin": "https://sitio-malicioso.example"}).headers
    assert "access-control-allow-origin" not in h


# --- A04 / A09: los errores no revelan detalles internos -------------------------
def test_metodo_no_permitido_usa_el_formato_de_error(cliente):
    r = cliente.delete("/api/v1/vehicles")
    assert r.status_code == 405
    assert set(r.json()) == {"error"}


def test_error_de_validacion_no_expone_la_traza(cliente):
    texto = cliente.get("/api/v1/stops", params={"q": "a"}).text
    assert "Traceback" not in texto and "pydantic" not in texto.lower()
