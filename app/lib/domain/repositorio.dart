/// Contrato de acceso a los datos de RutaSur (paquete domain, Tabla 32 de P05).
///
/// Las pantallas dependen de esta interfaz y no de la implementación HTTP; así
/// pueden probarse con un repositorio falso, sin servidor ni internet.
library;

import 'modelos.dart';
import 'pasajero.dart';

abstract interface class RepositorioRutaSur {
  /// Línea LB con sus variantes, trazados y paraderos (GET /routes/lb).
  Future<Linea> obtenerLinea();

  /// Unidades con sesión abierta y su última posición (GET /vehicles).
  Future<List<UnidadActiva>> unidadesActivas();

  /// Próximas llegadas a un paradero, ordenadas por ETA (GET /stops/{codigo}/arrivals).
  Future<List<Llegada>> llegadas(String codigoParadero);

  /// Hasta 20 paraderos cuyo nombre contiene el texto, sin mayúsculas ni tildes (GET /stops?q=).
  Future<List<ParaderoEncontrado>> buscarParaderos(String texto);
}

/// El teléfono no pudo comunicarse con el servicio.
class SinConexion implements Exception {
  const SinConexion();

  @override
  String toString() => 'SinConexion';
}

/// El servicio respondió con un error (códigos de la Tabla 55 de P06).
class ErrorServicio implements Exception {
  const ErrorServicio({
    required this.estado,
    required this.codigo,
    required this.mensaje,
    this.reintentarEnS,
  });

  final int estado;
  final String codigo;
  final String mensaje;

  /// Segundos de espera de ACCOUNT_LOCKED y RATE_LIMITED (meta.retry_after_s).
  final int? reintentarEnS;

  @override
  String toString() => 'ErrorServicio($estado $codigo: $mensaje)';
}
