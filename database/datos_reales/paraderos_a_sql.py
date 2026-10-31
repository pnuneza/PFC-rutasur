"""Genera ruta_lb.sql: trazados y paraderos reales de la línea LB.

Entradas (en esta carpeta):
- yandex/datos_editor.json: trazado de cada variante y puntos candidatos. Lo genera
  yandex/preparar_editor.py a partir de Yandex Maps y del GPX propio. Es la fuente de
  la geometría: el editor no permite cambiar los trazados.
- paraderos.json: lo que exporta el editor (yandex/editor_paraderos.html): qué puntos
  son paraderos en cada variante y con qué nombre los conoce la gente.
- codigos_paraderos.json: código público (stp_NNN) de cada punto. Se conserva entre
  ejecuciones para que un paradero no cambie de código al volver a exportar; los
  puntos nuevos reciben el siguiente número libre.

Salida: ruta_lb.sql, que deja la línea LB con sus 4 variantes reales. Funciona en una
base recién creada y también en una que ya tiene datos (por ejemplo, los demo):
reemplaza trazados y paraderos sin borrar unidades, cuentas ni sesiones.

Uso:  py paraderos_a_sql.py      (Windows)      python3 paraderos_a_sql.py
"""

import json
import sys
from pathlib import Path

AQUI = Path(__file__).parent
EDITOR = AQUI / "yandex" / "datos_editor.json"
EXPORTADO = AQUI / "paraderos.json"
CODIGOS = AQUI / "codigos_paraderos.json"
SALIDA = AQUI / "ruta_lb.sql"

# Orden en que se numeran los paraderos nuevos (el primero es el terminal de Mollebaya)
ORDEN_VARIANTES = ["MOLLEBAYA-IDA", "MOLLEBAYA-VUELTA", "CERRILLO-IDA", "CERRILLO-VUELTA"]
# Destino que ve el pasajero («Va a …»). Se usa el nombre que usa la gente en la ruta.
DESTINOS = {
    "MOLLEBAYA-IDA": "Centro (2 de Mayo)",
    "MOLLEBAYA-VUELTA": "Mollebaya",
    "CERRILLO-IDA": "Centro (2 de Mayo)",
    "CERRILLO-VUELTA": "Cerrillo",
}


def sql_texto(valor):
    return "NULL" if valor is None else "'" + str(valor).replace("'", "''") + "'"


def normalizar(texto):
    return " ".join(texto.lower().replace("avenida", "av.").replace("carretera", "carr.").split())


def leer_entradas():
    editor = json.loads(EDITOR.read_text(encoding="utf-8"))
    exportado = json.loads(EXPORTADO.read_text(encoding="utf-8"))
    nombres = {p["clave"]: p["nombre"].strip() for p in exportado["paraderos"]}
    elegidos = {v["id"]: v["paraderos"] for v in exportado["variantes"]}
    return editor, nombres, elegidos


def paraderos_por_variante(editor, elegidos):
    """Puntos elegidos de cada variante, en orden de recorrido.

    Igual que el editor al abrirse: descarta los puntos que ya no están en el trazado
    (si el trazado cambió después de exportar) y agrega los obligatorios (terminales).
    """
    resultado = {}
    for v in editor["variantes"]:
        orden = [clave for clave, _ in v["paradas"]]
        validos = set(orden)
        marcados = {k for k in elegidos.get(v["id"], v["elegidas"]) if k in validos}
        marcados |= set(v.get("obligatorias", []))
        resultado[v["id"]] = [k for k in orden if k in marcados]
    return resultado


def asignar_codigos(por_variante):
    codigos = json.loads(CODIGOS.read_text(encoding="utf-8")) if CODIGOS.exists() else {}
    usados = {int(c[4:]) for c in codigos.values()}
    siguiente = max(usados, default=0) + 1
    for vid in ORDEN_VARIANTES:
        for clave in por_variante[vid]:
            if clave not in codigos:
                while siguiente in usados:
                    siguiente += 1
                if siguiente > 899:  # stp_9NN queda para las pruebas de la base de datos
                    sys.exit("Se acabaron los códigos de paradero disponibles")
                codigos[clave] = f"stp_{siguiente:03d}"
                usados.add(siguiente)
    CODIGOS.write_text(json.dumps(codigos, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return codigos


def advertir_nombres_repetidos(por_variante, nombre_de):
    avisos = []
    for vid, claves in por_variante.items():
        vistos = {}
        for k in claves:
            vistos.setdefault(nombre_de(k), []).append(k)
        for nombre, ks in vistos.items():
            if len(ks) > 1:
                avisos.append(f"  {vid}: «{nombre}» se repite {len(ks)} veces")
    if avisos:
        print("AVISO: nombres repetidos en un mismo sentido (el pasajero no los distingue):")
        print("\n".join(avisos))


def generar():
    editor, nombres, elegidos = leer_entradas()
    variantes = {v["id"]: v for v in editor["variantes"]}
    por_variante = paraderos_por_variante(editor, elegidos)
    codigos = asignar_codigos(por_variante)

    def nombre_de(clave):
        return nombres.get(clave) or editor["paradas"][clave]["nombre"]

    advertir_nombres_repetidos(por_variante, nombre_de)

    usados = {}
    for vid, claves in por_variante.items():
        for k in claves:
            usados.setdefault(k, set()).add(variantes[vid]["ramal"])

    lineas = [
        "-- ==========================================================",
        "-- RutaSur v1.0 — ruta_lb.sql (GENERADO por paraderos_a_sql.py; no editar a mano)",
        "-- Trazados y paraderos reales de la línea LB.",
        f"-- Fuente: {editor['fuente']}.",
        "-- Ramal Mollebaya de vuelta: GPX propio trazado en BRouter (31/10/2026).",
        "-- Paraderos: elegidos y nombrados por el autor con el editor de paraderos.",
        "-- ==========================================================",
        "",
        "BEGIN;",
        "",
        "-- 1. Se sueltan los paraderos de las variantes LB (se vuelven a asignar al final)",
        "DELETE FROM paradero_variante pv",
        "      USING variante v, linea l",
        " WHERE pv.variante_id = v.id AND v.linea_id = l.id AND l.codigo = 'LB';",
        "",
        "-- 2. Variantes: se actualizan si existen (conservan su id y sus sesiones) o se crean",
    ]
    for vid in ORDEN_VARIANTES:
        v = variantes[vid]
        wkt = ", ".join(f"{lon} {lat}" for lon, lat in v["trazado"])
        lineas += [
            "INSERT INTO variante (linea_id, ramal, sentido, destino, trazado, activa)",
            f"SELECT id, '{v['ramal']}', '{v['sentido']}', {sql_texto(DESTINOS[vid])},",
            f"       ST_GeomFromText('LINESTRING({wkt})', 4326), true",
            "  FROM linea WHERE codigo = 'LB'",
            "ON CONFLICT (linea_id, ramal, sentido) DO UPDATE",
            "   SET destino = EXCLUDED.destino, trazado = EXCLUDED.trazado, activa = true;",
            "",
        ]

    lineas += [
        "-- 3. Paraderos reales (se actualizan por código si ya existen)",
        "INSERT INTO paradero (codigo, nombre, referencia, ubicacion, en_tramo_comun, activo) VALUES",
    ]
    filas = []
    for clave in sorted(usados, key=lambda k: codigos[k]):
        punto = editor["paradas"][clave]
        nombre = nombre_de(clave)
        if not 3 <= len(nombre) <= 80:
            sys.exit(f"Nombre de paradero inválido (3 a 80 caracteres): «{nombre}»")
        # Referencia: el nombre de Yandex (cruce de calles) cuando aporta algo al nombre elegido
        yandex = punto.get("nombre_yandex", "")
        referencia = yandex[:120] if yandex and normalizar(yandex) != normalizar(nombre) else None
        comun = "true" if len(usados[clave]) > 1 else "false"
        filas.append(
            f"  ('{codigos[clave]}', {sql_texto(nombre)}, {sql_texto(referencia)}, "
            f"ST_SetSRID(ST_MakePoint({punto['lon']}, {punto['lat']}), 4326), {comun}, true)"
        )
    lineas += [",\n".join(filas)]
    lineas += [
        "ON CONFLICT (codigo) DO UPDATE",
        "   SET nombre = EXCLUDED.nombre, referencia = EXCLUDED.referencia,",
        "       ubicacion = EXCLUDED.ubicacion, en_tramo_comun = EXCLUDED.en_tramo_comun, activo = true;",
        "",
        "-- Los paraderos que ya no se usan (por ejemplo, los demo) quedan inactivos, no se borran",
        "UPDATE paradero p SET activo = false",
        f" WHERE p.codigo <> ALL (ARRAY[{', '.join(sql_texto(codigos[k]) for k in sorted(usados, key=lambda k: codigos[k]))}])",
        "   AND NOT EXISTS (SELECT 1 FROM paradero_variante pv WHERE pv.paradero_id = p.id);",
        "",
        "-- 4. Paraderos de cada variante. El orden y la distancia los calcula la base",
        "--    (fn_asignar_paraderos_variante) y se comprueba que coincidan con el editor.",
    ]
    for vid in ORDEN_VARIANTES:
        v = variantes[vid]
        arreglo = ", ".join(f"'{codigos[k]}'" for k in por_variante[vid])
        lineas += [
            "DO $$",
            "DECLARE",
            "    v_id uuid;",
            f"    v_esperado varchar[] := ARRAY[{arreglo}];",
            "    v_obtenido varchar[];",
            "BEGIN",
            "    SELECT v.id INTO v_id FROM variante v JOIN linea l ON l.id = v.linea_id",
            f"     WHERE l.codigo = 'LB' AND v.ramal = '{v['ramal']}' AND v.sentido = '{v['sentido']}';",
            "    PERFORM fn_asignar_paraderos_variante(v_id, v_esperado);",
            "    SELECT array_agg(p.codigo ORDER BY pv.orden) INTO v_obtenido",
            "      FROM paradero_variante pv JOIN paradero p ON p.id = pv.paradero_id",
            "     WHERE pv.variante_id = v_id;",
            "    IF v_obtenido IS DISTINCT FROM v_esperado THEN",
            f"        RAISE EXCEPTION 'El orden de los paraderos de {vid} no coincide con el editor: %', v_obtenido;",
            "    END IF;",
            "END $$;",
            "",
        ]
    lineas += ["COMMIT;", ""]
    SALIDA.write_text("\n".join(lineas), encoding="utf-8")

    print(f"{SALIDA.name}: {len(usados)} paraderos")
    for vid in ORDEN_VARIANTES:
        claves = por_variante[vid]
        print(f"  {vid:17} {len(claves):3} paraderos  {nombre_de(claves[0])} → {nombre_de(claves[-1])}")


if __name__ == "__main__":
    generar()
