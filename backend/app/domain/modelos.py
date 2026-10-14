"""Objetos del dominio que circulan entre los servicios y los repositorios.

Son estructuras inmutables y sin lógica de acceso a datos. Corresponden a las
clases del modelo del dominio (P05, Figura 22 y Tabla 33).
"""

from dataclasses import dataclass, field
from datetime import datetime, time
from enum import StrEnum
from uuid import UUID


class Ramal(StrEnum):
    MOLLEBAYA = "MOLLEBAYA"
    CERRILLO = "CERRILLO"


class Sentido(StrEnum):
    IDA = "IDA"  # hacia el Centro (2 de Mayo)
    VUELTA = "VUELTA"  # hacia el ramal


class EstadoSesion(StrEnum):
    ACTIVA = "ACTIVA"
    SIN_SENAL = "SIN_SENAL"
    CERRADA_POR_CONDUCTOR = "CERRADA_POR_CONDUCTOR"
    CERRADA_AUTOMATICAMENTE = "CERRADA_AUTOMATICAMENTE"

    @property
    def abierta(self) -> bool:
        return self in (EstadoSesion.ACTIVA, EstadoSesion.SIN_SENAL)


class MotivoDescarte(StrEnum):
    FUERA_DE_CORREDOR = "FUERA_DE_CORREDOR"
    VELOCIDAD_IMPOSIBLE = "VELOCIDAD_IMPOSIBLE"
    DUPLICADA = "DUPLICADA"
    PRECISION_INSUFICIENTE = "PRECISION_INSUFICIENTE"


class Frescura(StrEnum):
    """Estados de la frescura del dato mostrado al pasajero (P05, Figura 26)."""

    VIGENTE = "VIGENTE"
    DEMORADA = "DEMORADA"
    NO_CONFIABLE = "NO_CONFIABLE"


# ----------------------------------------------------------
# Ruta (línea, variantes y paraderos)
# ----------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Coordenada:
    lat: float
    lon: float


@dataclass(frozen=True, slots=True)
class ParaderoEnVariante:
    codigo: str
    nombre: str
    referencia: str | None
    ubicacion: Coordenada
    orden: int
    distancia_desde_inicio_m: float
    en_tramo_comun: bool


@dataclass(frozen=True, slots=True)
class VarianteRuta:
    ramal: Ramal
    sentido: Sentido
    destino: str
    longitud_m: float
    trazado: list[Coordenada]
    paraderos: list[ParaderoEnVariante] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class LineaRuta:
    codigo: str
    nombre: str
    hora_inicio: time
    hora_fin: time
    actualizado_en: datetime
    variantes: list[VarianteRuta]


@dataclass(frozen=True, slots=True)
class ParaderoEncontrado:
    codigo: str
    nombre: str
    referencia: str | None
    ubicacion: Coordenada
    ramales: list[Ramal]


# ----------------------------------------------------------
# Unidades en servicio y llegadas
# ----------------------------------------------------------
@dataclass(frozen=True, slots=True)
class UnidadEnServicio:
    etiqueta: str
    ramal: Ramal
    sentido: Sentido
    destino: str
    ubicacion: Coordenada
    rumbo: int | None
    ultima_posicion_en: datetime


@dataclass(frozen=True, slots=True)
class CandidatoLlegada:
    """Unidad que aún no pasa por el paradero, con los datos que necesita el estimador."""

    etiqueta: str
    ramal: Ramal
    sentido: Sentido
    destino: str
    distancia_recorrida_m: float
    distancia_paradero_m: float
    ultima_posicion_en: datetime
    velocidades_recientes_kmh: list[float | None]


@dataclass(frozen=True, slots=True)
class EstimacionLlegada:
    """Resultado del cálculo del ETA. Objeto de valor: no se guarda en la base (P05, Tabla 33)."""

    etiqueta: str
    ramal: Ramal
    destino: str
    eta_s: int
    distancia_m: int
    antiguedad_s: int
    confiable: bool


# ----------------------------------------------------------
# Emisión de posiciones
# ----------------------------------------------------------
@dataclass(frozen=True, slots=True)
class SesionEmision:
    id: UUID
    unidad_id: UUID
    variante_id: UUID
    estado: EstadoSesion
    inicio: datetime
    destino: str = ""


@dataclass(frozen=True, slots=True)
class PosicionEntrante:
    """Lectura GPS tal como llega del teléfono del conductor."""

    id: UUID
    ubicacion: Coordenada
    velocidad_kmh: float | None
    rumbo: int | None
    precision_m: float
    capturada_en: datetime


@dataclass(frozen=True, slots=True)
class MedicionTrazado:
    """Relación de una posición con el trazado de su variante, calculada con PostGIS."""

    distancia_al_trazado_m: float
    distancia_recorrida_m: float


@dataclass(frozen=True, slots=True)
class ReferenciaPosicion:
    """Última posición válida conocida, contra la que se compara la siguiente."""

    ubicacion: Coordenada
    capturada_en: datetime


@dataclass(frozen=True, slots=True)
class ResultadoValidacion:
    valida: bool
    motivo: MotivoDescarte | None = None


@dataclass(frozen=True, slots=True)
class PosicionValidada:
    posicion: PosicionEntrante
    resultado: ResultadoValidacion


@dataclass(frozen=True, slots=True)
class AcuseLote:
    """Respuesta al teléfono: qué posiciones puede borrar de su cola (P06, Tabla 54)."""

    confirmados: list[UUID]
    publicadas: int
    descartadas: int
    duplicadas: int
