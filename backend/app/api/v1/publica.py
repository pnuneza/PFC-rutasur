"""Interfaces ISalud e IConsultaPublica (P06, Tabla 49).

Operaciones de solo lectura, sin token: todo lo que necesita la aplicación del
pasajero. Los enrutadores no contienen reglas de negocio: validan la entrada,
delegan en el servicio y traducen el resultado al DTO del contrato.
"""

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, Response, status
from sqlalchemy import text

from app import __version__
from app.api.dependencias import servicio_flota, servicio_llegadas, servicio_rutas
from app.api.v1.esquemas import (
    EstadoServicioDTO,
    LineaDTO,
    LlegadaDTO,
    Meta,
    ParaderoDeVarianteDTO,
    ParaderoEncontradoDTO,
    Respuesta,
    RespuestaError,
    UnidadActivaDTO,
    VarianteDTO,
)
from app.db.conexion import cupo_de_conexion, obtener_motor
from app.domain.modelos import Ramal
from app.services.servicio_flota import ServicioFlota
from app.services.servicio_llegadas import ServicioLlegadas
from app.services.servicio_rutas import ServicioRutas

router = APIRouter(prefix="/api/v1")

ERRORES_COMUNES = {
    400: {"model": RespuestaError, "description": "VALIDATION_ERROR"},
    500: {"model": RespuestaError, "description": "INTERNAL_ERROR"},
}

CodigoParadero = Annotated[
    str, Path(pattern=r"^stp_\d{3}$", description="Código del paradero", examples=["stp_004"])
]


def _ahora() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


# ----------------------------------------------------------------------
# ISalud
# ----------------------------------------------------------------------
@router.get(
    "/health",
    tags=["ISalud"],
    summary="verificarEstado — estado del servicio",
    response_model=Respuesta[EstadoServicioDTO],
    # También pasa por el cupo: bajo carga no debe dejar hilos esperando conexión (D-11)
    dependencies=[Depends(cupo_de_conexion)],
)
def verificar_estado(response: Response) -> Respuesta[EstadoServicioDTO]:
    """Estado, versión y hora del servidor. Lo consulta el monitor de disponibilidad (RNF-03)."""
    try:
        with obtener_motor().connect() as conexion:
            conexion.execute(text("SELECT 1"))
        base_datos = "ok"
    except Exception:  # cualquier fallo de conexión significa "no disponible"
        base_datos = "error"
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    ahora = _ahora()
    return Respuesta(
        data=EstadoServicioDTO(
            status="ok" if base_datos == "ok" else "degraded",
            version=__version__,
            server_time=ahora,
            database=base_datos,
        ),
        meta=Meta(timestamp=ahora),
    )


# ----------------------------------------------------------------------
# IConsultaPublica
# ----------------------------------------------------------------------
@router.get(
    "/routes/lb",
    tags=["IConsultaPublica"],
    summary="obtenerLinea — trazado y paraderos de la línea LB",
    response_model=Respuesta[LineaDTO],
    responses=ERRORES_COMUNES,
)
def obtener_linea(servicio: ServicioRutas = Depends(servicio_rutas)) -> Respuesta[LineaDTO]:
    """Línea con su horario, variantes activas con trazado y destino, y paraderos (RF-001)."""
    linea = servicio.obtener_linea()
    variantes = [
        VarianteDTO(
            branch=v.ramal,
            direction=v.sentido,
            destination=v.destino,
            length_m=v.longitud_m,
            shape=[(c.lat, c.lon) for c in v.trazado],
            stops=[
                ParaderoDeVarianteDTO(
                    code=p.codigo,
                    name=p.nombre,
                    reference=p.referencia,
                    lat=p.ubicacion.lat,
                    lon=p.ubicacion.lon,
                    order=p.orden,
                    distance_from_start_m=p.distancia_desde_inicio_m,
                    shared_trunk=p.en_tramo_comun,
                )
                for p in v.paraderos
            ],
        )
        for v in linea.variantes
    ]
    return Respuesta(
        data=LineaDTO(
            code=linea.codigo,
            name=linea.nombre,
            service_start=linea.hora_inicio.strftime("%H:%M"),
            service_end=linea.hora_fin.strftime("%H:%M"),
            updated_at=linea.actualizado_en,
            variants=variantes,
        ),
        meta=Meta(timestamp=_ahora(), count=len(variantes)),
    )


@router.get(
    "/stops",
    tags=["IConsultaPublica"],
    summary="buscarParaderos — búsqueda por nombre",
    response_model=Respuesta[list[ParaderoEncontradoDTO]],
    responses=ERRORES_COMUNES,
)
def buscar_paraderos(
    q: Annotated[
        str,
        # Sin caracteres de control: un byte nulo hacía fallar a PostgreSQL con 500 (D-08)
        Query(
            min_length=2,
            max_length=40,
            pattern=r"^[^\x00-\x1f\x7f]+$",
            description="Parte del nombre",
        ),
    ],
    servicio: ServicioRutas = Depends(servicio_rutas),
) -> Respuesta[list[ParaderoEncontradoDTO]]:
    """Hasta 20 paraderos cuyo nombre contiene el texto, sin mayúsculas ni tildes (RF-005)."""
    encontrados = [
        ParaderoEncontradoDTO(
            code=p.codigo,
            name=p.nombre,
            reference=p.referencia,
            lat=p.ubicacion.lat,
            lon=p.ubicacion.lon,
            branches=p.ramales,
        )
        for p in servicio.buscar_paraderos(q)
    ]
    return Respuesta(data=encontrados, meta=Meta(timestamp=_ahora(), count=len(encontrados)))


@router.get(
    "/vehicles",
    tags=["IConsultaPublica"],
    summary="listarUnidadesActivas — unidades en servicio",
    response_model=Respuesta[list[UnidadActivaDTO]],
    responses=ERRORES_COMUNES,
)
def listar_unidades_activas(
    branch: Annotated[Ramal | None, Query(description="Filtrar por ramal")] = None,
    servicio: ServicioFlota = Depends(servicio_flota),
) -> Respuesta[list[UnidadActivaDTO]]:
    """Posición vigente de cada unidad con sesión abierta y la frescura del dato (P06, Tabla 50)."""
    ahora = _ahora()
    unidades = [
        UnidadActivaDTO(
            vehicle_label=u.unidad.etiqueta,
            branch=u.unidad.ramal,
            direction=u.unidad.sentido,
            destination=u.unidad.destino,
            lat=u.unidad.ubicacion.lat,
            lon=u.unidad.ubicacion.lon,
            heading=u.unidad.rumbo,
            position_age_s=u.antiguedad_s,
            freshness=u.frescura,
        )
        for u in servicio.unidades_en_servicio(ahora, branch)
    ]
    return Respuesta(data=unidades, meta=Meta(timestamp=ahora, count=len(unidades)))


@router.get(
    "/stops/{code}/arrivals",
    tags=["IConsultaPublica"],
    summary="consultarLlegadas — próximas llegadas a un paradero",
    response_model=Respuesta[list[LlegadaDTO]],
    responses={**ERRORES_COMUNES, 404: {"model": RespuestaError, "description": "NOT_FOUND"}},
)
def consultar_llegadas(
    code: CodigoParadero,
    servicio: ServicioLlegadas = Depends(servicio_llegadas),
) -> Respuesta[list[LlegadaDTO]]:
    """Resuelve el CU-01: llegadas ordenadas por ETA, hasta 60 minutos (P06, Tabla 51)."""
    ahora = _ahora()
    llegadas = [
        LlegadaDTO(
            vehicle_label=e.etiqueta,
            branch=e.ramal,
            destination=e.destino,
            eta_seconds=e.eta_s,
            distance_m=e.distancia_m,
            position_age_s=e.antiguedad_s,
            reliable=e.confiable,
        )
        for e in servicio.proximas_llegadas(code, ahora)
    ]
    return Respuesta(data=llegadas, meta=Meta(timestamp=ahora, count=len(llegadas)))
