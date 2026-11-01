/// Preferencias del pasajero guardadas solo en el teléfono (RF-007, P-00).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pasajero.dart';

class PreferenciasLocales implements PreferenciasPasajero {
  static const _claveBienvenida = 'pasajero.bienvenida_vista';
  static const _claveFavoritos = 'pasajero.favoritos';

  @override
  Future<bool> bienvenidaVista() async =>
      (await SharedPreferences.getInstance()).getBool(_claveBienvenida) ?? false;

  @override
  Future<void> marcarBienvenidaVista() async =>
      (await SharedPreferences.getInstance()).setBool(_claveBienvenida, true);

  @override
  Future<List<String>> favoritos() async =>
      (await SharedPreferences.getInstance()).getStringList(_claveFavoritos) ?? [];

  @override
  Future<void> guardarFavoritos(List<String> codigos) async =>
      (await SharedPreferences.getInstance()).setStringList(_claveFavoritos, codigos);
}
