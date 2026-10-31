"""Objetos de transferencia de datos (DTO) de la API.

Fijan qué campos viajan en cada mensaje (P06, Figura 44). Los nombres de los
campos están en inglés, como en el contrato de la sección 2.10 de P05. Pydantic
valida cada entrada contra estos esquemas y genera con ellos el contrato OpenAPI
publicado en /docs.
"""

from datetime import datetime
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field

from app.domain.modelos import Frescura, Ramal, Rol, Sentido


class Meta(BaseModel):
    timestamp: datetime = Field(description="Hora del servidor (UTC, ISO 8601)")
    count: int | None = Field(default=None, description="Cantidad de elementos en data")


class Respuesta[T](BaseModel):
    """Sobre estándar de toda respuesta exitosa (P05, Tabla 38)."""

    data: T
    meta: Meta


class ErrorDetalle(BaseModel):
    code: str = Field(examples=["NOT_FOUND"])
    message: str


class RespuestaError(BaseModel):
    error: ErrorDetalle


# --- ISalud -----------------------------------------------------------
class EstadoServicioDTO(BaseModel):
    status: str = Field(examples=["ok"])
    version: str
    server_time: datetime
    database: str = Field(examples=["ok"])


# --- IConsultaPublica: ruta ---------------------------------------------
class ParaderoDeVarianteDTO(BaseModel):
    code: str = Field(examples=["stp_004"])
    name: str
    reference: str | None
    lat: float
    lon: float
    order: int
    distance_from_start_m: float
    shared_trunk: bool = Field(description="Pertenece al tramo común de ambos ramales")


class VarianteDTO(BaseModel):
    branch: Ramal
    direction: Sentido
    destination: str
    length_m: float
    shape: list[tuple[float, float]] = Field(description="Trazado como pares [lat, lon]")
    stops: list[ParaderoDeVarianteDTO]


class LineaDTO(BaseModel):
    code: str = Field(examples=["LB"])
    name: str
    service_start: str = Field(examples=["05:00"])
    service_end: str = Field(examples=["21:00"])
    updated_at: datetime = Field(description="Si cambia, el teléfono renueva su caché de la ruta")
    variants: list[VarianteDTO]


class ParaderoEncontradoDTO(BaseModel):
    code: str
    name: str
    reference: str | None
    lat: float
    lon: float
    branches: list[Ramal]


# --- IConsultaPublica: unidades y llegadas -------------------------------
class UnidadActivaDTO(BaseModel):
    vehicle_label: str = Field(examples=["07"])
    branch: Ramal
    direction: Sentido
    destination: str
    lat: float
    lon: float
    heading: int | None
    position_age_s: int
    freshness: Frescura


class LlegadaDTO(BaseModel):
    vehicle_label: str = Field(examples=["07"])
    branch: Ramal
    destination: str
    eta_seconds: int
    distance_m: int
    position_age_s: int
    reliable: bool = Field(description="Falso si la última posición tiene más de 90 s (RN-005)")


# --- IAutenticacion (P06 Tabla 52) ----------------------------------------
class CredencialesDTO(BaseModel):
    username: str = Field(pattern=r"^[a-z0-9._]{4,30}$", examples=["unidad07"])
    password: str = Field(min_length=8, max_length=64, examples=["********"])


class TokenDTO(BaseModel):
    access_token: str
    token_type: str = Field(default="bearer", examples=["bearer"])
    expires_in: int = Field(description="Vigencia en segundos (12 h)", examples=[43200])
    role: Rol
    vehicle_label: str | None = Field(description="Unidad del conductor; null para el panel")


# --- IEmision (P06 Tablas 53 y 54) -----------------------------------------
class AperturaSesionDTO(BaseModel):
    branch: Ramal
    direction: Sentido


class SesionAbiertaDTO(BaseModel):
    session_id: UUID
    variant: str = Field(examples=["MOLLEBAYA-VUELTA"])
    destination: str = Field(examples=["Mollebaya"])
    started_at: datetime


class PosicionDTO(BaseModel):
    id: UUID = Field(description="Generado en el teléfono: hace idempotente el reenvío")
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    speed_kmh: float | None = Field(default=None, ge=0, le=200)
    heading: int | None = Field(default=None, ge=0, le=359)
    accuracy_m: float = Field(ge=0)
    captured_at: AwareDatetime = Field(description="Con zona horaria, por ejemplo ...Z")


class LotePosicionesDTO(BaseModel):
    positions: list[PosicionDTO] = Field(min_length=1, max_length=200)


class AcuseLoteDTO(BaseModel):
    confirmed: list[UUID] = Field(description="El teléfono borra de su cola exactamente estos")
    published: int
    discarded: int
    duplicates: int


class SesionCerradaDTO(BaseModel):
    session_id: UUID
    status: str = Field(examples=["CERRADA_POR_CONDUCTOR"])
