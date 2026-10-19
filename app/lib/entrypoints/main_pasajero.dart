/// Punto de arranque de la aplicación del pasajero (paquete entrypoints, Tabla 32 de P05).
///
/// Cada aplicación tendrá su propio punto de arranque sobre el mismo código:
/// main_pasajero (este), main_conductor y main_panel (siguientes sprints).
library;

import 'package:flutter/material.dart';

import '../data/api_rutasur.dart';
import '../features/pasajero/app_pasajero.dart';

void main() {
  runApp(AppPasajero(repositorio: ApiRutaSur()));
}
