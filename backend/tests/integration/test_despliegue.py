"""Depuración contra la base real y verificación de despliegue contra la API completa."""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app import main
from app.core.config import Configuracion
from app.db.conexion import sesion_bd
from app.db.depuracion import depurar
from app.herramientas.verificar_despliegue import Respuesta, verificar

pytestmark = pytest.mark.integracion


def test_depuracion_llama_a_la_funcion_de_la_base(motor):
    # Con 10 años de retención no se borra nada de los datos de prueba
    resultado = depurar(motor, 3650)
    assert resultado == {
        "posiciones_eliminadas": 0,
        "sesiones_eliminadas": 0,
        "eventos_eliminados": 0,
    }


@pytest.fixture
def cliente_produccion(sesion: Session, monkeypatch) -> TestClient:
    """La API tal como corre en Render (entorno de producción), sobre la base de prueba."""
    monkeypatch.setattr(main, "obtener_configuracion", lambda: Configuracion(entorno="produccion"))
    app = main.crear_app()

    def _sesion_de_prueba() -> Iterator[Session]:
        yield sesion

    app.dependency_overrides[sesion_bd] = _sesion_de_prueba
    return TestClient(app)  # sin «with»: no arranca la depuración automática


def _obtener_con(cliente: TestClient):
    def obtener(ruta: str) -> Respuesta:
        r = cliente.get(ruta)
        return Respuesta(r.status_code, {k.lower(): v for k, v in r.headers.items()}, r.json(), 0.0)

    return obtener


def test_verificacion_de_despliegue_pasa_con_la_api_de_produccion(cliente_produccion):
    resultado = verificar(_obtener_con(cliente_produccion), "https://rutasur-api.onrender.com")
    fallas = [v for v in resultado.verificaciones if not v[1]]
    assert resultado.correcto, fallas


def test_verificacion_detecta_que_falta_hsts_y_https(cliente):
    resultado = verificar(_obtener_con(cliente), "http://localhost:8000")
    fallas = {nombre for nombre, ok, _ in resultado.verificaciones if not ok}
    assert fallas == {"Conexión HTTPS"}
