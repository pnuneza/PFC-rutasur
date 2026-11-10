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
    Duration reintento = Config.reintentoConsulta,
  })  : _intervalo = intervalo,
        _reintento = reintento;

  final RepositorioRutaSur _repositorio;
  final String codigoParadero;
  final Duration _intervalo;
  final Duration _reintento;
  Timer? _temporizador;
  Timer? _temporizadorReintento;
  bool _cerrado = false;
  bool _pausado = false;
  bool _consultando = false;
  bool _huboDatos = false;
  int _fallosSeguidos = 0;

  List<Llegada> llegadas = const [];
  bool cargando = true;
  bool sinConexion = false;
  String? error;

  /// Consulta las llegadas y las actualiza cada 15 s mientras la hoja está abierta.
  Future<void> iniciar() async {
    await refrescar();
    _programarConsultas();
  }

  void _programarConsultas() {
    _temporizador?.cancel();
    _temporizador = Timer.periodic(_intervalo, (_) => refrescar());
  }

  /// La app pasó a segundo plano: deja de consultar (D-20).
  void pausar() {
    _pausado = true;
    _temporizador?.cancel();
    _temporizadorReintento?.cancel();
  }

  /// La app volvió al frente: consulta de inmediato (D-20).
  Future<void> reanudar() async {
    if (!_pausado) return;
    _pausado = false;
    _fallosSeguidos = 0;
    _programarConsultas();
    await refrescar();
  }

  /// Igual que el mapa: un fallo aislado con datos en pantalla se reintenta a los 3 s
  /// sin anunciarlo; el aviso sale tras [Config.fallosParaAviso] fallos seguidos (D-20).
  Future<void> refrescar() async {
    if (_consultando || _cerrado) return;
    _consultando = true;
    _temporizadorReintento?.cancel();
    try {
      llegadas = await _repositorio.llegadas(codigoParadero);
      _huboDatos = true;
      _fallosSeguidos = 0;
      sinConexion = false;
      error = null;
    } on SinConexion {
      // se conservan las llegadas anteriores
      _fallosSeguidos++;
      sinConexion = !_huboDatos || _fallosSeguidos >= Config.fallosParaAviso;
      if (!_pausado && !_cerrado) {
        _temporizadorReintento = Timer(_reintento, refrescar);
      }
    } on ErrorServicio catch (e) {
      error = e.mensaje;
    } finally {
      _consultando = false;
    }
    cargando = false;
    _notificar();
  }

  @override
  void dispose() {
    _cerrado = true;
    _temporizador?.cancel();
    _temporizadorReintento?.cancel();
    super.dispose();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }
}
