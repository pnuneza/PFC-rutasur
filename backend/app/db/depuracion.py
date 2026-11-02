"""Depuración automática de datos operativos (RN-012).

La regla la aplica la función fn_depurar_datos_operativos de la base de datos; aquí
solo se decide cuándo llamarla. En la nube no hay un programador de tareas gratuito,
así que el propio servicio la ejecuta al arrancar y luego cada 24 horas. En Render el
servicio se apaga a los 15 minutos sin tráfico y vuelve a arrancar con la primera
petición. Por eso, al arrancar primero se mira cuándo corrió la última depuración
(queda en registro_evento) y solo se ejecuta si ya pasaron 24 horas; si no, se espera
lo que falta. Antes corría en cada arranque y llenaba el registro de eventos (D-18).
La función es idempotente: borrar dos veces lo que ya venció no cambia nada.
"""

import asyncio
import logging

from sqlalchemy import Engine, text

logger = logging.getLogger("rutasur.depuracion")

INTERVALO_S = 24 * 60 * 60
ESPERA_INICIAL_S = 30  # deja que el servicio atienda primero las peticiones del arranque


def segundos_para_la_siguiente(motor: Engine) -> float:
    """Cuánto falta para que se cumplan 24 h desde la última depuración (0 si ya toca)."""
    with motor.connect() as conexion:
        fila = conexion.execute(
            text(
                "SELECT max(fecha) AS ultima, now() AS ahora FROM registro_evento"
                " WHERE tipo = 'TAREA' AND origen = 'depuracion_diaria'"
            )
        ).one()
    if fila.ultima is None:
        return 0.0
    transcurrido = (fila.ahora - fila.ultima).total_seconds()
    return max(0.0, INTERVALO_S - transcurrido)


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
    """Tarea en segundo plano: una vez cada 24 h aunque el servicio se reinicie.

    Un fallo se registra y se reintenta en el siguiente ciclo.
    """
    await asyncio.sleep(espera_inicial_s)
    while True:
        espera = INTERVALO_S
        try:
            falta = await asyncio.to_thread(segundos_para_la_siguiente, motor)
            if falta > 0:
                espera = falta
                logger.info("La depuración ya corrió hace menos de 24 h; faltan %.0f s", falta)
            else:
                await asyncio.to_thread(depurar, motor, dias)
        except Exception:  # la depuración nunca debe tumbar el servicio
            logger.exception("Falló la depuración automática; se reintentará")
        await asyncio.sleep(espera)
