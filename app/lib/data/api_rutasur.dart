/// Implementación del repositorio sobre la API REST de RutaSur (paquete data).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../domain/modelos.dart';
import '../domain/repositorio.dart';

class ApiRutaSur implements RepositorioRutaSur {
  ApiRutaSur({http.Client? cliente, String? urlBase})
      : _cliente = cliente ?? http.Client(),
        _urlBase = urlBase ?? Config.urlApi;

  final http.Client _cliente;
  final String _urlBase;

  @override
  Future<Linea> obtenerLinea() async =>
      Linea.fromJson(await _obtener('/routes/lb') as Map<String, dynamic>);

  @override
  Future<List<UnidadActiva>> unidadesActivas() async => [
        for (final u in await _obtener('/vehicles') as List<dynamic>)
          UnidadActiva.fromJson(u as Map<String, dynamic>),
      ];

  @override
  Future<List<Llegada>> llegadas(String codigoParadero) async => [
        for (final l in await _obtener('/stops/${Uri.encodeComponent(codigoParadero)}/arrivals')
            as List<dynamic>)
          Llegada.fromJson(l as Map<String, dynamic>),
      ];

  /// Hace la petición y devuelve el contenido de `data` (sobre estándar de P05, Tabla 38).
  Future<Object?> _obtener(String ruta) async {
    final http.Response respuesta;
    try {
      respuesta = await _cliente
          .get(Uri.parse('$_urlBase/api/v1$ruta'))
          .timeout(Config.tiempoEspera);
    } on TimeoutException {
      throw const SinConexion();
    } on http.ClientException {
      throw const SinConexion();
    }

    final cuerpo = _decodificar(respuesta);
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 && cuerpo is Map) {
      return cuerpo['data'];
    }

    final error = cuerpo is Map && cuerpo['error'] is Map ? cuerpo['error'] as Map : const {};
    throw ErrorServicio(
      estado: respuesta.statusCode,
      codigo: error['code'] as String? ?? 'HTTP_ERROR',
      mensaje: error['message'] as String? ?? 'El servicio respondió con un error.',
    );
  }

  Object? _decodificar(http.Response respuesta) {
    try {
      return jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      return null; // por ejemplo, una página de error HTML de un proxy
    }
  }
}
