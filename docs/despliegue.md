# Despliegue en la nube — Neon + Render

RutaSur corre en dos servicios gratuitos:

| Parte | Servicio | Plan gratuito (octubre de 2026) |
|---|---|---|
| Base de datos PostgreSQL 16 + PostGIS | **Neon** | 1 GB por proyecto, 100 CU-horas al mes, se suspende tras 5 min sin uso |
| API (FastAPI) | **Render** | 750 horas al mes, se apaga tras 15 min sin tráfico y tarda ~1 min en arrancar |

Las dos regiones están en el este de EE. UU. (Virginia), juntas para que la API y la base
se hablen rápido. Ni Render ni Neon tienen una región en Sudamérica que sirva para ambos.

## Qué implican los límites

- **Primera consulta lenta.** Si nadie usó la app en 15 minutos, la primera petición tarda
  alrededor de un minuto mientras Render arranca el servicio. Mientras los conductores
  transmiten, el servicio no se apaga.
- **Espacio.** Cada unidad que transmite cada 5 s genera unas 11 500 posiciones al día. Para
  no superar 1 GB, la API borra cada 24 h las posiciones con más de `RETENCION_DIAS` = 14
  días (RN-012). Se puede cambiar en Render.
- **Horas de cómputo.** Con unidades transmitiendo 16 h al día, Neon queda despierto unas
  480 h al mes, por encima de las 100 CU-horas gratuitas (unas 400 h con el tamaño mínimo).
  Alcanza para la demostración y una prueba de campo de algunos días, no para operar todo el mes.

## Paso 1 — Base de datos en Neon

1. Cree una cuenta en <https://neon.com> e inicie un proyecto nuevo:
   - Nombre: `rutasur`
   - Postgres: **16**
   - Región: **AWS US East 1 (N. Virginia)**
2. En **Connect**, desactive **Connection pooling** y copie la cadena de conexión del dueño
   (`neondb_owner`). Tiene esta forma:
   `postgresql://neondb_owner:XXXX@ep-xxxx.us-east-1.aws.neon.tech/neondb?sslmode=require`
3. Genere una contraseña larga para el rol de la aplicación (PowerShell):
   ```powershell
   $b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
   [Convert]::ToBase64String($b) -replace '[+/=]', ''
   ```
   Guárdela en su gestor de contraseñas: se usa en el paso 2 y en Render.
4. Con Docker levantado (`docker compose up -d`), en la raíz del proyecto:
   ```powershell
   docker compose exec `
     -e DATABASE_URL="(cadena del dueño, del punto 2)" `
     -e RUTASUR_APP_PASSWORD="(contraseña del punto 3)" `
     db bash /rutasur/database/aplicar_en_nube.sh
   ```
   El script usa el `psql` del contenedor; no hace falta instalar nada. Crea el esquema,
   las extensiones y el rol `rutasur_app`, y carga la ruta real. Al final muestra las 4
   variantes con sus paraderos. **No carga datos demo.**

## Paso 2 — API en Render

1. Cree una cuenta en <https://render.com> con **GitHub** y autorice el repositorio
   `PFC-rutasur`.
2. **New → Blueprint** → elija el repositorio. Render lee `render.yaml` y propone el
   servicio `rutasur-api`.
3. Le pedirá `DATABASE_URL`. Use la misma cadena del paso 1, pero con el rol de la
   aplicación:
   `postgresql://rutasur_app:(contraseña del paso 1.3)@ep-xxxx.us-east-1.aws.neon.tech/neondb?sslmode=require`
   Cambie solo el usuario y la contraseña; el resto queda igual.
4. **Apply.** Render instala, arranca y espera a que `/api/v1/health` responda. Después
   despliega solo cuando se fusiona un cambio en `main` y pasa la integración continua.

## Paso 3 — Verificar

En la carpeta `backend`, con el entorno virtual activo:
```powershell
python -m app.herramientas.verificar_despliegue https://rutasur-api.onrender.com
```
(use la URL que Render muestre). Todas las líneas deben decir `OK`. La primera puede
tardar un minuto si el servicio estaba apagado.

## Actualizar la ruta en la nube

Después de cambiar paraderos o trazados (`database/datos_reales/README.md`), vuelva a
ejecutar el comando del paso 1.4. Si el esquema ya existe, solo actualiza la ruta.

## Seguridad

- Las contraseñas solo se escriben en Neon, en Render y en la terminal propia. Nunca en
  el repositorio ni en archivos `.env` que se suban.
- Render usa `rutasur_app`, con permisos mínimos: no puede borrar posiciones ni cambiar
  el esquema. La cadena del dueño solo se usa para crear o actualizar la base.
- En producción la API envía HSTS y las cabeceras de seguridad (D-09).
