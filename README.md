# RutaSur v1.0

Aplicación de seguimiento en tiempo real de los buses de las rutas **LB Mollebaya** (131 paraderos) y **LB Cerrillos** (125 paraderos) del Cono Sur de Arequipa (Characato – Mollebaya – centro de Arequipa).

Proyecto de Fin de Carrera — Escuela Profesional de Ingeniería de Sistemas, Universidad Católica de Santa María (UCSM).

## Problema

Los pasajeros de estas rutas no tienen forma de saber dónde están los buses ni cuánto tardarán en llegar a su paradero. El intercambio informal de ubicación por WhatsApp es inconsistente y no ofrece tiempos estimados de llegada.

## Solución

- **App Conductor:** el dispositivo de cada unidad envía su ubicación GPS en tiempo real. Es la única fuente de posición, por lo que no existen "buses fantasma".
- **App Pasajero:** muestra en el mapa los paraderos y los buses activos de cada variante, el destino de cada unidad y el tiempo estimado de llegada (ETA) al paradero elegido. No requiere registro.
- Ambas apps se generan desde un solo código base mediante *flavors* de Flutter.

## Estructura del repositorio

```
rutasur/
├── app/        # Flutter (flavors: pasajero, conductor)
├── backend/    # API REST + WebSocket (FastAPI)
├── database/   # Scripts SQL: esquema, índices, roles, datos semilla
└── docs/       # Diagramas, evidencias e informes
```

## Stack

| Capa | Tecnología |
|------|------------|
| Apps móviles | Flutter / Dart |
| Backend | Python + FastAPI |
| Base de datos | PostgreSQL + PostGIS |
| Control de versiones | Git + GitHub |
| Integración continua | GitHub Actions |

## Estrategia de ramas (Git Flow)

| Rama | Uso |
|------|-----|
| `main` | Versiones estables, etiquetadas (`v1.0.0`, …) |
| `develop` | Integración del trabajo en curso |
| `feature/<nombre>` | Nuevas funcionalidades (salen de `develop`) |
| `hotfix/<nombre>` | Correcciones urgentes (salen de `main`) |
| `refactor/<nombre>` | Mejoras de estructura sin cambiar comportamiento |

Todo cambio entra a `develop` o `main` mediante **Pull Request**.

## Convención de commits

Se usa [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/):

```
feat(app): agrega mapa de paraderos
fix(backend): corrige cálculo de ETA en paraderos compartidos
docs: actualiza diagrama entidad-relación
refactor(database): separa índices en script propio
test(backend): pruebas del endpoint de posiciones
```

## Estándares de codificación

- **Dart / Flutter:** Effective Dart, verificado con `flutter_lints` (`flutter analyze`).
- **Python:** PEP 8, verificado con `ruff`.
- **SQL:** nombres de tablas y columnas en `snake_case`, en singular.

## Versionado

Versionado semántico `MAJOR.MINOR.PATCH`. La primera versión estable es `v1.0.0`.

## Puesta en marcha

### Requisitos

- Docker Desktop
- Git

### 1. Base de datos

```
cp .env.example .env        # luego cambie las contraseñas en .env
docker compose up -d        # crea la base con el esquema y datos demo
docker compose ps           # debe aparecer "healthy"
```

En `database/README.md` están las pruebas, el respaldo y la trazabilidad con el diseño.

### 2. Backend

_Pendiente._

### 3. Apps móviles

_Pendiente._
