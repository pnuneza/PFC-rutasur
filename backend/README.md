# Backend — RutaSur API

Servicio en la nube de RutaSur v1.0: Python 3.12 + FastAPI 0.142 sobre PostgreSQL 16 + PostGIS 3.4.

## Estructura (P05, Figura 21 y Tabla 32)

```
backend/
├── app/
│   ├── main.py               # Punto de entrada
│   ├── api/v1/               # Enrutadores y esquemas (DTO) — capa de servicios
│   │   ├── publica.py        #   ISalud + IConsultaPublica
│   │   └── esquemas.py       #   Objetos de transferencia de datos (Pydantic)
│   ├── api/dependencias.py   # Inyección de dependencias
│   ├── core/                 # Configuración y errores transversales
│   ├── services/             # Reglas de negocio — capa de negocio
│   │   ├── estimador_eta.py          # EstimadorETA (interfaz) + EstimadorDirecto
│   │   ├── validador_posiciones.py   # RF-019
│   │   ├── servicio_llegadas.py      # CU-01
│   │   ├── servicio_emision.py       # CU-02
│   │   ├── servicio_flota.py         # Frescura del dato (RN-005)
│   │   └── servicio_rutas.py
│   ├── domain/               # Entidades, enumeraciones, excepciones y umbrales
│   ├── repositories/         # Interfaces + implementaciones SQL — capa de datos
│   ├── db/                   # Conexión
│   └── herramientas/         # Simulador de unidad y verificación del despliegue
└── tests/
    ├── unit/                 # Reglas de negocio con repositorios en memoria
    └── integration/          # API y servicios contra PostGIS real
```

Las dependencias van en un solo sentido: `api → services → repositories → db`, y todos dependen de `domain`. Los servicios conocen los repositorios solo por su interfaz (`repositories/interfaces.py`), lo que permite probarlos sin base de datos.

## Puesta en marcha (Windows, PowerShell)

Requisitos: Python 3.12 y la base de datos de Docker en marcha (`docker compose up -d` en la raíz).

```
cd backend
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
copy .env.example .env      # luego ponga la contraseña de rutasur_app
uvicorn app.main:app --reload
```

Abra **http://localhost:8000/docs**: es la documentación interactiva del contrato (OpenAPI 3) y desde ahí se prueba cada operación.

> Si PowerShell bloquea `Activate.ps1`, ejecute una vez:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## Operaciones disponibles

| Interfaz | Método y ruta | Función | RF |
|---|---|---|---|
| ISalud | `GET /api/v1/health` | Estado, versión y hora del servidor | RNF-03 |
| IConsultaPublica | `GET /api/v1/routes/lb` | Línea, variantes, trazados y paraderos ordenados | RF-001 |
| IConsultaPublica | `GET /api/v1/stops?q=` | Búsqueda de paraderos sin mayúsculas ni tildes | RF-005 |
| IConsultaPublica | `GET /api/v1/vehicles` | Unidades en servicio con frescura del dato | RF-002, 003, 008 |
| IConsultaPublica | `GET /api/v1/stops/{code}/arrivals` | Próximas llegadas ordenadas por ETA | RF-004, 018 |
| IAutenticacion | `POST /api/v1/auth/login` | Token JWT (12 h) para el conductor o el panel; bloqueo a los 5 fallos | RF-009, 014 |
| IEmision | `POST /api/v1/sessions` | Abre la sesión de la unidad del token (cierra la anterior, RN-002) | RF-010, 013 |
| IEmision | `POST /api/v1/sessions/{id}/positions` | Lote de 1 a 200 posiciones; acuse idempotente; 60 envíos/min | RF-011, 012, 019 |
| IEmision | `POST /api/v1/sessions/{id}/close` | Cierra la sesión | RF-010 |

**Pendiente para el Sprint 3:** `IAutenticacion` (login con JWT), los endpoints HTTP de `IEmision` (la lógica ya está en `servicio_emision.py`), `IAdministracion`, límite de peticiones y tareas programadas.

## Simulador de unidad

Mientras no exista la app del conductor, el simulador recorre el trazado y emite posiciones a través del mismo servicio de emisión que usará la API:

```
python -m app.herramientas.simular_unidad --unidad 12 --ramal CERRILLO --sentido IDA
```

Con la opción `--con-errores` mezcla lecturas defectuosas para ver al validador en acción. Mientras corre, `GET /vehicles` y `GET /stops/stp_001/arrivals` cambian en vivo. Se detiene con Ctrl+C.

## Calidad

```
ruff check app tests            # análisis estático (PEP 8, errores, complejidad, seguridad)
ruff format --check app tests   # formato
bandit -c pyproject.toml -r app # seguridad
pytest --cov                    # 91 pruebas, cobertura 96 %
```

El detalle de los hallazgos y su corrección está en `docs/calidad/analisis-estatico.md`.

## Despliegue en la nube

La API se publica en Render y la base en Neon: vea [`docs/despliegue.md`](../docs/despliegue.md).
Para comprobar un despliegue:

```
python -m app.herramientas.verificar_despliegue https://rutasur-api.onrender.com
```

## Cuentas y simulación

```
python -m app.herramientas.cuentas listar
python -m app.herramientas.cuentas crear-conductor --unidad 07
python -m app.herramientas.cuentas crear-panel --usuario pierre.admin --rol ADMINISTRADOR

# Simular una unidad transmitiendo por la API, como la app del conductor
$env:RUTASUR_CLAVE = "(contraseña)"
python -m app.herramientas.simular_unidad --api http://localhost:8000 --usuario unidad07 --ramal MOLLEBAYA --sentido IDA
```

En `/docs`, el botón **Authorize** acepta el token de `POST /auth/login` para probar las
operaciones del conductor.
