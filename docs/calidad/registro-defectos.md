# Registro de defectos — Sprint 2

Defectos encontrados durante la construcción y las pruebas, con su causa y su corrección. Sirve como evidencia de las etapas de "pruebas durante la codificación", "depuración" y "refactorización" que pide la guía de la Práctica 07.

| N.° | Fecha | Componente | Síntoma | Causa raíz | Corrección | Prueba que lo cubre |
|---|---|---|---|---|---|---|
| D-01 | 11/10 | Base de datos | La restauración del respaldo con `pg_restore` fallaba con "relation linea does not exist" | `pg_restore` ejecuta con `search_path` vacío, y las funciones de los triggers buscaban las tablas sin esquema | Se fijó `SET search_path = public, pg_temp` en todas las funciones. Además protege contra el secuestro de `search_path` | Respaldo → base vacía → restauración, con la misma huella MD5 |
| D-02 | 11/10 | Base de datos | La depuración diaria leía toda la tabla de posiciones (1,7 millones de filas) | El índice BRIN no resumía los bloques nuevos | Índice BRIN con `autosummarize = on`; la depuración pasó a leer cerca del 10 % de la tabla | `02_prueba_rendimiento.sql`, sección 3d |
| D-03 | 11/10 | Pruebas SQL | La prueba de coordenadas "sin sistema de referencia" fallaba | PostGIS asigna el SRID de la columna a un punto sin SRID: la prueba estaba mal planteada | La prueba ahora usa coordenadas UTM 19S (SRID 32719), un error realista | `01_pruebas_integridad.sql`, prueba 38 |
| D-04 | 11/10 | Pruebas SQL | Con `docker compose exec` no se veía la tabla de resultados | El paginador de `psql` ocultaba la salida en la terminal interactiva | `\pset pager off` en los scripts de prueba | Ejecución manual |
| D-05 | 11/10 | Backend | El analizador estático marcó complejidad 9 en el manejo de errores (máximo: 8) | Un manejador por cada tipo de excepción | Refactorización a una tabla excepción → (HTTP, código) | Ruff C901 |
| D-06 | 14/10 | Backend — emisión | En una segunda PC (Windows con Docker Desktop), el simulador se detuvo con "Una posición es anterior al inicio de la sesión" | La hora de inicio de la sesión la ponía el reloj de la **base de datos** (máquina virtual de Docker), mientras que las posiciones y la validación usaban el reloj de la **aplicación**. El reloj de la máquina virtual de Docker Desktop puede adelantarse al de Windows, y entonces la primera posición parecía anterior al inicio | 1) El inicio de la sesión lo fija ahora el reloj de la aplicación: todas las reglas usan un único reloj. 2) Se admite el mismo margen de 30 s hacia antes del inicio que ya existía hacia el futuro, porque el reloj del teléfono del conductor tampoco coincide exactamente con el del servidor. 3) El simulador ya no se detiene si un lote es rechazado; informa y continúa, como lo hará la app | `test_tolera_hasta_30_s_de_desfase_antes_del_inicio`, `test_la_sesion_empieza_a_la_hora_de_la_aplicacion_y_no_a_la_de_la_base` |

## Lección del D-06

El defecto no apareció en el entorno de desarrollo original, donde la aplicación y la base de datos comparten el mismo reloj. Apareció al ejecutar el sistema en otra computadora: probar en más de un entorno detecta problemas que las pruebas en una sola máquina no revelan.

El mismo riesgo existe en producción. El reloj de cada teléfono de conductor puede diferir del reloj del servidor, de modo que el arreglo fortalece también el sistema real y no solo la demostración.
