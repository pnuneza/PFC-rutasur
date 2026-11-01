/// Estado de P-02 Buscar paradero (RF-005).
///
/// Busca desde 2 letras y espera a que el pasajero deje de escribir (300 ms) para no
/// consultar al servidor con cada tecla. La búsqueda no distingue mayúsculas ni tildes
/// (lo resuelve el servidor).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/pasajero.dart';
import '../../domain/repositorio.dart';

class ControladorBusqueda extends ChangeNotifier {
  ControladorBusqueda(this._repositorio, {this.espera = const Duration(milliseconds: 300)});

  final RepositorioRutaSur _repositorio;
  final Duration espera;
  Timer? _temporizador;
  int _consulta = 0; // descarta respuestas de consultas viejas
  bool _cerrado = false;

  String texto = '';
  bool buscando = false;
  List<ParaderoEncontrado> resultados = const [];
  String? error;

  /// Hay suficientes letras para buscar.
  bool get activa => texto.trim().length >= 2;

  void escribir(String nuevo) {
    texto = nuevo;
    _temporizador?.cancel();
    error = null;
    if (!activa) {
      resultados = const [];
      buscando = false;
      _notificar();
      return;
    }
    buscando = true;
    _notificar();
    _temporizador = Timer(espera, buscar);
  }

  Future<void> buscar() async {
    if (!activa) return;
    final numero = ++_consulta;
    final buscado = texto.trim();
    try {
      final encontrados = await _repositorio.buscarParaderos(buscado);
      if (numero != _consulta) return;
      resultados = encontrados;
      error = null;
    } on SinConexion {
      if (numero != _consulta) return;
      error = 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
    } on ErrorServicio catch (e) {
      if (numero != _consulta) return;
      error = e.codigo == 'VALIDATION_ERROR'
          ? 'Escribe solo letras y números.'
          : 'Algo salió mal. Inténtalo de nuevo en unos segundos.';
    }
    buscando = false;
    _notificar();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _temporizador?.cancel();
    super.dispose();
  }
}
