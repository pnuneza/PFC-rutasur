"""Contraseñas y tokens (P05 Tabla 34: bcrypt y JWT firmado).

Funciones puras, sin base de datos ni HTTP: las usan el servicio de autenticación,
las dependencias de la API y la herramienta de cuentas.
"""

import secrets
import string
from datetime import UTC, datetime, timedelta
from uuid import UUID

import bcrypt
import jwt

from app.domain.excepciones import TokenInvalido
from app.domain.modelos import Identidad, Rol

ALGORITMO = "HS256"
EMISOR = "rutasur-api"
COSTO_BCRYPT = 12
LIMITE_BYTES_BCRYPT = 72  # bcrypt solo usa los primeros 72 bytes; la versión 5 los rechaza

# Hash de una contraseña que nadie conoce. Se compara contra él cuando el usuario no
# existe, para que la respuesta tarde lo mismo exista o no la cuenta (P06 Tabla 52).
_HASH_SEÑUELO = bcrypt.hashpw(secrets.token_bytes(16), bcrypt.gensalt(COSTO_BCRYPT)).decode()


# ----------------------------------------------------------------------
# Contraseñas
# ----------------------------------------------------------------------
def hash_contrasena(contrasena: str) -> str:
    datos = contrasena.encode()
    if len(datos) > LIMITE_BYTES_BCRYPT:
        raise ValueError("La contraseña es demasiado larga")
    return bcrypt.hashpw(datos, bcrypt.gensalt(COSTO_BCRYPT)).decode()


def verificar_contrasena(contrasena: str, hash_guardado: str | None) -> bool:
    """Compara en tiempo constante. Sin hash (usuario inexistente) usa el señuelo."""
    datos = contrasena.encode()
    if len(datos) > LIMITE_BYTES_BCRYPT:
        datos = datos[:LIMITE_BYTES_BCRYPT]  # igual se calcula el hash: mismo tiempo
        hash_guardado = None
    objetivo = (hash_guardado or _HASH_SEÑUELO).encode()
    try:
        coincide = bcrypt.checkpw(datos, objetivo)
    except ValueError:  # hash corrupto en la base
        return False
    return coincide and hash_guardado is not None


def contrasena_aleatoria(largo: int = 12) -> str:
    """Contraseña temporal legible (P06 A-04: 12 caracteres, se muestra una sola vez).

    Sin caracteres que se confunden al dictarlos o leerlos (0/O, 1/l/I).
    """
    alfabeto = "".join(c for c in string.ascii_letters + string.digits if c not in "0O1lI")
    return "".join(secrets.choice(alfabeto) for _ in range(largo))


# ----------------------------------------------------------------------
# Tokens JWT
# ----------------------------------------------------------------------
def emitir_token(identidad: Identidad, secreto: str, vigencia_s: int, ahora: datetime) -> str:
    reclamos = {
        "iss": EMISOR,
        "sub": str(identidad.cuenta_id),
        "rol": identidad.rol.value,
        "iat": ahora,
        "exp": ahora + timedelta(seconds=vigencia_s),
    }
    if identidad.unidad_id is not None:
        reclamos["uni"] = str(identidad.unidad_id)
        reclamos["lbl"] = identidad.etiqueta_unidad
    return jwt.encode(reclamos, secreto, algorithm=ALGORITMO)


def leer_token(token: str, secreto: str, ahora: datetime | None = None) -> Identidad:
    """Verifica firma, emisor y vencimiento. Cualquier problema es TokenInvalido."""
    try:
        reclamos = jwt.decode(
            token,
            secreto,
            # Solo el algoritmo esperado: impide el truco del token con alg «none»
            algorithms=[ALGORITMO],
            issuer=EMISOR,
            options={"require": ["exp", "iat", "sub", "iss"]},
        )
        if ahora is not None and datetime.fromtimestamp(reclamos["exp"], UTC) <= ahora:
            raise jwt.ExpiredSignatureError
        rol = Rol(reclamos["rol"])
        unidad = UUID(reclamos["uni"]) if "uni" in reclamos else None
        if (rol == Rol.CONDUCTOR) != (unidad is not None):
            raise TokenInvalido("El token no corresponde a su rol")
        return Identidad(
            cuenta_id=UUID(reclamos["sub"]),
            rol=rol,
            unidad_id=unidad,
            etiqueta_unidad=reclamos.get("lbl"),
        )
    except jwt.ExpiredSignatureError as e:
        raise TokenInvalido("La sesión de acceso venció; vuelva a ingresar") from e
    except (jwt.InvalidTokenError, KeyError, ValueError) as e:
        raise TokenInvalido("Token inválido; vuelva a ingresar") from e
