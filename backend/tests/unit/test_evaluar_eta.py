"""Evaluación del ETA con viajes reales (Módulo 7): se prueba con viajes sintéticos."""

from datetime import UTC, datetime, timedelta

import pytest

from app.domain.modelos import Ramal, Sentido
from app.herramientas.evaluar_eta import (
    SOLO_GPS,
    Contraste,
    Lectura,
    ParaderoDeViaje,
    Viaje,
    escribir_csv,
    informe,
    llegadas_reales,
    por_horizonte,
    reproducir,
    resumir,
)

INICIO = datetime(2026, 11, 3, 11, 0, tzinfo=UTC)  # 06:00 en Lima
PARADEROS = [
    ParaderoDeViaje("stp_001", "Santa Ana", 0.0, principal=True),
    ParaderoDeViaje("stp_002", "Plaza", 3000.0, principal=True),
    ParaderoDeViaje("stp_003", "Cruce", 6000.0),
]


def viaje(lecturas: list[Lectura]) -> Viaje:
    return Viaje("s1", "07", Ramal.MOLLEBAYA, Sentido.IDA, "Centro", PARADEROS, lecturas)


def a_velocidad_constante(kmh: float, hasta_m: float, cada_s: int = 5) -> list[Lectura]:
    ms = kmh / 3.6
    pasos = int(hasta_m / ms / cada_s) + 1
    return [
        Lectura(INICIO + timedelta(seconds=i * cada_s), i * cada_s * ms, kmh) for i in range(pasos)
    ]


def test_la_llegada_se_interpola_entre_dos_posiciones():
    lecturas = [Lectura(INICIO, 2900, 36), Lectura(INICIO + timedelta(seconds=20), 3100, 36)]
    llegadas = llegadas_reales(lecturas, PARADEROS)
    # 100 de 200 m: a mitad de camino entre las dos posiciones
    assert llegadas == {"stp_002": INICIO + timedelta(seconds=10)}


def test_el_paradero_inicial_y_los_no_alcanzados_no_se_cronometran():
    llegadas = llegadas_reales(a_velocidad_constante(36, 4000), PARADEROS)
    assert set(llegadas) == {"stp_002"}


def test_a_velocidad_constante_el_eta_es_exacto():
    contrastes = reproducir(viaje(a_velocidad_constante(36, 6500)))
    r = resumir(contrastes)
    assert r is not None and r.n > 0
    assert r.mae_s < 6  # solo el redondeo y el paso de 5 s
    assert r.aciertos == 1.0
    # Una estimación por minuto y por paradero que queda por delante
    assert {c.paradero.codigo for c in contrastes} == {"stp_002", "stp_003"}


def test_una_parada_larga_hace_que_la_combi_llegue_tarde():
    """La app no sabe que la combi se quedará 3 minutos recogiendo pasajeros."""
    antes = a_velocidad_constante(36, 1000)
    parada = [
        Lectura(antes[-1].en + timedelta(seconds=5 * (i + 1)), antes[-1].recorrido_m, 0.0)
        for i in range(36)
    ]
    ms = 10.0
    t0, r0 = parada[-1].en, parada[-1].recorrido_m
    despues = [
        Lectura(t0 + timedelta(seconds=5 * (i + 1)), r0 + ms * 5 * (i + 1), 36.0)
        for i in range(530)
    ]
    contrastes = reproducir(viaje(antes + parada + despues))
    primera = next(c for c in contrastes if c.paradero.codigo == "stp_002")
    # Al salir de Santa Ana: 3000 m a 36 km/h = 300 s, pero tardó 3 min más
    assert primera.estimado_en == INICIO
    assert primera.eta_s == pytest.approx(300, abs=5)
    assert primera.error_s == pytest.approx(-180, abs=5)
    # Con la combi detenida, el estimador de la 0.7.2 (solo GPS) anunciaba de más: la
    # velocidad caía al mínimo de 5 km/h. Con la ventana de 10 min el error baja (D-21).
    detenida = [c for c in contrastes if parada[3].en <= c.estimado_en <= t0]
    viejo = reproducir(viaje(antes + parada + despues), umbrales=SOLO_GPS)
    detenida_vieja = [c for c in viejo if parada[3].en <= c.estimado_en <= t0]
    assert detenida_vieja and all(c.error_s > 0 for c in detenida_vieja)
    assert resumir(detenida).mae_s < resumir(detenida_vieja).mae_s / 2


def test_no_se_evaluan_llegadas_que_la_app_no_muestra():
    """RN-007: a 5 km/h, 6 km son 72 min; la app no muestra llegadas de más de 60."""
    lecturas = a_velocidad_constante(5, 7000, cada_s=30)
    contrastes = reproducir(viaje(lecturas))
    assert all(c.eta_s <= 3600 for c in contrastes)


def test_por_horizonte_agrupa_segun_lo_que_faltaba():
    def c(real_min: float, error_min: float) -> Contraste:
        return Contraste(
            "s1", "07", "MOLLEBAYA-IDA", PARADEROS[1], INICIO, 1000,
            (real_min + error_min) * 60, real_min * 60,
        )  # fmt: skip

    filas = dict(por_horizonte([c(3, 1), c(4, -1), c(15, 4)]))
    assert filas["0–5 min"].n == 2 and filas["0–5 min"].mae_s == 60
    assert filas["10–20 min"].n == 1 and filas["10–20 min"].aciertos == 0
    assert filas["40–60 min"] is None


def test_informe_y_hoja_de_contraste(tmp_path):
    v = viaje(a_velocidad_constante(36, 6500))
    contrastes = reproducir(v)
    texto = informe([v], contrastes)
    assert "| 03/11 06:00 | 07 | MOLLEBAYA-IDA |" in texto
    assert "| Paraderos principales |" in texto

    ruta = tmp_path / "contraste.csv"
    escribir_csv(str(ruta), contrastes)
    filas = ruta.read_text(encoding="utf-8-sig").splitlines()
    assert filas[0].startswith("sesion;unidad;variante;paradero")
    assert len(filas) == len(contrastes) + 1
    assert ";Plaza;sí;2026-11-03 06:" in filas[1]
