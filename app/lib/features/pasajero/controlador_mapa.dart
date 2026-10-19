/// Estado de la pantalla del mapa (P-01).
///
/// Separa la lógica de la interfaz: el widget solo dibuja lo que este
/// controlador expone, y el controlador puede probarse sin Flutter ni red.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../domain/modelos.dart';
import '../../domain/repositorio.dart';

class ControladorMapa extends ChangeNotifier {
  ControladorMapa(
    this._repositorio, {
    DateTime Function()? reloj,
    Duration intervalo = Config.intervaloConsulta,
  })  : _reloj = reloj ?? DateTime.now,
        _intervalo = intervalo;

  final RepositorioRutaSur _repositorio;
  final DateTime Function() _reloj;
  final Duration _intervalo;
  Timer? _temporizador;
  bool _cerrado = false;

  // Ruta (se descarga una vez)
  Linea? linea;
  List<ParaderoEnMapa> paraderos = const [];
  bool cargandoLinea = true;
  String? errorLinea;

  // Unidades (se consultan cada 15 s, RF-002)
  List<UnidadActiva> unidades = const [];
  DateTime? ultimaActualizacion;
  bool sinConexion = false;

  /// Descarga la ruta, consulta las unidades y programa la consulta periódica.
  Future<void> iniciar() async {
    await cargarLinea();
    if (linea == null) return;
    await refrescarUnidades();
    _temporizador?.cancel();
    _temporizador = Timer.periodic(_intervalo, (_) => refrescarUnidades());
  }

  Future<void> cargarLinea() async {
    cargandoLinea = true;
    errorLinea = null;
    _notificar();
    try {
      final descargada = await _repositorio.obtenerLinea();
      linea = descargada;
      paraderos = paraderosUnicos(descargada);
    } on SinConexion {
      errorLinea = 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
    } on ErrorServicio catch (e) {
      errorLinea = e.mensaje;
    }
    cargandoLinea = false;
    _notificar();
  }

  /// Consulta las unidades. Si falla, conserva las últimas conocidas (P06, P-01).
  Future<void> refrescarUnidades() async {
    try {
      unidades = await _repositorio.unidadesActivas();
      ultimaActualizacion = _reloj();
      sinConexion = false;
    } on SinConexion {
      sinConexion = true;
    } on ErrorServicio {
      sinConexion = true;
    }
    _notificar();
  }

  /// Segundos desde la última consulta exitosa (indicador de P-01).
  int? segundosDesdeActualizacion() {
    final ultima = ultimaActualizacion;
    return ultima == null ? null : _reloj().difference(ultima).inSeconds;
  }

  /// No hay unidades transmitiendo y el servicio sí respondió (P-05, RNF-04).
  bool get sinUnidadesEnCirculacion =>
      ultimaActualizacion != null && !sinConexion && unidades.isEmpty;

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
