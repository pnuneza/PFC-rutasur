"""Panel de administración por HTTP, contra la base real (CU-13 a CU-17; RF-014 a RF-017, RF-020).

Cuentas de los datos demo (contraseña rutasur-demo): admin.demo (ADMINISTRADOR),
moderador.demo (MODERADOR), unidad07 y unidad12 (conductores). La unidad 07 tiene una
sesión abierta; la 12 no.
"""

import pytest

pytestmark = pytest.mark.integracion

CLAVE_DEMO = "rutasur-demo"


def ingresar(cliente, usuario, clave=CLAVE_DEMO):
    return cliente.post("/api/v1/auth/login", json={"username": usuario, "password": clave})


def cabecera(cliente, usuario, clave=CLAVE_DEMO) -> dict:
    token = ingresar(cliente, usuario, clave).json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin(cliente):
    return cabecera(cliente, "admin.demo")


@pytest.fixture
def moderador(cliente):
    return cabecera(cliente, "moderador.demo")


def variante(cliente, admin, ramal, sentido) -> dict:
    datos = cliente.get("/api/v1/admin/variants", headers=admin).json()["data"]
    return next(v for v in datos if (v["branch"], v["direction"]) == (ramal, sentido))


# ----------------------------------------------------------------------
# RF-014: permisos por rol
# ----------------------------------------------------------------------
SOLO_ADMINISTRADOR = [
    ("GET", "/api/v1/admin/units"),
    ("GET", "/api/v1/admin/stops"),
    ("GET", "/api/v1/admin/variants"),
    ("GET", "/api/v1/admin/driver-accounts"),
    ("GET", "/api/v1/admin/panel-accounts"),
    ("PUT", "/api/v1/admin/line"),
]


@pytest.mark.parametrize(("metodo", "ruta"), SOLO_ADMINISTRADOR)
def test_el_moderador_no_accede_a_funciones_del_administrador(cliente, moderador, metodo, ruta):
    cuerpo = {"service_start": "05:00", "service_end": "21:00"} if metodo == "PUT" else None
    r = cliente.request(metodo, ruta, headers=moderador, json=cuerpo)
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize("ruta", ["/api/v1/admin/fleet", "/api/v1/admin/events"])
def test_el_moderador_ve_la_flota_y_los_eventos(cliente, moderador, ruta):
    assert cliente.get(ruta, headers=moderador).status_code == 200


def test_un_conductor_no_entra_al_panel(cliente):
    r = cliente.get("/api/v1/admin/fleet", headers=cabecera(cliente, "unidad07"))
    assert r.status_code == 403


def test_sin_token_no_hay_panel(cliente):
    r = cliente.get("/api/v1/admin/fleet")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "TOKEN_MISSING_OR_EXPIRED"


# ----------------------------------------------------------------------
# RF-017: estado de la flota
# ----------------------------------------------------------------------
def test_la_flota_distingue_unidades_con_y_sin_sesion(cliente, moderador):
    datos = cliente.get("/api/v1/admin/fleet", headers=moderador).json()["data"]
    por_unidad = {u["vehicle_label"]: u for u in datos["vehicles"]}
    assert por_unidad["12"]["status"] == "INACTIVA"
    assert por_unidad["12"]["lat"] is None
    assert por_unidad["07"]["status"] in ("TRANSMITIENDO", "SIN_SENAL")
    assert por_unidad["07"]["branch"] is not None
    resumen = datos["summary"]
    assert resumen["transmitting"] + resumen["no_signal"] + resumen["inactive"] == len(
        datos["vehicles"]
    )


# ----------------------------------------------------------------------
# RF-015 y RN-009: horario, variantes y paraderos
# ----------------------------------------------------------------------
def test_cambiar_el_horario_se_ve_en_la_app(cliente, admin):
    r = cliente.put(
        "/api/v1/admin/line",
        headers=admin,
        json={"service_start": "04:30", "service_end": "22:00"},
    )
    assert r.status_code == 200
    linea = cliente.get("/api/v1/routes/lb").json()["data"]
    assert (linea["service_start"], linea["service_end"]) == ("04:30", "22:00")


def test_el_horario_debe_terminar_despues_de_empezar(cliente, admin):
    r = cliente.put(
        "/api/v1/admin/line",
        headers=admin,
        json={"service_start": "21:00", "service_end": "05:00"},
    )
    assert r.status_code == 400
    assert "RN-009" in r.json()["error"]["message"]


def test_el_orden_de_los_paraderos_lo_calcula_el_servidor(cliente, admin):
    v = variante(cliente, admin, "MOLLEBAYA", "IDA")
    codigos = [p["code"] for p in v["stops"]]
    r = cliente.put(
        f"/api/v1/admin/variants/{v['id']}/stops",
        headers=admin,
        json={"codes": list(reversed(codigos))},
    )
    assert r.status_code == 200
    assert [p["code"] for p in r.json()["data"]["stops"]] == codigos


@pytest.mark.parametrize(
    "codigos",
    [["stp_001"], ["stp_001", "stp_001", "stp_002"]],
    ids=["un_solo_paradero", "repetidos"],
)
def test_una_variante_rechaza_listas_invalidas(cliente, admin, codigos):
    v = variante(cliente, admin, "MOLLEBAYA", "IDA")
    r = cliente.put(
        f"/api/v1/admin/variants/{v['id']}/stops", headers=admin, json={"codes": codigos}
    )
    assert r.status_code == 400


def test_un_paradero_lejos_del_trazado_se_rechaza(cliente, admin):
    # Plaza de Armas de Arequipa: a varios kilómetros de la línea LB
    r = cliente.post(
        "/api/v1/admin/stops",
        headers=admin,
        json={"name": "Plaza de Armas", "lat": -16.3988, "lon": -71.5369},
    )
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "OUT_OF_CORRIDOR"


def test_crear_un_paradero_y_agregarlo_a_una_variante(cliente, admin):
    v = variante(cliente, admin, "CERRILLO", "IDA")
    lat, lon = v["shape"][len(v["shape"]) // 3]
    creado = cliente.post(
        "/api/v1/admin/stops",
        headers=admin,
        json={
            "name": "  Paradero   de prueba ",
            "reference": "Frente a la posta",
            "lat": lat,
            "lon": lon,
        },
    )
    assert creado.status_code == 201
    paradero = creado.json()["data"]
    assert paradero["name"] == "Paradero de prueba"
    assert paradero["code"].startswith("stp_") and paradero["variants"] == []

    codigos = [p["code"] for p in v["stops"]] + [paradero["code"]]
    r = cliente.put(
        f"/api/v1/admin/variants/{v['id']}/stops", headers=admin, json={"codes": codigos}
    )
    assert r.status_code == 200
    orden = [p["code"] for p in r.json()["data"]["stops"]]
    assert paradero["code"] in orden[1:-1]  # queda entre los demás, no al final

    linea = cliente.get("/api/v1/routes/lb").json()["data"]
    publica = next(
        x for x in linea["variants"] if (x["branch"], x["direction"]) == ("CERRILLO", "IDA")
    )
    assert paradero["code"] in [p["code"] for p in publica["stops"]]


def test_mover_un_paradero_fuera_del_corredor_no_cambia_nada(cliente, admin):
    v = variante(cliente, admin, "MOLLEBAYA", "IDA")
    p = v["stops"][1]
    r = cliente.put(
        f"/api/v1/admin/stops/{p['code']}",
        headers=admin,
        json={"name": p["name"], "lat": -16.3988, "lon": -71.5369},
    )
    assert r.status_code == 422
    sigue = next(
        x for x in variante(cliente, admin, "MOLLEBAYA", "IDA")["stops"] if x["code"] == p["code"]
    )
    assert (sigue["lat"], sigue["lon"]) == (p["lat"], p["lon"])


def test_marcar_un_paradero_como_principal_se_ve_en_la_app(cliente, admin):
    v = variante(cliente, admin, "MOLLEBAYA", "IDA")
    p = next(x for x in v["stops"][1:-1] if not x["main"])
    datos = {"name": p["name"], "lat": p["lat"], "lon": p["lon"], "main": True}

    r = cliente.put(f"/api/v1/admin/stops/{p['code']}", headers=admin, json=datos)
    assert r.status_code == 200 and r.json()["data"]["main"] is True

    def en_la_app() -> bool:
        linea = cliente.get("/api/v1/routes/lb").json()["data"]
        publica = next(
            x for x in linea["variants"] if (x["branch"], x["direction"]) == ("MOLLEBAYA", "IDA")
        )
        return next(x["main"] for x in publica["stops"] if x["code"] == p["code"])

    assert en_la_app() is True
    marcado = next(
        x for x in variante(cliente, admin, "MOLLEBAYA", "IDA")["stops"] if x["code"] == p["code"]
    )
    assert marcado["main"] is True

    r = cliente.put(
        f"/api/v1/admin/stops/{p['code']}", headers=admin, json={**datos, "main": False}
    )
    assert r.status_code == 200 and en_la_app() is False


def test_desactivar_un_paradero_lo_quita_de_sus_variantes(cliente, admin):
    v = variante(cliente, admin, "MOLLEBAYA", "IDA")
    p = v["stops"][2]
    r = cliente.put(
        f"/api/v1/admin/stops/{p['code']}",
        headers=admin,
        json={"name": p["name"], "lat": p["lat"], "lon": p["lon"], "active": False},
    )
    assert r.status_code == 200
    assert r.json()["data"]["variants"] == []
    assert p["code"] not in [
        x["code"] for x in variante(cliente, admin, "MOLLEBAYA", "IDA")["stops"]
    ]


def test_editar_un_paradero_inexistente(cliente, admin):
    r = cliente.put(
        "/api/v1/admin/stops/stp_998",
        headers=admin,
        json={"name": "No existe", "lat": -16.46, "lon": -71.49},
    )
    assert r.status_code == 404


# ----------------------------------------------------------------------
# RF-016: unidades y cuentas sin datos personales
# ----------------------------------------------------------------------
def test_alta_de_unidad_y_cuenta_con_contrasena_temporal(cliente, admin):
    unidad = cliente.post("/api/v1/admin/units", headers=admin, json={"label": "15"})
    assert unidad.status_code == 201
    unidad_id = unidad.json()["data"]["id"]

    r = cliente.post(
        "/api/v1/admin/driver-accounts",
        headers=admin,
        json={"vehicle_id": unidad_id, "username": "unidad15"},
    )
    assert r.status_code == 201
    datos = r.json()["data"]
    clave = datos["temporary_password"]
    assert len(clave) == 12
    # Sin campos de datos personales (RN-011)
    assert set(datos["account"]) == {
        "id",
        "username",
        "role",
        "active",
        "locked_until",
        "vehicle_label",
    }
    assert ingresar(cliente, "unidad15", clave).status_code == 200

    # La contraseña temporal no se vuelve a ver
    lista = cliente.get("/api/v1/admin/driver-accounts", headers=admin).json()["data"]
    assert all("password" not in str(c) for c in lista)


def test_una_sola_cuenta_por_unidad(cliente, admin):
    unidades = cliente.get("/api/v1/admin/units", headers=admin).json()["data"]
    doce = next(u for u in unidades if u["label"] == "12")
    r = cliente.post(
        "/api/v1/admin/driver-accounts",
        headers=admin,
        json={"vehicle_id": doce["id"], "username": "otra.cuenta"},
    )
    assert r.status_code == 409
    assert "RN-001" in r.json()["error"]["message"]


@pytest.mark.parametrize(("etiqueta", "codigo"), [("07", 409), ("con espacio", 400)])
def test_etiquetas_de_unidad_invalidas(cliente, admin, etiqueta, codigo):
    r = cliente.post("/api/v1/admin/units", headers=admin, json={"label": etiqueta})
    assert r.status_code == codigo


def test_el_usuario_no_se_repite_entre_conductores_y_panel(cliente, admin):
    r = cliente.post(
        "/api/v1/admin/panel-accounts",
        headers=admin,
        json={"username": "unidad07", "role": "MODERADOR"},
    )
    assert r.status_code == 409


def test_restablecer_y_desactivar_una_cuenta_de_conductor(cliente, admin):
    cuentas = cliente.get("/api/v1/admin/driver-accounts", headers=admin).json()["data"]
    doce = next(c for c in cuentas if c["username"] == "unidad12")
    url = f"/api/v1/admin/driver-accounts/{doce['id']}"

    r = cliente.put(url, headers=admin, json={"action": "RESET_PASSWORD"})
    nueva = r.json()["data"]["temporary_password"]
    assert ingresar(cliente, "unidad12").status_code == 401
    assert ingresar(cliente, "unidad12", nueva).status_code == 200

    r = cliente.put(url, headers=admin, json={"action": "DEACTIVATE"})
    assert r.json()["data"]["account"]["active"] is False
    assert ingresar(cliente, "unidad12", nueva).status_code == 401


def test_deshabilitar_una_unidad_cierra_su_sesion(cliente, admin):
    assert "07" in [u["vehicle_label"] for u in cliente.get("/api/v1/vehicles").json()["data"]]
    unidades = cliente.get("/api/v1/admin/units", headers=admin).json()["data"]
    siete = next(u for u in unidades if u["label"] == "07")
    r = cliente.put(f"/api/v1/admin/units/{siete['id']}", headers=admin, json={"active": False})
    assert r.status_code == 200
    assert "07" not in [u["vehicle_label"] for u in cliente.get("/api/v1/vehicles").json()["data"]]


def test_cuentas_del_panel_y_proteccion_del_administrador(cliente, admin):
    nueva = cliente.post(
        "/api/v1/admin/panel-accounts",
        headers=admin,
        json={"username": "ana.moderadora", "role": "MODERADOR"},
    )
    assert nueva.status_code == 201
    clave = nueva.json()["data"]["temporary_password"]
    datos = ingresar(cliente, "ana.moderadora", clave).json()["data"]
    assert datos["role"] == "MODERADOR"

    cuentas = cliente.get("/api/v1/admin/panel-accounts", headers=admin).json()["data"]
    yo = next(c for c in cuentas if c["username"] == "admin.demo")
    r = cliente.put(
        f"/api/v1/admin/panel-accounts/{yo['id']}", headers=admin, json={"action": "DEACTIVATE"}
    )
    assert r.status_code == 409


# ----------------------------------------------------------------------
# RF-020: registro de eventos
# ----------------------------------------------------------------------
def test_los_cambios_del_panel_quedan_en_el_registro(cliente, admin):
    cliente.post("/api/v1/admin/units", headers=admin, json={"label": "21"})
    r = cliente.get("/api/v1/admin/events?type=SEGURIDAD", headers=admin)
    assert r.status_code == 200
    datos = r.json()["data"]
    reciente = datos["events"][0]
    assert reciente["panel_user"] == "admin.demo"
    assert reciente["detail"]["accion"] == "crear_unidad"
    assert datos["total"] >= 1 and datos["retention_days"] > 0


@pytest.mark.parametrize(
    "consulta",
    [
        "from=2026-10-10T00:00:00Z&to=2026-10-01T00:00:00Z",
        "from=2020-01-01T00:00:00Z",
    ],
    ids=["fechas_invertidas", "mas_de_30_dias"],
)
def test_filtros_de_eventos_invalidos(cliente, moderador, consulta):
    r = cliente.get(f"/api/v1/admin/events?{consulta}", headers=moderador)
    assert r.status_code == 400
