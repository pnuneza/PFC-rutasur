"""Tarea de depuración en segundo plano (RN-012): no debe tumbar el servicio."""

import asyncio

import pytest
from fastapi.testclient import TestClient

from app import main
from app.core.config import Configuracion
from app.db import depuracion


def test_un_fallo_se_registra_y_la_tarea_sigue(monkeypatch, caplog):
    llamadas = []

    def depurar_falso(motor, dias):
        llamadas.append(dias)
        if len(llamadas) == 1:
            raise RuntimeError("Neon suspendido")
        if len(llamadas) == 2:
            raise asyncio.CancelledError  # termina la prueba

    monkeypatch.setattr(depuracion, "depurar", depurar_falso)
    monkeypatch.setattr(depuracion, "INTERVALO_S", 0)
    with pytest.raises(asyncio.CancelledError):
        asyncio.run(depuracion.depurar_periodicamente(object(), 14, espera_inicial_s=0))

    assert llamadas == [14, 14]
    assert "Falló la depuración automática" in caplog.text


def test_el_servicio_arranca_la_depuracion_solo_si_corresponde(monkeypatch):
    arrancadas = []

    async def tarea_falsa(motor, dias):
        arrancadas.append(dias)

    monkeypatch.setattr(main, "depurar_periodicamente", tarea_falsa)
    monkeypatch.setattr(main, "obtener_motor", lambda: object())

    for config, esperado in [
        (Configuracion(entorno="desarrollo"), []),
        (Configuracion(entorno="produccion", retencion_dias=14), [14]),
    ]:
        arrancadas.clear()
        monkeypatch.setattr(main, "obtener_configuracion", lambda c=config: c)
        with TestClient(main.crear_app()):
            pass
        assert arrancadas == esperado


def test_verificador_rechaza_esquemas_que_no_son_http():
    from app.herramientas.verificar_despliegue import obtener_por_red

    with pytest.raises(ValueError, match="http"):
        obtener_por_red("file:///etc/passwd")
