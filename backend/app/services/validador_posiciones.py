"""Validador de posiciones (RF-019, P05 Figura 25).

Decide si una lectura GPS se publica o se descarta, y por qué. Es una pieza pura:
no consulta la base de datos. La distancia al trazado y la distancia recorrida le
llegan ya medidas con PostGIS, de modo que la regla puede probarse aislada.

Las reglas se evalúan de la más barata a la más costosa, y la primera que falla
define el motivo del descarte:

1. PRECISION_INSUFICIENTE — el GPS informa un radio de error mayor a 50 m.
2. FUERA_DE_CORREDOR      — a más de 150 m del trazado de la variante (RN-003).
3. DUPLICADA              — mismo instante que la última posición válida, o
                            anterior a ella (lectura repetida o llegada fuera de
                            orden: ya no aporta información nueva al mapa).
4. VELOCIDAD_IMPOSIBLE    — para llegar desde la posición anterior habría
                            tenido que ir a más de 90 km/h (RN-004).
"""

from app.domain.geo import distancia_m
from app.domain.modelos import (
    MedicionTrazado,
    MotivoDescarte,
    PosicionEntrante,
    ReferenciaPosicion,
    ResultadoValidacion,
)
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales

VALIDA = ResultadoValidacion(valida=True)


class ValidadorPosiciones:
    def __init__(self, umbrales: Umbrales = UMBRALES_POR_DEFECTO) -> None:
        self._u = umbrales

    def velocidad_implicita_kmh(
        self, anterior: ReferenciaPosicion, posicion: PosicionEntrante
    ) -> float | None:
        """Velocidad necesaria para ir de la posición anterior a la nueva.

        Devuelve None si no transcurrió tiempo (ese caso lo resuelve la regla de duplicado).
        """
        segundos = (posicion.capturada_en - anterior.capturada_en).total_seconds()
        if segundos <= 0:
            return None
        metros = distancia_m(anterior.ubicacion, posicion.ubicacion)
        return metros / segundos * 3.6

    def validar(
        self,
        posicion: PosicionEntrante,
        medicion: MedicionTrazado,
        anterior: ReferenciaPosicion | None,
    ) -> ResultadoValidacion:
        if posicion.precision_m > self._u.precision_maxima_m:
            return ResultadoValidacion(False, MotivoDescarte.PRECISION_INSUFICIENTE)

        if medicion.distancia_al_trazado_m > self._u.tolerancia_corredor_m:
            return ResultadoValidacion(False, MotivoDescarte.FUERA_DE_CORREDOR)

        if anterior is None:
            return VALIDA

        if posicion.capturada_en <= anterior.capturada_en:
            return ResultadoValidacion(False, MotivoDescarte.DUPLICADA)

        velocidad = self.velocidad_implicita_kmh(anterior, posicion)
        if velocidad is not None and velocidad > self._u.velocidad_maxima_kmh:
            return ResultadoValidacion(False, MotivoDescarte.VELOCIDAD_IMPOSIBLE)

        return VALIDA
