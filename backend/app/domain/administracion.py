"""Objetos del panel de administración (CU-13 a CU-17, P06 Tabla 46).

Las cuentas no tienen ningún dato personal: solo usuario, rol o unidad y estado (RN-011,
RNF-15). La contraseña temporal se entrega una sola vez y nunca se guarda en claro.
"""

from dataclasses import dataclass
from datetime import datetime, time
from enum import StrEnum
from uuid import UUID

from app.domain.modelos import Coordenada, Ramal, Rol, Sentido


class EstadoUnidad(StrEnum):
    """Estado de cada unidad en A-02 (RF-017)."""

    TRANSMITIENDO = "TRANSMITIENDO"  # sesión abierta y posición válida hace 90 s o menos
    SIN_SENAL = "SIN_SENAL"  # sesión abierta, pero más de 90 s sin posiciones válidas
    INACTIVA = "INACTIVA"  # sin sesión abierta


class AccionCuenta(StrEnum):
    """Acciones de A-04 sobre una cuenta existente."""

    RESTABLECER_CONTRASENA = "RESET_PASSWORD"
    DESACTIVAR = "DEACTIVATE"
    ACTIVAR = "ACTIVATE"
    DESBLOQUEAR = "UNLOCK"


# ----------------------------------------------------------------------
# A-02 Estado de la flota
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class UnidadDeFlota:
    """Fila cruda del repositorio: la unidad y su sesión abierta, si la tiene."""

    unidad_id: UUID
    etiqueta: str
    usuario: str | None
    creada_en: datetime
    ultimo_fin: datetime | None
    sesion_inicio: datetime | None
    ultima_posicion_en: datetime | None
    ubicacion: Coordenada | None
    rumbo: int | None
    ramal: Ramal | None
    sentido: Sentido | None
    destino: str | None


@dataclass(frozen=True, slots=True)
class EstadoDeUnidad:
    fila: UnidadDeFlota
    estado: EstadoUnidad
    desde: datetime
    antiguedad_s: int | None


# ----------------------------------------------------------------------
# A-03 Rutas y paraderos
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Horario:
    inicio: time
    fin: time


@dataclass(frozen=True, slots=True)
class ParaderoAdmin:
    codigo: str
    nombre: str
    referencia: str | None
    ubicacion: Coordenada
    en_tramo_comun: bool
    activo: bool
    variantes: list[str]  # «MOLLEBAYA-IDA», …
    principal: bool = False  # se ve con el mapa alejado


@dataclass(frozen=True, slots=True)
class DatosParadero:
    """Lo que el formulario A-03a envía para crear o editar un paradero."""

    nombre: str
    referencia: str | None
    ubicacion: Coordenada
    en_tramo_comun: bool
    principal: bool = False


# ----------------------------------------------------------------------
# A-04 Unidades y cuentas
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class UnidadAdmin:
    id: UUID
    etiqueta: str
    activa: bool
    usuario: str | None
    creada_en: datetime


@dataclass(frozen=True, slots=True)
class CuentaAdmin:
    """Cuenta de conductor (con su unidad) o del panel (con su rol)."""

    id: UUID
    usuario: str
    rol: Rol
    activa: bool
    bloqueada_hasta: datetime | None
    etiqueta_unidad: str | None = None


@dataclass(frozen=True, slots=True)
class CuentaConClave:
    """Respuesta de crear o restablecer: la contraseña temporal se muestra una sola vez."""

    cuenta: CuentaAdmin
    contrasena_temporal: str


# ----------------------------------------------------------------------
# A-05 Registro de eventos
# ----------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class FiltroEventos:
    desde: datetime
    hasta: datetime
    tipo: str | None
    etiqueta_unidad: str | None
    pagina: int
    tamano: int


@dataclass(frozen=True, slots=True)
class Evento:
    id: int
    fecha: datetime
    tipo: str
    origen: str
    etiqueta_unidad: str | None
    usuario_panel: str | None
    codigo_http: int | None
    detalle: dict | None


@dataclass(frozen=True, slots=True)
class PaginaEventos:
    eventos: list[Evento]
    total: int
