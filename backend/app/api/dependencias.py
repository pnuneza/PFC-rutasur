"""Inyección de dependencias: arma cada servicio con sus repositorios.

Es el único lugar donde se decide qué implementación concreta recibe cada
servicio. En las pruebas se sustituyen estas funciones por versiones en memoria.
"""

from collections.abc import Callable

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import obtener_configuracion
from app.core.limites import LimitadorVentana
from app.core.seguridad import leer_token
from app.db.conexion import sesion_bd
from app.domain.excepciones import AccesoDenegado, TokenInvalido
from app.domain.modelos import Identidad, Rol
from app.domain.umbrales import UMBRALES_POR_DEFECTO
from app.repositories.sql_cuentas import RepositorioCuentasSQL
from app.repositories.sql_emision import RepositorioEmisionSQL
from app.repositories.sql_flota import RepositorioFlotaSQL
from app.repositories.sql_rutas import RepositorioRutasSQL
from app.services.estimador_eta import EstimadorDirecto
from app.services.servicio_autenticacion import ServicioAutenticacion
from app.services.servicio_emision import ServicioEmision
from app.services.servicio_flota import ServicioFlota
from app.services.servicio_llegadas import ServicioLlegadas
from app.services.servicio_rutas import ServicioRutas
from app.services.validador_posiciones import ValidadorPosiciones

# Límites de peticiones: uno por proceso, compartido por todas las peticiones
limite_envios = LimitadorVentana(UMBRALES_POR_DEFECTO.envios_por_minuto_por_unidad, 60)
limite_ingresos = LimitadorVentana(UMBRALES_POR_DEFECTO.ingresos_por_minuto_por_origen, 60)

_portador = HTTPBearer(auto_error=False, description="Token JWT de POST /api/v1/auth/login")


def servicio_rutas(sesion: Session = Depends(sesion_bd)) -> ServicioRutas:
    return ServicioRutas(RepositorioRutasSQL(sesion))


def servicio_flota(sesion: Session = Depends(sesion_bd)) -> ServicioFlota:
    return ServicioFlota(RepositorioFlotaSQL(sesion))


def servicio_llegadas(sesion: Session = Depends(sesion_bd)) -> ServicioLlegadas:
    # Aquí se elige la estrategia de cálculo del ETA (patrón Estrategia)
    return ServicioLlegadas(
        rutas=RepositorioRutasSQL(sesion),
        flota=RepositorioFlotaSQL(sesion),
        estimador=EstimadorDirecto(),
    )


def servicio_autenticacion(sesion: Session = Depends(sesion_bd)) -> ServicioAutenticacion:
    return ServicioAutenticacion(RepositorioCuentasSQL(sesion), obtener_configuracion().jwt_secreto)


def servicio_emision(sesion: Session = Depends(sesion_bd)) -> ServicioEmision:
    return ServicioEmision(RepositorioEmisionSQL(sesion), ValidadorPosiciones())


# ----------------------------------------------------------------------
# Autorización (RBAC, P05 Tabla 35)
# ----------------------------------------------------------------------
def identidad_actual(
    credenciales: HTTPAuthorizationCredentials | None = Depends(_portador),
    autenticacion: ServicioAutenticacion = Depends(servicio_autenticacion),
) -> Identidad:
    """Lee y verifica el token; la cuenta debe seguir habilitada."""
    if credenciales is None or credenciales.scheme.lower() != "bearer":
        raise TokenInvalido("Falta el token de acceso; ingrese con su usuario")
    identidad = leer_token(credenciales.credentials, obtener_configuracion().jwt_secreto)
    autenticacion.verificar_vigente(identidad)
    return identidad


def requiere_rol(*roles: Rol) -> Callable[..., Identidad]:
    """Dependencia que deja pasar solo a los roles indicados (403 FORBIDDEN si no)."""

    def verificar(identidad: Identidad = Depends(identidad_actual)) -> Identidad:
        if identidad.rol not in roles:
            raise AccesoDenegado("Su rol no tiene permiso para esta operación")
        return identidad

    return verificar


def origen_de(request: Request) -> str:
    """Dirección del cliente. Detrás de Render, uvicorn la toma de X-Forwarded-For."""
    return request.client.host if request.client else "desconocido"
