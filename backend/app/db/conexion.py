"""Motor de conexión y sesión de base de datos por petición."""

from collections.abc import Iterator
from functools import lru_cache

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session

from app.core.config import obtener_configuracion


@lru_cache
def obtener_motor() -> Engine:
    """Crea el motor una sola vez, con un grupo pequeño de conexiones (capa gratuita)."""
    config = obtener_configuracion()
    return create_engine(
        config.database_url,
        pool_size=5,
        max_overflow=5,
        pool_pre_ping=True,  # descarta conexiones que el proveedor cerró por inactividad
        pool_recycle=300,
    )


def sesion_bd() -> Iterator[Session]:
    """Una transacción por petición: se confirma si todo sale bien y se deshace si falla."""
    with Session(obtener_motor()) as sesion:
        try:
            yield sesion
            sesion.commit()
        except Exception:
            sesion.rollback()
            raise
