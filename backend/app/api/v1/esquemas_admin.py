"""DTO del panel de administración (P06 Tabla 46 y Tabla 66).

Ninguna entrada ni salida tiene campos para nombre, documento o teléfono (RN-011).
"""

from datetime import datetime, time
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field

from app.domain.administracion import AccionCuenta, EstadoUnidad
from app.domain.modelos import Ramal, Rol, Sentido

USUARIO = r"^[a-z0-9._]{4,30}$"


# --- A-02 Estado de la flota ---------------------------------------------
class UnidadFlotaDTO(BaseModel):
    vehicle_id: UUID
    vehicle_label: str = Field(examples=["07"])
    username: str | None = Field(description="Cuenta de conductor de la unidad")
    status: EstadoUnidad
    since: datetime = Field(description="Desde cuándo está en ese estado")
    last_position_age_s: int | None
    lat: float | None
    lon: float | None
    heading: int | None
    branch: Ramal | None
    direction: Sentido | None
    destination: str | None


class ResumenFlotaDTO(BaseModel):
    transmitting: int
    no_signal: int
    inactive: int


class FlotaDTO(BaseModel):
    summary: ResumenFlotaDTO
    vehicles: list[UnidadFlotaDTO]


# --- A-03 Rutas y paraderos ----------------------------------------------
class HorarioDTO(BaseModel):
    service_start: time = Field(examples=["05:00"])
    service_end: time = Field(examples=["21:00"])


class ParaderoDeVarianteAdminDTO(BaseModel):
    code: str
    name: str
    reference: str | None
    lat: float
    lon: float
    order: int
    distance_from_start_m: float
    shared_trunk: bool
    main: bool = False


class VarianteAdminDTO(BaseModel):
    id: UUID
    branch: Ramal
    direction: Sentido
    destination: str
    length_m: float
    shape: list[tuple[float, float]] = Field(description="Trazado como pares [lat, lon]")
    stops: list[ParaderoDeVarianteAdminDTO]


class ParaderosVarianteEntradaDTO(BaseModel):
    codes: list[str] = Field(
        min_length=2,
        max_length=200,
        description="Paraderos de la variante; el orden lo calcula el servidor desde el trazado",
    )


class ParaderoAdminDTO(BaseModel):
    code: str = Field(examples=["stp_004"])
    name: str
    reference: str | None
    lat: float
    lon: float
    shared_trunk: bool
    main: bool = Field(default=False, description="Paradero principal: se ve con el mapa alejado")
    active: bool
    variants: list[str] = Field(examples=[["MOLLEBAYA-IDA", "CERRILLO-IDA"]])


class ParaderoEntradaDTO(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    reference: str | None = Field(default=None, max_length=120)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    shared_trunk: bool = False
    main: bool = False


class ParaderoEdicionDTO(ParaderoEntradaDTO):
    active: bool = True


# --- A-04 Unidades y cuentas ---------------------------------------------
class UnidadAdminDTO(BaseModel):
    id: UUID
    label: str
    active: bool
    username: str | None
    created_at: datetime


class UnidadEntradaDTO(BaseModel):
    label: str = Field(pattern=r"^[A-Za-z0-9-]{1,20}$", examples=["15"])


class UnidadEstadoDTO(BaseModel):
    active: bool


class CuentaDTO(BaseModel):
    id: UUID
    username: str
    role: Rol
    active: bool
    locked_until: datetime | None
    vehicle_label: str | None


class CuentaConClaveDTO(BaseModel):
    account: CuentaDTO
    temporary_password: str = Field(
        description="Se muestra una sola vez: el servidor solo guarda su hash"
    )


class CuentaConductorEntradaDTO(BaseModel):
    vehicle_id: UUID
    username: str = Field(pattern=USUARIO, examples=["unidad15"])


class RolPanel(StrEnum):
    ADMINISTRADOR = "ADMINISTRADOR"
    MODERADOR = "MODERADOR"


class CuentaPanelEntradaDTO(BaseModel):
    username: str = Field(pattern=USUARIO, examples=["ana.moderadora"])
    role: RolPanel


class AccionCuentaDTO(BaseModel):
    action: AccionCuenta


class ResultadoAccionDTO(BaseModel):
    account: CuentaDTO
    temporary_password: str | None = Field(
        default=None, description="Solo al restablecer la contraseña"
    )


# --- A-05 Registro de eventos --------------------------------------------
class TipoEvento(StrEnum):
    PETICION = "PETICION"
    ERROR = "ERROR"
    POSICION_DESCARTADA = "POSICION_DESCARTADA"
    SEGURIDAD = "SEGURIDAD"
    TAREA = "TAREA"


class EventoDTO(BaseModel):
    id: int
    date: datetime
    type: TipoEvento
    source: str
    vehicle_label: str | None
    panel_user: str | None
    http_status: int | None
    detail: dict | None


class PaginaEventosDTO(BaseModel):
    events: list[EventoDTO]
    total: int
    page: int
    page_size: int
    retention_days: int = Field(description="Días que se conservan los eventos (RN-012)")
