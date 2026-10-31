"""Repositorio de rutas sobre PostgreSQL + PostGIS.

Todas las consultas usan parámetros enlazados (:nombre), nunca texto concatenado,
lo que impide la inyección SQL (OWASP A03).
"""

import json
from decimal import Decimal

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.domain.modelos import (
    Coordenada,
    LineaRuta,
    ParaderoEncontrado,
    ParaderoEnVariante,
    Ramal,
    Sentido,
    VarianteRuta,
)

_SQL_LINEA = text("""
    SELECT id, codigo, nombre, hora_inicio, hora_fin, actualizado_en
      FROM linea
     WHERE codigo = :codigo
""")

_SQL_VARIANTES = text("""
    SELECT v.id, v.ramal::text AS ramal, v.sentido::text AS sentido, v.destino,
           v.longitud_m, ST_AsGeoJSON(v.trazado, 6) AS trazado
      FROM variante v
     WHERE v.linea_id = :linea_id AND v.activa
     ORDER BY v.ramal, v.sentido
""")

_SQL_PARADEROS_DE_VARIANTES = text("""
    SELECT pv.variante_id, p.codigo, p.nombre, p.referencia,
           ST_Y(p.ubicacion) AS lat, ST_X(p.ubicacion) AS lon,
           pv.orden, pv.distancia_desde_inicio_m, p.en_tramo_comun
      FROM paradero_variante pv
      JOIN paradero p ON p.id = pv.paradero_id
      JOIN variante v ON v.id = pv.variante_id
     WHERE v.linea_id = :linea_id AND v.activa AND p.activo
     ORDER BY pv.variante_id, pv.orden
""")

# Usa el índice ix_paradero_nombre_trgm (búsqueda sin mayúsculas ni tildes)
_SQL_BUSCAR_PARADEROS = text(r"""
    SELECT p.codigo, p.nombre, p.referencia,
           ST_Y(p.ubicacion) AS lat, ST_X(p.ubicacion) AS lon,
           COALESCE(array_agg(DISTINCT v.ramal::text) FILTER (WHERE v.id IS NOT NULL),
                    '{}') AS ramales
      FROM paradero p
      LEFT JOIN paradero_variante pv ON pv.paradero_id = p.id
      LEFT JOIN variante v ON v.id = pv.variante_id AND v.activa
     WHERE p.activo
       AND lower(f_unaccent(p.nombre)) LIKE '%' || lower(f_unaccent(:patron)) || '%' ESCAPE '\'
     GROUP BY p.id
     ORDER BY similarity(lower(f_unaccent(p.nombre)), lower(f_unaccent(:texto))) DESC, p.nombre
     LIMIT :limite
""")

_SQL_EXISTE_PARADERO = text("""
    SELECT EXISTS (SELECT 1 FROM paradero WHERE codigo = :codigo AND activo)
""")


def _escapar_like(texto: str) -> str:
    """Evita que % y _ escritos por el usuario actúen como comodines."""
    return texto.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_")


def _flotante(valor: Decimal | float) -> float:
    return float(valor)


class RepositorioRutasSQL:
    def __init__(self, sesion: Session) -> None:
        self._s = sesion

    def obtener_linea(self, codigo: str) -> LineaRuta | None:
        linea = self._s.execute(_SQL_LINEA, {"codigo": codigo}).mappings().first()
        if linea is None:
            return None

        paraderos_por_variante: dict = {}
        for p in self._s.execute(_SQL_PARADEROS_DE_VARIANTES, {"linea_id": linea["id"]}).mappings():
            paraderos_por_variante.setdefault(p["variante_id"], []).append(
                ParaderoEnVariante(
                    codigo=p["codigo"],
                    nombre=p["nombre"],
                    referencia=p["referencia"],
                    ubicacion=Coordenada(p["lat"], p["lon"]),
                    orden=p["orden"],
                    distancia_desde_inicio_m=_flotante(p["distancia_desde_inicio_m"]),
                    en_tramo_comun=p["en_tramo_comun"],
                )
            )

        variantes = []
        for v in self._s.execute(_SQL_VARIANTES, {"linea_id": linea["id"]}).mappings():
            geojson = json.loads(v["trazado"])
            variantes.append(
                VarianteRuta(
                    ramal=Ramal(v["ramal"]),
                    sentido=Sentido(v["sentido"]),
                    destino=v["destino"],
                    longitud_m=_flotante(v["longitud_m"]),
                    trazado=[Coordenada(lat, lon) for lon, lat in geojson["coordinates"]],
                    paraderos=paraderos_por_variante.get(v["id"], []),
                )
            )

        return LineaRuta(
            codigo=linea["codigo"],
            nombre=linea["nombre"],
            hora_inicio=linea["hora_inicio"],
            hora_fin=linea["hora_fin"],
            actualizado_en=linea["actualizado_en"],
            variantes=variantes,
        )

    def buscar_paraderos(self, texto: str, limite: int) -> list[ParaderoEncontrado]:
        filas = self._s.execute(
            _SQL_BUSCAR_PARADEROS,
            {"patron": _escapar_like(texto), "texto": texto, "limite": limite},
        ).mappings()
        return [
            ParaderoEncontrado(
                codigo=f["codigo"],
                nombre=f["nombre"],
                referencia=f["referencia"],
                ubicacion=Coordenada(f["lat"], f["lon"]),
                ramales=[Ramal(r) for r in f["ramales"]],
            )
            for f in filas
        ]

    def existe_paradero_activo(self, codigo: str) -> bool:
        return bool(self._s.execute(_SQL_EXISTE_PARADERO, {"codigo": codigo}).scalar())
