"""Repositorio de emisión: sesiones, posiciones y eventos de auditoría."""

import json
from collections.abc import Sequence
from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.domain.excepciones import RecursoNoEncontrado
from app.domain.modelos import (
    Coordenada,
    EstadoSesion,
    MedicionTrazado,
    PosicionValidada,
    Ramal,
    ReferenciaPosicion,
    Sentido,
    SesionEmision,
)

_SQL_SESION = text("""
    SELECT s.id, s.unidad_id, s.variante_id, s.estado::text AS estado, s.inicio, v.destino
      FROM sesion_emision s
      JOIN variante v ON v.id = s.variante_id
     WHERE s.id = :id
""")

_SQL_UNIDAD_ACTIVA = text("SELECT activa FROM unidad WHERE id = :id")

_SQL_VARIANTE = text("""
    SELECT v.id, v.destino
      FROM variante v
      JOIN linea l ON l.id = v.linea_id
     WHERE l.codigo = 'LB'
       AND v.ramal = CAST(:ramal AS ramal_t)
       AND v.sentido = CAST(:sentido AS sentido_t)
       AND v.activa
""")

# RN-002: al abrir una sesión se cierra cualquier otra abierta de la misma unidad
# GREATEST(...): fin siempre posterior a inicio, aunque ambos ocurran en la misma transacción
_SQL_CERRAR_ABIERTAS_DE_UNIDAD = text("""
    UPDATE sesion_emision
       SET estado = 'CERRADA_AUTOMATICAMENTE',
           fin = GREATEST(clock_timestamp(), inicio + interval '1 millisecond')
     WHERE unidad_id = :unidad_id AND estado IN ('ACTIVA', 'SIN_SENAL')
""")

_SQL_ABRIR = text("""
    INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id, inicio)
    VALUES (:unidad_id, :cuenta_id, :variante_id, :inicio)
    RETURNING id, unidad_id, variante_id, estado::text AS estado, inicio
""")

_SQL_CERRAR = text("""
    UPDATE sesion_emision
       SET estado = CAST(:estado AS estado_sesion_t),
           fin = GREATEST(clock_timestamp(), inicio + interval '1 millisecond')
     WHERE id = :id AND estado IN ('ACTIVA', 'SIN_SENAL')
""")

_SQL_IDS_REGISTRADOS = text("SELECT id FROM posicion WHERE id = ANY(CAST(:ids AS uuid[]))")

# Mide cada punto contra el trazado en una sola consulta:
#   · distancia al trazado (validación de corredor, RN-003)
#   · distancia recorrida desde el inicio de la variante (base del ETA)
_SQL_MEDIR = text("""
    SELECT t.n,
           ST_Distance(g.punto::geography, v.trazado::geography) AS al_trazado,
           ST_Length(ST_LineSubstring(v.trazado, 0,
                     ST_LineLocatePoint(v.trazado, g.punto))::geography) AS recorrido
      FROM variante v
     CROSS JOIN unnest(CAST(:lats AS float8[]), CAST(:lons AS float8[]))
                WITH ORDINALITY AS t(lat, lon, n)
     CROSS JOIN LATERAL (SELECT ST_SetSRID(ST_MakePoint(t.lon, t.lat), 4326) AS punto) g
     WHERE v.id = :variante_id
     ORDER BY t.n
""")

_SQL_ULTIMA_VALIDA = text("""
    SELECT ST_Y(coordenada) AS lat, ST_X(coordenada) AS lon, capturada_en
      FROM posicion
     WHERE sesion_id = :sesion_id AND valida
     ORDER BY capturada_en DESC
     LIMIT 1
""")

# ON CONFLICT: si dos lotes con la misma posición llegan a la vez, no se duplica
_SQL_GUARDAR_POSICION = text("""
    INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m,
                          capturada_en, valida, motivo_descarte)
    VALUES (:id, :sesion_id, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326), :velocidad, :rumbo,
            :precision, :capturada_en, :valida, CAST(:motivo AS motivo_descarte_t))
    ON CONFLICT (id) DO NOTHING
""")

# Copia de la última posición válida (desnormalización de P06); una posición
# válida devuelve la sesión de SIN_SENAL a ACTIVA (P05, Figura 24).
_SQL_ACTUALIZAR_ULTIMA = text("""
    UPDATE sesion_emision
       SET ultima_posicion_en   = :capturada_en,
           ultima_ubicacion     = ST_SetSRID(ST_MakePoint(:lon, :lat), 4326),
           ultimo_rumbo         = :rumbo,
           ultima_velocidad_kmh = :velocidad,
           ultima_distancia_m   = :distancia,
           estado = CASE WHEN estado = 'SIN_SENAL' THEN 'ACTIVA'::estado_sesion_t ELSE estado END
     WHERE id = :sesion_id
       AND (ultima_posicion_en IS NULL OR ultima_posicion_en < :capturada_en)
""")

_SQL_EVENTO = text("""
    INSERT INTO registro_evento (tipo, origen, unidad_id, detalle)
    VALUES (CAST(:tipo AS tipo_evento_t), :origen, :unidad_id, CAST(:detalle AS jsonb))
""")

_SQL_UNIDAD_POR_ETIQUETA = text("""
    SELECT u.id AS unidad_id, c.id AS cuenta_id
      FROM unidad u
      JOIN cuenta_conductor c ON c.unidad_id = u.id
     WHERE u.etiqueta = :etiqueta
""")


class RepositorioEmisionSQL:
    def __init__(self, sesion: Session) -> None:
        self._s = sesion

    # --- sesiones -------------------------------------------------------
    def obtener_sesion(self, sesion_id: UUID) -> SesionEmision | None:
        f = self._s.execute(_SQL_SESION, {"id": sesion_id}).mappings().first()
        if f is None:
            return None
        return SesionEmision(
            id=f["id"],
            unidad_id=f["unidad_id"],
            variante_id=f["variante_id"],
            estado=EstadoSesion(f["estado"]),
            inicio=f["inicio"],
            destino=f["destino"],
        )

    def unidad_activa(self, unidad_id: UUID) -> bool | None:
        return self._s.execute(_SQL_UNIDAD_ACTIVA, {"id": unidad_id}).scalar()

    def abrir_sesion(
        self, unidad_id: UUID, cuenta_id: UUID, ramal: Ramal, sentido: Sentido, inicio: datetime
    ) -> SesionEmision:
        variante = (
            self._s.execute(_SQL_VARIANTE, {"ramal": ramal.value, "sentido": sentido.value})
            .mappings()
            .first()
        )
        if variante is None:
            raise RecursoNoEncontrado(f"No existe la variante {ramal}-{sentido}")

        self._s.execute(_SQL_CERRAR_ABIERTAS_DE_UNIDAD, {"unidad_id": unidad_id})
        f = (
            self._s.execute(
                _SQL_ABRIR,
                {
                    "unidad_id": unidad_id,
                    "cuenta_id": cuenta_id,
                    "variante_id": variante["id"],
                    "inicio": inicio,
                },
            )
            .mappings()
            .one()
        )
        return SesionEmision(
            id=f["id"],
            unidad_id=f["unidad_id"],
            variante_id=f["variante_id"],
            estado=EstadoSesion(f["estado"]),
            inicio=f["inicio"],
            destino=variante["destino"],
        )

    def cerrar_sesion(self, sesion_id: UUID, estado: EstadoSesion) -> None:
        self._s.execute(_SQL_CERRAR, {"id": sesion_id, "estado": estado.value})

    # --- posiciones -----------------------------------------------------
    def ids_registrados(self, ids: Sequence[UUID]) -> set[UUID]:
        if not ids:
            return set()
        return set(self._s.execute(_SQL_IDS_REGISTRADOS, {"ids": list(ids)}).scalars())

    def medir_contra_trazado(
        self, variante_id: UUID, puntos: Sequence[Coordenada]
    ) -> list[MedicionTrazado]:
        filas = self._s.execute(
            _SQL_MEDIR,
            {
                "variante_id": variante_id,
                "lats": [p.lat for p in puntos],
                "lons": [p.lon for p in puntos],
            },
        ).mappings()
        return [MedicionTrazado(float(f["al_trazado"]), float(f["recorrido"])) for f in filas]

    def ultima_posicion_valida(self, sesion_id: UUID) -> ReferenciaPosicion | None:
        f = self._s.execute(_SQL_ULTIMA_VALIDA, {"sesion_id": sesion_id}).mappings().first()
        if f is None:
            return None
        return ReferenciaPosicion(Coordenada(f["lat"], f["lon"]), f["capturada_en"])

    def guardar_posiciones(self, sesion_id: UUID, posiciones: Sequence[PosicionValidada]) -> None:
        self._s.execute(
            _SQL_GUARDAR_POSICION,
            [
                {
                    "id": v.posicion.id,
                    "sesion_id": sesion_id,
                    "lat": v.posicion.ubicacion.lat,
                    "lon": v.posicion.ubicacion.lon,
                    "velocidad": v.posicion.velocidad_kmh,
                    "rumbo": v.posicion.rumbo,
                    "precision": v.posicion.precision_m,
                    "capturada_en": v.posicion.capturada_en,
                    "valida": v.resultado.valida,
                    "motivo": v.resultado.motivo.value if v.resultado.motivo else None,
                }
                for v in posiciones
            ],
        )

    def actualizar_ultima_posicion(
        self, sesion_id: UUID, posicion: PosicionValidada, distancia_recorrida_m: float
    ) -> None:
        p = posicion.posicion
        self._s.execute(
            _SQL_ACTUALIZAR_ULTIMA,
            {
                "sesion_id": sesion_id,
                "capturada_en": p.capturada_en,
                "lat": p.ubicacion.lat,
                "lon": p.ubicacion.lon,
                "rumbo": p.rumbo,
                "velocidad": p.velocidad_kmh,
                "distancia": round(distancia_recorrida_m, 1),
            },
        )

    # --- auditoría ------------------------------------------------------
    def registrar_evento(
        self, tipo: str, origen: str, unidad_id: UUID | None, detalle: dict[str, Any]
    ) -> None:
        self._s.execute(
            _SQL_EVENTO,
            {
                "tipo": tipo,
                "origen": origen,
                "unidad_id": unidad_id,
                "detalle": json.dumps(detalle),
            },
        )

    # --- apoyo al simulador --------------------------------------------
    def buscar_unidad_por_etiqueta(self, etiqueta: str) -> tuple[UUID, UUID] | None:
        f = self._s.execute(_SQL_UNIDAD_POR_ETIQUETA, {"etiqueta": etiqueta}).mappings().first()
        return (f["unidad_id"], f["cuenta_id"]) if f else None
