"""Contraseñas (bcrypt) y tokens (JWT) — P05 Tabla 34."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest

from app.core.seguridad import (
    EMISOR,
    contrasena_aleatoria,
    emitir_token,
    hash_contrasena,
    leer_token,
    verificar_contrasena,
)
from app.domain.excepciones import TokenInvalido
from app.domain.modelos import Identidad, Rol

SECRETO = "s" * 40
CONDUCTOR = Identidad(cuenta_id=uuid4(), rol=Rol.CONDUCTOR, unidad_id=uuid4(), etiqueta_unidad="07")
ADMIN = Identidad(cuenta_id=uuid4(), rol=Rol.ADMINISTRADOR)


def ahora():
    return datetime.now(UTC)


# --- contraseñas -------------------------------------------------------------
def test_el_hash_no_contiene_la_contrasena_y_se_verifica():
    h = hash_contrasena("clave-segura-123")
    assert "clave-segura-123" not in h and h.startswith("$2b$12$")
    assert verificar_contrasena("clave-segura-123", h)
    assert not verificar_contrasena("clave-segura-124", h)


def test_usuario_inexistente_nunca_se_verifica():
    assert not verificar_contrasena("cualquier-cosa", None)


def test_contrasena_de_mas_de_72_bytes_no_se_acepta():
    with pytest.raises(ValueError):
        hash_contrasena("ñ" * 40)  # 80 bytes en UTF-8
    h = hash_contrasena("a" * 72)
    assert not verificar_contrasena("a" * 72 + "extra", h)


def test_contrasena_aleatoria_sin_caracteres_confusos():
    claves = {contrasena_aleatoria() for _ in range(200)}
    assert len(claves) == 200
    assert all(len(c) == 12 and not set(c) & set("0O1lI") for c in claves)


# --- tokens --------------------------------------------------------------------
@pytest.mark.parametrize("identidad", [CONDUCTOR, ADMIN])
def test_token_ida_y_vuelta_conserva_la_identidad(identidad):
    token = emitir_token(identidad, SECRETO, 3600, ahora())
    assert leer_token(token, SECRETO) == identidad


def test_token_vencido_se_rechaza():
    token = emitir_token(CONDUCTOR, SECRETO, 60, ahora() - timedelta(hours=13))
    with pytest.raises(TokenInvalido, match="venció"):
        leer_token(token, SECRETO)


def test_token_firmado_con_otra_clave_se_rechaza():
    token = emitir_token(CONDUCTOR, "otra-clave-" * 4, 3600, ahora())
    with pytest.raises(TokenInvalido):
        leer_token(token, SECRETO)


def test_token_alterado_se_rechaza():
    token = emitir_token(CONDUCTOR, SECRETO, 3600, ahora())
    cabecera, cuerpo, firma = token.split(".")
    otro = emitir_token(ADMIN, SECRETO, 3600, ahora()).split(".")[1]
    with pytest.raises(TokenInvalido):
        leer_token(f"{cabecera}.{otro}.{firma}", SECRETO)


def test_token_sin_firma_alg_none_se_rechaza():
    reclamos = {
        "iss": EMISOR,
        "sub": str(ADMIN.cuenta_id),
        "rol": "ADMINISTRADOR",
        "iat": ahora(),
        "exp": ahora() + timedelta(hours=1),
    }
    token = jwt.encode(reclamos, key=None, algorithm="none")
    with pytest.raises(TokenInvalido):
        leer_token(token, SECRETO)


def test_token_de_conductor_sin_unidad_se_rechaza():
    reclamos = {
        "iss": EMISOR,
        "sub": str(uuid4()),
        "rol": "CONDUCTOR",
        "iat": ahora(),
        "exp": ahora() + timedelta(hours=1),
    }
    with pytest.raises(TokenInvalido):
        leer_token(jwt.encode(reclamos, SECRETO, algorithm="HS256"), SECRETO)


@pytest.mark.parametrize("basura", ["", "abc", "a.b.c", "Bearer x"])
def test_texto_que_no_es_token_se_rechaza(basura):
    with pytest.raises(TokenInvalido):
        leer_token(basura, SECRETO)
