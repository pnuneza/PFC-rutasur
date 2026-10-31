"""Prueba de extremo a extremo: el recorrido completo de un pasajero.

Usa el grupo de conexiones real (sin transacción compartida), como en producción:
cada pantalla de la app es una petición independiente que abre y cierra su sesión.
"""

import pytest

pytestmark = [pytest.mark.e2e, pytest.mark.integracion]


def test_recorrido_del_pasajero_de_principio_a_fin(cliente_real):
    # 1. La app arranca y comprueba que el servicio responde
    assert cliente_real.get("/api/v1/health").json()["data"]["status"] == "ok"

    # 2. Descarga la línea y dibuja las variantes en el mapa
    linea = cliente_real.get("/api/v1/routes/lb").json()["data"]
    codigos_en_mapa = {p["code"] for v in linea["variants"] for p in v["stops"]}
    assert codigos_en_mapa

    # 3. Muestra las unidades en servicio
    unidades = cliente_real.get("/api/v1/vehicles").json()["data"]
    assert all(u["branch"] in {"MOLLEBAYA", "CERRILLO"} for u in unidades)

    # 4. El pasajero busca su paradero; el resultado está en el mapa
    resultado = cliente_real.get("/api/v1/stops", params={"q": "plaza"}).json()["data"]
    assert resultado and resultado[0]["code"] in codigos_en_mapa

    # 5. Abre las llegadas: solo aparecen unidades que están en el mapa
    llegadas = cliente_real.get(f"/api/v1/stops/{resultado[0]['code']}/arrivals").json()["data"]
    etiquetas = {u["vehicle_label"] for u in unidades}
    assert all(e["vehicle_label"] in etiquetas for e in llegadas)
