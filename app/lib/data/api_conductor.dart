/// Operaciones del conductor sobre la API REST de RutaSur (paquete data).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../domain/conductor.dart';
import '../domain/modelos.dart';
import '../domain/repositorio.dart';

class ApiConductor implements ServicioConductor {
  ApiConductor({http.Client? cliente, String? urlBase})
      : _cliente = cliente ?? http.Client(),
        _urlBase = urlBase ?? Config.urlApi;

  final http.Client _cliente;
  final String _urlBase;

  @override
  Future<AccesoConductor> iniciarSesion(String usuario, String contrasena) async {
    final datos = await _enviar('/auth/login', null, {'username': usuario, 'password': contrasena})
        as Map<String, dynamic>;
    if (datos['role'] != 'CONDUCTOR') {
      // Una cuenta del panel no puede transmitir: mismo trato que una clave incorrecta
      throw const ErrorServicio(
        estado: 403,
        codigo: 'FORBIDDEN',
        mensaje: 'Esta cuenta no es de conductor.',
      );
    }
    return AccesoConductor.desdeToken(
      datos['access_token'] as String,
      datos['vehicle_label'] as String,
    );
  }

  @override
  Future<SesionConductor> abrirSesion(String token, Ramal ramal, Sentido sentido) async {
    final datos = await _enviar(
      '/sessions',
      token,
      {'branch': ramal.codigoApi, 'direction': sentido.codigoApi},
    ) as Map<String, dynamic>;
    return SesionConductor(
      id: datos['session_id'] as String,
      ramal: ramal,
      sentido: sentido,
      destino: datos['destination'] as String,
      inicio: DateTime.parse(datos['started_at'] as String),
    );
  }

  @override
  Future<AcuseEnvio> enviarPosiciones(String token, String sesionId, List<Lectura> lote) async {
    final datos = await _enviar(
      '/sessions/${Uri.encodeComponent(sesionId)}/positions',
      token,
      {'positions': [for (final l in lote) l.toJson()]},
    );
    return AcuseEnvio.fromJson(datos as Map<String, dynamic>);
  }

  @override
  Future<void> cerrarSesion(String token, String sesionId) async {
    await _enviar('/sessions/${Uri.encodeComponent(sesionId)}/close', token, null);
  }

  /// POST con JSON; devuelve `data` o lanza SinConexion / ErrorServicio (Tabla 55).
  Future<Object?> _enviar(String ruta, String? token, Object? cuerpo) async {
    final http.Response respuesta;
    try {
      respuesta = await _cliente
          .post(
            Uri.parse('$_urlBase/api/v1$ruta'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: cuerpo == null ? null : jsonEncode(cuerpo),
          )
          // El servicio gratuito tarda ~1 min en despertar si estaba apagado
          .timeout(Config.tiempoEsperaConductor);
    } on TimeoutException {
      throw const SinConexion();
    } on http.ClientException {
      throw const SinConexion();
    }

    Object? json;
    try {
      json = jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 && json is Map) {
      return json['data'];
    }
    final error = json is Map && json['error'] is Map ? json['error'] as Map : const {};
    final meta = json is Map && json['meta'] is Map ? json['meta'] as Map : const {};
    throw ErrorServicio(
      estado: respuesta.statusCode,
      codigo: error['code'] as String? ?? 'HTTP_ERROR',
      mensaje: error['message'] as String? ?? 'El servicio respondió con un error.',
      reintentarEnS: meta['retry_after_s'] as int?,
    );
  }
}
