"""Flujo completo de CU-02 → CU-01 contra la base real.

Una unidad abre sesión, emite posiciones por el servicio de emisión y, en la
misma transacción, la API pública la muestra en el mapa y calcula su llegada.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError

from app.domain.modelos import Coordenada, EstadoSesion, PosicionEntrante, Ramal, Sentido
from app.herramientas.simular_unidad import Recorrido
from app.repositories.sql_emision import RepositorioEmisionSQL
from app.repositories.sql_rutas import RepositorioRutasSQL
from app.services.servicio_emision import ServicioEmision
from app.services.validador_posiciones import ValidadorPosiciones
from tests.conftest import paraderos_de

pytestmark = pytest.mark.integracion


@pytest.fixture
def emision(sesion):
    return ServicioEmision(RepositorioEmisionSQL(sesion), ValidadorPosiciones())


@pytest.fixture
def unidad_12(sesion):
    return RepositorioEmisionSQL(sesion).buscar_unidad_por_etiqueta("12")


@pytest.fixture
def recorrido_cerrillo_ida(sesion) -> Recorrido:
    linea = RepositorioRutasSQL(sesion).obtener_linea("LB")
    variante = next(
        v for v in linea.variantes if (v.ramal, v.sentido) == (Ramal.CERRILLO, Sentido.IDA)
    )
    return Recorrido.desde(variante.trazado)


def lecturas(recorrido: Recorrido, inicio: datetime, metros: list[float]) -> list[PosicionEntrante]:
    """Una lectura cada 5 s en los puntos del trazado indicados."""
    resultado = []
    for i, m in enumerate(metros):
        punto, rumbo = recorrido.punto_a(m)
        resultado.append(
            PosicionEntrante(
                uuid4(), punto, 36.0, rumbo, 8.0, inicio + timedelta(seconds=1 + 5 * i)
            )
        )
    return resultado


def test_unidad_emite_y_aparece_en_el_mapa_y_en_las_llegadas(
    sesion, cliente, linea, emision, unidad_12, recorrido_cerrillo_ida
):
    unidad_id, cuenta_id = unidad_12
    abierta = emision.abrir_sesion(
        unidad_id, cuenta_id, Ramal.CERRILLO, Sentido.IDA, datetime.now(UTC)
    )

    lote = lecturas(recorrido_cerrillo_ida, abierta.inicio, [1000, 1050, 1100])
    acuse = emision.recibir_lote(
        abierta.id, unidad_id, lote, abierta.inicio + timedelta(seconds=20)
    )
    assert (acuse.publicadas, acuse.descartadas, acuse.duplicadas) == (3, 0, 0)

    # Aparece en el mapa con su destino
    unidades = cliente.get("/api/v1/vehicles").json()["data"]
    u12 = next(u for u in unidades if u["vehicle_label"] == "12")
    assert u12["destination"] == "Centro (2 de Mayo)"
    assert u12["freshness"] == "VIGENTE"

    # Y en las llegadas al último paradero (en el Centro), con la distancia restante
    # medida sobre el trazado
    centro = paraderos_de(linea, "CERRILLO", "IDA")[-1]
    llegadas = cliente.get(f"/api/v1/stops/{centro['code']}/arrivals").json()["data"]
    l12 = next(e for e in llegadas if e["vehicle_label"] == "12")
    restante_esperado = centro["distance_from_start_m"] - 1100
    assert l12["distance_m"] == pytest.approx(restante_esperado, rel=0.02)
    assert l12["eta_seconds"] == pytest.approx(l12["distance_m"] / 10, rel=0.02)  # 36 km/h = 10 m/s
    assert l12["reliable"] is True


def test_reenvio_del_lote_no_duplica_en_la_base(sesion, emision, unidad_12, recorrido_cerrillo_ida):
    unidad_id, cuenta_id = unidad_12
    abierta = emision.abrir_sesion(
        unidad_id, cuenta_id, Ramal.CERRILLO, Sentido.IDA, datetime.now(UTC)
    )
    lote = lecturas(recorrido_cerrillo_ida, abierta.inicio, [500, 550])
    ahora = abierta.inicio + timedelta(seconds=20)

    emision.recibir_lote(abierta.id, unidad_id, lote, ahora)
    acuse = emision.recibir_lote(abierta.id, unidad_id, lote, ahora)

    assert acuse.duplicadas == 2
    total = sesion.execute(
        text("SELECT count(*) FROM posicion WHERE sesion_id = :s"), {"s": abierta.id}
    ).scalar()
    assert total == 2


def test_posicion_fuera_del_corredor_se_guarda_descartada_con_su_motivo(
    sesion, emision, unidad_12, recorrido_cerrillo_ida
):
    unidad_id, cuenta_id = unidad_12
    abierta = emision.abrir_sesion(
        unidad_id, cuenta_id, Ramal.CERRILLO, Sentido.IDA, datetime.now(UTC)
    )
    punto, _ = recorrido_cerrillo_ida.punto_a(2000)
    lejos = PosicionEntrante(
        uuid4(),
        Coordenada(punto.lat + 0.006, punto.lon),
        30.0,
        0,
        8.0,
        abierta.inicio + timedelta(seconds=2),
    )
    acuse = emision.recibir_lote(
        abierta.id, unidad_id, [lejos], abierta.inicio + timedelta(seconds=5)
    )

    assert acuse.descartadas == 1
    motivo = sesion.execute(
        text("SELECT motivo_descarte::text FROM posicion WHERE id = :id"), {"id": lejos.id}
    ).scalar()
    assert motivo == "FUERA_DE_CORREDOR"


def test_abrir_una_sesion_cierra_la_anterior_de_la_misma_unidad(sesion, emision, unidad_12):
    """RN-002: una sola fuente de posición por unidad."""
    unidad_id, cuenta_id = unidad_12
    primera = emision.abrir_sesion(
        unidad_id, cuenta_id, Ramal.CERRILLO, Sentido.IDA, datetime.now(UTC)
    )
    segunda = emision.abrir_sesion(
        unidad_id, cuenta_id, Ramal.CERRILLO, Sentido.VUELTA, datetime.now(UTC)
    )

    repo = RepositorioEmisionSQL(sesion)
    assert repo.obtener_sesion(primera.id).estado == EstadoSesion.CERRADA_AUTOMATICAMENTE
    assert repo.obtener_sesion(segunda.id).estado == EstadoSesion.ACTIVA


def test_el_rol_de_la_aplicacion_no_puede_borrar_posiciones(sesion):
    """La conexión del backend usa rutasur_app, con permisos mínimos."""
    usuario = sesion.execute(text("SELECT current_user")).scalar()
    if usuario != "rutasur_app":
        pytest.skip("Esta prueba requiere conectarse como rutasur_app")
    with pytest.raises(ProgrammingError, match="permission denied"), sesion.begin_nested():
        sesion.execute(text("DELETE FROM posicion"))


def test_hora_del_servidor_esta_en_utc(cliente):
    hora = datetime.fromisoformat(cliente.get("/api/v1/health").json()["data"]["server_time"])
    assert hora.utcoffset() == timedelta(0)
    assert abs((datetime.now(UTC) - hora).total_seconds()) < 60
