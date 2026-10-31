"""Gestión de unidades y cuentas desde la terminal (RF-014, RF-016).

Mientras el panel de administración no exista (Módulo 6), esta herramienta crea las
unidades, las cuentas de conductor y las del panel. La contraseña se genera al azar y
se muestra UNA sola vez; en la base solo queda su hash bcrypt (P06 A-04).

Usa la conexión de DATABASE_URL (archivo .env o variable de entorno). Para la nube,
antes de ejecutar defina la cadena del rol rutasur_app de Neon:
    $env:DATABASE_URL = "postgresql://rutasur_app:…@ep-….neon.tech/neondb?sslmode=require"

Uso:
    python -m app.herramientas.cuentas listar
    python -m app.herramientas.cuentas crear-conductor --unidad 07
    python -m app.herramientas.cuentas crear-panel --usuario pierre.admin --rol ADMINISTRADOR
    python -m app.herramientas.cuentas nueva-clave --usuario unidad07
    python -m app.herramientas.cuentas desbloquear --usuario unidad07
    python -m app.herramientas.cuentas habilitar --usuario unidad07 --no
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.seguridad import contrasena_aleatoria, hash_contrasena
from app.db.conexion import obtener_motor

FORMATO_USUARIO = re.compile(r"^[a-z0-9._]{4,30}$")
FORMATO_ETIQUETA = re.compile(r"^[A-Za-z0-9-]{1,20}$")


class ErrorDeCuenta(Exception):
    pass


@dataclass(frozen=True)
class CuentaCreada:
    usuario: str
    contrasena: str
    detalle: str


# ----------------------------------------------------------------------
# Operaciones (reciben la sesión: se prueban dentro de una transacción)
# ----------------------------------------------------------------------
def _usuario_libre(s: Session, usuario: str) -> None:
    if not FORMATO_USUARIO.match(usuario):
        raise ErrorDeCuenta(
            "El usuario debe tener de 4 a 30 caracteres: minúsculas, números, . o _"
        )
    existe = s.execute(
        text("""SELECT 1 FROM cuenta_conductor WHERE usuario = :u
                UNION ALL SELECT 1 FROM cuenta_administrativa WHERE usuario = :u"""),
        {"u": usuario},
    ).first()
    if existe:
        raise ErrorDeCuenta(f"Ya existe una cuenta con el usuario «{usuario}»")


def _evento(s: Session, accion: str, detalle: dict) -> None:
    s.execute(
        text("""INSERT INTO registro_evento (tipo, origen, detalle)
                VALUES ('SEGURIDAD', 'herramienta_cuentas', CAST(:d AS jsonb))"""),
        {"d": json.dumps({"accion": accion, **detalle})},
    )


def crear_conductor(s: Session, etiqueta: str, usuario: str | None = None) -> CuentaCreada:
    """Crea la unidad si no existe y su única cuenta de conductor (RN-001)."""
    if not FORMATO_ETIQUETA.match(etiqueta):
        raise ErrorDeCuenta(
            "La etiqueta de la unidad debe tener de 1 a 20 letras, números o guiones"
        )
    usuario = usuario or f"unidad{etiqueta.lower()}"
    _usuario_libre(s, usuario)
    unidad_id = s.execute(
        text("""INSERT INTO unidad (etiqueta) VALUES (:e)
                ON CONFLICT (etiqueta) DO UPDATE SET etiqueta = EXCLUDED.etiqueta
                RETURNING id"""),
        {"e": etiqueta},
    ).scalar_one()
    if s.execute(
        text("SELECT 1 FROM cuenta_conductor WHERE unidad_id = :u"), {"u": unidad_id}
    ).first():
        raise ErrorDeCuenta(f"La unidad {etiqueta} ya tiene cuenta (una sola por unidad, RN-001)")
    clave = contrasena_aleatoria()
    s.execute(
        text("""INSERT INTO cuenta_conductor (unidad_id, usuario, hash_contrasena)
                VALUES (:u, :usuario, :h)"""),
        {"u": unidad_id, "usuario": usuario, "h": hash_contrasena(clave)},
    )
    _evento(s, "crear_conductor", {"usuario": usuario, "unidad": etiqueta})
    return CuentaCreada(usuario, clave, f"conductor de la unidad {etiqueta}")


def crear_panel(s: Session, usuario: str, rol: str) -> CuentaCreada:
    if rol not in ("ADMINISTRADOR", "MODERADOR"):
        raise ErrorDeCuenta("El rol debe ser ADMINISTRADOR o MODERADOR")
    _usuario_libre(s, usuario)
    clave = contrasena_aleatoria()
    s.execute(
        text("""INSERT INTO cuenta_administrativa (usuario, hash_contrasena, rol)
                VALUES (:usuario, :h, CAST(:rol AS rol_t))"""),
        {"usuario": usuario, "h": hash_contrasena(clave), "rol": rol},
    )
    _evento(s, "crear_panel", {"usuario": usuario, "rol": rol})
    return CuentaCreada(usuario, clave, rol.lower())


# Los usuarios no se repiten entre las dos tablas, así que cada cambio se aplica a ambas
# y afecta exactamente una fila (sin armar SQL con el nombre de la tabla).
_SQL_CLAVE = [
    text("""UPDATE cuenta_conductor SET hash_contrasena = :h, intentos_fallidos = 0,
            bloqueada_hasta = NULL WHERE usuario = :u"""),
    text("""UPDATE cuenta_administrativa SET hash_contrasena = :h, intentos_fallidos = 0,
            bloqueada_hasta = NULL WHERE usuario = :u"""),
]
_SQL_DESBLOQUEAR = [
    text("""UPDATE cuenta_conductor SET intentos_fallidos = 0, bloqueada_hasta = NULL
             WHERE usuario = :u"""),
    text("""UPDATE cuenta_administrativa SET intentos_fallidos = 0, bloqueada_hasta = NULL
             WHERE usuario = :u"""),
]
_SQL_HABILITAR = [
    text("UPDATE cuenta_conductor SET activa = :a WHERE usuario = :u"),
    text("UPDATE cuenta_administrativa SET activa = :a WHERE usuario = :u"),
]


def _actualizar(s: Session, consultas: list, usuario: str, **valores) -> None:
    filas = sum(s.execute(c, {"u": usuario, **valores}).rowcount for c in consultas)
    if filas == 0:
        raise ErrorDeCuenta(f"No existe la cuenta «{usuario}»")


def nueva_clave(s: Session, usuario: str) -> CuentaCreada:
    """Contraseña nueva; también desbloquea la cuenta."""
    clave = contrasena_aleatoria()
    _actualizar(s, _SQL_CLAVE, usuario, h=hash_contrasena(clave))
    _evento(s, "nueva_clave", {"usuario": usuario})
    return CuentaCreada(usuario, clave, "contraseña restablecida")


def desbloquear(s: Session, usuario: str) -> None:
    _actualizar(s, _SQL_DESBLOQUEAR, usuario)
    _evento(s, "desbloquear", {"usuario": usuario})


def habilitar(s: Session, usuario: str, activa: bool) -> None:
    _actualizar(s, _SQL_HABILITAR, usuario, a=activa)
    if not activa:  # quien deja de estar habilitado no sigue transmitiendo
        s.execute(
            text("""UPDATE sesion_emision SET estado = 'CERRADA_AUTOMATICAMENTE', fin = now()
                     WHERE fin IS NULL AND cuenta_conductor_id IN
                           (SELECT id FROM cuenta_conductor WHERE usuario = :u)"""),
            {"u": usuario},
        )
    _evento(s, "habilitar" if activa else "deshabilitar", {"usuario": usuario})


def listar(s: Session) -> list[dict]:
    filas = s.execute(
        text("""SELECT c.usuario, 'CONDUCTOR' AS rol, u.etiqueta AS unidad,
                       c.activa AND u.activa AS activa, c.bloqueada_hasta > now() AS bloqueada
                  FROM cuenta_conductor c JOIN unidad u ON u.id = c.unidad_id
                UNION ALL
                SELECT usuario, rol::text, NULL, activa, bloqueada_hasta > now()
                  FROM cuenta_administrativa
                 ORDER BY rol, usuario""")
    ).mappings()
    return [dict(f) for f in filas]


# ----------------------------------------------------------------------
# Terminal
# ----------------------------------------------------------------------
def _mostrar_clave(c: CuentaCreada) -> None:
    print(f"\n  Cuenta: {c.usuario}  ({c.detalle})")
    print(f"  Contraseña: {c.contrasena}")
    print("\n  Anótela ahora y entréguela en persona: no se vuelve a mostrar.\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cuentas", description="Unidades y cuentas de RutaSur")
    sub = parser.add_subparsers(dest="orden", required=True)
    sub.add_parser("listar", help="Cuentas con su rol, unidad y estado")
    p = sub.add_parser("crear-conductor", help="Unidad y su cuenta de conductor")
    p.add_argument("--unidad", required=True, help="Etiqueta visible de la unidad, por ejemplo 07")
    p.add_argument("--usuario", help="Por defecto: unidad + etiqueta (unidad07)")
    p = sub.add_parser("crear-panel", help="Cuenta del panel de administración")
    p.add_argument("--usuario", required=True)
    p.add_argument("--rol", required=True, choices=["ADMINISTRADOR", "MODERADOR"])
    for orden, ayuda in [
        ("nueva-clave", "Genera otra contraseña y desbloquea"),
        ("desbloquear", "Quita el bloqueo por intentos fallidos"),
    ]:
        sub.add_parser(orden, help=ayuda).add_argument("--usuario", required=True)
    p = sub.add_parser("habilitar", help="Habilita o deshabilita una cuenta")
    p.add_argument("--usuario", required=True)
    p.add_argument("--no", action="store_true", help="Deshabilitar en vez de habilitar")
    args = parser.parse_args(argv)

    try:
        with Session(obtener_motor()) as s, s.begin():
            _ORDENES[args.orden](s, args)
    except ErrorDeCuenta as e:
        print(f"\n  ERROR: {e}\n", file=sys.stderr)
        return 1
    return 0


def _listar(s: Session, _: argparse.Namespace) -> None:
    filas = listar(s)
    print(f"\n  {'USUARIO':<22}{'ROL':<15}{'UNIDAD':<8}ESTADO")
    for f in filas:
        estado = "bloqueada" if f["bloqueada"] else ("activa" if f["activa"] else "deshabilitada")
        print(f"  {f['usuario']:<22}{f['rol']:<15}{f['unidad'] or '-':<8}{estado}")
    print(f"\n  {len(filas)} cuentas\n")


def _desbloquear(s: Session, args: argparse.Namespace) -> None:
    desbloquear(s, args.usuario)
    print(f"\n  Cuenta {args.usuario} desbloqueada.\n")


def _habilitar(s: Session, args: argparse.Namespace) -> None:
    habilitar(s, args.usuario, activa=not args.no)
    print(f"\n  Cuenta {args.usuario} {'deshabilitada' if args.no else 'habilitada'}.\n")


_ORDENES = {
    "listar": _listar,
    "crear-conductor": lambda s, a: _mostrar_clave(crear_conductor(s, a.unidad, a.usuario)),
    "crear-panel": lambda s, a: _mostrar_clave(crear_panel(s, a.usuario, a.rol)),
    "nueva-clave": lambda s, a: _mostrar_clave(nueva_clave(s, a.usuario)),
    "desbloquear": _desbloquear,
    "habilitar": _habilitar,
}


if __name__ == "__main__":
    sys.exit(main())
