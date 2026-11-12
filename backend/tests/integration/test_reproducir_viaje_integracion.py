"""Un viaje grabado se reproduce por la API real y se vuelve a exportar igual (Módulo 7)."""

import argparse
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text

from app.domain.modelos import Ramal, Sentido
from app.herramientas.reproducir_viaje import (
    LecturaGrabada,
    ReproductorViaje,
    ViajeGrabado,
    exportar,
)
from app.herramientas.simular_unidad import ErrorApi, Recorrido
from app.repositories.sql_rutas import RepositorioRutasSQL

pytestmark = pytest.mark.integracion


class ReproductorEnPrueba(ReproductorViaje):
    """Pide a la API de la prueba (TestClient) en vez de salir a la red."""

    def __init__(self, cliente, viaje: ViajeGrabado, ahora: datetime) -> None:
        args = argparse.Namespace(
            api="http://prueba", usuario="unidad12", desde_minuto=0.0, rapidez=1.0, lote=3
        )
        self.segundos = 0.0

        def dormir(s: float) -> None:
            self.segundos += s

        super().__init__(
            args, viaje, reloj=lambda: self.segundos, dormir=dormir, ahora=lambda: ahora
        )
        self.cliente = cliente

    def _pedir(self, metodo, ruta, cuerpo=None):
        cabeceras = {"Authorization": f"Bearer {self.token}"} if self.token else {}
        r = self.cliente.request(metodo, "/api/v1" + ruta, json=cuerpo, headers=cabeceras)
        if r.status_code >= 400:
            error = r.json().get("error", {})
            raise ErrorApi(r.status_code, error.get("code", ""), error.get("message", ""))
        return r.json()


def test_el_viaje_reproducido_se_publica_y_se_exporta_igual(cliente, sesion, monkeypatch):
    # Un tramo corto de Cerrillo · bajada, con una parada de 10 s, a 36 km/h
    linea = RepositorioRutasSQL(sesion).obtener_linea("LB")
    variante = next(
        v for v in linea.variantes if (v.ramal, v.sentido) == (Ramal.CERRILLO, Sentido.IDA)
    )
    recorrido = Recorrido.desde(variante.trazado)
    metros = [2000, 2050, 2100, 2100, 2100, 2150]
    lecturas = []
    for i, m in enumerate(metros):
        punto, rumbo = recorrido.punto_a(m)
        lecturas.append(LecturaGrabada(5.0 * i, punto.lat, punto.lon, 36.0, rumbo, 5.0))
    viaje = ViajeGrabado(Ramal.CERRILLO, Sentido.IDA, "2026-11-10", tuple(lecturas))

    # Los 25 s del viaje caen dentro de la tolerancia del reloj del servidor
    monkeypatch.setenv("RUTASUR_CLAVE", "rutasur-demo")
    reproductor = ReproductorEnPrueba(cliente, viaje, datetime.now(UTC) - timedelta(seconds=10))
    assert reproductor.ejecutar() == 0
    assert reproductor.cola == []  # el servidor confirmó todas las lecturas

    # La sesión quedó cerrada y sus posiciones son las del viaje, con los mismos intervalos
    sesion_id = sesion.execute(
        text(
            """SELECT s.id::text FROM sesion_emision s JOIN unidad u ON u.id = s.unidad_id
               WHERE u.etiqueta = '12' ORDER BY s.inicio DESC LIMIT 1"""
        )
    ).scalar_one()
    estado = sesion.execute(
        text("SELECT estado::text FROM sesion_emision WHERE id = :id"), {"id": sesion_id}
    ).scalar_one()
    assert estado != "ACTIVA"

    exportado = exportar(sesion, sesion_id)
    assert (exportado.ramal, exportado.sentido) == (Ramal.CERRILLO, Sentido.IDA)
    assert len(exportado.lecturas) == len(lecturas)
    intervalos = [
        round(b.t - a.t, 1)
        for a, b in zip(exportado.lecturas, exportado.lecturas[1:], strict=False)
    ]
    assert intervalos == [5.0] * 5
    for original, copia in zip(lecturas, exportado.lecturas, strict=True):
        assert copia.lat == pytest.approx(original.lat, abs=1e-6)
        assert copia.lon == pytest.approx(original.lon, abs=1e-6)
