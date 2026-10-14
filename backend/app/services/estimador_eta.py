"""Estimador del tiempo estimado de llegada (RF-018).

Patrón Estrategia (P05, sección 2.7.2 y Tabla 38): el servicio de llegadas solo
conoce la interfaz `EstimadorETA`. Hoy existe una implementación,
`EstimadorDirecto`; un método distinto se agregaría creando otra clase que cumpla
la interfaz, sin modificar ninguna otra parte del sistema.
"""

from datetime import datetime
from statistics import fmean
from typing import Protocol

from app.domain.modelos import CandidatoLlegada, EstimacionLlegada
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales

KMH_A_MS = 1 / 3.6


class EstimadorETA(Protocol):
    """Interfaz del cálculo del ETA."""

    def estimar(self, candidato: CandidatoLlegada, ahora: datetime) -> EstimacionLlegada: ...


class EstimadorDirecto:
    """ETA = distancia restante sobre el trazado ÷ velocidad promedio reciente.

    1. Distancia restante: distancia acumulada del paradero menos lo que la unidad
       ya recorrió, ambas medidas sobre el trazado y no en línea recta.
    2. Velocidad: promedio de las últimas posiciones válidas, con un mínimo de
       5 km/h para que una unidad detenida no produzca una división entre cero.
    3. Confiabilidad: el dato deja de ser confiable si la última posición tiene
       más de 90 s (RN-005).
    """

    def __init__(self, umbrales: Umbrales = UMBRALES_POR_DEFECTO) -> None:
        self._u = umbrales

    def velocidad_estimada_kmh(self, velocidades_kmh: list[float | None]) -> float:
        """Promedio de las velocidades conocidas, nunca menor que la mínima."""
        conocidas = [v for v in velocidades_kmh if v is not None]
        promedio = fmean(conocidas) if conocidas else 0.0
        return max(promedio, self._u.velocidad_minima_kmh)

    def estimar(self, candidato: CandidatoLlegada, ahora: datetime) -> EstimacionLlegada:
        restante_m = max(candidato.distancia_paradero_m - candidato.distancia_recorrida_m, 0.0)
        velocidad_kmh = self.velocidad_estimada_kmh(candidato.velocidades_recientes_kmh)
        eta_s = restante_m / (velocidad_kmh * KMH_A_MS)

        antiguedad_s = max(int((ahora - candidato.ultima_posicion_en).total_seconds()), 0)

        return EstimacionLlegada(
            etiqueta=candidato.etiqueta,
            ramal=candidato.ramal,
            destino=candidato.destino,
            eta_s=round(eta_s),
            distancia_m=round(restante_m),
            antiguedad_s=antiguedad_s,
            confiable=antiguedad_s <= self._u.frescura_demorada_s,
        )
