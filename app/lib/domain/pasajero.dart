/// Modelos y contratos propios de la app del pasajero (paquete domain).
///
/// La ubicación del pasajero y sus favoritos se usan y se guardan SOLO en el teléfono:
/// nunca viajan al servidor (RF-006, RF-007, RNF-15).
library;

import 'package:latlong2/latlong.dart';

import 'geometria.dart';
import 'modelos.dart';

/// Resultado de GET /stops?q= (RF-005).
class ParaderoEncontrado {
  const ParaderoEncontrado({
    required this.codigo,
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.ramales,
  });

  factory ParaderoEncontrado.fromJson(Map<String, dynamic> json) => ParaderoEncontrado(
        codigo: json['code'] as String,
        nombre: json['name'] as String,
        referencia: json['reference'] as String?,
        ubicacion: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
        ramales: {for (final r in json['branches'] as List<dynamic>) Ramal.desdeApi(r as String)},
      );

  final String codigo;
  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final Set<Ramal> ramales;

  ParaderoEnMapa comoParaderoEnMapa() => ParaderoEnMapa(
        codigo: codigo,
        nombre: nombre,
        referencia: referencia,
        ubicacion: ubicacion,
        tramoComun: ramales.length > 1,
        ramales: ramales,
      );
}

/// Paradero propuesto en P-01 (RF-006).
class ParaderoCercano {
  const ParaderoCercano({required this.paradero, required this.distanciaM});

  final ParaderoEnMapa paradero;
  final double distanciaM;
}

/// El paradero más cercano a la posición del pasajero, calculado en el teléfono.
ParaderoCercano? paraderoMasCercano(List<ParaderoEnMapa> paraderos, LatLng posicion) {
  ParaderoCercano? mejor;
  for (final p in paraderos) {
    final d = distanciaM(posicion, p.ubicacion);
    if (mejor == null || d < mejor.distanciaM) {
      mejor = ParaderoCercano(paradero: p, distanciaM: d);
    }
  }
  return mejor;
}

/// Máximo de favoritos (P06 Tabla 44, P-01 #7).
const int maximoFavoritos = 10;

/// Preferencias guardadas en el teléfono: bienvenida vista y favoritos (por código).
abstract interface class PreferenciasPasajero {
  Future<bool> bienvenidaVista();
  Future<void> marcarBienvenidaVista();
  Future<List<String>> favoritos();
  Future<void> guardarFavoritos(List<String> codigos);

  /// Sentido elegido en el mapa: bajada, subida o ambos (null). Se recuerda (0.6.1).
  Future<Sentido?> sentidoElegido();
  Future<void> guardarSentido(Sentido? sentido);
}

/// Ubicación del pasajero, solo mientras usa la app (no en segundo plano).
abstract interface class UbicacionPasajero {
  Future<bool> permisoConcedido();

  /// Pide el permiso del sistema. Devuelve si quedó concedido.
  Future<bool> pedirPermiso();

  /// Posición actual, o null si no se pudo obtener (GPS apagado, sin señal).
  Future<LatLng?> posicionActual();
}
