"""Herramienta de cuentas: lo que la crea debe poder ingresar por la API."""

import pytest
from sqlalchemy import text

from app.herramientas import cuentas

pytestmark = pytest.mark.integracion


def ingresar(cliente, usuario, clave):
    return cliente.post("/api/v1/auth/login", json={"username": usuario, "password": clave})


def test_conductor_creado_ingresa_con_la_clave_mostrada(sesion, cliente):
    creada = cuentas.crear_conductor(sesion, "21")
    assert creada.usuario == "unidad21" and len(creada.contrasena) == 12
    r = ingresar(cliente, "unidad21", creada.contrasena)
    assert r.status_code == 200
    assert r.json()["data"]["vehicle_label"] == "21"
    # En la base solo queda el hash
    guardado = sesion.execute(
        text("SELECT hash_contrasena FROM cuenta_conductor WHERE usuario = 'unidad21'")
    ).scalar()
    assert creada.contrasena not in guardado


def test_cuenta_del_panel(sesion, cliente):
    creada = cuentas.crear_panel(sesion, "pierre.admin", "ADMINISTRADOR")
    assert (
        ingresar(cliente, "pierre.admin", creada.contrasena).json()["data"]["role"]
        == "ADMINISTRADOR"
    )


@pytest.mark.parametrize(
    ("accion", "mensaje"),
    [
        (lambda s: cuentas.crear_conductor(s, "07", "otro.usuario"), "ya tiene cuenta"),
        (lambda s: cuentas.crear_conductor(s, "30", "admin.demo"), "Ya existe"),
        (lambda s: cuentas.crear_panel(s, "unidad07", "MODERADOR"), "Ya existe"),
        (lambda s: cuentas.crear_panel(s, "Mayusculas", "MODERADOR"), "minúsculas"),
        (lambda s: cuentas.crear_conductor(s, "07 B"), "etiqueta"),
        (lambda s: cuentas.nueva_clave(s, "noexiste"), "No existe"),
    ],
)
def test_reglas_de_la_herramienta(sesion, accion, mensaje):
    with pytest.raises(cuentas.ErrorDeCuenta, match=mensaje):
        accion(sesion)


def test_nueva_clave_reemplaza_la_anterior_y_desbloquea(sesion, cliente):
    sesion.execute(
        text(
            "UPDATE cuenta_conductor SET bloqueada_hasta = now() + interval '10 min' "
            "WHERE usuario = 'unidad12'"
        )
    )
    nueva = cuentas.nueva_clave(sesion, "unidad12")
    assert ingresar(cliente, "unidad12", "rutasur-demo").status_code == 401
    assert ingresar(cliente, "unidad12", nueva.contrasena).status_code == 200


def test_desbloquear(sesion, cliente):
    sesion.execute(
        text(
            "UPDATE cuenta_administrativa SET bloqueada_hasta = now() + interval '10 min' "
            "WHERE usuario = 'admin.demo'"
        )
    )
    cuentas.desbloquear(sesion, "admin.demo")
    assert ingresar(cliente, "admin.demo", "rutasur-demo").status_code == 200


def test_deshabilitar_cierra_su_sesion_y_le_impide_ingresar(sesion, cliente):
    cuentas.habilitar(sesion, "unidad07", activa=False)
    assert all(u["vehicle_label"] != "07" for u in cliente.get("/api/v1/vehicles").json()["data"])
    assert ingresar(cliente, "unidad07", "rutasur-demo").status_code == 401
    cuentas.habilitar(sesion, "unidad07", activa=True)
    assert ingresar(cliente, "unidad07", "rutasur-demo").status_code == 200


def test_listar(sesion):
    usuarios = {f["usuario"]: f for f in cuentas.listar(sesion)}
    assert usuarios["unidad07"]["unidad"] == "07"
    assert usuarios["admin.demo"]["rol"] == "ADMINISTRADOR"
