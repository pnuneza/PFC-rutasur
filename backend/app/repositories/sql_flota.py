"""Repositorio de flota: unidades en servicio y candidatos a llegar a un paradero."""

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.domain.modelos import CandidatoLlegada, Coordenada, Ramal, Sentido, UnidadEnServicio

# Lee la copia de la última posición guardada en la sesión (vista v_unidades_activas):
# no recorre la tabla de posiciones (P06, Tabla 50: rendimiento).
_SQL_UNIDADES = text("""
    SELECT etiqueta, ramal::text AS ramal, sentido::text AS sentido, destino,
           latitud, longitud, ultimo_rumbo, ultima_posicion_en
      FROM v_unidades_activas
     WHERE ultima_posicion_en IS NOT NULL
       AND (CAST(:ramal AS ramal_t) IS NULL OR ramal = CAST(:ramal AS ramal_t))
     ORDER BY etiqueta
""")

# RN-006: solo las sesiones abiertas cuya variante incluye el paradero y que
# todavía no lo pasaron (lo recorrido es menor que la distancia del paradero).
# Trae además las velocidades de las últimas N posiciones válidas.
_SQL_CANDIDATOS = text("""
    SELECT u.etiqueta, v.ramal::text AS ramal, v.sentido::text AS sentido, v.destino,
           s.ultima_distancia_m, pv.distancia_desde_inicio_m, s.ultima_posicion_en,
           ARRAY(SELECT p.velocidad_kmh::float8
                   FROM posicion p
                  WHERE p.sesion_id = s.id AND p.valida
                  ORDER BY p.capturada_en DESC
                  LIMIT :n) AS velocidades
      FROM paradero pa
      JOIN paradero_variante pv ON pv.paradero_id = pa.id
      JOIN sesion_emision s     ON s.variante_id = pv.variante_id
                               AND s.estado IN ('ACTIVA', 'SIN_SENAL')
      JOIN variante v           ON v.id = s.variante_id
      JOIN unidad u             ON u.id = s.unidad_id
     WHERE pa.codigo = :codigo
       AND pa.activo
       AND s.ultima_distancia_m IS NOT NULL
       AND s.ultima_distancia_m < pv.distancia_desde_inicio_m
""")


class RepositorioFlotaSQL:
    def __init__(self, sesion: Session) -> None:
        self._s = sesion

    def listar_unidades_en_servicio(self, ramal: Ramal | None) -> list[UnidadEnServicio]:
        filas = self._s.execute(_SQL_UNIDADES, {"ramal": ramal.value if ramal else None}).mappings()
        return [
            UnidadEnServicio(
                etiqueta=f["etiqueta"],
                ramal=Ramal(f["ramal"]),
                sentido=Sentido(f["sentido"]),
                destino=f["destino"],
                ubicacion=Coordenada(f["latitud"], f["longitud"]),
                rumbo=f["ultimo_rumbo"],
                ultima_posicion_en=f["ultima_posicion_en"],
            )
            for f in filas
        ]

    def candidatos_llegada(
        self, codigo_paradero: str, n_velocidades: int
    ) -> list[CandidatoLlegada]:
        filas = self._s.execute(
            _SQL_CANDIDATOS, {"codigo": codigo_paradero, "n": n_velocidades}
        ).mappings()
        return [
            CandidatoLlegada(
                etiqueta=f["etiqueta"],
                ramal=Ramal(f["ramal"]),
                sentido=Sentido(f["sentido"]),
                destino=f["destino"],
                distancia_recorrida_m=float(f["ultima_distancia_m"]),
                distancia_paradero_m=float(f["distancia_desde_inicio_m"]),
                ultima_posicion_en=f["ultima_posicion_en"],
                velocidades_recientes_kmh=list(f["velocidades"]),
            )
            for f in filas
        ]
