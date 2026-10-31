# Base de datos — RutaSur v1.0

Implementación del modelo de datos diseñado en la **Práctica 06, sección 2.16**: PostgreSQL 16 con PostGIS 3.4.

## Estructura

```
database/
├── sql/                         # Esquema, en orden de ejecución
│   ├── 01_extensiones.sql       # PostGIS, pg_trgm, unaccent
│   ├── 02_tipos.sql             # Tipos enumerados (Tabla 59)
│   ├── 03_tablas.sql            # 10 tablas con sus restricciones (Tablas 60 y 61)
│   ├── 04_indices.sql           # Estrategia de indexación (Tabla 62)
│   ├── 05_funciones.sql         # Funciones, triggers y vista
│   ├── 06_roles.sql             # Rol de la aplicación con permisos mínimos
│   └── 07_semilla.sql           # Línea LB
├── datos_reales/                # Ruta real de la línea LB: trazados y paraderos (ver su README)
│   └── ruta_lb.sql              # Se carga siempre, después del esquema
├── demo/datos_demo.sql          # Unidades, cuentas y una sesión ficticias para desarrollo
├── pruebas/
│   ├── 01_pruebas_integridad.sql   # 51 pruebas de reglas y seguridad
│   └── 02_prueba_rendimiento.sql   # Carga de 1,7 millones de posiciones
├── scripts/
│   ├── respaldo_configuracion.sh   # Política de respaldo (Tabla 63)
│   └── restaurar_configuracion.sh
├── docker-init/00_rutasur.sh    # Se ejecuta solo al crear el contenedor
├── aplicar_esquema.sh           # Crea el esquema en cualquier servidor (local o Neon)
└── respaldos/                   # Copias generadas (no se suben a Git)
```

## Puesta en marcha (Docker Desktop)

> En Windows, ejecute los comandos de `docker` desde **PowerShell** o la terminal de VS Code.
> Las terminales tipo Git Bash / MSYS2 convierten las rutas `/rutasur/...` en rutas de Windows y los comandos fallan.

1. En la raíz del proyecto, copie `.env.example` como `.env` y cambie las dos contraseñas.
2. Levante la base:
   ```
   docker compose up -d
   ```
   La primera vez descarga la imagen, crea el esquema, carga la ruta real de la línea LB
   y agrega los datos demo (unidades, cuentas y una sesión).
3. Verifique que esté sana (columna STATUS = `healthy`):
   ```
   docker compose ps
   docker compose logs db
   ```
   En el log debe aparecer `RutaSur: esquema creado correctamente.`

**Conexión con DBeaver o pgAdmin:** host `localhost`, puerto `5432`, base `rutasur`, usuario `rutasur_owner` y la contraseña de `POSTGRES_PASSWORD`.

**Volver a crear todo desde cero** (borra los datos):
```
docker compose down -v
docker compose up -d
```

## Pruebas

**Integridad y seguridad** (menos de 1 segundo; no deja datos):
```
docker compose exec db psql -U rutasur_owner -d rutasur -f /rutasur/database/pruebas/01_pruebas_integridad.sql
```

**Rendimiento** con el volumen de la Tabla 65 (20 a 60 segundos; no deja datos):
```
docker compose exec db psql -U rutasur_owner -d rutasur -f /rutasur/database/pruebas/02_prueba_rendimiento.sql
```

**Respaldo y restauración:**
```
docker compose exec db bash /rutasur/database/scripts/respaldo_configuracion.sh
```
La copia queda en `database/respaldos/`.

## Trazabilidad diseño → implementación

| Diseño (Práctica 06) | Implementación |
|---|---|
| Tabla 57 — Tipo de base de datos | `docker-compose.yml` (PostgreSQL 16 + PostGIS 3.4), `01_extensiones.sql` |
| Figura 47 / Tabla 60 — Modelo lógico y diccionario | `03_tablas.sql` (10 tablas, nombres y tipos idénticos) |
| Tabla 59 — Tipos enumerados | `02_tipos.sql` |
| Tabla 61 — Restricciones de integridad | `03_tablas.sql`, `04_indices.sql` (índice único parcial) |
| Tabla 62 — Indexación | `04_indices.sql` (9 índices) |
| Desnormalizaciones justificadas | `05_funciones.sql`: trigger de longitud y `fn_recalcular_paraderos_variante` |
| Validación de la carga (150 m) | `fn_recalcular_paraderos_variante` |
| RN-012 — Retención de 30 días | `fn_depurar_datos_operativos` |
| Tabla 63 — Respaldo y restauración | `scripts/respaldo_configuracion.sh`, `scripts/restaurar_configuracion.sh` |
| Tabla 65 — Volumetría | `pruebas/02_prueba_rendimiento.sql` |

## Decisiones tomadas al implementar

Complementan el diseño de P06 sin cambiarlo:

- **Los datos calculados se mantienen solos.** `variante.longitud_m` la calcula un trigger al guardar el trazado. El orden y la distancia acumulada de los paraderos los calcula `fn_asignar_paraderos_variante` a partir del propio trazado, así que el panel no puede guardar un orden incoherente.
- **Recalculo automático.** Si se edita un trazado o se mueve un paradero, se recalculan las distancias. Si algún paradero queda a más de 150 m del trazado, el cambio se rechaza completo.
- **Apertura de sesión validada en la base.** Un trigger impide abrir sesión con una unidad inactiva, una cuenta inactiva o la cuenta de otra unidad (RN-001).
- **Contraseñas.** Una restricción solo acepta hashes bcrypt, así que es imposible guardar una contraseña en texto plano.
- **Menor privilegio.** El backend se conecta como `rutasur_app`. Ese rol no puede crear ni borrar tablas, borrar configuración, alterar la auditoría ni borrar posiciones fuera de la depuración.
- **Funciones con `search_path` fijo.** Evita el secuestro de `search_path` y permite que `pg_restore` funcione. Esta falla se detectó en la prueba de restauración y se corrigió.
- **BRIN con `autosummarize`.** La depuración lee solo los bloques antiguos y no la tabla completa (unas 10 veces menos lectura).
- **Orden de paraderos `DEFERRABLE`.** Permite reordenar una variante dentro de una transacción.

## Resultados de la verificación

Obtenidos sobre PostgreSQL 16 + PostGIS 3.4:

| Prueba | Resultado |
|---|---|
| Pruebas de integridad y seguridad | 51 de 51 OK |
| Carga de 1 728 000 posiciones | ≈ 22 s |
| Tamaño real de `posicion` | 411 MB (P06 estimó ≈ 390 MB) |
| Últimas 4 posiciones de una sesión | < 1 ms (Index Scan) |
| Unidades activas (GET /vehicles) | < 1 ms |
| Lote de 200 posiciones | ≈ 4 ms |
| Depuración de datos de más de 30 días | ≈ 25 ms (BRIN) |
| Respaldo → base vacía → restauración | Ruta restaurada idéntica (misma huella MD5) |
