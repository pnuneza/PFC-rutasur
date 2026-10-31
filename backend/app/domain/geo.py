"""Cálculos geográficos simples que no necesitan la base de datos."""

from math import asin, cos, radians, sin, sqrt

from app.domain.modelos import Coordenada

RADIO_TERRESTRE_M = 6_371_008.8  # radio medio de la Tierra (WGS 84)


def distancia_m(a: Coordenada, b: Coordenada) -> float:
    """Distancia en metros entre dos puntos, por la fórmula del semiverseno (haversine).

    Para tramos cortos como los que separan dos lecturas GPS consecutivas, su error
    frente al cálculo geodésico de PostGIS es menor a un metro.
    """
    lat1, lon1, lat2, lon2 = map(radians, (a.lat, a.lon, b.lat, b.lon))
    h = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 2 * RADIO_TERRESTRE_M * asin(sqrt(h))
