"""Configuración del servicio.

Todo valor sensible o que cambia entre entornos se lee de variables de entorno
(o de un archivo .env en desarrollo), nunca del código. Así el mismo código se
despliega en la PC del desarrollador, en la integración continua y en Render
(P05, Tabla 38: configuración externa).
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Configuracion(BaseSettings):
    """Variables de entorno del servicio."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Conexión con el rol de permisos mínimos (rutasur_app), nunca con el dueño del esquema
    database_url: str = "postgresql+psycopg://rutasur_app@localhost:5432/rutasur"

    # Grupo de conexiones: Neon gratuito admite pocas conexiones simultáneas.
    # El cupo de peticiones concurrentes a la base es la suma de ambos (D-11).
    db_pool_size: int = 5
    db_max_overflow: int = 5
    db_pool_timeout_s: int = 10

    # Dominios autorizados a llamar a la API desde un navegador (panel web)
    cors_origenes: list[str] = []

    entorno: str = "desarrollo"


@lru_cache
def obtener_configuracion() -> Configuracion:
    """Devuelve la configuración, leída una sola vez."""
    return Configuracion()
