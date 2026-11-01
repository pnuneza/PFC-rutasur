# Panel administrativo (Módulo 6)

Panel web de RutaSur hecho en Flutter Web (P06, pantallas A-01 a A-05). Usa la misma API que
las apps, con las rutas `/api/v1/admin/...`.

| Pantalla | Qué hace | Administrador | Moderador |
|---|---|:-:|:-:|
| A-01 Ingreso | Usuario y contraseña. Tras 5 intentos fallidos, la cuenta se bloquea 15 min. Las cuentas de conductor no entran | ✔ | ✔ |
| A-02 Flota | Unidades transmitiendo, sin señal (más de 90 s) e inactivas, desde cuándo, con un mapa. Se actualiza cada 15 s | ✔ | ✔ |
| A-03 Rutas y paraderos | Horario referencial, paraderos de cada variante, crear y editar paraderos a 150 m o menos del trazado | ✔ | — |
| A-04 Unidades y cuentas | Registrar y deshabilitar unidades. Cuentas de conductor y del panel con contraseña temporal | ✔ | — |
| A-05 Eventos | Registro de peticiones, errores, posiciones descartadas y seguridad, hasta 30 días atrás | ✔ | ✔ |

## Reglas que conviene saber

- **Sin datos personales.** No hay campos para nombre, DNI ni teléfono (RN-011).
- **Contraseña temporal.** Al crear una cuenta o restablecer su contraseña, el panel la
  muestra **una sola vez**. Cópiela y entréguela en persona. El servidor solo guarda su hash.
- **Una cuenta por unidad** (RN-001). Para dar de alta un bus nuevo: primero registre la
  unidad y después cree su cuenta de conductor.
- **Deshabilitar una unidad** cierra su turno abierto, la saca del mapa e impide que su
  conductor ingrese hasta que se vuelva a habilitar.
- **Nadie se desactiva a sí mismo,** y siempre queda al menos un administrador activo.
- **El orden de los paraderos se calcula solo,** a lo largo del trazado. El panel decide
  qué paraderos tiene cada variante; nunca quedan huecos ni repetidos.
- **Desactivar un paradero** lo quita de todas sus variantes. No se borra: puede volver.
- **Paradero principal (★):** se ve en la app aunque el mapa esté alejado; los demás
  aparecen al acercar (zoom 14). Conviene marcar solo los puntos que la gente reconoce
  (plazas, cruces, terminales): hoy son 28 de 92.
- **Todo cambio queda en el registro de eventos** con el usuario del panel que lo hizo.
- **La sesión dura 12 horas** y vive solo en la pestaña: al recargar la página se vuelve
  a ingresar.

## Publicarlo en Render (una vez)

El panel es un segundo servicio en `render.yaml`: un sitio estático gratuito que Render
compila descargando Flutter (unos 5 a 8 minutos).

1. En Render, abra el Blueprint **rutasur** y pulse **Manual sync**. Aparecerá el servicio
   nuevo **rutasur-panel**. Confírmelo con **Apply**.
2. Cuando termine, Render muestra su dirección. Normalmente es
   `https://rutasur-panel.onrender.com`. Si es otra, cópiela en `render.yaml`, en
   `CORS_ORIGENES` del servicio `rutasur-api`, y avíseme para actualizarla.
3. Entre con `pierre.admin` y su contraseña.

El panel se vuelve a publicar solo cada vez que se fusiona un cambio en `main` y pasa la
integración continua, igual que la API.

### Si la API responde, pero el panel dice «No hay conexión con el servicio»

Casi siempre es CORS: la dirección del panel no está en `CORS_ORIGENES`. Revise que sea
exactamente la que muestra Render, con `https://` y sin `/` al final.

## Probarlo en la PC

Con la API local en marcha (`uvicorn app.main:app --reload`) y en `backend/.env`:
`CORS_ORIGENES=["http://localhost:5000"]`. Luego, en la carpeta `app`:

```powershell
flutter run -d chrome --web-port 5000 -t lib/entrypoints/main_panel.dart --dart-define=API_URL=http://localhost:8000
```

Cuentas de los datos demo (contraseña `rutasur-demo`): `admin.demo` y `moderador.demo`.

## Cuidado con `ruta_lb.sql`

Desde que el panel existe, **el panel es la fuente de verdad de los paraderos en la nube**.
Volver a aplicar `database/datos_reales/ruta_lb.sql` con `aplicar_en_nube.sh` reemplaza los
paraderos de las cuatro variantes con los del editor de la carpeta `datos_reales`, y se
perderían los cambios hechos en el panel. Úselo solo para cargar trazados nuevos, y luego
haga los ajustes finos en el panel.
