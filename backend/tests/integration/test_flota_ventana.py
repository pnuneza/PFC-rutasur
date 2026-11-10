"""Velocidad por el avance real en los últimos minutos (D-21), leída de la base."""

import pytest
from sqlalchemy import text

from app.repositories.sql_flota import RepositorioFlotaSQL

pytestmark = pytest.mark.integracion


def _posicion(conexion, sesion_id, fraccion: float, hace_s: int) -> None:
    """Posición válida sobre el trazado de la sesión, en la fracción dada de la ruta."""
    conexion.execute(
        text("""
            INSERT INTO posicion (id, sesion_id, coordenada, velocidad_kmh, rumbo, precision_m,
                                  capturada_en, valida)
            SELECT gen_random_uuid(), s.id, ST_LineInterpolatePoint(v.trazado, :f), 0, 0, 5,
                   now() - make_interval(secs => :hace), true
              FROM sesion_emision s JOIN variante v ON v.id = s.variante_id
             WHERE s.id = :sesion
        """),
        {"f": fraccion, "hace": hace_s, "sesion": sesion_id},
    )


def test_los_candidatos_traen_el_avance_de_los_ultimos_minutos(sesion):
    conexion = sesion.connection()
    # Sesión nueva de la unidad 12 (la demo no le abre ninguna); se deshace al terminar
    s = conexion.execute(
        text("""INSERT INTO sesion_emision (unidad_id, cuenta_conductor_id, variante_id, inicio)
                SELECT u.id, c.id, v.id, now() - interval '20 minutes'
                  FROM unidad u JOIN cuenta_conductor c ON c.unidad_id = u.id
                  JOIN variante v ON v.ramal = 'CERRILLO' AND v.sentido = 'IDA'
                 WHERE u.etiqueta = '12'
                RETURNING id, variante_id AS variante,
                          (SELECT longitud_m FROM variante WHERE id = variante_id) AS longitud_m""")
    ).one()
    # Hace 8 min estaba al 10 % de la ruta; ahora, al 20 %, detenida (GPS en 0 km/h)
    _posicion(conexion, s.id, 0.10, 480)
    _posicion(conexion, s.id, 0.20, 0)
    conexion.execute(
        text("""UPDATE sesion_emision SET ultima_posicion_en = now(),
                       ultima_distancia_m = :d WHERE id = :s"""),
        {"d": 0.20 * float(s.longitud_m), "s": s.id},
    )
    codigo = conexion.execute(
        text("""SELECT p.codigo FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id
                 WHERE pv.variante_id = :v AND pv.distancia_desde_inicio_m > :d
                 ORDER BY pv.distancia_desde_inicio_m LIMIT 1"""),
        {"v": s.variante, "d": 0.30 * float(s.longitud_m)},
    ).scalar_one()

    candidato = next(
        c
        for c in RepositorioFlotaSQL(sesion).candidatos_llegada(codigo, 4, 600)
        if c.etiqueta == "12"
    )
    assert candidato.duracion_ventana_s == pytest.approx(480, abs=1)
    assert candidato.avance_ventana_m == pytest.approx(0.10 * float(s.longitud_m), rel=0.02)

    # Con una ventana de 5 min, la posición de hace 8 min queda fuera: solo hay la actual
    corta = next(
        c
        for c in RepositorioFlotaSQL(sesion).candidatos_llegada(codigo, 4, 300)
        if c.etiqueta == "12"
    )
    assert corta.duracion_ventana_s == pytest.approx(0, abs=1)
