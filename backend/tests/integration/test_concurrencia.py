"""D-11: con 100 pasajeros a la vez el servicio se bloqueaba.

FastAPI atiende las operaciones síncronas con 40 hilos y el grupo solo tiene 10
conexiones. Sin el cupo asíncrono, los hilos esperaban conexiones que no se
liberaban (el cierre de sesión también necesita un hilo) hasta vencer la espera.
"""

import time
from concurrent.futures import ThreadPoolExecutor

import pytest

from app.db.conexion import capacidad_del_grupo

pytestmark = pytest.mark.integracion

PETICIONES = 100


def test_el_cupo_coincide_con_el_grupo_de_conexiones():
    assert capacidad_del_grupo() == 10  # 5 fijas + 5 adicionales por defecto


@pytest.mark.parametrize("ruta", ["/api/v1/vehicles", "/api/v1/health"])
def test_100_peticiones_simultaneas_responden_todas_y_sin_bloqueo(cliente_real, ruta):
    inicio = time.monotonic()
    with ThreadPoolExecutor(max_workers=PETICIONES) as hilos:
        codigos = list(hilos.map(lambda _: cliente_real.get(ruta).status_code, range(PETICIONES)))
    duracion = time.monotonic() - inicio

    assert codigos == [200] * PETICIONES
    # Antes del arreglo tardaba más de 30 s (vencimiento del grupo) y fallaba
    assert duracion < 15, f"{PETICIONES} peticiones tardaron {duracion:.1f} s"
