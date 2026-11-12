"""Reproducción de viajes reales: horario de envío, formato y corte de la sesión."""

import argparse
import json
from datetime import UTC, datetime, timedelta

import pytest

from app.domain.modelos import Ramal, Sentido
from app.herramientas.reproducir_viaje import (
    LecturaGrabada,
    ReproductorViaje,
    ViajeGrabado,
    _argumentos,
    cargar_viaje,
    lectura_a_json,
    programa,
    viaje_a_json,
)
from app.herramientas.simular_unidad import ErrorApi

HORA = datetime(2026, 11, 12, 22, 25, tzinfo=UTC)  # 17:25 en Lima


def lectura(t: float, velocidad: float | None = 20.0) -> LecturaGrabada:
    return LecturaGrabada(t, -16.47 + t / 1e5, -71.48, velocidad, 315, 4.0)


def viaje(tiempos: list[float]) -> ViajeGrabado:
    return ViajeGrabado(
        Ramal.MOLLEBAYA, Sentido.IDA, "2026-11-10", tuple(lectura(t) for t in tiempos)
    )


def args(**cambios) -> argparse.Namespace:
    base = {
        "api": "https://api.prueba",
        "usuario": "unidad07",
        "desde_minuto": 0.0,
        "rapidez": 1.0,
        "lote": 3,
    }
    return argparse.Namespace(**(base | cambios))


# ----------------------------------------------------------------------
# Archivo del viaje
# ----------------------------------------------------------------------
def test_el_viaje_se_guarda_y_se_lee_igual(tmp_path):
    original = viaje([5.0, 10.0, 15.0])
    ruta = tmp_path / "viaje.json"
    ruta.write_text(json.dumps(viaje_a_json(original)), encoding="utf-8")
    assert cargar_viaje(ruta) == original


def test_las_lecturas_se_ordenan_y_los_campos_vacios_se_aceptan(tmp_path):
    datos = viaje_a_json(viaje([10.0, 5.0]))
    datos["lecturas"][0]["speed_kmh"] = None
    datos["lecturas"][0]["heading"] = None
    ruta = tmp_path / "viaje.json"
    ruta.write_text(json.dumps(datos), encoding="utf-8")
    cargado = cargar_viaje(ruta)
    assert [x.t for x in cargado.lecturas] == [5.0, 10.0]
    assert cargado.lecturas[1].velocidad_kmh is None
    assert cargado.duracion_s == 5.0


@pytest.mark.parametrize(
    "contenido",
    [
        "no es json",
        json.dumps({"ramal": "MOLLEBAYA", "sentido": "IDA"}),  # sin lecturas
        json.dumps({"ramal": "YURA", "sentido": "IDA", "lecturas": []}),  # ramal inexistente
        json.dumps({"ramal": "MOLLEBAYA", "sentido": "IDA", "lecturas": []}),  # vacío
    ],
)
def test_un_archivo_que_no_sirve_se_explica(tmp_path, contenido):
    ruta = tmp_path / "viaje.json"
    ruta.write_text(contenido, encoding="utf-8")
    with pytest.raises(SystemExit, match="viaje"):
        cargar_viaje(ruta)


# ----------------------------------------------------------------------
# Horario de envío
# ----------------------------------------------------------------------
def test_el_programa_conserva_los_intervalos_reales():
    plan = programa(viaje([4.7, 9.7, 30.0, 35.0]))
    assert [round(s, 1) for s, _ in plan] == [0.0, 5.0, 25.3, 30.3]


def test_desde_minuto_omite_el_principio_y_rapidez_acorta_las_esperas():
    v = viaje([0.0, 60.0, 120.0, 125.0, 185.0])
    plan = programa(v, desde_minuto=2, rapidez=2)
    assert [x.t for _, x in plan] == [120.0, 125.0, 185.0]
    assert [s for s, _ in plan] == [0.0, 2.5, 32.5]


def test_si_no_quedan_lecturas_el_programa_esta_vacio_y_la_rapidez_debe_ser_positiva():
    assert programa(viaje([0.0, 5.0]), desde_minuto=10) == []
    with pytest.raises(ValueError):
        programa(viaje([0.0]), rapidez=0)


def test_cada_lectura_sale_como_la_app_del_conductor():
    json_ = lectura_a_json(lectura(5.0, velocidad=30.0), HORA, rapidez=2)
    assert json_["captured_at"] == HORA.isoformat()
    assert json_["speed_kmh"] == 60.0  # al doble de rapidez, el doble de velocidad
    assert (json_["heading"], json_["accuracy_m"]) == (315, 4.0)
    otra = lectura_a_json(lectura(5.0, velocidad=None), HORA)
    assert otra["speed_kmh"] is None
    assert otra["id"] != json_["id"]  # id nuevo: el servidor no la toma por duplicada
    # La API no admite más de 200 km/h
    assert lectura_a_json(lectura(5.0, velocidad=120.0), HORA, rapidez=4)["speed_kmh"] == 200.0


# ----------------------------------------------------------------------
# Reproducción con reloj falso
# ----------------------------------------------------------------------
class RelojFalso:
    def __init__(self) -> None:
        self.segundos = 1000.0
        self.esperas: list[float] = []

    def __call__(self) -> float:
        return self.segundos

    def dormir(self, s: float) -> None:
        self.esperas.append(round(s, 3))
        self.segundos += s


class ReproductorDePrueba(ReproductorViaje):
    """Responde como la API sin red: confirma todo o corta la sesión al n-ésimo envío."""

    def __init__(self, v: ViajeGrabado, cortar_en: int | None = None, **cambios) -> None:
        self.reloj = RelojFalso()
        super().__init__(
            args(**cambios), v, reloj=self.reloj, dormir=self.reloj.dormir, ahora=lambda: HORA
        )
        self.lotes: list[list[dict]] = []
        self.cortar_en = cortar_en

    def _pedir(self, metodo, ruta, cuerpo=None):
        assert ruta == "/sessions/s1/positions"
        self.lotes.append(list(cuerpo["positions"]))
        if self.cortar_en == len(self.lotes):
            raise ErrorApi(409, "SESSION_NOT_ACTIVE", "La sesión ya no está activa")
        ids = [p["id"] for p in cuerpo["positions"]]
        return {"data": {"confirmed": ids, "published": len(ids), "discarded": 0, "duplicates": 0}}


def test_envia_en_lotes_a_su_hora_y_con_la_hora_de_ahora():
    r = ReproductorDePrueba(viaje([0.0, 5.0, 10.0, 15.0, 20.0, 40.0, 45.0]))
    assert r.recorrer("s1") is True
    # Lotes de 3 y el resto al final; nada queda en la cola
    assert [len(lote) for lote in r.lotes] == [3, 3, 1]
    assert r.cola == []
    # Espera los intervalos reales, incluida la parada de 20 s
    assert r.reloj.esperas == [5, 5, 5, 5, 20, 5]
    horas = [p["captured_at"] for lote in r.lotes for p in lote]
    esperadas = [HORA + timedelta(seconds=s) for s in (0, 5, 10, 15, 20, 40, 45)]
    assert horas == [h.isoformat() for h in esperadas]


def test_si_un_envio_se_demora_no_se_acumula_el_retraso():
    r = ReproductorDePrueba(viaje([0.0, 5.0, 10.0, 15.0, 20.0, 25.0]))

    def pedir_lento(metodo, ruta, cuerpo=None):
        r.reloj.segundos += 7  # la red tarda 7 s
        return ReproductorDePrueba._pedir(r, metodo, ruta, cuerpo)

    r._pedir = pedir_lento
    r.recorrer("s1")
    # Tras el envío lento de t=10, la lectura de t=15 sale de inmediato (ya tocaba)
    assert r.reloj.esperas == [5, 5, 3, 5]
    horas = [p["captured_at"] for lote in r.lotes for p in lote]
    assert horas[3] == (HORA + timedelta(seconds=15)).isoformat()


def test_si_el_servidor_cierra_la_sesion_se_detiene():
    r = ReproductorDePrueba(viaje([float(t) for t in range(0, 60, 5)]), cortar_en=2)
    assert r.recorrer("s1") is False
    assert len(r.lotes) == 2


def test_empezar_despues_del_final_no_envia_nada():
    r = ReproductorDePrueba(viaje([0.0, 5.0]), desde_minuto=5)
    assert r.recorrer("s1") is True
    assert r.lotes == []


# ----------------------------------------------------------------------
# Línea de comandos
# ----------------------------------------------------------------------
def test_los_argumentos_se_validan():
    a = _argumentos(
        ["reproducir", "--api", "https://x", "--usuario", "u", "--viaje", "v.json",
         "--desde-minuto", "10", "--rapidez", "2"]
    )  # fmt: skip
    assert (a.desde_minuto, a.rapidez, a.lote) == (10.0, 2.0, 3)
    with pytest.raises(SystemExit):
        _argumentos(
            ["reproducir", "--api", "x", "--usuario", "u", "--viaje", "v", "--rapidez", "3"]
        )
    with pytest.raises(SystemExit):
        _argumentos(["exportar", "--sesion", "s"])  # falta --salida
