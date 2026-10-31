"""Inyección de dependencias: arma cada servicio con sus repositorios.

Es el único lugar donde se decide qué implementación concreta recibe cada
servicio. En las pruebas se sustituyen estas funciones por versiones en memoria.
"""

from fastapi import Depends
from sqlalchemy.orm import Session

from app.db.conexion import sesion_bd
from app.repositories.sql_flota import RepositorioFlotaSQL
from app.repositories.sql_rutas import RepositorioRutasSQL
from app.services.estimador_eta import EstimadorDirecto
from app.services.servicio_flota import ServicioFlota
from app.services.servicio_llegadas import ServicioLlegadas
from app.services.servicio_rutas import ServicioRutas


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
