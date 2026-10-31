"""Motor de conexión, sesión por petición y cupo de conexiones (D-11).

Por qué existe el cupo
----------------------
Las operaciones de la API son síncronas: FastAPI las ejecuta en un grupo de hilos
(40 por defecto). El grupo de conexiones a PostgreSQL es mucho menor (5 + 5). Con
100 peticiones simultáneas, los 40 hilos quedaban ocupados esperando una conexión,
y las peticiones que ya habían terminado no podían devolver la suya porque el cierre
de la sesión también necesita un hilo libre. Resultado: todo se detenía hasta que
vencía la espera del grupo (30 s) y llovían errores (Práctica 08, D-11).

La solución es una compuerta asíncrona: antes de ocupar un hilo, cada petición
espera su turno en el bucle de eventos —sin gastar hilos— y solo pasan a la vez
tantas como conexiones existen. Así nunca hay un hilo esperando una conexión.
"""

import asyncio
from collections.abc import AsyncIterator, Iterator
from functools import lru_cache
from weakref import WeakKeyDictionary

from fastapi import Depends
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session

from app.core.config import obtener_configuracion


@lru_cache
def obtener_motor() -> Engine:
    """Crea el motor una sola vez, con un grupo pequeño de conexiones (capa gratuita)."""
    config = obtener_configuracion()
    return create_engine(
        config.database_url,
        pool_size=config.db_pool_size,
        max_overflow=config.db_max_overflow,
        pool_timeout=config.db_pool_timeout_s,
        pool_pre_ping=True,  # descarta conexiones que el proveedor cerró por inactividad
        pool_recycle=300,
    )


def capacidad_del_grupo() -> int:
    """Cantidad máxima de conexiones que el grupo puede entregar a la vez."""
    config = obtener_configuracion()
    return config.db_pool_size + config.db_max_overflow


# Un semáforo por bucle de eventos: en producción hay uno solo, pero las pruebas
# crean un bucle por cliente y un semáforo no puede compartirse entre bucles.
_cupos: WeakKeyDictionary[asyncio.AbstractEventLoop, asyncio.Semaphore] = WeakKeyDictionary()


def _cupo_del_bucle() -> asyncio.Semaphore:
    bucle = asyncio.get_running_loop()
    cupo = _cupos.get(bucle)
    if cupo is None:
        cupo = asyncio.Semaphore(capacidad_del_grupo())
        _cupos[bucle] = cupo
    return cupo


async def cupo_de_conexion() -> AsyncIterator[None]:
    """Compuerta asíncrona: la petición espera aquí, sin ocupar un hilo, su turno."""
    async with _cupo_del_bucle():
        yield


def sesion_bd(_: None = Depends(cupo_de_conexion)) -> Iterator[Session]:
    """Una transacción por petición: se confirma si todo sale bien y se deshace si falla.

    Depende del cupo, de modo que cuando se ejecuta ya hay una conexión garantizada.
    """
    with Session(obtener_motor()) as sesion:
        try:
            yield sesion
            sesion.commit()
        except Exception:
            sesion.rollback()
            raise
