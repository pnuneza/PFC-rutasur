/// Punto de entrada del panel administrativo (Flutter Web).
///
///   flutter run -d chrome -t lib/entrypoints/main_panel.dart --dart-define=API_URL=http://localhost:8000
///   flutter build web -t lib/entrypoints/main_panel.dart --dart-define=API_URL=https://rutasur-api.onrender.com
library;

import 'package:flutter/material.dart';

import '../data/api_panel.dart';
import '../features/panel/app_panel.dart';

void main() {
  runApp(AppPanel(servicio: ApiPanel()));
}
