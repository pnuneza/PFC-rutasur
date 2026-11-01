/// Almacenamiento del teléfono para la app del conductor (paquete data).
///
/// - El token va al almacenamiento seguro del sistema (Keystore en Android), como
///   pide la ficha de seguridad (P05 Tabla 34).
/// - La sesión y la cola de posiciones van a las preferencias de la app: así una
///   emisión sobrevive a un reinicio del teléfono y lo pendiente se envía después.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/conductor.dart';

class AlmacenLocal implements AlmacenConductor {
  AlmacenLocal({FlutterSecureStorage? seguro}) : _seguro = seguro ?? const FlutterSecureStorage();

  static const _claveAcceso = 'rutasur.acceso';
  static const _claveSesion = 'rutasur.sesion';
  static const _claveCola = 'rutasur.cola';

  final FlutterSecureStorage _seguro;

  @override
  Future<AccesoConductor?> leerAcceso() async {
    final texto = await _seguro.read(key: _claveAcceso);
    if (texto == null) return null;
    try {
      return AccesoConductor.fromJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardarAcceso(AccesoConductor? acceso) async {
    if (acceso == null) {
      await _seguro.delete(key: _claveAcceso);
    } else {
      await _seguro.write(key: _claveAcceso, value: jsonEncode(acceso.toJson()));
    }
  }

  @override
  Future<SesionConductor?> leerSesion() async {
    final texto = (await SharedPreferences.getInstance()).getString(_claveSesion);
    if (texto == null) return null;
    try {
      return SesionConductor.fromJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardarSesion(SesionConductor? sesion) async {
    final prefs = await SharedPreferences.getInstance();
    if (sesion == null) {
      await prefs.remove(_claveSesion);
    } else {
      await prefs.setString(_claveSesion, jsonEncode(sesion.toJson()));
    }
  }

  @override
  Future<List<Lectura>> leerCola() async {
    final texto = (await SharedPreferences.getInstance()).getString(_claveCola);
    if (texto == null) return [];
    try {
      return [
        for (final l in jsonDecode(texto) as List<dynamic>)
          Lectura.fromJson(l as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> guardarCola(List<Lectura> cola) async {
    await (await SharedPreferences.getInstance())
        .setString(_claveCola, jsonEncode([for (final l in cola) l.toJson()]));
  }
}
