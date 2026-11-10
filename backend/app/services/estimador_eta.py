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
    """ETA = distancia restante sobre el trazado ÷ velocidad reciente.

    1. Distancia restante: distancia acumulada del paradero menos lo que la unidad
       ya recorrió, ambas medidas sobre el trazado y no en línea recta.
    2. Velocidad: lo que la unidad avanzó de verdad sobre la ruta en los últimos
       10 minutos, paradas incluidas. Si todavía no hay un minuto de historia, el
       promedio de la velocidad del GPS en las últimas posiciones. En ambos casos con
       un mínimo de 5 km/h, para que una unidad detenida no divida entre cero.
       (Hasta la 0.7.2 se usaba solo el GPS de los últimos 20 s; en el piloto del
       10/11/2026 eso dio un error medio de 18 min frente a 2,5 min con la ventana: D-21.)
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

    def velocidad_de_avance_kmh(self, candidato: CandidatoLlegada) -> float | None:
        """Avance sobre la ruta ÷ tiempo, en la ventana reciente; None si hay poca historia."""
        duracion = candidato.duracion_ventana_s
        if candidato.avance_ventana_m is None or duracion is None:
            return None
        if duracion < self._u.ventana_minima_s:
            return None
        return max(candidato.avance_ventana_m, 0.0) / duracion * 3.6

    def estimar(self, candidato: CandidatoLlegada, ahora: datetime) -> EstimacionLlegada:
        restante_m = max(candidato.distancia_paradero_m - candidato.distancia_recorrida_m, 0.0)
        de_avance = self.velocidad_de_avance_kmh(candidato)
        velocidad_kmh = (
            max(de_avance, self._u.velocidad_minima_kmh)
            if de_avance is not None
            else self.velocidad_estimada_kmh(candidato.velocidades_recientes_kmh)
        )
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
