"""Interfaces de los repositorios (IRepositorios en P06, Figura 43).

Los servicios de negocio solo conocen estos contratos. En producción se cumplen
con las implementaciones SQL; en las pruebas unitarias, con repositorios en
memoria. Es el patrón Repositorio con inyección de dependencias (P05, Tabla 38).
"""

from collections.abc import Sequence
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

from app.domain.modelos import (
    CandidatoLlegada,
    Coordenada,
    CuentaAcceso,
    EstadoSesion,
    LineaRuta,
    MedicionTrazado,
    ParaderoEncontrado,
    PosicionValidada,
    Ramal,
    ReferenciaPosicion,
    Rol,
    Sentido,
    SesionEmision,
    UnidadEnServicio,
)


class RepositorioRutas(Protocol):
    def obtener_linea(self, codigo: str) -> LineaRuta | None: ...

    def buscar_paraderos(self, texto: str, limite: int) -> list[ParaderoEncontrado]: ...

    def existe_paradero_activo(self, codigo: str) -> bool: ...


class RepositorioFlota(Protocol):
    def listar_unidades_en_servicio(self, ramal: Ramal | None) -> list[UnidadEnServicio]: ...

    def candidatos_llegada(
        self, codigo_paradero: str, n_velocidades: int
    ) -> list[CandidatoLlegada]: ...


class RepositorioEmision(Protocol):
    def obtener_sesion(self, sesion_id: UUID) -> SesionEmision | None: ...

    def unidad_activa(self, unidad_id: UUID) -> bool | None: ...

    def abrir_sesion(
        self, unidad_id: UUID, cuenta_id: UUID, ramal: Ramal, sentido: Sentido, inicio: datetime
    ) -> SesionEmision: ...

    def cerrar_sesion(self, sesion_id: UUID, estado: EstadoSesion) -> None: ...

    def ids_registrados(self, ids: Sequence[UUID]) -> set[UUID]: ...

    def medir_contra_trazado(
        self, variante_id: UUID, puntos: Sequence[Coordenada]
    ) -> list[MedicionTrazado]: ...

    def ultima_posicion_valida(self, sesion_id: UUID) -> ReferenciaPosicion | None: ...

    def guardar_posiciones(
        self, sesion_id: UUID, posiciones: Sequence[PosicionValidada]
    ) -> None: ...

    def actualizar_ultima_posicion(
        self, sesion_id: UUID, posicion: PosicionValidada, distancia_recorrida_m: float
    ) -> None: ...

    def registrar_evento(
        self, tipo: str, origen: str, unidad_id: UUID | None, detalle: dict[str, Any]
    ) -> None: ...


class RepositorioCuentas(Protocol):
    def buscar_por_usuario(self, usuario: str) -> CuentaAcceso | None: ...

    def registrar_fallo(
        self, cuenta: CuentaAcceso, intentos_maximos: int, bloquear_hasta: datetime
    ) -> bool:
        """Suma un intento fallido; al llegar al máximo bloquea. Devuelve si quedó bloqueada."""
        ...

    def registrar_ingreso(self, cuenta: CuentaAcceso) -> None: ...

    def cuenta_vigente(self, cuenta_id: UUID, rol: Rol) -> bool:
        """La cuenta sigue activa (y, si es de conductor, también su unidad)."""
        ...

    def registrar_evento(
        self, tipo: str, origen: str, cuenta: CuentaAcceso | None, detalle: dict[str, Any]
    ) -> None: ...
