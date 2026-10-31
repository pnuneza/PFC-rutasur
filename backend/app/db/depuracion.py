"""Depuración automática de datos operativos (RN-012).

La regla la aplica la función fn_depurar_datos_operativos de la base de datos; aquí
solo se decide cuándo llamarla. En la nube no hay un programador de tareas gratuito,
así que el propio servicio la ejecuta al arrancar y luego cada 24 horas. En Render el
servicio se apaga cuando no tiene tráfico y vuelve a arrancar con la primera petición,
de modo que la depuración también corre cada vez que se reanuda. Es idempotente: borrar
dos veces lo que ya venció no cambia nada.
"""

import asyncio
import logging

from sqlalchemy import Engine, text

logger = logging.getLogger("rutasur.depuracion")

INTERVALO_S = 24 * 60 * 60
ESPERA_INICIAL_S = 30  # deja que el servicio atienda primero las peticiones del arranque


def depurar(motor: Engine, dias: int) -> dict[str, int]:
    """Ejecuta la depuración en su propia transacción y devuelve lo eliminado."""
    with motor.begin() as conexion:
        fila = conexion.execute(
            text("SELECT * FROM fn_depurar_datos_operativos(:dias)"), {"dias": dias}
        ).one()
    resultado = dict(fila._mapping)
    logger.info("Depuración de datos con más de %s días: %s", dias, resultado)
    return resultado


async def depurar_periodicamente(
    motor: Engine, dias: int, espera_inicial_s: float = ESPERA_INICIAL_S
) -> None:
    """Tarea en segundo plano: un fallo se registra y se reintenta en el siguiente ciclo."""
    await asyncio.sleep(espera_inicial_s)
    while True:
        try:
            await asyncio.to_thread(depurar, motor, dias)
        except Exception:  # la depuración nunca debe tumbar el servicio
            logger.exception("Falló la depuración automática; se reintentará")
        await asyncio.sleep(INTERVALO_S)
