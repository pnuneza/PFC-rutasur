"""Clasificación de las unidades en A-02 (RF-017): transmitiendo, sin señal e inactiva."""

from datetime import UTC, datetime, timedelta

from app.domain.administracion import EstadoUnidad
from app.services.servicio_administracion import clasificar_unidad

AHORA = datetime(2026, 11, 1, 8, 0, tzinfo=UTC)
CREADA = AHORA - timedelta(days=10)


def hace(segundos: int) -> datetime:
    return AHORA - timedelta(seconds=segundos)


def test_sin_sesion_esta_inactiva_desde_su_ultimo_turno():
    estado, desde, antiguedad = clasificar_unidad(None, None, hace(3600), CREADA, AHORA)
    assert (estado, desde, antiguedad) == (EstadoUnidad.INACTIVA, hace(3600), None)


def test_sin_sesion_ni_turnos_esta_inactiva_desde_que_se_registro():
    assert clasificar_unidad(None, None, None, CREADA, AHORA)[1] == CREADA


def test_con_posicion_de_90_s_o_menos_transmite_desde_el_inicio_del_turno():
    estado, desde, antiguedad = clasificar_unidad(hace(1800), hace(90), None, CREADA, AHORA)
    assert (estado, desde, antiguedad) == (EstadoUnidad.TRANSMITIENDO, hace(1800), 90)


def test_con_mas_de_90_s_sin_posiciones_esta_sin_senal_desde_la_ultima():
    estado, desde, antiguedad = clasificar_unidad(hace(1800), hace(91), None, CREADA, AHORA)
    assert (estado, desde, antiguedad) == (EstadoUnidad.SIN_SENAL, hace(91), 91)


def test_recien_abierta_sin_posiciones_aun_cuenta_como_transmitiendo():
    assert clasificar_unidad(hace(30), None, None, CREADA, AHORA)[0] == EstadoUnidad.TRANSMITIENDO


def test_abierta_hace_rato_sin_ninguna_posicion_esta_sin_senal():
    assert clasificar_unidad(hace(600), None, None, CREADA, AHORA)[0] == EstadoUnidad.SIN_SENAL
