"""IAdministracion: servicios del panel (A-01 a A-05; RF-014 a RF-017 y RF-020).

Permisos (RF-014, P05 Tabla 35): el moderador solo consulta la flota y los eventos; todo
lo demás es exclusivo del administrador. Un rol sin permiso recibe 403 FORBIDDEN.
"""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.api.dependencias import requiere_rol, servicio_administracion
from app.api.v1.esquemas import Meta, Respuesta, RespuestaError
from app.api.v1.esquemas_admin import (
    AccionCuentaDTO,
    CuentaConClaveDTO,
    CuentaConductorEntradaDTO,
    CuentaDTO,
    CuentaPanelEntradaDTO,
    EventoDTO,
    FlotaDTO,
    HorarioDTO,
    PaginaEventosDTO,
    ParaderoAdminDTO,
    ParaderoDeVarianteAdminDTO,
    ParaderoEdicionDTO,
    ParaderoEntradaDTO,
    ParaderosVarianteEntradaDTO,
    ResultadoAccionDTO,
    ResumenFlotaDTO,
    TipoEvento,
    UnidadAdminDTO,
    UnidadEntradaDTO,
    UnidadEstadoDTO,
    UnidadFlotaDTO,
    VarianteAdminDTO,
)
from app.core.config import obtener_configuracion
from app.domain.administracion import (
    CuentaAdmin,
    CuentaConClave,
    DatosParadero,
    EstadoUnidad,
    FiltroEventos,
    Horario,
    ParaderoAdmin,
    UnidadAdmin,
)
from app.domain.modelos import Coordenada, Identidad, Rol
from app.services.servicio_administracion import ServicioAdministracion

router = APIRouter(prefix="/api/v1/admin", tags=["IAdministracion"])

panel = requiere_rol(Rol.ADMINISTRADOR, Rol.MODERADOR)
solo_administrador = requiere_rol(Rol.ADMINISTRADOR)

Servicio = Annotated[ServicioAdministracion, Depends(servicio_administracion)]
Administrador = Annotated[Identidad, Depends(solo_administrador)]


def _error(*codigos: str) -> dict:
    return {"model": RespuestaError, "description": " · ".join(codigos)}


ERRORES_PANEL = {
    401: _error("TOKEN_MISSING_OR_EXPIRED"),
    403: _error("FORBIDDEN (rol sin permiso)"),
}
ERRORES_EDICION = {**ERRORES_PANEL, 400: _error("VALIDATION_ERROR"), 404: _error("NOT_FOUND")}


def _ahora() -> datetime:
    return datetime.now(UTC)


def _meta(count: int | None = None) -> Meta:
    return Meta(timestamp=_ahora().replace(microsecond=0), count=count)


# ----------------------------------------------------------------------
# Conversión dominio → DTO
# ----------------------------------------------------------------------
def _cuenta(c: CuentaAdmin) -> CuentaDTO:
    return CuentaDTO(
        id=c.id,
        username=c.usuario,
        role=c.rol,
        active=c.activa,
        locked_until=c.bloqueada_hasta,
        vehicle_label=c.etiqueta_unidad,
    )


def _con_clave(c: CuentaConClave) -> CuentaConClaveDTO:
    return CuentaConClaveDTO(account=_cuenta(c.cuenta), temporary_password=c.contrasena_temporal)


def _paradero(p: ParaderoAdmin) -> ParaderoAdminDTO:
    return ParaderoAdminDTO(
        code=p.codigo,
        name=p.nombre,
        reference=p.referencia,
        lat=p.ubicacion.lat,
        lon=p.ubicacion.lon,
        shared_trunk=p.en_tramo_comun,
        main=p.principal,
        active=p.activo,
        variants=p.variantes,
    )


def _variante(v: dict) -> VarianteAdminDTO:
    return VarianteAdminDTO(
        id=v["id"],
        branch=v["ramal"],
        direction=v["sentido"],
        destination=v["destino"],
        length_m=v["longitud_m"],
        shape=[(c.lat, c.lon) for c in v["trazado"]],
        stops=[
            ParaderoDeVarianteAdminDTO(
                code=p["codigo"],
                name=p["nombre"],
                reference=p["referencia"],
                lat=p["ubicacion"].lat,
                lon=p["ubicacion"].lon,
                order=p["orden"],
                distance_from_start_m=p["distancia_m"],
                shared_trunk=p["en_tramo_comun"],
                main=p["principal"],
            )
            for p in v["paraderos"]
        ],
    )


def _unidad(u: UnidadAdmin) -> UnidadAdminDTO:
    return UnidadAdminDTO(
        id=u.id, label=u.etiqueta, active=u.activa, username=u.usuario, created_at=u.creada_en
    )


def _datos(d: ParaderoEntradaDTO) -> DatosParadero:
    return DatosParadero(
        d.name, d.reference, Coordenada(d.lat, d.lon), d.shared_trunk, principal=d.main
    )


# ----------------------------------------------------------------------
# A-02 Estado de la flota (RF-017) — administrador y moderador
# ----------------------------------------------------------------------
@router.get(
    "/fleet",
    summary="estadoFlota — unidades transmitiendo, sin señal e inactivas",
    response_model=Respuesta[FlotaDTO],
    responses=ERRORES_PANEL,
)
def estado_flota(servicio: Servicio, _: Identidad = Depends(panel)) -> Respuesta[FlotaDTO]:
    estados = servicio.estado_flota(_ahora())
    cuenta = {e: sum(1 for x in estados if x.estado == e) for e in EstadoUnidad}
    unidades = [
        UnidadFlotaDTO(
            vehicle_id=e.fila.unidad_id,
            vehicle_label=e.fila.etiqueta,
            username=e.fila.usuario,
            status=e.estado,
            since=e.desde,
            last_position_age_s=e.antiguedad_s,
            lat=e.fila.ubicacion.lat if e.fila.ubicacion else None,
            lon=e.fila.ubicacion.lon if e.fila.ubicacion else None,
            heading=e.fila.rumbo,
            branch=e.fila.ramal,
            direction=e.fila.sentido,
            destination=e.fila.destino,
        )
        for e in estados
    ]
    return Respuesta(
        data=FlotaDTO(
            summary=ResumenFlotaDTO(
                transmitting=cuenta[EstadoUnidad.TRANSMITIENDO],
                no_signal=cuenta[EstadoUnidad.SIN_SENAL],
                inactive=cuenta[EstadoUnidad.INACTIVA],
            ),
            vehicles=unidades,
        ),
        meta=_meta(len(unidades)),
    )


# ----------------------------------------------------------------------
# A-05 Registro de eventos (RF-020) — administrador y moderador
# ----------------------------------------------------------------------
@router.get(
    "/events",
    summary="consultarEventos — filtros por fecha, tipo y unidad; del más reciente",
    response_model=Respuesta[PaginaEventosDTO],
    responses={**ERRORES_PANEL, 400: _error("VALIDATION_ERROR")},
)
def consultar_eventos(
    servicio: Servicio,
    _: Identidad = Depends(panel),
    desde: Annotated[datetime | None, Query(alias="from")] = None,
    hasta: Annotated[datetime | None, Query(alias="to")] = None,
    tipo: Annotated[TipoEvento | None, Query(alias="type")] = None,
    unidad: Annotated[str | None, Query(alias="vehicle", max_length=20)] = None,
    pagina: Annotated[int, Query(alias="page", ge=1, le=10_000)] = 1,
    tamano: Annotated[int, Query(alias="page_size", ge=1, le=200)] = 50,
) -> Respuesta[PaginaEventosDTO]:
    """Sin fechas devuelve las últimas 24 horas."""
    ahora = _ahora()
    hasta = hasta or ahora
    desde = desde or hasta - timedelta(hours=24)
    filtro = FiltroEventos(
        desde=desde if desde.tzinfo else desde.replace(tzinfo=UTC),
        hasta=hasta if hasta.tzinfo else hasta.replace(tzinfo=UTC),
        tipo=tipo.value if tipo else None,
        etiqueta_unidad=unidad,
        pagina=pagina,
        tamano=tamano,
    )
    resultado = servicio.eventos(filtro, ahora)
    eventos = [
        EventoDTO(
            id=e.id,
            date=e.fecha,
            type=TipoEvento(e.tipo),
            source=e.origen,
            vehicle_label=e.etiqueta_unidad,
            panel_user=e.usuario_panel,
            http_status=e.codigo_http,
            detail=e.detalle,
        )
        for e in resultado.eventos
    ]
    return Respuesta(
        data=PaginaEventosDTO(
            events=eventos,
            total=resultado.total,
            page=pagina,
            page_size=tamano,
            retention_days=obtener_configuracion().retencion_dias,
        ),
        meta=_meta(len(eventos)),
    )


# ----------------------------------------------------------------------
# A-03 Rutas y paraderos (RF-015, RN-009) — solo administrador
# ----------------------------------------------------------------------
@router.put(
    "/line",
    summary="cambiarHorario — horario referencial de la línea",
    response_model=Respuesta[HorarioDTO],
    responses={**ERRORES_PANEL, 400: _error("VALIDATION_ERROR")},
)
def cambiar_horario(
    entrada: HorarioDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[HorarioDTO]:
    h = servicio.cambiar_horario(admin, Horario(entrada.service_start, entrada.service_end))
    return Respuesta(data=HorarioDTO(service_start=h.inicio, service_end=h.fin), meta=_meta())


@router.get(
    "/variants",
    summary="variantes — trazado y paraderos en orden de cada variante",
    response_model=Respuesta[list[VarianteAdminDTO]],
    responses=ERRORES_PANEL,
)
def variantes(servicio: Servicio, _: Administrador) -> Respuesta[list[VarianteAdminDTO]]:
    datos = [_variante(v) for v in servicio.variantes()]
    return Respuesta(data=datos, meta=_meta(len(datos)))


@router.put(
    "/variants/{variant_id}/stops",
    summary="asignarParaderos — reemplaza los paraderos de una variante",
    response_model=Respuesta[VarianteAdminDTO],
    responses={**ERRORES_EDICION, 422: _error("OUT_OF_CORRIDOR")},
)
def asignar_paraderos(
    variant_id: UUID,
    entrada: ParaderosVarianteEntradaDTO,
    servicio: Servicio,
    admin: Administrador,
) -> Respuesta[VarianteAdminDTO]:
    """El orden no se envía: el servidor lo calcula a lo largo del trazado (RN-006)."""
    variante = servicio.asignar_paraderos(admin, variant_id, entrada.codes)
    return Respuesta(data=_variante(variante), meta=_meta(len(variante["paraderos"])))


@router.get(
    "/stops",
    summary="paraderos — todos, incluidos los inactivos",
    response_model=Respuesta[list[ParaderoAdminDTO]],
    responses=ERRORES_PANEL,
)
def paraderos(
    servicio: Servicio,
    _: Administrador,
    q: Annotated[str | None, Query(max_length=40)] = None,
) -> Respuesta[list[ParaderoAdminDTO]]:
    datos = [_paradero(p) for p in servicio.paraderos(q)]
    return Respuesta(data=datos, meta=_meta(len(datos)))


@router.post(
    "/stops",
    summary="crearParadero — a 150 m o menos del trazado (RN-003)",
    status_code=status.HTTP_201_CREATED,
    response_model=Respuesta[ParaderoAdminDTO],
    responses={**ERRORES_EDICION, 422: _error("OUT_OF_CORRIDOR")},
)
def crear_paradero(
    entrada: ParaderoEntradaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[ParaderoAdminDTO]:
    """El código (stp_NNN) lo asigna el servidor. El paradero nace sin variantes."""
    return Respuesta(data=_paradero(servicio.crear_paradero(admin, _datos(entrada))), meta=_meta())


@router.put(
    "/stops/{code}",
    summary="editarParadero — datos, ubicación y estado",
    response_model=Respuesta[ParaderoAdminDTO],
    responses={**ERRORES_EDICION, 422: _error("OUT_OF_CORRIDOR")},
)
def editar_paradero(
    code: str, entrada: ParaderoEdicionDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[ParaderoAdminDTO]:
    """Desactivar un paradero lo quita de todas sus variantes."""
    p = servicio.editar_paradero(admin, code, _datos(entrada), entrada.active)
    return Respuesta(data=_paradero(p), meta=_meta())


# ----------------------------------------------------------------------
# A-04 Unidades y cuentas (RF-016) — solo administrador
# ----------------------------------------------------------------------
@router.get(
    "/units",
    summary="unidades — con su cuenta de conductor, si la tienen",
    response_model=Respuesta[list[UnidadAdminDTO]],
    responses=ERRORES_PANEL,
)
def unidades(servicio: Servicio, _: Administrador) -> Respuesta[list[UnidadAdminDTO]]:
    datos = [_unidad(u) for u in servicio.unidades()]
    return Respuesta(data=datos, meta=_meta(len(datos)))


@router.post(
    "/units",
    summary="registrarUnidad",
    status_code=status.HTTP_201_CREATED,
    response_model=Respuesta[UnidadAdminDTO],
    responses={**ERRORES_EDICION, 409: _error("CONFLICT")},
)
def registrar_unidad(
    entrada: UnidadEntradaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[UnidadAdminDTO]:
    return Respuesta(data=_unidad(servicio.crear_unidad(admin, entrada.label)), meta=_meta())


@router.put(
    "/units/{unit_id}",
    summary="habilitarUnidad — deshabilitarla cierra su sesión abierta",
    response_model=Respuesta[UnidadAdminDTO],
    responses=ERRORES_EDICION,
)
def habilitar_unidad(
    unit_id: UUID, entrada: UnidadEstadoDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[UnidadAdminDTO]:
    u = servicio.cambiar_estado_unidad(admin, unit_id, entrada.active)
    return Respuesta(data=_unidad(u), meta=_meta())


@router.get(
    "/driver-accounts",
    summary="cuentasConductor",
    response_model=Respuesta[list[CuentaDTO]],
    responses=ERRORES_PANEL,
)
def cuentas_conductor(servicio: Servicio, _: Administrador) -> Respuesta[list[CuentaDTO]]:
    datos = [_cuenta(c) for c in servicio.cuentas_conductor()]
    return Respuesta(data=datos, meta=_meta(len(datos)))


@router.post(
    "/driver-accounts",
    summary="crearCuentaConductor — una por unidad; contraseña temporal visible una vez",
    status_code=status.HTTP_201_CREATED,
    response_model=Respuesta[CuentaConClaveDTO],
    responses={**ERRORES_EDICION, 409: _error("CONFLICT")},
)
def crear_cuenta_conductor(
    entrada: CuentaConductorEntradaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[CuentaConClaveDTO]:
    creada = servicio.crear_cuenta_conductor(admin, entrada.vehicle_id, entrada.username)
    return Respuesta(data=_con_clave(creada), meta=_meta())


@router.put(
    "/driver-accounts/{account_id}",
    summary="gestionarCuentaConductor — restablecer, activar, desactivar o desbloquear",
    response_model=Respuesta[ResultadoAccionDTO],
    responses=ERRORES_EDICION,
)
def gestionar_cuenta_conductor(
    account_id: UUID, entrada: AccionCuentaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[ResultadoAccionDTO]:
    return _resultado(servicio.actuar_sobre_cuenta(admin, account_id, entrada.action, panel=False))


@router.get(
    "/panel-accounts",
    summary="cuentasPanel — administradores y moderadores",
    response_model=Respuesta[list[CuentaDTO]],
    responses=ERRORES_PANEL,
)
def cuentas_panel(servicio: Servicio, _: Administrador) -> Respuesta[list[CuentaDTO]]:
    datos = [_cuenta(c) for c in servicio.cuentas_panel()]
    return Respuesta(data=datos, meta=_meta(len(datos)))


@router.post(
    "/panel-accounts",
    summary="crearCuentaPanel — contraseña temporal visible una vez",
    status_code=status.HTTP_201_CREATED,
    response_model=Respuesta[CuentaConClaveDTO],
    responses={**ERRORES_EDICION, 409: _error("CONFLICT")},
)
def crear_cuenta_panel(
    entrada: CuentaPanelEntradaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[CuentaConClaveDTO]:
    creada = servicio.crear_cuenta_panel(admin, entrada.username, Rol(entrada.role.value))
    return Respuesta(data=_con_clave(creada), meta=_meta())


@router.put(
    "/panel-accounts/{account_id}",
    summary="gestionarCuentaPanel — nadie se desactiva a sí mismo; queda un administrador",
    response_model=Respuesta[ResultadoAccionDTO],
    responses={**ERRORES_EDICION, 409: _error("CONFLICT")},
)
def gestionar_cuenta_panel(
    account_id: UUID, entrada: AccionCuentaDTO, servicio: Servicio, admin: Administrador
) -> Respuesta[ResultadoAccionDTO]:
    return _resultado(servicio.actuar_sobre_cuenta(admin, account_id, entrada.action, panel=True))


def _resultado(r: CuentaConClave | CuentaAdmin) -> Respuesta[ResultadoAccionDTO]:
    if isinstance(r, CuentaConClave):
        dato = ResultadoAccionDTO(
            account=_cuenta(r.cuenta), temporary_password=r.contrasena_temporal
        )
    else:
        dato = ResultadoAccionDTO(account=_cuenta(r))
    return Respuesta(data=dato, meta=_meta())
