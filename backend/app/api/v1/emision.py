"""IAutenticacion e IEmision: ingreso y emisión del conductor (CU-02, CU-03).

P06 Tablas 52 a 54. La unidad que transmite sale siempre del token y nunca del cuerpo
de la petición: un conductor no puede abrir sesiones ni enviar posiciones por otra
unidad (P05 Tabla 35, OWASP A01).
"""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.api.dependencias import (
    limite_envios,
    limite_ingresos,
    origen_de,
    requiere_rol,
    servicio_autenticacion,
    servicio_emision,
)
from app.api.v1.esquemas import (
    AcuseLoteDTO,
    AperturaSesionDTO,
    CredencialesDTO,
    LotePosicionesDTO,
    Meta,
    Respuesta,
    RespuestaError,
    SesionAbiertaDTO,
    SesionCerradaDTO,
    TokenDTO,
)
from app.db.conexion import sesion_bd
from app.domain.excepciones import CredencialesInvalidas, CuentaBloqueada
from app.domain.modelos import (
    Coordenada,
    EstadoSesion,
    Identidad,
    PosicionEntrante,
    Rol,
)
from app.services.servicio_autenticacion import ServicioAutenticacion
from app.services.servicio_emision import ServicioEmision

router = APIRouter(prefix="/api/v1")

solo_conductor = requiere_rol(Rol.CONDUCTOR)


def _error(*codigos: str) -> dict:
    return {"model": RespuestaError, "description": " · ".join(codigos)}


def _ahora() -> datetime:
    return datetime.now(UTC)


def _meta() -> Meta:
    return Meta(timestamp=_ahora().replace(microsecond=0))


# ----------------------------------------------------------------------
# IAutenticacion
# ----------------------------------------------------------------------
@router.post(
    "/auth/login",
    tags=["IAutenticacion"],
    summary="iniciarSesion — token para el conductor o el panel",
    response_model=Respuesta[TokenDTO],
    responses={
        400: _error("VALIDATION_ERROR"),
        401: _error("INVALID_CREDENTIALS"),
        403: _error("ACCOUNT_LOCKED (meta.retry_after_s)"),
        429: _error("RATE_LIMITED"),
    },
)
def iniciar_sesion(
    credenciales: CredencialesDTO,
    origen: str = Depends(origen_de),
    servicio: ServicioAutenticacion = Depends(servicio_autenticacion),
    sesion: Session = Depends(sesion_bd),
) -> Respuesta[TokenDTO]:
    """Tras 5 intentos fallidos la cuenta se bloquea 15 minutos (RN-011)."""
    limite_ingresos.registrar(origen)
    try:
        emitido = servicio.iniciar_sesion(credenciales.username, credenciales.password, _ahora())
    except (CredencialesInvalidas, CuentaBloqueada):
        # El intento fallido y el bloqueo deben quedar guardados aunque se responda error
        sesion.commit()
        raise
    return Respuesta(
        data=TokenDTO(
            access_token=emitido.token,
            expires_in=emitido.vigencia_s,
            role=emitido.identidad.rol,
            vehicle_label=emitido.identidad.etiqueta_unidad,
        ),
        meta=_meta(),
    )


# ----------------------------------------------------------------------
# IEmision
# ----------------------------------------------------------------------
ERRORES_CONDUCTOR = {
    400: _error("VALIDATION_ERROR"),
    401: _error("TOKEN_MISSING_OR_EXPIRED"),
    403: _error("FORBIDDEN"),
}


@router.post(
    "/sessions",
    tags=["IEmision"],
    summary="abrirSesion — inicia la emisión de la unidad del token",
    status_code=status.HTTP_201_CREATED,
    response_model=Respuesta[SesionAbiertaDTO],
    responses={**ERRORES_CONDUCTOR, 409: _error("UNIT_INACTIVE")},
)
def abrir_sesion(
    entrada: AperturaSesionDTO,
    conductor: Identidad = Depends(solo_conductor),
    servicio: ServicioEmision = Depends(servicio_emision),
) -> Respuesta[SesionAbiertaDTO]:
    """Cierra cualquier sesión abierta de la misma unidad y abre la nueva (RN-002)."""
    sesion = servicio.abrir_sesion(
        conductor.unidad_id, conductor.cuenta_id, entrada.branch, entrada.direction, _ahora()
    )
    return Respuesta(
        data=SesionAbiertaDTO(
            session_id=sesion.id,
            variant=f"{entrada.branch}-{entrada.direction}",
            destination=sesion.destino,
            started_at=sesion.inicio,
        ),
        meta=_meta(),
    )


@router.post(
    "/sessions/{session_id}/positions",
    tags=["IEmision"],
    summary="enviarPosiciones — lote de 1 a 200 posiciones",
    response_model=Respuesta[AcuseLoteDTO],
    responses={
        **ERRORES_CONDUCTOR,
        404: _error("NOT_FOUND"),
        409: _error("SESSION_NOT_ACTIVE"),
        429: _error("RATE_LIMITED"),
    },
)
def enviar_posiciones(
    session_id: UUID,
    lote: LotePosicionesDTO,
    conductor: Identidad = Depends(solo_conductor),
    servicio: ServicioEmision = Depends(servicio_emision),
) -> Respuesta[AcuseLoteDTO]:
    """El teléfono borra de su cola exactamente los identificadores de `confirmed`."""
    limite_envios.registrar(str(conductor.unidad_id))
    posiciones = [
        PosicionEntrante(
            id=p.id,
            ubicacion=Coordenada(lat=p.lat, lon=p.lon),
            velocidad_kmh=p.speed_kmh,
            rumbo=p.heading,
            precision_m=p.accuracy_m,
            capturada_en=p.captured_at,
        )
        for p in lote.positions
    ]
    acuse = servicio.recibir_lote(session_id, conductor.unidad_id, posiciones, _ahora())
    return Respuesta(
        data=AcuseLoteDTO(
            confirmed=acuse.confirmados,
            published=acuse.publicadas,
            discarded=acuse.descartadas,
            duplicates=acuse.duplicadas,
        ),
        meta=_meta(),
    )


@router.post(
    "/sessions/{session_id}/close",
    tags=["IEmision"],
    summary="cerrarSesion — termina la emisión",
    response_model=Respuesta[SesionCerradaDTO],
    responses={**ERRORES_CONDUCTOR, 404: _error("NOT_FOUND"), 409: _error("SESSION_NOT_ACTIVE")},
)
def cerrar_sesion(
    session_id: UUID,
    conductor: Identidad = Depends(solo_conductor),
    servicio: ServicioEmision = Depends(servicio_emision),
) -> Respuesta[SesionCerradaDTO]:
    servicio.cerrar_sesion(session_id, conductor.unidad_id)
    return Respuesta(
        data=SesionCerradaDTO(session_id=session_id, status=EstadoSesion.CERRADA_POR_CONDUCTOR),
        meta=_meta(),
    )
