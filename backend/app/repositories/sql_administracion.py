"""Repositorio del panel de administración sobre PostgreSQL + PostGIS (RF-014 a RF-020).

Todas las consultas usan parámetros enlazados (OWASP A03). El orden de los paraderos y la
regla de los 150 m (RN-003) los aplica la propia base con fn_asignar_paraderos_variante y
fn_recalcular_paraderos_variante; aquí solo se traducen sus errores a errores del negocio.
"""

import json
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm import Session

from app.domain.administracion import (
    CuentaAdmin,
    DatosParadero,
    Evento,
    FiltroEventos,
    Horario,
    PaginaEventos,
    ParaderoAdmin,
    UnidadAdmin,
    UnidadDeFlota,
)
from app.domain.excepciones import Conflicto, ErrorDeNegocio, FueraDelCorredor
from app.domain.modelos import Coordenada, Ramal, Rol, Sentido

CODIGO_LINEA = "LB"
# Los códigos stp_900 a stp_999 quedan para las pruebas de la base de datos
ULTIMO_CODIGO_PARADERO = 899

# ----------------------------------------------------------------------
# A-02 Flota
# ----------------------------------------------------------------------
_SQL_FLOTA = text("""
    SELECT u.id, u.etiqueta, c.usuario, u.creada_en,
           (SELECT max(x.fin) FROM sesion_emision x WHERE x.unidad_id = u.id) AS ultimo_fin,
           s.inicio, s.ultima_posicion_en,
           ST_Y(s.ultima_ubicacion) AS lat, ST_X(s.ultima_ubicacion) AS lon, s.ultimo_rumbo,
           v.ramal::text AS ramal, v.sentido::text AS sentido, v.destino
      FROM unidad u
      LEFT JOIN cuenta_conductor c ON c.unidad_id = u.id
      LEFT JOIN sesion_emision s   ON s.unidad_id = u.id AND s.estado IN ('ACTIVA', 'SIN_SENAL')
      LEFT JOIN variante v         ON v.id = s.variante_id
     WHERE u.activa
     ORDER BY u.etiqueta
""")

# ----------------------------------------------------------------------
# A-03 Línea, variantes y paraderos
# ----------------------------------------------------------------------
_SQL_HORARIO = text("""
    UPDATE linea SET hora_inicio = :inicio, hora_fin = :fin, actualizado_en = now()
     WHERE codigo = :codigo
 RETURNING hora_inicio, hora_fin
""")

_SQL_VARIANTES = text("""
    SELECT v.id, v.ramal::text AS ramal, v.sentido::text AS sentido, v.destino, v.longitud_m,
           ST_AsGeoJSON(v.trazado, 6) AS trazado
      FROM variante v JOIN linea l ON l.id = v.linea_id
     WHERE l.codigo = :codigo AND v.activa
     ORDER BY v.ramal, v.sentido
""")

_SQL_PARADEROS_VARIANTE = text("""
    SELECT p.codigo, p.nombre, p.referencia, ST_Y(p.ubicacion) AS lat, ST_X(p.ubicacion) AS lon,
           p.en_tramo_comun, pv.orden, pv.distancia_desde_inicio_m
      FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
     WHERE pv.variante_id = :variante
     ORDER BY pv.orden
""")

_SQL_PARADEROS = text(r"""
    SELECT p.codigo, p.nombre, p.referencia, ST_Y(p.ubicacion) AS lat, ST_X(p.ubicacion) AS lon,
           p.en_tramo_comun, p.activo,
           COALESCE(array_agg(v.ramal::text || '-' || v.sentido::text
                              ORDER BY v.ramal, v.sentido)
                    FILTER (WHERE v.id IS NOT NULL), '{}') AS variantes
      FROM paradero p
      LEFT JOIN paradero_variante pv ON pv.paradero_id = p.id
      LEFT JOIN variante v ON v.id = pv.variante_id
     WHERE CAST(:patron AS text) IS NULL
        OR lower(f_unaccent(p.nombre)) LIKE '%' || lower(f_unaccent(:patron)) || '%' ESCAPE '\'
        OR p.codigo = lower(:texto)
     GROUP BY p.id
     ORDER BY p.codigo
""")

# Distancia del punto al trazado de variante activa más cercano (RN-003)
_SQL_DISTANCIA_AL_CORREDOR = text("""
    SELECT min(ST_Distance(ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography,
                           v.trazado::geography))
      FROM variante v
     WHERE v.activa
""")

_SQL_CODIGOS_USADOS = text("SELECT codigo FROM paradero")

_SQL_CREAR_PARADERO = text("""
    INSERT INTO paradero (codigo, nombre, referencia, ubicacion, en_tramo_comun)
    VALUES (:codigo, :nombre, :referencia, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326), :comun)
""")

_SQL_EDITAR_PARADERO = text("""
    UPDATE paradero
       SET nombre = :nombre, referencia = :referencia, en_tramo_comun = :comun,
           ubicacion = ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)
     WHERE codigo = :codigo
""")

_SQL_ACTIVAR_PARADERO = text("UPDATE paradero SET activo = :activo WHERE codigo = :codigo")

_SQL_VARIANTES_DE_PARADERO = text("""
    SELECT pv.variante_id
      FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
     WHERE p.codigo = :codigo
""")

_SQL_CODIGOS_DE_VARIANTE = text("""
    SELECT p.codigo
      FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
     WHERE pv.variante_id = :variante
     ORDER BY pv.orden
""")

_SQL_ASIGNAR = text("SELECT fn_asignar_paraderos_variante(:variante, CAST(:codigos AS varchar[]))")

# ----------------------------------------------------------------------
# A-04 Unidades y cuentas
# ----------------------------------------------------------------------
_SQL_UNIDADES = text("""
    SELECT u.id, u.etiqueta, u.activa, c.usuario, u.creada_en
      FROM unidad u LEFT JOIN cuenta_conductor c ON c.unidad_id = u.id
     ORDER BY u.etiqueta
""")

_SQL_CREAR_UNIDAD = text("""
    INSERT INTO unidad (etiqueta) VALUES (:etiqueta)
    ON CONFLICT (etiqueta) DO NOTHING
    RETURNING id
""")

_SQL_ACTIVAR_UNIDAD = text("UPDATE unidad SET activa = :activa WHERE id = :id RETURNING id")

# Al deshabilitar una unidad, su sesión abierta se cierra: deja de verse en el mapa
_SQL_CERRAR_SESIONES_UNIDAD = text("""
    UPDATE sesion_emision
       SET estado = 'CERRADA_AUTOMATICAMENTE', fin = greatest(now(), inicio + interval '1 second')
     WHERE unidad_id = :id AND estado IN ('ACTIVA', 'SIN_SENAL')
""")

_SQL_CUENTAS_CONDUCTOR = text("""
    SELECT c.id, c.usuario, c.activa, c.bloqueada_hasta, u.etiqueta
      FROM cuenta_conductor c JOIN unidad u ON u.id = c.unidad_id
     ORDER BY u.etiqueta
""")

_SQL_CUENTAS_PANEL = text("""
    SELECT id, usuario, rol::text AS rol, activa, bloqueada_hasta
      FROM cuenta_administrativa
     ORDER BY usuario
""")

_SQL_USUARIO_EXISTE = text("""
    SELECT 1 FROM cuenta_conductor WHERE usuario = :u
    UNION ALL SELECT 1 FROM cuenta_administrativa WHERE usuario = :u
""")

_SQL_UNIDAD_TIENE_CUENTA = text("SELECT 1 FROM cuenta_conductor WHERE unidad_id = :id")
_SQL_UNIDAD_POR_ID = text("SELECT etiqueta, activa FROM unidad WHERE id = :id")

_SQL_CREAR_CONDUCTOR = text("""
    INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
    VALUES (:unidad, :usuario, :hash) RETURNING id
""")

_SQL_CREAR_PANEL = text("""
    INSERT INTO cuenta_administrativa (usuario, hash_contrasena, rol)
    VALUES (:usuario, :hash, CAST(:rol AS rol_t)) RETURNING id
""")

_SQL_ADMINISTRADORES_ACTIVOS = text("""
    SELECT count(*) FROM cuenta_administrativa WHERE rol = 'ADMINISTRADOR' AND activa
""")

# Cada tabla de cuentas tiene sus propias sentencias (sin SQL armado con texto, Bandit B608)
_SQL_CUENTA = {
    "cuenta_conductor": {
        "clave": text("""UPDATE cuenta_conductor SET hash_contrasena = :hash,
                         intentos_fallidos = 0, bloqueada_hasta = NULL WHERE id = :id"""),
        "activa": text("UPDATE cuenta_conductor SET activa = :activa WHERE id = :id"),
        "desbloquear": text("""UPDATE cuenta_conductor SET intentos_fallidos = 0,
                               bloqueada_hasta = NULL WHERE id = :id"""),
    },
    "cuenta_administrativa": {
        "clave": text("""UPDATE cuenta_administrativa SET hash_contrasena = :hash,
                         intentos_fallidos = 0, bloqueada_hasta = NULL WHERE id = :id"""),
        "activa": text("UPDATE cuenta_administrativa SET activa = :activa WHERE id = :id"),
        "desbloquear": text("""UPDATE cuenta_administrativa SET intentos_fallidos = 0,
                               bloqueada_hasta = NULL WHERE id = :id"""),
    },
}

# ----------------------------------------------------------------------
# A-05 Eventos y auditoría del panel
# ----------------------------------------------------------------------
# Las dos consultas repiten el filtro a propósito: ningún SQL se arma con texto (Bandit B608)
_SQL_CONTAR_EVENTOS = text("""
    SELECT count(*)
      FROM registro_evento e
      LEFT JOIN unidad u ON u.id = e.unidad_id
     WHERE e.fecha BETWEEN :desde AND :hasta
       AND (CAST(:tipo AS text) IS NULL OR e.tipo = CAST(:tipo AS tipo_evento_t))
       AND (CAST(:unidad AS text) IS NULL OR u.etiqueta = :unidad)
""")
_SQL_EVENTOS = text("""
    SELECT e.id, e.fecha, e.tipo::text AS tipo, e.origen, u.etiqueta, a.usuario,
           e.codigo_http, e.detalle
      FROM registro_evento e
      LEFT JOIN unidad u ON u.id = e.unidad_id
      LEFT JOIN cuenta_administrativa a ON a.id = e.cuenta_administrativa_id
     WHERE e.fecha BETWEEN :desde AND :hasta
       AND (CAST(:tipo AS text) IS NULL OR e.tipo = CAST(:tipo AS tipo_evento_t))
       AND (CAST(:unidad AS text) IS NULL OR u.etiqueta = :unidad)
     ORDER BY e.fecha DESC, e.id DESC
     LIMIT :limite OFFSET :desplazamiento
""")

_SQL_AUDITAR = text("""
    INSERT INTO registro_evento (tipo, origen, unidad_id, cuenta_administrativa_id, detalle)
    VALUES (CAST(:tipo AS tipo_evento_t), 'panel', :unidad, :admin, CAST(:detalle AS jsonb))
""")


def _coordenada(lat: Any, lon: Any) -> Coordenada | None:
    return None if lat is None else Coordenada(float(lat), float(lon))


class RepositorioAdministracionSQL:
    def __init__(self, sesion: Session) -> None:
        self._s = sesion

    @contextmanager
    def _traducir_errores_de_ruta(self) -> Iterator[None]:
        """Los errores de las funciones de la base, como errores del negocio.

        El punto de guardado deja la transacción usable si la base rechaza el cambio.
        """
        try:
            with self._s.begin_nested():
                yield
        except DBAPIError as e:
            estado = getattr(e.orig, "sqlstate", None)
            diag = getattr(e.orig, "diag", None)
            mensaje = getattr(diag, "message_primary", None) or "La base rechazó el cambio"
            if estado == "23514":  # check_violation: paradero a más de 150 m del trazado
                raise FueraDelCorredor(mensaje) from None
            if estado in ("23505", "23503"):  # repetidos o paradero inexistente/inactivo
                raise ErrorDeNegocio(mensaje) from None
            raise

    # --- A-02 ---------------------------------------------------------------
    def listar_flota(self) -> list[UnidadDeFlota]:
        return [
            UnidadDeFlota(
                unidad_id=f["id"],
                etiqueta=f["etiqueta"],
                usuario=f["usuario"],
                creada_en=f["creada_en"],
                ultimo_fin=f["ultimo_fin"],
                sesion_inicio=f["inicio"],
                ultima_posicion_en=f["ultima_posicion_en"],
                ubicacion=_coordenada(f["lat"], f["lon"]),
                rumbo=f["ultimo_rumbo"],
                ramal=Ramal(f["ramal"]) if f["ramal"] else None,
                sentido=Sentido(f["sentido"]) if f["sentido"] else None,
                destino=f["destino"],
            )
            for f in self._s.execute(_SQL_FLOTA).mappings()
        ]

    # --- A-03 ---------------------------------------------------------------
    def actualizar_horario(self, horario: Horario) -> Horario:
        f = self._s.execute(
            _SQL_HORARIO, {"inicio": horario.inicio, "fin": horario.fin, "codigo": CODIGO_LINEA}
        ).first()
        return Horario(f.hora_inicio, f.hora_fin)

    def listar_variantes(self) -> list[dict]:
        """Variantes con su trazado y sus paraderos en orden (para el mapa de A-03)."""
        variantes = []
        for v in self._s.execute(_SQL_VARIANTES, {"codigo": CODIGO_LINEA}).mappings():
            paraderos = self._s.execute(_SQL_PARADEROS_VARIANTE, {"variante": v["id"]}).mappings()
            variantes.append(
                {
                    "id": v["id"],
                    "ramal": Ramal(v["ramal"]),
                    "sentido": Sentido(v["sentido"]),
                    "destino": v["destino"],
                    "longitud_m": float(v["longitud_m"]),
                    "trazado": [
                        Coordenada(lat, lon) for lon, lat in json.loads(v["trazado"])["coordinates"]
                    ],
                    "paraderos": [
                        {
                            "codigo": p["codigo"],
                            "nombre": p["nombre"],
                            "referencia": p["referencia"],
                            "ubicacion": Coordenada(p["lat"], p["lon"]),
                            "en_tramo_comun": p["en_tramo_comun"],
                            "orden": p["orden"],
                            "distancia_m": float(p["distancia_desde_inicio_m"]),
                        }
                        for p in paraderos
                    ],
                }
            )
        return variantes

    def variante_existe(self, variante_id: UUID) -> bool:
        return any(
            v["id"] == variante_id
            for v in self._s.execute(_SQL_VARIANTES, {"codigo": CODIGO_LINEA}).mappings()
        )

    def asignar_paraderos(self, variante_id: UUID, codigos: list[str]) -> None:
        with self._traducir_errores_de_ruta():
            self._s.execute(_SQL_ASIGNAR, {"variante": variante_id, "codigos": codigos})

    def listar_paraderos(self, texto: str | None) -> list[ParaderoAdmin]:
        patron = None
        if texto:
            patron = texto.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_")
        return [
            ParaderoAdmin(
                codigo=f["codigo"],
                nombre=f["nombre"],
                referencia=f["referencia"],
                ubicacion=Coordenada(f["lat"], f["lon"]),
                en_tramo_comun=f["en_tramo_comun"],
                activo=f["activo"],
                variantes=list(f["variantes"]),
            )
            for f in self._s.execute(_SQL_PARADEROS, {"patron": patron, "texto": texto}).mappings()
        ]

    def obtener_paradero(self, codigo: str) -> ParaderoAdmin | None:
        return next((p for p in self.listar_paraderos(codigo) if p.codigo == codigo), None)

    def distancia_al_corredor(self, punto: Coordenada) -> float | None:
        valor = self._s.execute(
            _SQL_DISTANCIA_AL_CORREDOR, {"lat": punto.lat, "lon": punto.lon}
        ).scalar()
        return None if valor is None else float(valor)

    def siguiente_codigo_paradero(self) -> str:
        usados = {int(c[4:]) for (c,) in self._s.execute(_SQL_CODIGOS_USADOS) if c[4:].isdigit()}
        for n in range(1, ULTIMO_CODIGO_PARADERO + 1):
            if n not in usados:
                return f"stp_{n:03d}"
        raise Conflicto("No quedan códigos de paradero disponibles")

    def crear_paradero(self, codigo: str, datos: DatosParadero) -> None:
        self._s.execute(_SQL_CREAR_PARADERO, {"codigo": codigo, **self._parametros(datos)})

    def editar_paradero(self, codigo: str, datos: DatosParadero) -> None:
        # Si cambia la ubicación, un trigger recalcula sus variantes y valida los 150 m
        with self._traducir_errores_de_ruta():
            self._s.execute(_SQL_EDITAR_PARADERO, {"codigo": codigo, **self._parametros(datos)})

    def cambiar_estado_paradero(self, codigo: str, activo: bool) -> None:
        self._s.execute(_SQL_ACTIVAR_PARADERO, {"codigo": codigo, "activo": activo})

    def quitar_de_variantes(self, codigo: str) -> None:
        """Saca el paradero de todas sus variantes y recalcula el orden de cada una."""
        variantes = [v for (v,) in self._s.execute(_SQL_VARIANTES_DE_PARADERO, {"codigo": codigo})]
        for variante in variantes:
            restantes = [
                c
                for (c,) in self._s.execute(_SQL_CODIGOS_DE_VARIANTE, {"variante": variante})
                if c != codigo
            ]
            self.asignar_paraderos(variante, restantes)

    @staticmethod
    def _parametros(datos: DatosParadero) -> dict:
        return {
            "nombre": datos.nombre,
            "referencia": datos.referencia,
            "lat": datos.ubicacion.lat,
            "lon": datos.ubicacion.lon,
            "comun": datos.en_tramo_comun,
        }

    # --- A-04 ---------------------------------------------------------------
    def listar_unidades(self) -> list[UnidadAdmin]:
        return [
            UnidadAdmin(f["id"], f["etiqueta"], f["activa"], f["usuario"], f["creada_en"])
            for f in self._s.execute(_SQL_UNIDADES).mappings()
        ]

    def crear_unidad(self, etiqueta: str) -> UUID | None:
        """Devuelve None si la etiqueta ya existe."""
        return self._s.execute(_SQL_CREAR_UNIDAD, {"etiqueta": etiqueta}).scalar()

    def cambiar_estado_unidad(self, unidad_id: UUID, activa: bool) -> bool:
        encontrada = self._s.execute(
            _SQL_ACTIVAR_UNIDAD, {"id": unidad_id, "activa": activa}
        ).scalar()
        if encontrada and not activa:
            self._s.execute(_SQL_CERRAR_SESIONES_UNIDAD, {"id": unidad_id})
        return encontrada is not None

    def unidad(self, unidad_id: UUID) -> tuple[str, bool] | None:
        f = self._s.execute(_SQL_UNIDAD_POR_ID, {"id": unidad_id}).first()
        return None if f is None else (f.etiqueta, f.activa)

    def unidad_tiene_cuenta(self, unidad_id: UUID) -> bool:
        return self._s.execute(_SQL_UNIDAD_TIENE_CUENTA, {"id": unidad_id}).first() is not None

    def usuario_existe(self, usuario: str) -> bool:
        return self._s.execute(_SQL_USUARIO_EXISTE, {"u": usuario}).first() is not None

    def listar_cuentas_conductor(self) -> list[CuentaAdmin]:
        return [
            CuentaAdmin(
                id=f["id"],
                usuario=f["usuario"],
                rol=Rol.CONDUCTOR,
                activa=f["activa"],
                bloqueada_hasta=f["bloqueada_hasta"],
                etiqueta_unidad=f["etiqueta"],
            )
            for f in self._s.execute(_SQL_CUENTAS_CONDUCTOR).mappings()
        ]

    def listar_cuentas_panel(self) -> list[CuentaAdmin]:
        return [
            CuentaAdmin(
                id=f["id"],
                usuario=f["usuario"],
                rol=Rol(f["rol"]),
                activa=f["activa"],
                bloqueada_hasta=f["bloqueada_hasta"],
            )
            for f in self._s.execute(_SQL_CUENTAS_PANEL).mappings()
        ]

    def crear_cuenta_conductor(self, unidad_id: UUID, usuario: str, hash_clave: str) -> UUID:
        return self._s.execute(
            _SQL_CREAR_CONDUCTOR, {"unidad": unidad_id, "usuario": usuario, "hash": hash_clave}
        ).scalar_one()

    def crear_cuenta_panel(self, usuario: str, rol: Rol, hash_clave: str) -> UUID:
        return self._s.execute(
            _SQL_CREAR_PANEL, {"usuario": usuario, "hash": hash_clave, "rol": rol.value}
        ).scalar_one()

    def administradores_activos(self) -> int:
        return int(self._s.execute(_SQL_ADMINISTRADORES_ACTIVOS).scalar_one())

    def cambiar_clave(self, tabla: str, cuenta_id: UUID, hash_clave: str) -> None:
        self._s.execute(_SQL_CUENTA[tabla]["clave"], {"id": cuenta_id, "hash": hash_clave})

    def cambiar_estado_cuenta(self, tabla: str, cuenta_id: UUID, activa: bool) -> None:
        self._s.execute(_SQL_CUENTA[tabla]["activa"], {"id": cuenta_id, "activa": activa})

    def desbloquear(self, tabla: str, cuenta_id: UUID) -> None:
        self._s.execute(_SQL_CUENTA[tabla]["desbloquear"], {"id": cuenta_id})

    # --- A-05 ---------------------------------------------------------------
    def buscar_eventos(self, filtro: FiltroEventos) -> PaginaEventos:
        parametros = {
            "desde": filtro.desde,
            "hasta": filtro.hasta,
            "tipo": filtro.tipo,
            "unidad": filtro.etiqueta_unidad,
        }
        total = int(self._s.execute(_SQL_CONTAR_EVENTOS, parametros).scalar_one())
        filas = self._s.execute(
            _SQL_EVENTOS,
            {
                **parametros,
                "limite": filtro.tamano,
                "desplazamiento": (filtro.pagina - 1) * filtro.tamano,
            },
        ).mappings()
        eventos = [
            Evento(
                id=f["id"],
                fecha=f["fecha"],
                tipo=f["tipo"],
                origen=f["origen"],
                etiqueta_unidad=f["etiqueta"],
                usuario_panel=f["usuario"],
                codigo_http=f["codigo_http"],
                detalle=f["detalle"],
            )
            for f in filas
        ]
        return PaginaEventos(eventos, total)

    def auditar(
        self,
        tipo: str,
        admin_id: UUID,
        detalle: dict[str, Any],
        unidad_id: UUID | None = None,
    ) -> None:
        self._s.execute(
            _SQL_AUDITAR,
            {
                "tipo": tipo,
                "unidad": unidad_id,
                "admin": admin_id,
                "detalle": json.dumps(detalle, ensure_ascii=False),
            },
        )
