"""Cierre automático de sesiones abandonadas.

Si el conductor no pulsa «Terminar» (se le acabó la batería, cerró la app, perdió el
teléfono), su sesión queda abierta para siempre: el panel la muestra «Sin señal» y la
unidad no puede abrir otra sin cerrar esa. Esta tarea cierra las sesiones que llevan
más de `HORAS_SIN_POSICIONES` sin recibir una posición, con el estado
CERRADA_AUTOMATICAMENTE, y deja constancia en el registro de eventos.

Corre al arrancar el servicio y luego cada 15 minutos. En Render el servicio se apaga
sin tráfico, así que al despertar lo primero que hace es este cierre.
"""

import asyncio
import json
import logging

from sqlalchemy import Connection, Engine, text

logger = logging.getLogger("rutasur.sesiones")

HORAS_SIN_POSICIONES = 2  # un viaje completo dura alrededor de una hora
INTERVALO_S = 15 * 60
ESPERA_INICIAL_S = 10

_SQL_CERRAR = text("""
    UPDATE sesion_emision
       SET estado = 'CERRADA_AUTOMATICAMENTE', fin = greatest(now(), inicio + interval '1 second')
     WHERE estado IN ('ACTIVA', 'SIN_SENAL')
       AND coalesce(ultima_posicion_en, inicio) < now() - make_interval(hours => :horas)
    RETURNING id
""")

_SQL_EVENTO = text("""
    INSERT INTO registro_evento (tipo, origen, detalle)
    VALUES ('TAREA', 'cierre_sesiones_abandonadas', CAST(:detalle AS jsonb))
""")


def cerrar_en(conexion: Connection, horas: int = HORAS_SIN_POSICIONES) -> int:
    """Cierra, dentro de la transacción dada, las sesiones sin posiciones hace más de `horas`.

    Devuelve cuántas cerró. Solo registra un evento cuando cerró alguna, para no llenar
    el registro de eventos (D-18).
    """
    cerradas = conexion.execute(_SQL_CERRAR, {"horas": horas}).fetchall()
    if cerradas:
        conexion.execute(
            _SQL_EVENTO,
            {"detalle": json.dumps({"sesiones": len(cerradas), "horas_sin_posiciones": horas})},
        )
        logger.info("Sesiones abandonadas cerradas: %s", len(cerradas))
    return len(cerradas)


def cerrar_abandonadas(motor: Engine, horas: int = HORAS_SIN_POSICIONES) -> int:
    with motor.begin() as conexion:
        return cerrar_en(conexion, horas)


async def cerrar_periodicamente(motor: Engine, espera_inicial_s: float = ESPERA_INICIAL_S) -> None:
    """Tarea en segundo plano: un fallo se registra y se reintenta en el siguiente ciclo."""
    await asyncio.sleep(espera_inicial_s)
    while True:
        try:
            await asyncio.to_thread(cerrar_abandonadas, motor)
        except Exception:  # nunca debe tumbar el servicio
            logger.exception("Falló el cierre de sesiones abandonadas; se reintentará")
        await asyncio.sleep(INTERVALO_S)
