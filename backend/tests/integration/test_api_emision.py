"""Ingreso y emisión del conductor por HTTP, contra la base real (CU-02, CU-03).

Cuentas de los datos demo (contraseña rutasur-demo): unidad07, unidad12, admin.demo,
moderador.demo. La unidad 07 ya tiene una sesión abierta; la 12 no.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import text

from app.api.dependencias import limite_envios
from app.domain.modelos import Ramal, Sentido
from app.herramientas.simular_unidad import Recorrido
from app.repositories.sql_rutas import RepositorioRutasSQL

pytestmark = pytest.mark.integracion

CLAVE_DEMO = "rutasur-demo"


def ingresar(cliente, usuario, clave=CLAVE_DEMO):
    return cliente.post("/api/v1/auth/login", json={"username": usuario, "password": clave})


def cabecera(cliente, usuario) -> dict:
    token = ingresar(cliente, usuario).json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def conductor_12(cliente):
    return cabecera(cliente, "unidad12")


@pytest.fixture
def recorrido_cerrillo_ida(sesion) -> Recorrido:
    linea = RepositorioRutasSQL(sesion).obtener_linea("LB")
    variante = next(
        v for v in linea.variantes if (v.ramal, v.sentido) == (Ramal.CERRILLO, Sentido.IDA)
    )
    return Recorrido.desde(variante.trazado)


def lote(recorrido, metros, inicio=None):
    inicio = inicio or datetime.now(UTC)
    posiciones = []
    for i, m in enumerate(metros):
        punto, rumbo = recorrido.punto_a(m)
        posiciones.append(
            {
                "id": str(uuid4()),
                "lat": punto.lat,
                "lon": punto.lon,
                "speed_kmh": 36,
                "heading": rumbo,
                "accuracy_m": 8,
                "captured_at": (inicio + timedelta(seconds=1 + 5 * i)).isoformat(),
            }
        )
    return {"positions": posiciones}


def abrir(cliente, cabeceras, ramal="CERRILLO", sentido="IDA"):
    return cliente.post(
        "/api/v1/sessions", json={"branch": ramal, "direction": sentido}, headers=cabeceras
    )


# --- iniciarSesion ----------------------------------------------------------------
def test_ingreso_de_conductor_entrega_token_rol_y_unidad(cliente):
    r = ingresar(cliente, "unidad07")
    assert r.status_code == 200
    datos = r.json()["data"]
    assert datos["token_type"] == "bearer" and datos["expires_in"] == 43200  # noqa: S105
    assert (datos["role"], datos["vehicle_label"]) == ("CONDUCTOR", "07")


@pytest.mark.parametrize(
    ("usuario", "rol"), [("admin.demo", "ADMINISTRADOR"), ("moderador.demo", "MODERADOR")]
)
def test_ingreso_del_panel_no_tiene_unidad(cliente, usuario, rol):
    datos = ingresar(cliente, usuario).json()["data"]
    assert (datos["role"], datos["vehicle_label"]) == (rol, None)


@pytest.mark.parametrize(
    ("usuario", "clave"), [("unidad07", "clave-incorrecta"), ("noexiste", CLAVE_DEMO)]
)
def test_credenciales_incorrectas_mismo_mensaje_exista_o_no(cliente, usuario, clave):
    r = ingresar(cliente, usuario, clave)
    assert r.status_code == 401
    assert r.json()["error"] == {
        "code": "INVALID_CREDENTIALS",
        "message": "Usuario o contraseña incorrectos",
    }
    assert r.headers["www-authenticate"] == "Bearer"


def test_cinco_fallos_bloquean_la_cuenta_y_queda_guardado(cliente, sesion):
    for _ in range(4):
        assert ingresar(cliente, "unidad12", "clave-incorrecta").status_code == 401
    r = ingresar(cliente, "unidad12", "clave-incorrecta")
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "ACCOUNT_LOCKED"
    assert r.json()["meta"]["retry_after_s"] == 900
    assert r.headers["retry-after"] == "900"
    # Bloqueada: ni la contraseña correcta entra
    assert ingresar(cliente, "unidad12").json()["error"]["code"] == "ACCOUNT_LOCKED"
    # El bloqueo y el evento se guardaron aunque la respuesta fue un error
    assert sesion.execute(
        text("SELECT bloqueada_hasta > now() FROM cuenta_conductor WHERE usuario = 'unidad12'")
    ).scalar()
    assert (
        sesion.execute(
            text(
                "SELECT count(*) FROM registro_evento WHERE tipo = 'SEGURIDAD' "
                "AND detalle->>'motivo' = 'cuenta_bloqueada'"
            )
        ).scalar()
        == 1
    )


@pytest.mark.parametrize(
    "cuerpo",
    [
        {"username": "UNIDAD07", "password": CLAVE_DEMO},
        {"username": "unidad07", "password": "corta"},
        {"username": "unidad07"},
        {"username": "a b", "password": CLAVE_DEMO},
    ],
)
def test_credenciales_mal_formadas_son_400(cliente, cuerpo):
    r = cliente.post("/api/v1/auth/login", json=cuerpo)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"


def test_once_intentos_por_minuto_desde_un_origen_son_429(cliente):
    for _ in range(10):
        ingresar(cliente, "noexiste")
    r = ingresar(cliente, "noexiste")
    assert r.status_code == 429
    assert r.json()["error"]["code"] == "RATE_LIMITED"
    assert int(r.headers["retry-after"]) > 0


# --- abrirSesion / enviarPosiciones / cerrarSesion ------------------------------
def test_recorrido_completo_del_conductor(cliente, conductor_12, recorrido_cerrillo_ida):
    r = abrir(cliente, conductor_12)
    assert r.status_code == 201
    datos = r.json()["data"]
    assert datos["variant"] == "CERRILLO-IDA"
    assert datos["destination"] == "Centro (2 de Mayo)"
    sesion_id = datos["session_id"]

    cuerpo = lote(recorrido_cerrillo_ida, [1000, 1050, 1100])
    acuse = cliente.post(
        f"/api/v1/sessions/{sesion_id}/positions", json=cuerpo, headers=conductor_12
    )
    assert acuse.status_code == 200
    a = acuse.json()["data"]
    assert (a["published"], a["discarded"], a["duplicates"]) == (3, 0, 0)
    assert a["confirmed"] == [p["id"] for p in cuerpo["positions"]]

    # El pasajero ya la ve en el mapa
    unidades = cliente.get("/api/v1/vehicles").json()["data"]
    assert any(u["vehicle_label"] == "12" and u["freshness"] == "VIGENTE" for u in unidades)

    # Reenviar el mismo lote (se perdió la confirmación) no duplica
    otra_vez = cliente.post(
        f"/api/v1/sessions/{sesion_id}/positions", json=cuerpo, headers=conductor_12
    )
    assert otra_vez.json()["data"]["duplicates"] == 3

    cierre = cliente.post(f"/api/v1/sessions/{sesion_id}/close", headers=conductor_12)
    assert cierre.status_code == 200
    assert cierre.json()["data"]["status"] == "CERRADA_POR_CONDUCTOR"

    # Después del cierre: 409 y desaparece del mapa
    tarde = cliente.post(
        f"/api/v1/sessions/{sesion_id}/positions", json=cuerpo, headers=conductor_12
    )
    assert tarde.status_code == 409
    assert tarde.json()["error"]["code"] == "SESSION_NOT_ACTIVE"
    assert all(u["vehicle_label"] != "12" for u in cliente.get("/api/v1/vehicles").json()["data"])


def test_abrir_otra_sesion_cierra_la_anterior_de_la_unidad(cliente):
    """RN-002: la 07 ya tenía una sesión demo abierta."""
    conductor_07 = cabecera(cliente, "unidad07")
    nueva = abrir(cliente, conductor_07, "MOLLEBAYA", "VUELTA").json()["data"]
    unidades = [
        u for u in cliente.get("/api/v1/vehicles").json()["data"] if u["vehicle_label"] == "07"
    ]
    assert len(unidades) <= 1
    assert all(u["destination"] == nueva["destination"] for u in unidades)


def test_un_conductor_no_puede_usar_la_sesion_de_otra_unidad(
    cliente, conductor_12, recorrido_cerrillo_ida
):
    sesion_id = abrir(cliente, conductor_12).json()["data"]["session_id"]
    conductor_07 = cabecera(cliente, "unidad07")
    r = cliente.post(
        f"/api/v1/sessions/{sesion_id}/positions",
        json=lote(recorrido_cerrillo_ida, [1000]),
        headers=conductor_07,
    )
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "FORBIDDEN"
    assert (
        cliente.post(f"/api/v1/sessions/{sesion_id}/close", headers=conductor_07).status_code == 403
    )


def test_sesion_inexistente_es_404(cliente, conductor_12):
    r = cliente.post(f"/api/v1/sessions/{uuid4()}/close", headers=conductor_12)
    assert r.status_code == 404


def test_lote_vacio_o_de_mas_de_200_es_400(cliente, conductor_12, recorrido_cerrillo_ida):
    sesion_id = abrir(cliente, conductor_12).json()["data"]["session_id"]
    url = f"/api/v1/sessions/{sesion_id}/positions"
    assert cliente.post(url, json={"positions": []}, headers=conductor_12).status_code == 400
    grande = lote(recorrido_cerrillo_ida, [1000] * 201)
    assert cliente.post(url, json=grande, headers=conductor_12).status_code == 400


def test_mas_de_60_envios_por_minuto_son_429(
    cliente, conductor_12, recorrido_cerrillo_ida, monkeypatch
):
    monkeypatch.setattr(limite_envios, "_maximo", 2)
    sesion_id = abrir(cliente, conductor_12).json()["data"]["session_id"]
    url = f"/api/v1/sessions/{sesion_id}/positions"
    for m in (1000, 1050):
        assert (
            cliente.post(
                url, json=lote(recorrido_cerrillo_ida, [m]), headers=conductor_12
            ).status_code
            == 200
        )
    r = cliente.post(url, json=lote(recorrido_cerrillo_ida, [1100]), headers=conductor_12)
    assert r.status_code == 429
    assert r.json()["meta"]["retry_after_s"] > 0


def test_unidad_deshabilitada_no_puede_seguir_emitiendo(cliente, conductor_12, sesion):
    sesion.execute(text("UPDATE unidad SET activa = false WHERE etiqueta = '12'"))
    r = abrir(cliente, conductor_12)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "TOKEN_MISSING_OR_EXPIRED"
    # Y ya no puede volver a ingresar (mismo mensaje que una clave incorrecta)
    assert ingresar(cliente, "unidad12").json()["error"]["code"] == "INVALID_CREDENTIALS"
