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


# ----------------------------------------------------------------------
# Paraderos de la ruta real, tomados de la propia API (sin códigos fijos):
# así las pruebas siguen valiendo cuando se renombran o agregan paraderos.
# ----------------------------------------------------------------------
@pytest.fixture
def linea(cliente: TestClient) -> dict:
    return cliente.get("/api/v1/routes/lb").json()["data"]


def paraderos_de(linea: dict, ramal: str, sentido: str) -> list[dict]:
    variante = next(
        v for v in linea["variants"] if (v["branch"], v["direction"]) == (ramal, sentido)
    )
    return variante["stops"]


@pytest.fixture
def paradero_destino_07(linea: dict) -> str:
    """Último paradero de Mollebaya → Centro: la unidad 07 de los datos demo va hacia él."""
    return paraderos_de(linea, "MOLLEBAYA", "IDA")[-1]["code"]


@pytest.fixture
def paradero_ya_pasado_por_07(linea: dict) -> str:
    """Primer paradero de Mollebaya → Centro (Santa Ana): la unidad 07 ya salió de ahí."""
    return paraderos_de(linea, "MOLLEBAYA", "IDA")[0]["code"]
