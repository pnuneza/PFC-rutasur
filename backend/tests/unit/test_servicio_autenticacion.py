"""Reglas de autenticación con un repositorio en memoria (P06 Tabla 52, RN-011)."""

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.core.seguridad import hash_contrasena, leer_token
from app.domain.excepciones import CredencialesInvalidas, CuentaBloqueada, TokenInvalido
from app.domain.modelos import CuentaAcceso, Rol
from app.services.servicio_autenticacion import ServicioAutenticacion

SECRETO = "s" * 40
CLAVE = "rutasur-demo"
HASH = hash_contrasena(CLAVE)


class RepositorioCuentasFalso:
    def __init__(self, *cuentas: CuentaAcceso):
        self.cuentas = {c.usuario: c for c in cuentas}
        self.intentos = {c.id: 0 for c in cuentas}
        self.eventos: list[tuple[str, dict]] = []

    def buscar_por_usuario(self, usuario):
        return self.cuentas.get(usuario)

    def registrar_fallo(self, cuenta, intentos_maximos, bloquear_hasta):
        self.intentos[cuenta.id] += 1
        if self.intentos[cuenta.id] >= intentos_maximos:
            self.intentos[cuenta.id] = 0
            self.cuentas[cuenta.usuario] = replace(cuenta, bloqueada_hasta=bloquear_hasta)
            return True
        return False

    def registrar_ingreso(self, cuenta):
        self.intentos[cuenta.id] = 0
        self.cuentas[cuenta.usuario] = replace(cuenta, bloqueada_hasta=None)

    def cuenta_vigente(self, cuenta_id, rol):
        return any(c.id == cuenta_id and c.activa for c in self.cuentas.values())

    def registrar_evento(self, tipo, origen, cuenta, detalle):
        self.eventos.append((tipo, detalle))


def conductor(**cambios) -> CuentaAcceso:
    base = CuentaAcceso(
        id=uuid4(),
        usuario="unidad07",
        hash_contrasena=HASH,
        rol=Rol.CONDUCTOR,
        activa=True,
        bloqueada_hasta=None,
        unidad_id=uuid4(),
        etiqueta_unidad="07",
    )
    return replace(base, **cambios)


AHORA = datetime.now(UTC)


def servicio(*cuentas):
    repo = RepositorioCuentasFalso(*cuentas)
    return ServicioAutenticacion(repo, SECRETO), repo


def test_ingreso_correcto_entrega_token_con_rol_y_unidad():
    cuenta = conductor()
    s, _ = servicio(cuenta)
    emitido = s.iniciar_sesion("unidad07", CLAVE, AHORA)
    assert emitido.vigencia_s == 12 * 3600
    identidad = leer_token(emitido.token, SECRETO)
    assert (identidad.rol, identidad.unidad_id, identidad.etiqueta_unidad) == (
        Rol.CONDUCTOR,
        cuenta.unidad_id,
        "07",
    )


def test_usuario_inexistente_y_clave_incorrecta_dan_el_mismo_mensaje():
    s, _ = servicio(conductor())
    with pytest.raises(CredencialesInvalidas) as no_existe:
        s.iniciar_sesion("nadie", CLAVE, AHORA)
    with pytest.raises(CredencialesInvalidas) as clave_mala:
        s.iniciar_sesion("unidad07", "otra-clave", AHORA)
    assert str(no_existe.value) == str(clave_mala.value)


def test_al_quinto_fallo_la_cuenta_se_bloquea_15_minutos_y_se_registra():
    s, repo = servicio(conductor())
    for _ in range(4):
        with pytest.raises(CredencialesInvalidas):
            s.iniciar_sesion("unidad07", "otra-clave", AHORA)
    with pytest.raises(CuentaBloqueada) as e:
        s.iniciar_sesion("unidad07", "otra-clave", AHORA)
    assert e.value.reintentar_en_s == 15 * 60
    assert repo.eventos == [
        ("SEGURIDAD", {"motivo": "cuenta_bloqueada", "intentos": 5, "http": 403})
    ]


def test_cuenta_bloqueada_rechaza_incluso_la_clave_correcta():
    s, _ = servicio(conductor(bloqueada_hasta=AHORA + timedelta(minutes=10)))
    with pytest.raises(CuentaBloqueada) as e:
        s.iniciar_sesion("unidad07", CLAVE, AHORA)
    assert 590 <= e.value.reintentar_en_s <= 601


def test_pasado_el_bloqueo_se_puede_ingresar_y_el_contador_vuelve_a_cero():
    cuenta = conductor(bloqueada_hasta=AHORA - timedelta(seconds=1))
    s, repo = servicio(cuenta)
    repo.intentos[cuenta.id] = 3
    s.iniciar_sesion("unidad07", CLAVE, AHORA)
    assert repo.intentos[cuenta.id] == 0


def test_un_ingreso_correcto_reinicia_los_intentos():
    cuenta = conductor()
    s, repo = servicio(cuenta)
    for _ in range(3):
        with pytest.raises(CredencialesInvalidas):
            s.iniciar_sesion("unidad07", "otra-clave", AHORA)
    s.iniciar_sesion("unidad07", CLAVE, AHORA)
    assert repo.intentos[cuenta.id] == 0


def test_cuenta_deshabilitada_responde_como_credenciales_invalidas():
    s, repo = servicio(conductor(activa=False))
    with pytest.raises(CredencialesInvalidas, match="Usuario o contraseña incorrectos"):
        s.iniciar_sesion("unidad07", CLAVE, AHORA)
    assert repo.eventos[0][1]["motivo"] == "cuenta_deshabilitada"


def test_token_de_cuenta_deshabilitada_deja_de_servir():
    cuenta = conductor()
    s, repo = servicio(cuenta)
    identidad = leer_token(s.iniciar_sesion("unidad07", CLAVE, AHORA).token, SECRETO)
    s.verificar_vigente(identidad)
    repo.cuentas["unidad07"] = replace(cuenta, activa=False)
    with pytest.raises(TokenInvalido):
        s.verificar_vigente(identidad)
