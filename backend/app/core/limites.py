"""Límite de peticiones por ventana deslizante (P05 Tabla 34, P06 §2.15.2).

- 60 envíos de posiciones por minuto y por unidad. Cuenta peticiones, no posiciones,
  para que el reenvío de la cola acumulada tras perder señal no sea rechazado.
- 10 intentos de ingreso por minuto y por dirección de origen, además del bloqueo de
  la cuenta a los cinco fallos: frena a quien prueba muchos usuarios distintos.

Vive en memoria. Alcanza porque en Render corre una sola instancia del servicio; si
algún día hubiera varias, cada una contaría por separado y habría que llevarlo a la base.
"""

import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from math import ceil

from app.domain.excepciones import LimiteExcedido


class LimitadorVentana:
    def __init__(
        self, maximo: int, ventana_s: float, reloj: Callable[[], float] = time.monotonic
    ) -> None:
        self._maximo = maximo
        self._ventana = ventana_s
        self._reloj = reloj
        self._marcas: dict[str, deque[float]] = defaultdict(deque)
        self._candado = threading.Lock()  # las operaciones síncronas corren en varios hilos

    def registrar(self, clave: str) -> None:
        """Cuenta una petición o lanza LimiteExcedido con los segundos que faltan."""
        ahora = self._reloj()
        with self._candado:
            marcas = self._marcas[clave]
            while marcas and marcas[0] <= ahora - self._ventana:
                marcas.popleft()
            if len(marcas) >= self._maximo:
                espera = max(1, ceil(marcas[0] + self._ventana - ahora))
                raise LimiteExcedido(
                    f"Demasiadas peticiones; vuelva a intentar en {espera} s", espera
                )
            marcas.append(ahora)
            if len(self._marcas) > 10_000:  # evita crecer sin fin con claves viejas
                self._limpiar(ahora)

    def _limpiar(self, ahora: float) -> None:
        for clave in [
            k for k, m in self._marcas.items() if not m or m[-1] <= ahora - self._ventana
        ]:
            del self._marcas[clave]
