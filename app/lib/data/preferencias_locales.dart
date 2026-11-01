/// Preferencias del pasajero guardadas solo en el teléfono (RF-007, P-00).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/modelos.dart';
import '../domain/pasajero.dart';

class PreferenciasLocales implements PreferenciasPasajero {
  static const _claveBienvenida = 'pasajero.bienvenida_vista';
  static const _claveFavoritos = 'pasajero.favoritos';
  static const _claveSentido = 'pasajero.sentido';

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

  @override
  Future<Sentido?> sentidoElegido() async {
    final codigo = (await SharedPreferences.getInstance()).getString(_claveSentido);
    try {
      return codigo == null ? null : Sentido.desdeApi(codigo);
    } on FormatException {
      return null; // valor viejo o dañado: se muestran ambos sentidos
    }
  }

  @override
  Future<void> guardarSentido(Sentido? sentido) async {
    final p = await SharedPreferences.getInstance();
    if (sentido == null) {
      await p.remove(_claveSentido);
    } else {
      await p.setString(_claveSentido, sentido.codigoApi);
    }
  }
}
