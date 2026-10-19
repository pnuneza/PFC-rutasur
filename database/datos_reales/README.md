# Trazados reales

Reemplazan las líneas rectas de `demo/datos_demo.sql` por recorridos que siguen las calles.

| Archivo | Qué es |
|---|---|
| `RutaMollebaya.gpx` | Recorrido de ida y vuelta del ramal Mollebaya, dibujado en BRouter-Web (33,4 km) |
| `gpx_a_sql.py` | Convierte el GPX en SQL: lo parte en el punto más alejado del inicio (el Centro) |
| `plantilla_mollebaya.sql` | Plantilla que usa el conversor |
| `trazado_mollebaya.sql` | **Generado.** Es el que se aplica a la base |

## Aplicar (PowerShell, en la raíz del proyecto, con Docker levantado)

```
docker compose exec db psql -U rutasur_owner -d rutasur -f /rutasur/database/datos_reales/trazado_mollebaya.sql
```

Después: reinicie el simulador (lee el trazado al arrancar) y recargue la app con F5.
Si se recrea la base con `docker compose down -v`, se debe aplicar otra vez.

## Qué cambia

- **Mollebaya IDA** (Mollebaya → Centro, 17,5 km) y **VUELTA** (Centro → Mollebaya, 15,8 km): trazado real.
- **Cerrillo queda desactivado** (`variante.activa = false`, paraderos stp_007 y stp_008 inactivos) hasta
  dibujar su GPX. No se borra nada; se cierran sus sesiones abiertas y el simulador ya no acepta ese ramal.
- Los paraderos stp_001 a stp_006 se colocan sobre la ruta real; su orden y distancia se recalculan y se
  valida que ninguno quede a más de 150 m del trazado. Sin Cerrillo no hay tramo común, así que toda la
  ruta se dibuja en azul. Los nombres siguen siendo de demostración.

Los datos demo originales no se modifican: las pruebas de CI siguen usando `demo/datos_demo.sql`.

> **Pruebas locales:** las de integración del backend esperan los datos demo (4 variantes). Con este
> trazado aplicado, 6 de ellas fallan en su PC. Para correr `pytest` completo, vuelva a los datos demo
> con `docker compose down -v` y `docker compose up -d`, y después aplique este script otra vez.

## Volver a generar (si se corrige el GPX)

```
cd database\datos_reales
py gpx_a_sql.py RutaMollebaya.gpx --ramal MOLLEBAYA
```
