"""Pruebas del servicio de emisión (CU-02, P06 Tabla 54) con repositorio en memoria."""

from datetime import timedelta
from uuid import uuid4

import pytest

from app.domain.excepciones import (
    AccesoDenegado,
    ErrorDeNegocio,
    RecursoNoEncontrado,
    SesionNoActiva,
    UnidadInactiva,
)
from app.domain.modelos import Coordenada, EstadoSesion, PosicionEntrante, Ramal, Sentido
from app.services.servicio_emision import ServicioEmision
from app.services.validador_posiciones import ValidadorPosiciones
from tests.fakes import T0, EmisionEnMemoria

AHORA = T0 + timedelta(minutes=10)


def lectura(segundos: float, metros_al_sur: float = 0, precision: float = 8) -> PosicionEntrante:
    return PosicionEntrante(
        id=uuid4(),
        ubicacion=Coordenada(-16.45 - metros_al_sur / 111_195, -71.5),
        velocidad_kmh=30,
        rumbo=180,
        precision_m=precision,
        capturada_en=T0 + timedelta(seconds=segundos),
    )


@pytest.fixture
def repo() -> EmisionEnMemoria:
    return EmisionEnMemoria()


@pytest.fixture
def servicio(repo: EmisionEnMemoria) -> ServicioEmision:
    return ServicioEmision(repo, ValidadorPosiciones())


# --- quién puede enviar --------------------------------------------------
def test_sesion_inexistente(servicio):
    with pytest.raises(RecursoNoEncontrado):
        servicio.recibir_lote(uuid4(), uuid4(), [lectura(5)], AHORA)


def test_no_se_puede_enviar_a_la_sesion_de_otra_unidad(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    with pytest.raises(AccesoDenegado):
        servicio.recibir_lote(sesion.id, uuid4(), [lectura(5)], AHORA)


def test_sesion_cerrada_rechaza_posiciones(repo, servicio):
    sesion = repo.agregar_sesion(uuid4(), EstadoSesion.CERRADA_AUTOMATICAMENTE)
    with pytest.raises(SesionNoActiva):
        servicio.recibir_lote(sesion.id, sesion.unidad_id, [lectura(5)], AHORA)


def test_sesion_sin_senal_si_acepta_posiciones(repo, servicio):
    sesion = repo.agregar_sesion(uuid4(), EstadoSesion.SIN_SENAL)
    acuse = servicio.recibir_lote(sesion.id, sesion.unidad_id, [lectura(5)], AHORA)
    assert acuse.publicadas == 1


# --- forma del lote ------------------------------------------------------
@pytest.mark.parametrize("cantidad", [0, 201])
def test_el_lote_debe_tener_entre_1_y_200_posiciones(repo, servicio, cantidad):
    sesion = repo.agregar_sesion(uuid4())
    lote = [lectura(i * 5) for i in range(cantidad)]
    with pytest.raises(ErrorDeNegocio):
        servicio.recibir_lote(sesion.id, sesion.unidad_id, lote, AHORA)


def test_rechaza_fechas_en_el_futuro_mas_alla_de_30_s(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    en_el_futuro = lectura(segundos=(AHORA - T0).total_seconds() + 31)
    with pytest.raises(ErrorDeNegocio):
        servicio.recibir_lote(sesion.id, sesion.unidad_id, [en_el_futuro], AHORA)


def test_rechaza_posiciones_muy_anteriores_al_inicio_de_la_sesion(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    with pytest.raises(ErrorDeNegocio):
        servicio.recibir_lote(sesion.id, sesion.unidad_id, [lectura(-60)], AHORA)


# --- validación e idempotencia -----------------------------------------
def test_lote_mixto_publica_las_validas_y_descarta_las_demas(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    lote = [lectura(5, 0), lectura(10, 40, precision=85), lectura(15, 80)]
    acuse = servicio.recibir_lote(sesion.id, sesion.unidad_id, lote, AHORA)

    assert (acuse.publicadas, acuse.descartadas, acuse.duplicadas) == (2, 1, 0)
    assert acuse.confirmados == [p.id for p in lote]  # el teléfono borra todo de su cola
    assert len(repo.posiciones) == 3  # la descartada se guarda para auditoría
    assert repo.eventos == [("POSICION_DESCARTADA", {"PRECISION_INSUFICIENTE": 1})]


def test_la_ultima_posicion_de_la_sesion_es_la_valida_mas_reciente(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    lote = [lectura(15, 80), lectura(5, 0), lectura(20, 2000)]  # desordenado; la última salta 2 km
    servicio.recibir_lote(sesion.id, sesion.unidad_id, lote, AHORA)
    ultima, _ = repo.ultima[sesion.id]
    assert ultima.posicion.id == lote[0].id  # la de los 15 s; la de 2 km es VELOCIDAD_IMPOSIBLE


def test_reenviar_un_lote_no_duplica_posiciones(repo, servicio):
    """Si se pierde la confirmación, el teléfono reenvía el mismo lote (P05, Tabla 38)."""
    sesion = repo.agregar_sesion(uuid4())
    lote = [lectura(5, 0), lectura(10, 40)]
    servicio.recibir_lote(sesion.id, sesion.unidad_id, lote, AHORA)
    acuse = servicio.recibir_lote(sesion.id, sesion.unidad_id, lote, AHORA)

    assert (acuse.publicadas, acuse.descartadas, acuse.duplicadas) == (0, 0, 2)
    assert acuse.confirmados == [p.id for p in lote]
    assert len(repo.posiciones) == 2


def test_posicion_fuera_del_corredor(repo, servicio):
    repo.distancia_al_trazado_m = 600
    sesion = repo.agregar_sesion(uuid4())
    acuse = servicio.recibir_lote(sesion.id, sesion.unidad_id, [lectura(5)], AHORA)
    assert acuse.descartadas == 1
    assert sesion.id not in repo.ultima  # no se publica en el mapa


# --- apertura de sesión --------------------------------------------------
def test_no_se_abre_sesion_en_una_unidad_deshabilitada(repo, servicio):
    unidad = uuid4()
    repo.unidades[unidad] = False
    with pytest.raises(UnidadInactiva):
        servicio.abrir_sesion(unidad, uuid4(), Ramal.MOLLEBAYA, Sentido.IDA, AHORA)


def test_no_se_abre_sesion_en_una_unidad_inexistente(servicio):
    with pytest.raises(RecursoNoEncontrado):
        servicio.abrir_sesion(uuid4(), uuid4(), Ramal.MOLLEBAYA, Sentido.IDA, AHORA)


def test_cerrar_sesion(repo, servicio):
    sesion = repo.agregar_sesion(uuid4())
    servicio.cerrar_sesion(sesion.id, sesion.unidad_id)
    assert repo.sesiones[sesion.id].estado == EstadoSesion.CERRADA_POR_CONDUCTOR


# --- diferencia entre relojes (defecto hallado en la prueba con Docker Desktop) ----------
@pytest.mark.parametrize(("segundos", "aceptada"), [(-30, True), (-31, False)])
def test_tolera_hasta_30_s_de_desfase_antes_del_inicio(repo, servicio, segundos, aceptada):
    """El reloj del teléfono puede ir algunos segundos atrás del servidor (P06, Tabla 54)."""
    sesion = repo.agregar_sesion(uuid4())
    posicion = lectura(segundos=segundos)
    if aceptada:
        assert servicio.recibir_lote(sesion.id, sesion.unidad_id, [posicion], AHORA).publicadas == 1
    else:
        with pytest.raises(ErrorDeNegocio):
            servicio.recibir_lote(sesion.id, sesion.unidad_id, [posicion], AHORA)


def test_la_sesion_empieza_a_la_hora_de_la_aplicacion_y_no_a_la_de_la_base(repo):
    """Todas las horas de las reglas salen del mismo reloj: el de la aplicación."""
    capturado = {}

    class Espia(EmisionEnMemoria):
        def abrir_sesion(self, unidad_id, cuenta_id, ramal, sentido, inicio):
            capturado["inicio"] = inicio
            return super().abrir_sesion(unidad_id, cuenta_id, ramal, sentido, inicio)

    espia = Espia()
    unidad = uuid4()
    espia.unidades[unidad] = True
    ServicioEmision(espia, ValidadorPosiciones()).abrir_sesion(
        unidad, uuid4(), Ramal.CERRILLO, Sentido.IDA, AHORA
    )
    assert capturado["inicio"] == AHORA
