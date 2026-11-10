# CLAUDE.md — guía para trabajar en RutaSur

Léelo completo antes de tocar el repositorio. **El repositorio es público:** aquí no va nada que no pueda leer cualquiera (ni contraseñas, ni cadenas de conexión, ni datos personales); lo privado vive en el Proyecto de Claude. Resume qué es el proyecto, cómo está
armado, cómo se trabaja y qué reglas no se rompen. Actualizado al 10/11/2026 (v0.7.3).

## 1. Qué es

**RutaSur v1.0**: seguimiento en tiempo real de las combis de la **línea LB** (empresa
Bus Characato S.A., Arequipa, Perú). Es el **proyecto de fin de carrera** de Pierre
Núñez Aco (Ingeniería de Sistemas, UCSM). Habla con él en **español**, en lenguaje sencillo.

- **App del pasajero.** Mapa, paraderos, ETA (minutos que faltan) y favoritos. No pide cuenta.
- **App del conductor.** Envía el GPS cada 5 s. Es la única fuente de posición, así que no hay «combis fantasma».
- **Panel web de administración.** Muestra la flota, permite editar rutas y paraderos, gestionar unidades y cuentas, y revisar el registro de eventos.
- **API en la nube.** Recibe posiciones, calcula el ETA y atiende las apps y el panel.

La línea tiene dos ramales, **Mollebaya** y **Cerrillo**, que salen de Santa Ana y
comparten tramo hasta el Centro (2 de Mayo). Cada ramal tiene dos sentidos: **IDA** (la
«bajada», hacia el Centro) y **VUELTA** (la «subida», hacia el ramal). En total son
4 variantes y **92 paraderos**, de los que **28 son principales** (★).

## 2. Estado por módulos

Regla de Pierre: **no se pasa al siguiente módulo sin terminar por completo el anterior.**

| Módulo | Contenido | Estado |
|---|---|---|
| M0 | Estabilización | ✅ v0.2.0 |
| M1 | Paraderos y trazados reales | ✅ |
| M2 | Nube (Render + Neon) | ✅ v0.3.0 |
| M3 | Inicio de sesión (JWT) y emisión de posiciones | ✅ v0.4.0 |
| M4 | App del conductor | ✅ v0.5.0, probada en un teléfono real |
| M5 | App del pasajero completa | ✅ v0.6.0 y v0.6.1 |
| M6 | Panel de administración | ✅ v0.7.0 y v0.7.1, en producción |
| M7 | Prueba de campo (piloto) | 🟡 en curso: 1.ª prueba real el 10/11 (2 viajes, D-20 y D-21 → v0.7.3) |

El M7 se hace del 2 al 27/11/2026:

- Pierre viaja como pasajero con la app del conductor, con la cuenta `unidad07`.
- Participan 15–20 familiares y conocidos.
- Se aplica un cuestionario antes y otro después, y se mide la espera en el paradero.
- El error del ETA (MAE y RMSE) se mide con `evaluar_eta` (sección 6).

El protocolo está en Claude Docs: «RutaSur — Protocolo del piloto (Módulo 7)».

## 3. Producción

| Pieza | Dónde |
|---|---|
| API | https://rutasur-api.onrender.com (`/docs`, `/api/v1/health`). Render, plan gratuito, se apaga a los 15 min sin uso |
| Panel | https://rutasur-panel.onrender.com (sitio estático de Render) |
| Base de datos | Neon (PostgreSQL 16 + PostGIS 3.3, AWS us-east-1). El identificador del proyecto está en la memoria privada del Proyecto de Claude, no aquí |
| Despliegue | `render.yaml` (Blueprint `rutasur`); rama `main`, solo si la CI pasó (`autoDeployTrigger: checksPass`) |
| APK | Workflow `apk.yml`, artefacto `rutasur-apk`, firmado con la clave propia de Pierre (CN=Pierre Nunez) |

Cuentas en producción: `unidad07` (conductor) y `pierre.admin` (administrador). Las
contraseñas **nunca** van al chat ni al repositorio.

## 4. Estructura del repositorio (monorepo)

```
app/                Flutter (Dart): pasajero, conductor y panel web desde un solo código
  lib/domain/       modelos e interfaces (modelos.dart, pasajero.dart, conductor.dart, panel.dart, geometria.dart)
  lib/data/         clientes HTTP (api_rutasur, api_conductor, api_panel), almacenamiento local, GPS
  lib/features/     pasajero/, conductor/, panel/ (pantallas y controladores)
  lib/entrypoints/  main_pasajero.dart, main_conductor.dart, main_panel.dart
  test/             unit/, pasajero/, conductor/, panel/ (las pruebas de pantalla usan servicios falsos)
backend/            Python 3.12 + FastAPI
  app/api/v1/       publica.py (sin cuenta), emision.py (conductor), admin.py (panel) + esquemas
  app/services/     estimador_eta.py (patrón Estrategia), llegadas, emisión, flota, administración
  app/repositories/ SQL con SQLAlchemy (text), un repositorio por área
  app/domain/       modelos, umbrales (RN-xxx), excepciones
  app/herramientas/ simular_unidad, cuentas, verificar_despliegue, evaluar_eta
  tests/            unit/, integration/, funcionales/, seguridad/, e2e/
database/
  sql/01..07        esquema completo (extensiones, tipos, tablas, índices, funciones, roles, semilla)
  migraciones/      cambios posteriores (001 principal, 002 horario); se pueden aplicar varias veces
  datos_reales/     GPX, editor de paraderos, paraderos.json → ruta_lb.sql; análisis del chat
  demo/             datos_demo.sql (solo desarrollo y CI: admin.demo, moderador.demo, unidad07, unidad12)
  pruebas/          01_pruebas_integridad.sql (51 pruebas SQL)
  aplicar_en_nube.sh  crea el esquema en Neon o aplica las migraciones, y carga la ruta
docs/               despliegue.md, panel.md, firma-apk.md, calidad/ (defectos D-07..D-18, línea base del chat)
.github/workflows/  ci.yml (pruebas y calidad), apk.yml (instaladores)
render.yaml         API + panel
```

## 5. Tecnologías

| Capa | Tecnología |
|---|---|
| Apps y panel | Flutter (canal estable), Dart ^3.6. Paquetes: flutter_map 8 (OpenStreetMap; Esri en el editor), geolocator 14, permission_handler 12, flutter_secure_storage 10, shared_preferences, http, uuid |
| API | Python 3.12, FastAPI 0.142, Starlette 1.7, Uvicorn, SQLAlchemy 2 (SQL a mano con `text`), psycopg 3, pydantic-settings, PyJWT 2.15 (HS256, 12 h), bcrypt 5 |
| Base de datos | PostgreSQL 16 + PostGIS: proyección sobre el trazado con `ST_LineLocatePoint` y distancias en `geography`. Funciones SQL y triggers recalculan el orden de los paraderos y validan los 150 m |
| Calidad | pytest 9 (cobertura ~97 %), Ruff, Bandit, pip-audit, flutter analyze, flutter_test |
| CI/CD | GitHub Actions + Render (Blueprint) + Neon |
| Datos | GPX propios (BRouter y grabados), Yandex Maps, OpenStreetMap (Overpass y Nominatim) |

**ETA:** `EstimadorDirecto`, que divide la distancia restante sobre el trazado entre la
velocidad de **avance real sobre el trazado en los últimos 10 min** (incluye las paradas;
mínimo 5 km/h). Con menos de 60 s de historia usa el promedio del GPS de las últimas
4 posiciones. Desde la 0.7.3 (D-21): con 2 viajes reales el MAE bajó de 11,3 a 4,7 min (`evaluar_eta`, 1659 estimaciones). La interfaz `EstimadorETA`
permite enchufar otro método, por ejemplo un LSTM, sin tocar el resto. **El informe del PFC
ya no habla de LSTM** (ver `claude/estado-actual-proyecto.md` en el Proyecto); la tesis de
Investigación II todavía lo menciona y está por confirmar con Pierre.

## 6. Reglas de negocio que el código respeta

- **RN-001:** una cuenta de conductor por unidad.
- **RN-003:** un paradero debe estar a 150 m o menos del trazado.
- **RN-005:** una posición con más de 90 s de antigüedad es «no confiable». Si no llegan posiciones en ese tiempo, la unidad pasa a SIN_SEÑAL.
- **RN-006:** solo se calculan llegadas a paraderos que la unidad todavía no pasó.
- **RN-007:** no se muestran llegadas de más de 60 minutos.
- **RN-009:** horario referencial de la línea, de **05:00 a 19:30**. Viene del chat del grupo; de noche no hay servicio.
- **RN-011:** no se guardan datos personales (nombre, DNI ni teléfono). El pasajero no tiene cuenta y su posición no sale del teléfono.
- **RN-012:** posiciones, sesiones y eventos se borran a los **14 días** en producción. La depuración corre una vez cada 24 h (D-18).
- **Sesiones abandonadas:** una sesión sin posiciones durante más de 2 h se cierra sola (CERRADA_AUTOMATICAMENTE, D-19).

## 7. Cómo se trabaja

- **Git Flow.** Las ramas `feature/*` y `fix/*` salen de `develop` (la rama por defecto) y vuelven por PR. El release es un PR de `develop` a `main`, y Render despliega desde `main`.
- **Commits** con Conventional Commits, en español.
- **En la nube de Claude:** se puede hacer push, crear PR y fusionar por la API REST: `gh api repos/pnuneza/PFC-rutasur/pulls`, luego `PUT pulls/N/merge` con `merge_method=merge`. GraphQL, tags, releases y logs de Actions están bloqueados.
- **Fallas de la CI:** se leen como anotaciones, con `gh api .../check-runs/<id>/annotations`. Los scripts de `.github/scripts` publican los errores de Flutter y de Gradle.
- **Los tags los crea Pierre en su PC.** Hay que darle los comandos con el SHA exacto: `git tag -a vX.Y.Z <sha> -m "…"` y luego `git push origin vX.Y.Z`. Existen de v0.2.0 a v0.7.1; v0.7.2 y v0.7.3 se le pasaron a Pierre (confirmar que las creó).
- **Al empezar una rama nueva en la nube:** configurar `git config --add remote.origin.fetch "+refs/heads/RAMA:refs/remotes/origin/RAMA"` y luego `git branch -u origin/RAMA`.
- **Versiones:** se suben juntas en `app/pubspec.yaml`, `backend/pyproject.toml` y `backend/app/__init__.py`.
- **Defectos:** cada uno se registra en `docs/calidad/registro-defectos.md` (D-NN) con su causa, su corrección y la prueba que lo cubre.
- **Flutter no está instalado en el contenedor de la nube.** Las pruebas de la app se validan en la CI.

### Comandos útiles

```bash
# Backend contra un PostgreSQL local (roles rutasur_owner y rutasur_app)
cd backend && pip install -e ".[dev]"
DATABASE_URL="postgresql://rutasur_owner:…@localhost:5432/rutasur" bash ../database/aplicar_esquema.sh
psql "$OWNER_URL" -f ../database/datos_reales/ruta_lb.sql -f ../database/demo/datos_demo.sql
DATABASE_URL="postgresql+psycopg://rutasur_app:…@localhost:5432/rutasur" python -m pytest -q
ruff check . && ruff format --check .

# Simular una combi contra producción (pide la clave de unidad07)
python -m app.herramientas.simular_unidad --api https://rutasur-api.onrender.com \
  --usuario unidad07 --ramal MOLLEBAYA --sentido IDA --velocidad 40 --desde 6000

# Medir el error del ETA con los viajes del piloto (DATABASE_URL de rutasur_app)
python -m app.herramientas.evaluar_eta --desde 2026-11-09 --hasta 2026-11-20 --unidad 07 --csv contraste.csv
```

En producción (Neon) Claude puede **leer** con el MCP de Neon (`run_sql`, `role_name: rutasur_app`; el id del proyecto está en el doc privado `claude/guia-tecnica-rutasur.md`).
Los **cambios** en la base de producción los ejecuta Pierre desde su PC:

```powershell
docker compose exec -e DATABASE_URL="(cadena del dueño de Neon)" db bash /rutasur/database/aplicar_en_nube.sh
```

### Paraderos y trazados

El flujo es `datos_reales/yandex/preparar_editor.py`, luego el editor HTML, que exporta
`paraderos.json`, y por último `paraderos_a_sql.py`, que genera `ruta_lb.sql`. Ese archivo
se aplica con `aplicar_en_nube.sh`. **Ojo:** desde que existe el panel, reaplicar
`ruta_lb.sql` pisa los paraderos editados en el panel (`docs/panel.md`).

## 8. Seguridad (no negociable)

- **Credenciales:** nunca se escriben en el chat, en el código ni en commits. Esto incluye contraseñas, la cadena del dueño de Neon, `JWT_SECRETO`, el keystore `rutasur.jks` con su clave, `.env` y `key.properties`. Viven en Render, Neon, GitHub Secrets (`RUTASUR_KEYSTORE_BASE64`, `RUTASUR_KEYSTORE_PASSWORD`) y en la PC o el Drive de Pierre.
- **Permisos mínimos:** la API usa el rol `rutasur_app`, que no puede borrar posiciones ni cambiar el esquema.
- **Chat de WhatsApp:** del chat del grupo solo se guardan cifras agregadas, nunca nombres ni teléfonos. La exportación no se sube.
- **CORS:** solo se acepta el origen del panel.

## 9. Pendientes conocidos

- **Fase 3 del informe:** el Capítulo 3 (Fase 3) y la sustentación siguen pendientes; la sustentación es a mediados o fines de noviembre de 2026.
