"""Servicio del panel de administración (CU-14 a CU-17; P06 Tabla 46).

Reglas que aplica:
- A-02: una unidad TRANSMITE si su última posición válida tiene 90 s o menos; con la
  sesión abierta y más de 90 s sin posiciones está SIN SEÑAL; sin sesión, INACTIVA.
- A-03: un paradero nuevo o movido debe quedar a 150 m o menos del trazado (RN-003). El
  orden de los paraderos de una variante no lo decide el panel: lo calcula la base a
  partir del trazado, así no puede quedar con huecos ni repetidos.
- A-04: sin datos personales (RN-011); una cuenta por unidad (RN-001); usuario único
  entre conductores y panel; contraseña temporal de 12 caracteres mostrada una sola vez.
  Siempre queda al menos un administrador activo, y nadie se desactiva a sí mismo.
- A-05: eventos de hasta 30 días atrás (RN-012), del más reciente al más antiguo.
- Todo cambio queda en el registro de eventos con la cuenta del panel que lo hizo.
"""

import re
from datetime import datetime, timedelta
from uuid import UUID

from app.core.seguridad import contrasena_aleatoria, hash_contrasena
from app.domain.administracion import (
    AccionCuenta,
    CuentaAdmin,
    CuentaConClave,
    DatosParadero,
    EstadoDeUnidad,
    EstadoUnidad,
    FiltroEventos,
    Horario,
    PaginaEventos,
    ParaderoAdmin,
    UnidadAdmin,
)
from app.domain.excepciones import (
    Conflicto,
    ErrorDeNegocio,
    FueraDelCorredor,
    RecursoNoEncontrado,
)
from app.domain.modelos import Identidad, Rol
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.repositories.sql_administracion import RepositorioAdministracionSQL

FORMATO_USUARIO = re.compile(r"^[a-z0-9._]{4,30}$")
FORMATO_ETIQUETA = re.compile(r"^[A-Za-z0-9-]{1,20}$")
DIAS_MAXIMOS_EVENTOS = 30
MINIMO_PARADEROS_VARIANTE = 2

_TABLA_DE_ROL = {
    Rol.CONDUCTOR: "cuenta_conductor",
    Rol.ADMINISTRADOR: "cuenta_administrativa",
    Rol.MODERADOR: "cuenta_administrativa",
}


def clasificar_unidad(
    sesion_inicio: datetime | None,
    ultima_posicion_en: datetime | None,
    ultimo_fin: datetime | None,
    creada_en: datetime,
    ahora: datetime,
    umbrales: Umbrales = UMBRALES_POR_DEFECTO,
) -> tuple[EstadoUnidad, datetime, int | None]:
    """Estado de A-02, desde cuándo está así y la antigüedad de la última posición."""
    if sesion_inicio is None:
        return EstadoUnidad.INACTIVA, ultimo_fin or creada_en, None
    if ultima_posicion_en is None:
        # Abrió sesión pero todavía no llega ninguna posición válida
        antiguedad = max(int((ahora - sesion_inicio).total_seconds()), 0)
        estado = (
            EstadoUnidad.TRANSMITIENDO
            if antiguedad <= umbrales.frescura_demorada_s
            else EstadoUnidad.SIN_SENAL
        )
        return estado, sesion_inicio, None
    antiguedad = max(int((ahora - ultima_posicion_en).total_seconds()), 0)
    if antiguedad <= umbrales.frescura_demorada_s:
        return EstadoUnidad.TRANSMITIENDO, sesion_inicio, antiguedad
    return EstadoUnidad.SIN_SENAL, ultima_posicion_en, antiguedad


class ServicioAdministracion:
    def __init__(
        self, repositorio: RepositorioAdministracionSQL, umbrales: Umbrales = UMBRALES_POR_DEFECTO
    ) -> None:
        self._repo = repositorio
        self._u = umbrales

    # ------------------------------------------------------------------
    # A-02 Estado de la flota (RF-017)
    # ------------------------------------------------------------------
    def estado_flota(self, ahora: datetime) -> list[EstadoDeUnidad]:
        resultado = []
        for fila in self._repo.listar_flota():
            estado, desde, antiguedad = clasificar_unidad(
                fila.sesion_inicio,
                fila.ultima_posicion_en,
                fila.ultimo_fin,
                fila.creada_en,
                ahora,
                self._u,
            )
            resultado.append(EstadoDeUnidad(fila, estado, desde, antiguedad))
        return resultado

    # ------------------------------------------------------------------
    # A-03 Rutas y paraderos (RF-015, RN-009)
    # ------------------------------------------------------------------
    def cambiar_horario(self, admin: Identidad, horario: Horario) -> Horario:
        if horario.fin <= horario.inicio:
            raise ErrorDeNegocio("La hora de fin debe ser posterior a la de inicio (RN-009)")
        guardado = self._repo.actualizar_horario(horario)
        self._repo.auditar(
            "PETICION",
            admin.cuenta_id,
            {
                "accion": "cambiar_horario",
                "inicio": horario.inicio.strftime("%H:%M"),
                "fin": horario.fin.strftime("%H:%M"),
            },
        )
        return guardado

    def variantes(self) -> list[dict]:
        return self._repo.listar_variantes()

    def asignar_paraderos(self, admin: Identidad, variante_id: UUID, codigos: list[str]) -> dict:
        if not self._repo.variante_existe(variante_id):
            raise RecursoNoEncontrado("La variante no existe")
        if len(codigos) < MINIMO_PARADEROS_VARIANTE:
            raise ErrorDeNegocio("Una variante necesita al menos 2 paraderos")
        if len(set(codigos)) != len(codigos):
            raise ErrorDeNegocio("La lista tiene paraderos repetidos")
        self._repo.asignar_paraderos(variante_id, codigos)
        self._repo.auditar(
            "PETICION",
            admin.cuenta_id,
            {"accion": "asignar_paraderos", "variante": str(variante_id), "cantidad": len(codigos)},
        )
        return next(v for v in self._repo.listar_variantes() if v["id"] == variante_id)

    def paraderos(self, texto: str | None = None) -> list[ParaderoAdmin]:
        return self._repo.listar_paraderos(texto.strip() if texto else None)

    def crear_paradero(self, admin: Identidad, datos: DatosParadero) -> ParaderoAdmin:
        datos = self._normalizar(datos)
        self._exigir_dentro_del_corredor(datos)
        codigo = self._repo.siguiente_codigo_paradero()
        self._repo.crear_paradero(codigo, datos)
        self._repo.auditar(
            "PETICION", admin.cuenta_id, {"accion": "crear_paradero", "codigo": codigo}
        )
        return self._paradero(codigo)

    def editar_paradero(
        self, admin: Identidad, codigo: str, datos: DatosParadero, activo: bool
    ) -> ParaderoAdmin:
        actual = self._paradero(codigo)
        datos = self._normalizar(datos)
        if datos.ubicacion != actual.ubicacion:
            self._exigir_dentro_del_corredor(datos)
        self._repo.editar_paradero(codigo, datos)
        if activo != actual.activo:
            if not activo:
                # Un paradero inactivo no puede seguir en una variante
                self._repo.quitar_de_variantes(codigo)
            self._repo.cambiar_estado_paradero(codigo, activo)
        self._repo.auditar(
            "PETICION",
            admin.cuenta_id,
            {"accion": "editar_paradero", "codigo": codigo, "activo": activo},
        )
        return self._paradero(codigo)

    def _paradero(self, codigo: str) -> ParaderoAdmin:
        paradero = self._repo.obtener_paradero(codigo)
        if paradero is None:
            raise RecursoNoEncontrado(f"No existe el paradero {codigo}")
        return paradero

    @staticmethod
    def _normalizar(datos: DatosParadero) -> DatosParadero:
        nombre = " ".join(datos.nombre.split())
        referencia = " ".join((datos.referencia or "").split()) or None
        if not 3 <= len(nombre) <= 80:
            raise ErrorDeNegocio("El nombre debe tener de 3 a 80 caracteres")
        if referencia is not None and len(referencia) > 120:
            raise ErrorDeNegocio("La referencia puede tener hasta 120 caracteres")
        return DatosParadero(
            nombre, referencia, datos.ubicacion, datos.en_tramo_comun, datos.principal
        )

    def _exigir_dentro_del_corredor(self, datos: DatosParadero) -> None:
        distancia = self._repo.distancia_al_corredor(datos.ubicacion)
        if distancia is None or distancia > self._u.tolerancia_corredor_m:
            metros = "?" if distancia is None else f"{distancia:.0f}"
            raise FueraDelCorredor(
                f"El paradero queda a {metros} m del trazado más cercano; "
                f"debe estar a {self._u.tolerancia_corredor_m:.0f} m o menos (RN-003)"
            )

    # ------------------------------------------------------------------
    # A-04 Unidades y cuentas (RF-016)
    # ------------------------------------------------------------------
    def unidades(self) -> list[UnidadAdmin]:
        return self._repo.listar_unidades()

    def crear_unidad(self, admin: Identidad, etiqueta: str) -> UnidadAdmin:
        etiqueta = etiqueta.strip()
        if not FORMATO_ETIQUETA.match(etiqueta):
            raise ErrorDeNegocio("La etiqueta debe tener de 1 a 20 letras, números o guiones")
        unidad_id = self._repo.crear_unidad(etiqueta)
        if unidad_id is None:
            raise Conflicto(f"Ya existe la unidad {etiqueta}")
        self._repo.auditar(
            "SEGURIDAD", admin.cuenta_id, {"accion": "crear_unidad", "unidad": etiqueta}, unidad_id
        )
        return next(u for u in self._repo.listar_unidades() if u.id == unidad_id)

    def cambiar_estado_unidad(self, admin: Identidad, unidad_id: UUID, activa: bool) -> UnidadAdmin:
        if not self._repo.cambiar_estado_unidad(unidad_id, activa):
            raise RecursoNoEncontrado("La unidad no existe")
        self._repo.auditar(
            "SEGURIDAD",
            admin.cuenta_id,
            {"accion": "habilitar_unidad" if activa else "deshabilitar_unidad"},
            unidad_id,
        )
        return next(u for u in self._repo.listar_unidades() if u.id == unidad_id)

    def cuentas_conductor(self) -> list[CuentaAdmin]:
        return self._repo.listar_cuentas_conductor()

    def cuentas_panel(self) -> list[CuentaAdmin]:
        return self._repo.listar_cuentas_panel()

    def crear_cuenta_conductor(
        self, admin: Identidad, unidad_id: UUID, usuario: str
    ) -> CuentaConClave:
        unidad = self._repo.unidad(unidad_id)
        if unidad is None:
            raise RecursoNoEncontrado("La unidad no existe")
        etiqueta, _ = unidad
        if self._repo.unidad_tiene_cuenta(unidad_id):
            raise Conflicto(f"La unidad {etiqueta} ya tiene cuenta (una sola por unidad, RN-001)")
        self._exigir_usuario_libre(usuario)
        clave = contrasena_aleatoria()
        cuenta_id = self._repo.crear_cuenta_conductor(unidad_id, usuario, hash_contrasena(clave))
        self._repo.auditar(
            "SEGURIDAD",
            admin.cuenta_id,
            {"accion": "crear_cuenta_conductor", "usuario": usuario},
            unidad_id,
        )
        cuenta = next(c for c in self._repo.listar_cuentas_conductor() if c.id == cuenta_id)
        return CuentaConClave(cuenta, clave)

    def crear_cuenta_panel(self, admin: Identidad, usuario: str, rol: Rol) -> CuentaConClave:
        if rol not in (Rol.ADMINISTRADOR, Rol.MODERADOR):
            raise ErrorDeNegocio("El rol del panel debe ser ADMINISTRADOR o MODERADOR")
        self._exigir_usuario_libre(usuario)
        clave = contrasena_aleatoria()
        cuenta_id = self._repo.crear_cuenta_panel(usuario, rol, hash_contrasena(clave))
        self._repo.auditar(
            "SEGURIDAD",
            admin.cuenta_id,
            {"accion": "crear_cuenta_panel", "usuario": usuario, "rol": rol.value},
        )
        cuenta = next(c for c in self._repo.listar_cuentas_panel() if c.id == cuenta_id)
        return CuentaConClave(cuenta, clave)

    def actuar_sobre_cuenta(
        self, admin: Identidad, cuenta_id: UUID, accion: AccionCuenta, panel: bool
    ) -> CuentaConClave | CuentaAdmin:
        cuenta = self._cuenta(cuenta_id, panel)
        if cuenta is None:
            raise RecursoNoEncontrado("La cuenta no existe")
        if panel and accion == AccionCuenta.DESACTIVAR:
            self._proteger_administradores(admin, cuenta)
        tabla = _TABLA_DE_ROL[cuenta.rol]
        clave = None
        if accion == AccionCuenta.RESTABLECER_CONTRASENA:
            clave = contrasena_aleatoria()
            self._repo.cambiar_clave(tabla, cuenta_id, hash_contrasena(clave))
        elif accion in (AccionCuenta.ACTIVAR, AccionCuenta.DESACTIVAR):
            self._repo.cambiar_estado_cuenta(tabla, cuenta_id, accion == AccionCuenta.ACTIVAR)
        else:
            self._repo.desbloquear(tabla, cuenta_id)
        self._repo.auditar(
            "SEGURIDAD",
            admin.cuenta_id,
            {"accion": accion.value, "usuario": cuenta.usuario},
        )
        actualizada = self._cuenta(cuenta_id, panel) or cuenta
        return CuentaConClave(actualizada, clave) if clave else actualizada

    def _cuenta(self, cuenta_id: UUID, panel: bool) -> CuentaAdmin | None:
        repo = self._repo
        cuentas = repo.listar_cuentas_panel() if panel else repo.listar_cuentas_conductor()
        return next((c for c in cuentas if c.id == cuenta_id), None)

    def _exigir_usuario_libre(self, usuario: str) -> None:
        if not FORMATO_USUARIO.match(usuario):
            raise ErrorDeNegocio(
                "El usuario debe tener de 4 a 30 caracteres: minúsculas, números, . o _"
            )
        if self._repo.usuario_existe(usuario):
            raise Conflicto(f"Ya existe una cuenta con el usuario «{usuario}»")

    def _proteger_administradores(self, admin: Identidad, cuenta: CuentaAdmin) -> None:
        if cuenta.id == admin.cuenta_id:
            raise Conflicto("No puede desactivar su propia cuenta")
        if (
            cuenta.rol == Rol.ADMINISTRADOR
            and cuenta.activa
            and self._repo.administradores_activos() <= 1
        ):
            raise Conflicto("Debe quedar al menos un administrador activo")

    # ------------------------------------------------------------------
    # A-05 Registro de eventos (RF-020)
    # ------------------------------------------------------------------
    def eventos(self, filtro: FiltroEventos, ahora: datetime) -> PaginaEventos:
        if filtro.desde > filtro.hasta:
            raise ErrorDeNegocio("La fecha inicial debe ser anterior o igual a la final")
        if filtro.desde < ahora - timedelta(days=DIAS_MAXIMOS_EVENTOS, minutes=5):
            raise ErrorDeNegocio(
                f"Solo se conservan los eventos de los últimos {DIAS_MAXIMOS_EVENTOS} días (RN-012)"
            )
        return self._repo.buscar_eventos(filtro)
