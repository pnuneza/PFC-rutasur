# App del pasajero — RutaSur v1.0

Aplicación Flutter que muestra en el mapa la línea LB, sus paraderos y las unidades en tiempo real, y calcula cuándo llega cada unidad a un paradero.

## Requerimientos implementados (Sprint 2)

| RF | Qué hace | Dónde |
|---|---|---|
| **RF-001** | Trazado de las variantes y paraderos sobre OpenStreetMap; el tramo común se distingue en gris | `widgets/mapa_ruta.dart`, `domain/geometria.dart` |
| **RF-002** | Una flecha por unidad, orientada según su rumbo, actualizada cada 15 s | `widgets/marcadores.dart`, `controlador_mapa.dart` |
| **RF-003** | Número y destino de cada unidad en el mapa, con el color de su ramal | `widgets/marcadores.dart`, `hoja_unidad.dart` |
| **RF-004** | Al tocar un paradero, las próximas llegadas con su ETA en minutos | `hoja_llegadas.dart`, `controlador_llegadas.dart` |
| **RF-008** | Antigüedad del dato y estados vigente / demorado / no confiable | `widgets/paneles.dart`, `widgets/etiqueta_estado.dart` |

Pantallas de P06: **P-01** mapa principal, **P-03** llegadas, **P-04** detalle de unidad, **P-05** sin unidades en circulación y **P-06** ayuda (leyenda y estados).

## Estructura (P05, Figura 20 y Tabla 32)

```
lib/
├── entrypoints/main_pasajero.dart   # arranque de la app del pasajero
├── core/        # configuración y tema (paleta de P06)
├── domain/      # modelos, geometría y contrato del repositorio (sin Flutter)
├── data/        # implementación HTTP del repositorio
└── features/pasajero/   # pantallas y controladores
test/            # pruebas unitarias y de widgets (sin red)
```

## Primera vez en una PC (PowerShell)

Requisitos: Flutter (`flutter doctor` con ✓ en Flutter y Android toolchain) y un emulador de Android.

```
cd $HOME\Desktop\PFC-rutasur
flutter create --project-name rutasur --org pe.edu.ucsm --platforms android,web app
cd app
py tool\preparar_android.py
flutter pub get
flutter analyze
flutter test
```

`flutter create` solo **agrega** las carpetas de Android y Web; no reemplaza el código existente. El script `preparar_android.py` habilita internet y HTTP local en el `AndroidManifest.xml`.

## Ejecutar la demostración

Se necesitan **tres ventanas**, además de Docker con la base de datos:

1. **API** (en `backend`, con el `.venv` activo): `uvicorn app.main:app --reload`
2. **Simulador**, que hace de bus (en `backend`, con el `.venv` activo):
   `python -m app.herramientas.simular_unidad --unidad 12 --ramal CERRILLO --sentido IDA`
3. **App**: abre el emulador desde Android Studio y, en `app`, ejecuta `flutter run`.

Desde el emulador de Android, la API de la PC se ve en `http://10.0.2.2:8000`, que es el valor por defecto. Para usar otra dirección:
`flutter run --dart-define=API_URL=http://192.168.1.50:8000`

### Plan B: en el navegador

Si el emulador va lento, la misma app corre en Chrome:

1. En `backend\.env` agrega `CORS_ORIGENES=["http://localhost:5000"]` y reinicia `uvicorn`.
2. En `app`, ejecuta: `flutter run -d chrome --web-port 5000 --dart-define=API_URL=http://localhost:8000`

## Calidad

```
flutter analyze   # reglas de Effective Dart (flutter_lints)
flutter test      # pruebas unitarias y de widgets
```

GitHub Actions ejecuta ambos en cada push (job «App Flutter»).
