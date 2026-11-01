/// Punto de arranque de la aplicación del conductor (paquete entrypoints, Tabla 32 de P05).
///
///     flutter run -t lib/entrypoints/main_conductor.dart --dart-define=API_URL=https://rutasur-api.onrender.com
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/almacen_local.dart';
import '../data/api_conductor.dart';
import '../data/gps_geolocator.dart';
import '../features/conductor/app_conductor.dart';
import '../features/conductor/controlador_conductor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const uuid = Uuid();
  runApp(AppConductor(
    controlador: ControladorConductor(
      servicio: ApiConductor(),
      almacen: AlmacenLocal(),
      gps: GpsGeolocator(),
      nuevoId: uuid.v4,
    ),
  ));
}
