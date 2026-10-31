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
    monkeypatch.setattr(
        main,
        "obtener_configuracion",
        lambda: Configuracion(entorno="produccion", jwt_secreto="p" * 40),
    )
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


# --- A01 / A07: control de acceso a la emisión (P05 Tabla 35) ---------------------
RUTAS_CONDUCTOR = [
    ("/api/v1/sessions", {"branch": "MOLLEBAYA", "direction": "IDA"}),
    ("/api/v1/sessions/00000000-0000-0000-0000-000000000000/positions", {"positions": []}),
    ("/api/v1/sessions/00000000-0000-0000-0000-000000000000/close", None),
]


@pytest.mark.parametrize(("ruta", "cuerpo"), RUTAS_CONDUCTOR)
def test_sin_token_la_emision_es_401(cliente, ruta, cuerpo):
    r = cliente.post(ruta, json=cuerpo)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "TOKEN_MISSING_OR_EXPIRED"


@pytest.mark.parametrize(
    "token",
    [
        "no-es-un-token",
        # alg «none», sin firma
        "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJpc3MiOiJydXRhc3VyLWFwaSIsInJvbCI6IkNPTkRVQ1RPUiJ9.",
    ],
)
def test_token_falso_es_401(cliente, token):
    r = cliente.post(
        "/api/v1/sessions",
        json={"branch": "MOLLEBAYA", "direction": "IDA"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 401


@pytest.mark.parametrize("usuario", ["admin.demo", "moderador.demo"])
def test_el_panel_no_puede_emitir_posiciones(cliente, usuario):
    token = cliente.post(
        "/api/v1/auth/login", json={"username": usuario, "password": "rutasur-demo"}
    ).json()["data"]["access_token"]
    r = cliente.post(
        "/api/v1/sessions",
        json={"branch": "MOLLEBAYA", "direction": "IDA"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "FORBIDDEN"


def test_la_contrasena_no_viaja_en_la_respuesta_ni_en_el_token(cliente):
    r = cliente.post(
        "/api/v1/auth/login", json={"username": "unidad07", "password": "rutasur-demo"}
    )
    assert "rutasur-demo" not in r.text
    import base64

    cuerpo = r.json()["data"]["access_token"].split(".")[1]
    assert b"rutasur-demo" not in base64.urlsafe_b64decode(cuerpo + "==")


def test_produccion_no_arranca_con_la_clave_de_desarrollo():
    with pytest.raises(ValueError, match="JWT_SECRETO"):
        Configuracion(entorno="produccion")
