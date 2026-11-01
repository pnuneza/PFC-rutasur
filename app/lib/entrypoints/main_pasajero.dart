/// Punto de arranque de la aplicación del pasajero (paquete entrypoints, Tabla 32 de P05).
///
/// Cada aplicación tendrá su propio punto de arranque sobre el mismo código:
/// main_pasajero (este), main_conductor y main_panel.
library;

import 'package:flutter/material.dart';

import '../data/api_rutasur.dart';
import '../data/preferencias_locales.dart';
import '../data/ubicacion_pasajero.dart';
import '../features/pasajero/app_pasajero.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppPasajero(
    repositorio: ApiRutaSur(),
    preferencias: PreferenciasLocales(),
    ubicacion: UbicacionGeolocator(),
  ));
}
