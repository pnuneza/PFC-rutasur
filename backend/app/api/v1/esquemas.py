"""Objetos de transferencia de datos (DTO) de la API.

Fijan qué campos viajan en cada mensaje (P06, Figura 44). Los nombres de los
campos están en inglés, como en el contrato de la sección 2.10 de P05. Pydantic
valida cada entrada contra estos esquemas y genera con ellos el contrato OpenAPI
publicado en /docs.
"""

from datetime import datetime

from pydantic import BaseModel, Field

from app.domain.modelos import Frescura, Ramal, Sentido


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
