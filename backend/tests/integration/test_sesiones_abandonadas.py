"""Cierre automático de sesiones abandonadas (el conductor no pulsó «Terminar»)."""

import pytest
from sqlalchemy import text

from app.db.sesiones_abandonadas import cerrar_en

pytestmark = pytest.mark.integracion


def _abrir_sesion(conexion, etiqueta: str, hace: str, ultima_hace: str | None) -> str:
    return conexion.execute(
        text(f"""
            INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id, inicio,
                                        ultima_posicion_en)
            SELECT u.id, c.id, v.id, now() - interval '{hace}',
                   {"NULL" if ultima_hace is None else f"now() - interval '{ultima_hace}'"}
              FROM unidad u
              JOIN cuenta_conductor c ON c.unidad_id = u.id
              JOIN variante v ON v.ramal = 'CERRILLO' AND v.sentido = 'IDA'
             WHERE u.etiqueta = :etiqueta
            RETURNING id
        """),  # noqa: S608 — los intervalos son constantes de la prueba
        {"etiqueta": etiqueta},
    ).scalar_one()


def _estado(conexion, sesion_id) -> str:
    return conexion.execute(
        text("SELECT estado::text FROM sesion_emision WHERE id = :id"), {"id": sesion_id}
    ).scalar_one()


def test_cierra_solo_las_sesiones_sin_posiciones_hace_horas(sesion):
    conexion = sesion.connection()
    # Ninguna sesión previa queda abierta: así la prueba no depende de la hora de los datos demo
    conexion.execute(
        text("""UPDATE sesion_emision SET estado = 'CERRADA_POR_CONDUCTOR',
                       fin = greatest(now(), inicio + interval '1 second')
                 WHERE estado IN ('ACTIVA', 'SIN_SENAL')""")
    )
    abandonada = _abrir_sesion(conexion, "12", "5 hours", "3 hours")
    sin_ninguna_posicion = _abrir_sesion(conexion, "07", "4 hours", None)

    assert cerrar_en(conexion, horas=2) == 2
    assert _estado(conexion, abandonada) == "CERRADA_AUTOMATICAMENTE"
    assert _estado(conexion, sin_ninguna_posicion) == "CERRADA_AUTOMATICAMENTE"
    evento = conexion.execute(
        text("""SELECT detalle FROM registro_evento
                 WHERE origen = 'cierre_sesiones_abandonadas' ORDER BY id DESC LIMIT 1""")
    ).scalar_one()
    assert evento == {"sesiones": 2, "horas_sin_posiciones": 2}


def test_no_toca_una_sesion_que_sigue_transmitiendo(sesion):
    conexion = sesion.connection()
    conexion.execute(
        text("""UPDATE sesion_emision SET estado = 'CERRADA_POR_CONDUCTOR',
                       fin = greatest(now(), inicio + interval '1 second')
                 WHERE estado IN ('ACTIVA', 'SIN_SENAL')""")
    )
    en_viaje = _abrir_sesion(conexion, "12", "5 hours", "1 minute")  # viaje largo, pero vivo
    antes = conexion.execute(text("SELECT count(*) FROM registro_evento")).scalar_one()

    assert cerrar_en(conexion, horas=2) == 0
    assert _estado(conexion, en_viaje) == "ACTIVA"
    # Sin cierres no se escribe ningún evento (D-18: nada de ruido en el registro)
    assert conexion.execute(text("SELECT count(*) FROM registro_evento")).scalar_one() == antes
