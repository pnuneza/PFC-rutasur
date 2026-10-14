"""Umbrales de las reglas de negocio.

P05 (sección 2.7.2) decidió que estos valores sean atributos configurables y no
números escritos dentro de la lógica, para poder ajustarlos durante el piloto sin
modificar el código de las reglas.
"""

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Umbrales:
    """Valores iniciales definidos en el diseño (P05 §2.7.2, P06 Tablas 50, 51 y 54)."""

    # Validación de posiciones (RF-019)
    tolerancia_corredor_m: float = 150.0  # RN-003: distancia máxima al trazado
    velocidad_maxima_kmh: float = 90.0  # RN-004: velocidad implícita máxima
    precision_maxima_m: float = 50.0  # umbral inicial de precisión del GPS
    tolerancia_reloj_s: int = 30  # captured_at no puede estar en el futuro

    # Estimación de llegada (RF-018)
    posiciones_para_velocidad: int = 4  # promedio de las últimas N posiciones válidas
    velocidad_minima_kmh: float = 5.0  # evita dividir entre cero con la unidad detenida
    eta_maximo_s: int = 3600  # RN-007: no se muestran llegadas de más de 60 min

    # Frescura del dato (RN-005, Figura 26 de P05)
    frescura_vigente_s: int = 30
    frescura_demorada_s: int = 90  # más allá: NO_CONFIABLE


UMBRALES_POR_DEFECTO = Umbrales()
