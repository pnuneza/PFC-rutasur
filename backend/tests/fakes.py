"""Repositorios en memoria para probar las reglas de negocio sin base de datos.

Cumplen las mismas interfaces que los repositorios SQL (repositories/interfaces.py):
es lo que permite el patrón Repositorio decidido en P05 (Tabla 38).
"""

from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from app.domain.modelos import (
    CandidatoLlegada,
    Coordenada,
    EstadoSesion,
    MedicionTrazado,
    ParaderoEncontrado,
    PosicionValidada,
    Ramal,
    ReferenciaPosicion,
    Sentido,
    SesionEmision,
    UnidadEnServicio,
)

T0 = datetime(2026, 10, 20, 13, 0, 0, tzinfo=UTC)


class RutasEnMemoria:
    def __init__(self, paraderos_activos: set[str] | None = None) -> None:
        self.paraderos_activos = paraderos_activos or set()

    def obtener_linea(self, codigo: str):
        return None

    def buscar_paraderos(self, texto: str, limite: int) -> list[ParaderoEncontrado]:
        return []

    def existe_paradero_activo(self, codigo: str) -> bool:
        return codigo in self.paraderos_activos


class FlotaEnMemoria:
    def __init__(
        self,
        candidatos: list[CandidatoLlegada] | None = None,
        unidades: list[UnidadEnServicio] | None = None,
    ) -> None:
        self.candidatos = candidatos or []
        self.unidades = unidades or []

    def listar_unidades_en_servicio(self, ramal: Ramal | None) -> list[UnidadEnServicio]:
        return [u for u in self.unidades if ramal is None or u.ramal == ramal]

    def candidatos_llegada(
        self, codigo_paradero: str, n_velocidades: int
    ) -> list[CandidatoLlegada]:
        return self.candidatos


class EmisionEnMemoria:
    """Simula sesiones y posiciones. La distancia al trazado se fija por prueba."""

    def __init__(self) -> None:
        self.unidades: dict[UUID, bool] = {}
        self.sesiones: dict[UUID, SesionEmision] = {}
        self.posiciones: dict[UUID, PosicionValidada] = {}
        self.ultima: dict[UUID, tuple[PosicionValidada, float]] = {}
        self.eventos: list[tuple[str, dict[str, Any]]] = []
        self.distancia_al_trazado_m = 10.0

    # sesiones
    def agregar_sesion(
        self, unidad_id: UUID, estado: EstadoSesion = EstadoSesion.ACTIVA
    ) -> SesionEmision:
        sesion = SesionEmision(uuid4(), unidad_id, uuid4(), estado, T0)
        self.unidades.setdefault(unidad_id, True)
        self.sesiones[sesion.id] = sesion
        return sesion

    def obtener_sesion(self, sesion_id: UUID) -> SesionEmision | None:
        return self.sesiones.get(sesion_id)

    def unidad_activa(self, unidad_id: UUID) -> bool | None:
        return self.unidades.get(unidad_id)

    def abrir_sesion(
        self, unidad_id: UUID, cuenta_id: UUID, ramal: Ramal, sentido: Sentido, inicio: datetime
    ) -> SesionEmision:
        return self.agregar_sesion(unidad_id)

    def cerrar_sesion(self, sesion_id: UUID, estado: EstadoSesion) -> None:
        s = self.sesiones[sesion_id]
        self.sesiones[sesion_id] = SesionEmision(s.id, s.unidad_id, s.variante_id, estado, s.inicio)

    # posiciones
    def ids_registrados(self, ids: Sequence[UUID]) -> set[UUID]:
        return {i for i in ids if i in self.posiciones}

    def medir_contra_trazado(
        self, variante_id: UUID, puntos: Sequence[Coordenada]
    ) -> list[MedicionTrazado]:
        # Distancia recorrida proporcional a la latitud, suficiente para las pruebas
        return [
            MedicionTrazado(self.distancia_al_trazado_m, abs(p.lat + 16.0) * 111_000)
            for p in puntos
        ]

    def ultima_posicion_valida(self, sesion_id: UUID) -> ReferenciaPosicion | None:
        validas = [v.posicion for v in self.posiciones.values() if v.resultado.valida]
        if not validas:
            return None
        p = max(validas, key=lambda x: x.capturada_en)
        return ReferenciaPosicion(p.ubicacion, p.capturada_en)

    def guardar_posiciones(self, sesion_id: UUID, posiciones: Sequence[PosicionValidada]) -> None:
        for v in posiciones:
            self.posiciones.setdefault(v.posicion.id, v)

    def actualizar_ultima_posicion(
        self, sesion_id: UUID, posicion: PosicionValidada, distancia_recorrida_m: float
    ) -> None:
        self.ultima[sesion_id] = (posicion, distancia_recorrida_m)

    def registrar_evento(
        self, tipo: str, origen: str, unidad_id: UUID | None, detalle: dict[str, Any]
    ) -> None:
        self.eventos.append((tipo, detalle))
