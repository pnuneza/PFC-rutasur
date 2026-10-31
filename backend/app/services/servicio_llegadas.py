"""Servicio de llegadas: resuelve el caso de uso CU-01 (P05, Figura 18).

Mensajes del diagrama de colaboración que implementa:
  (5) obtener del repositorio las sesiones activas que pueden servir al paradero:
      su variante lo incluye y todavía no lo han pasado (RN-006);
  (6) pedir el ETA de cada una al estimador;
  (8) descartar las llegadas de más de 60 minutos (RN-007) y ordenar por ETA.
"""

from datetime import datetime

from app.domain.excepciones import RecursoNoEncontrado
from app.domain.modelos import EstimacionLlegada
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.repositories.interfaces import RepositorioFlota, RepositorioRutas
from app.services.estimador_eta import EstimadorETA


class ServicioLlegadas:
    def __init__(
        self,
        rutas: RepositorioRutas,
        flota: RepositorioFlota,
        estimador: EstimadorETA,
        umbrales: Umbrales = UMBRALES_POR_DEFECTO,
    ) -> None:
        self._rutas = rutas
        self._flota = flota
        self._estimador = estimador  # solo conoce la interfaz (patrón Estrategia)
        self._u = umbrales

    def proximas_llegadas(self, codigo_paradero: str, ahora: datetime) -> list[EstimacionLlegada]:
        if not self._rutas.existe_paradero_activo(codigo_paradero):
            raise RecursoNoEncontrado(f"El paradero {codigo_paradero} no existe o está inactivo")

        candidatos = self._flota.candidatos_llegada(
            codigo_paradero, self._u.posiciones_para_velocidad
        )
        estimaciones = [self._estimador.estimar(c, ahora) for c in candidatos]

        dentro_del_limite = [e for e in estimaciones if e.eta_s <= self._u.eta_maximo_s]
        return sorted(dentro_del_limite, key=lambda e: e.eta_s)
