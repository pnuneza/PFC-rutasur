# Ruta real de la línea LB

Trazados y paraderos reales de las 4 variantes de la línea LB. Se cargan siempre: en Docker al
crear la base, en la integración continua y, más adelante, en la nube. Los datos demo
(`demo/datos_demo.sql`) ya no traen ruta: solo unidades, cuentas y una sesión simulada.

## De dónde salen los datos

| Variante | Trazado | Paraderos candidatos |
|---|---|---|
| Mollebaya → Centro (bajada) | Yandex Maps, ruta «LB Mollebaya» (26/10/2026), coincide en 99 % con el GPX propio | Paradas de Yandex |
| Centro → Mollebaya (subida) | **GPX propio** trazado en BRouter (`Centro_Mollebaya_2026-10-31.gpx`) | Paradas de Yandex a ≤ 25 m del trazado |
| Cerrillo → Centro | **GPX propio** (BRouter y gpx.studio, `Cerrillo_Centro_2026-11-01.gpx`) | Paradas de Yandex a ≤ 25 m del trazado + puntos de apoyo |
| Centro → Cerrillo | **GPX propio** (BRouter, `Centro_Cerrillo_2026-11-01.gpx`) | Paradas de Yandex a ≤ 25 m del trazado + puntos de apoyo |

- **Yandex está desactualizado en la subida a Mollebaya.** Iba por Av. Mariscal Castilla,
  María Nieves y Bustamante, Av. Argentina y Av. Kennedy. Hoy la ruta va por el Óvalo de
  Mariscal Castilla, la Av. Jesús y la Av. Porongoche, y por eso se usa el GPX propio.
- **Terminal de Mollebaya («Santa Ana»).** Es el final del GPX de subida, donde la unidad se
  queda y de donde sale de bajada. Yandex seguía unos 100 m más por la Calle La Unión. La
  subida y la bajada comparten este paradero.
- **Ramal Cerrillo (01/11/2026).** Sale del terminal Santa Ana (el mismo de Mollebaya), pasa
  por la Plaza de Mollebaya, Yanayaco y Cerrillo, y sigue al Centro por el mismo camino que
  Mollebaya; de vuelta hace lo inverso. Yandex todavía lo mostraba saliendo de la Calle Grau,
  por eso se usan los GPX propios. En el tramo nuevo Yandex no tiene paradas: el editor muestra
  **puntos de apoyo** anaranjados cada 100 m para elegir y nombrar ahí los paraderos.
- **Paraderos del Cerrillo al cambiar el trazado.** Se conservaron los elegidos antes que siguen
  sobre el trazado nuevo y se agregaron los de Mollebaya del mismo sentido por donde los dos
  ramales van juntos (un mismo paradero para ambos).
- **Nombres de los paraderos.** El autor los eligió y les puso el nombre que usa la gente con
  el editor. La referencia de cada paradero es el cruce de calles que da Yandex, cuando
  aporta algo.

Fuente: Yandex Maps (2026), rutas «LB Mollebaya» y «LB Cerrillos», consulta del 26/10/2026.
`RutaMollebaya.gpx` es el primer trazado propio (ida y vuelta, 14/10/2026); se conserva como
referencia.

## Archivos

| Archivo | Qué es |
|---|---|
| `yandex/T1.txt`, `T0.txt`, `C1.txt`, `C0.txt` | Paradas y trazado de Yandex: Mollebaya ida/vuelta y Cerrillos ida/vuelta |
| `Centro_Mollebaya_2026-10-31.gpx` | Subida a Mollebaya trazada en BRouter-Web |
| `Cerrillo_Centro_2026-11-01.gpx`, `Centro_Cerrillo_2026-11-01.gpx` | Ramal Cerrillo en los dos sentidos, trazado por el autor |
| `yandex/preparar_editor.py` | Une Yandex y el GPX, limpia el GPX, ubica el terminal y preselecciona paraderos (uno cada 300–700 m) |
| `yandex/editor_paraderos.html` | **Generado.** Editor en el navegador: elegir y nombrar paraderos, y exportar `paraderos.json` |
| `yandex/datos_editor.json` | **Generado.** Trazados y puntos candidatos; también lo lee el generador SQL |
| `paraderos.json` | Lo que exporta el editor: paraderos de cada variante y sus nombres |
| `codigos_paraderos.json` | Código público (`stp_NNN`) de cada paradero. No cambia al volver a exportar |
| `paraderos_a_sql.py` | Genera `ruta_lb.sql` y avisa si hay nombres repetidos en un mismo sentido |
| `ruta_lb.sql` | **Generado.** Se aplica a la base |
| `propuestas_chat.py`, `renombrar_repetidos.py` | Ubican los hitos que nombra el chat del grupo y les dan nombre a los paraderos repetidos con el lugar más cercano de OpenStreetMap |
| `linea_base_chat.py` | Cifras de operación del chat (salidas por día, intervalos, tiempos programados). Resultados en `docs/calidad/linea-base-operacion.md`. El chat no se sube |

## Aplicar a una base que ya existe (PowerShell, en la raíz del proyecto, con Docker levantado)

```
docker compose exec db psql -U rutasur_owner -d rutasur -f /rutasur/database/datos_reales/ruta_lb.sql
```

Se puede aplicar varias veces y encima de los datos demo. Actualiza las variantes sin cambiar su
identificador, así que las unidades, las cuentas y las sesiones se conservan. Los paraderos que
dejan de usarse quedan inactivos y no se borran.

El script comprueba que el orden que calcula la base sobre cada trazado sea el mismo del editor.
Si no coinciden, se detiene sin cambiar nada.

## Cambiar paraderos o nombres

1. Abra `yandex/editor_paraderos.html` en el navegador. El avance se guarda en el navegador.
2. Exporte y reemplace `paraderos.json`.
3. Vuelva a generar el SQL:
   ```
   cd database\datos_reales
   py paraderos_a_sql.py
   ```
4. Aplique `ruta_lb.sql` como se indica arriba.

## Cambiar un trazado (por ejemplo, el ramal Cerrillo con un GPX propio)

1. Agregue el GPX a esta carpeta y regístrelo en `TRAZADO_PROPIO`, en `yandex/preparar_editor.py`.
2. Ejecute `py yandex\preparar_editor.py`. Regenera el editor y los datos.
3. Siga los pasos de «Cambiar paraderos o nombres».
