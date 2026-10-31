"""Preparación compartida de las pruebas que usan la base de datos.

La usan las carpetas integration, funcionales, seguridad y e2e. Necesitan la base
de Docker en marcha, con los datos demo cargados; las pruebas unitarias no.
Cada prueba trabaja dentro de una transacción que se deshace al terminar: la base
queda exactamente como estaba. Si la base no está disponible, se omiten.
"""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session

from app.db.conexion import obtener_motor, sesion_bd
from app.main import app


@pytest.fixture(scope="session")
def motor() -> Engine:
    try:
        m = obtener_motor()
        with m.connect() as conexion:
            conexion.execute(text("SELECT 1"))
    except Exception as e:  # cualquier fallo de conexión
        pytest.skip(f"Base de datos no disponible: {e.__class__.__name__}")
    return m


@pytest.fixture
def sesion(motor: Engine) -> Iterator[Session]:
    conexion = motor.connect()
    transaccion = conexion.begin()
    s = Session(bind=conexion, join_transaction_mode="create_savepoint")
    try:
        yield s
    finally:
        s.close()
        transaccion.rollback()
        conexion.close()


@pytest.fixture
def cliente(sesion: Session) -> Iterator[TestClient]:
    """Cliente HTTP cuya API usa la misma transacción de la prueba."""

    def _sesion_de_prueba() -> Iterator[Session]:
        yield sesion

    app.dependency_overrides[sesion_bd] = _sesion_de_prueba
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def cliente_real(motor: Engine) -> Iterator[TestClient]:
    """Cliente con el grupo de conexiones real, sin transacción compartida.

    Solo para pruebas de lectura: cada petición abre y confirma su propia sesión,
    igual que en producción. Lo usan las pruebas de concurrencia y la prueba E2E.
    """
    with TestClient(app) as c:
        yield c
