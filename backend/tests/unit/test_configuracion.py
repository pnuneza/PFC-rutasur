"""Configuración para la nube: URL de Neon/Render, retención y depuración automática."""

import pytest
from pydantic import ValidationError

from app.core.config import Configuracion


@pytest.mark.parametrize(
    "url",
    [
        "postgresql://rutasur_app:clave@ep-ejemplo.us-east-1.aws.neon.tech/rutasur?sslmode=require",
        "postgres://rutasur_app:clave@ep-ejemplo.us-east-1.aws.neon.tech/rutasur?sslmode=require",
    ],
)
def test_url_de_neon_usa_el_controlador_psycopg(url):
    config = Configuracion(database_url=url)
    assert config.database_url.startswith("postgresql+psycopg://rutasur_app:clave@ep-ejemplo")
    assert config.database_url.endswith("?sslmode=require")


def test_url_con_controlador_explicito_no_cambia():
    url = "postgresql+psycopg://rutasur_app@localhost:5432/rutasur"
    assert Configuracion(database_url=url).database_url == url


def test_retencion_menor_a_un_dia_es_invalida():
    with pytest.raises(ValidationError):
        Configuracion(retencion_dias=0)


@pytest.mark.parametrize(
    ("entorno", "explicita", "esperado"),
    [
        ("desarrollo", None, False),
        ("produccion", None, True),
        ("produccion", False, False),
        ("desarrollo", True, True),
    ],
)
def test_depuracion_automatica_por_defecto_solo_en_produccion(entorno, explicita, esperado):
    config = Configuracion(entorno=entorno, depuracion_automatica=explicita, jwt_secreto="p" * 40)
    assert config.depurar_automaticamente is esperado
