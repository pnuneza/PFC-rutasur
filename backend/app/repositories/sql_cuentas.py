"""Repositorio de cuentas: conductores (una por unidad) y personal del panel."""

import json
from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.domain.modelos import CuentaAcceso, Rol

# Un mismo inicio de sesión sirve a conductores y al panel (P06 Tabla 52). La herramienta
# de cuentas impide repetir un usuario entre las dos tablas.
_SQL_BUSCAR = text("""
    SELECT c.id, c.usuario, c.hash_contrasena, 'CONDUCTOR' AS rol,
           (c.activa AND u.activa) AS activa, c.bloqueada_hasta,
           u.id AS unidad_id, u.etiqueta AS etiqueta_unidad
      FROM cuenta_conductor c
      JOIN unidad u ON u.id = c.unidad_id
     WHERE c.usuario = :usuario
    UNION ALL
    SELECT a.id, a.usuario, a.hash_contrasena, a.rol::text,
           a.activa, a.bloqueada_hasta, NULL, NULL
      FROM cuenta_administrativa a
     WHERE a.usuario = :usuario
     LIMIT 1
""")

# Atómico: dos intentos simultáneos no pueden saltarse el bloqueo
_SQL_FALLO = """
    UPDATE {tabla}
       SET intentos_fallidos = CASE WHEN intentos_fallidos + 1 >= :maximo
                                    THEN 0 ELSE intentos_fallidos + 1 END,
           bloqueada_hasta   = CASE WHEN intentos_fallidos + 1 >= :maximo
                                    THEN :hasta ELSE bloqueada_hasta END
     WHERE id = :id
 RETURNING bloqueada_hasta = :hasta AS bloqueada
"""

_SQL_INGRESO = """
    UPDATE {tabla} SET intentos_fallidos = 0, bloqueada_hasta = NULL
     WHERE id = :id AND (intentos_fallidos <> 0 OR bloqueada_hasta IS NOT NULL)
"""

_SQL_VIGENTE_CONDUCTOR = text("""
    SELECT c.activa AND u.activa
      FROM cuenta_conductor c JOIN unidad u ON u.id = c.unidad_id
     WHERE c.id = :id
""")
_SQL_VIGENTE_PANEL = text("""
    SELECT activa FROM cuenta_administrativa WHERE id = :id AND rol::text = :rol
""")

_SQL_EVENTO = text("""
    INSERT INTO registro_evento
           (tipo, origen, unidad_id, cuenta_administrativa_id, codigo_http, detalle)
    VALUES (CAST(:tipo AS tipo_evento_t), :origen, :unidad_id, :admin_id, :http,
            CAST(:detalle AS jsonb))
""")

_TABLAS = {True: "cuenta_conductor", False: "cuenta_administrativa"}


def _tabla(cuenta: CuentaAcceso) -> str:
    return _TABLAS[cuenta.rol == Rol.CONDUCTOR]


class RepositorioCuentasSQL:
    def __init__(self, sesion: Session) -> None:
        self._s = sesion

    def buscar_por_usuario(self, usuario: str) -> CuentaAcceso | None:
        f = self._s.execute(_SQL_BUSCAR, {"usuario": usuario}).mappings().first()
        if f is None:
            return None
        return CuentaAcceso(
            id=f["id"],
            usuario=f["usuario"],
            hash_contrasena=f["hash_contrasena"].strip(),  # CHAR(60)
            rol=Rol(f["rol"]),
            activa=f["activa"],
            bloqueada_hasta=f["bloqueada_hasta"],
            unidad_id=f["unidad_id"],
            etiqueta_unidad=f["etiqueta_unidad"],
        )

    def registrar_fallo(
        self, cuenta: CuentaAcceso, intentos_maximos: int, bloquear_hasta: datetime
    ) -> bool:
        consulta = text(_SQL_FALLO.format(tabla=_tabla(cuenta)))  # nosec B608
        return bool(
            self._s.execute(
                consulta, {"id": cuenta.id, "maximo": intentos_maximos, "hasta": bloquear_hasta}
            ).scalar()
        )

    def registrar_ingreso(self, cuenta: CuentaAcceso) -> None:
        consulta = text(_SQL_INGRESO.format(tabla=_tabla(cuenta)))  # nosec B608
        self._s.execute(consulta, {"id": cuenta.id})

    def cuenta_vigente(self, cuenta_id: UUID, rol: Rol) -> bool:
        if rol == Rol.CONDUCTOR:
            fila = self._s.execute(_SQL_VIGENTE_CONDUCTOR, {"id": cuenta_id}).scalar()
        else:
            fila = self._s.execute(_SQL_VIGENTE_PANEL, {"id": cuenta_id, "rol": rol.value}).scalar()
        return bool(fila)

    def registrar_evento(
        self, tipo: str, origen: str, cuenta: CuentaAcceso | None, detalle: dict[str, Any]
    ) -> None:
        conductor = cuenta is not None and cuenta.rol == Rol.CONDUCTOR
        self._s.execute(
            _SQL_EVENTO,
            {
                "tipo": tipo,
                "origen": origen,
                "unidad_id": cuenta.unidad_id if conductor else None,
                "admin_id": cuenta.id if cuenta is not None and not conductor else None,
                "http": detalle.pop("http", None),
                "detalle": json.dumps(detalle),
            },
        )
