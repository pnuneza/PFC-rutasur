# Análisis estático del backend — Sprint 2

Registro de hallazgos y correcciones exigido por el checklist de la Unidad 6 del libro de cátedra ("Se ejecutó al menos una herramienta de análisis estático de código, con hallazgos documentados y atendidos").

## Herramientas

| Herramienta | Qué revisa | Configuración |
|---|---|---|
| **Ruff 0.7** | Estilo PEP 8, errores lógicos, orden de imports, nombres, complejidad ciclomática (máx. 8), simplificaciones y reglas de seguridad | `backend/pyproject.toml`, sección `[tool.ruff]` |
| **Bandit 1.7** | Vulnerabilidades de seguridad en Python: inyección SQL, secretos en el código, criptografía débil, etc. | `backend/pyproject.toml`, sección `[tool.bandit]` |
| **pytest-cov 6.0** | Porcentaje del código ejercitado por las pruebas | Umbral mínimo de 85 % en CI |

Las tres se ejecutan automáticamente en GitHub Actions en cada push y en cada pull request (`.github/workflows/ci.yml`).

## Primera ejecución: 31 hallazgos de Ruff y 0 de Bandit

| Regla | Cantidad | Qué significa | Cómo se atendió |
|---|---|---|---|
| **C901** | 1 | `registrar_manejadores` tenía complejidad ciclomática **9** (máximo fijado: 8): un manejador por cada tipo de error | **Refactorización.** Se reemplazaron los manejadores repetidos por una tabla `excepción → (estado HTTP, código)`. Agregar un error nuevo ahora es agregar una fila. La complejidad máxima del proyecto quedó en **6**. |
| **N818** | 1 | La convención exige que las excepciones terminen en el sufijo inglés *Error* | **Decisión documentada.** El proyecto nombra el dominio en español (`ErrorDeNegocio`, `RecursoNoEncontrado`). Se desactivó la regla en `pyproject.toml` con su justificación. |
| **SIM117** | 1 | Dos `with` anidados que pueden unirse en uno | Se unieron en una sola sentencia. |
| **I001** | 4 | Imports desordenados | Corrección automática (`ruff check --fix`). |
| **E501** | 24 | Líneas de más de 100 caracteres | Formateo automático (`ruff format`) y ajuste manual de 3 textos. |

**Bandit** no reportó problemas. Registró una exclusión justificada: el simulador usa el generador `random` solo para dar realismo al recorrido (regla B311), sin ninguna relación con la seguridad. La exclusión está marcada y comentada en el código.

## Resultado final

| Indicador | Antes | Después |
|---|---|---|
| Hallazgos de Ruff | 31 | **0** |
| Archivos sin formato estándar | 16 | **0** |
| Problemas de seguridad (Bandit) | 0 | **0** |
| Complejidad ciclomática máxima | 9 | **6** |
| Pruebas automatizadas | — | **91** (62 unitarias + 29 de integración) |
| Cobertura de código | — | **96 %** |

## Prácticas de seguridad verificadas en el código

- **Inyección SQL (OWASP A03):** todas las consultas usan parámetros enlazados (`:nombre`). Además, la búsqueda de paraderos escapa los comodines `%` y `_` que escriba el usuario; lo comprueba una prueba de integración.
- **Configuración (OWASP A05):** los errores internos devuelven un mensaje genérico sin detalles técnicos. La conexión y los secretos se leen de variables de entorno, nunca del código.
- **Menor privilegio:** el backend se conecta como `rutasur_app`. Una prueba de integración verifica que ese rol no puede borrar posiciones.
