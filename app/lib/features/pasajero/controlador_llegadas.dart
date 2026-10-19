/// Estado de la hoja de llegadas a un paradero (P-03, CU-01).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../domain/modelos.dart';
import '../../domain/repositorio.dart';

class ControladorLlegadas extends ChangeNotifier {
  ControladorLlegadas(
    this._repositorio,
    this.codigoParadero, {
    Duration intervalo = Config.intervaloConsulta,
  }) : _intervalo = intervalo;

  final RepositorioRutaSur _repositorio;
  final String codigoParadero;
  final Duration _intervalo;
  Timer? _temporizador;
  bool _cerrado = false;

  List<Llegada> llegadas = const [];
  bool cargando = true;
  bool sinConexion = false;
  String? error;

  /// Consulta las llegadas y las actualiza cada 15 s mientras la hoja está abierta.
  Future<void> iniciar() async {
    await refrescar();
    _temporizador?.cancel();
    _temporizador = Timer.periodic(_intervalo, (_) => refrescar());
  }

  Future<void> refrescar() async {
    try {
      llegadas = await _repositorio.llegadas(codigoParadero);
      sinConexion = false;
      error = null;
    } on SinConexion {
      sinConexion = true; // se conservan las llegadas anteriores
    } on ErrorServicio catch (e) {
      error = e.mensaje;
    }
    cargando = false;
    _notificar();
  }

  @override
  void dispose() {
    _cerrado = true;
    _temporizador?.cancel();
    super.dispose();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }
}
