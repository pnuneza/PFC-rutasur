/// Modelos y contratos de la aplicación del conductor (paquete domain, Tabla 32 de P05).
///
/// Como en la app del pasajero, la lógica depende de estas interfaces y no de la red,
/// del GPS ni del almacenamiento del teléfono: así se prueba sin dispositivo.
library;

import 'dart:convert';

import 'modelos.dart';

// ---------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------

/// Token entregado por POST /auth/login (P06 Tabla 52).
class AccesoConductor {
  const AccesoConductor({required this.token, required this.etiquetaUnidad, required this.vence});

  /// Lee el vencimiento del propio token (reclamo «exp» del JWT) para saber, sin red,
  /// si sigue vigente al abrir la aplicación.
  factory AccesoConductor.desdeToken(String token, String etiquetaUnidad) {
    return AccesoConductor(token: token, etiquetaUnidad: etiquetaUnidad, vence: venceDelToken(token));
  }

  factory AccesoConductor.fromJson(Map<String, dynamic> json) => AccesoConductor(
        token: json['token'] as String,
        etiquetaUnidad: json['unidad'] as String,
        vence: DateTime.parse(json['vence'] as String),
      );

  final String token;
  final String etiquetaUnidad;
  final DateTime vence;

  bool vigenteEn(DateTime ahora) => ahora.isBefore(vence.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() =>
      {'token': token, 'unidad': etiquetaUnidad, 'vence': vence.toUtc().toIso8601String()};
}

/// Fecha de vencimiento escrita dentro del token. Si no se puede leer, se da por vencido.
DateTime venceDelToken(String token) {
  try {
    final partes = token.split('.');
    final cuerpo = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final exp = (jsonDecode(cuerpo) as Map<String, dynamic>)['exp'] as int;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

/// Sesión de emisión abierta (P06 Tabla 53).
class SesionConductor {
  const SesionConductor({
    required this.id,
    required this.ramal,
    required this.sentido,
    required this.destino,
    required this.inicio,
  });

  factory SesionConductor.fromJson(Map<String, dynamic> json) => SesionConductor(
        id: json['id'] as String,
        ramal: Ramal.desdeApi(json['ramal'] as String),
        sentido: Sentido.desdeApi(json['sentido'] as String),
        destino: json['destino'] as String,
        inicio: DateTime.parse(json['inicio'] as String),
      );

  final String id;
  final Ramal ramal;
  final Sentido sentido;
  final String destino;
  final DateTime inicio;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ramal': ramal.codigoApi,
        'sentido': sentido.codigoApi,
        'destino': destino,
        'inicio': inicio.toUtc().toIso8601String(),
      };
}

/// Una lectura del GPS tal como se guarda en la cola y se envía (P06 Tabla 54).
class Lectura {
  const Lectura({
    required this.id,
    required this.lat,
    required this.lon,
    required this.velocidadKmh,
    required this.rumbo,
    required this.precisionM,
    required this.capturada,
  });

  factory Lectura.fromJson(Map<String, dynamic> json) => Lectura(
        id: json['id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        velocidadKmh: (json['speed_kmh'] as num?)?.toDouble(),
        rumbo: json['heading'] as int?,
        precisionM: (json['accuracy_m'] as num).toDouble(),
        capturada: DateTime.parse(json['captured_at'] as String),
      );

  /// El identificador lo genera el teléfono: reenviar no duplica (idempotencia).
  final String id;
  final double lat;
  final double lon;
  final double? velocidadKmh;
  final int? rumbo;
  final double precisionM;
  final DateTime capturada;

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lon': lon,
        if (velocidadKmh != null) 'speed_kmh': velocidadKmh,
        if (rumbo != null) 'heading': rumbo,
        'accuracy_m': precisionM,
        'captured_at': capturada.toUtc().toIso8601String(),
      };
}

/// Lo que devuelve el GPS del teléfono, antes de convertirse en una lectura.
class PosicionGps {
  const PosicionGps({
    required this.lat,
    required this.lon,
    required this.precisionM,
    this.velocidadMs,
    this.rumbo,
  });

  final double lat;
  final double lon;
  final double precisionM;
  final double? velocidadMs;
  final double? rumbo;
}

/// Acuse del lote: el teléfono borra de su cola exactamente `confirmados`.
class AcuseEnvio {
  const AcuseEnvio({
    required this.confirmados,
    required this.publicadas,
    required this.descartadas,
    required this.duplicadas,
  });

  factory AcuseEnvio.fromJson(Map<String, dynamic> json) => AcuseEnvio(
        confirmados: [for (final id in json['confirmed'] as List<dynamic>) id as String],
        publicadas: json['published'] as int,
        descartadas: json['discarded'] as int,
        duplicadas: json['duplicates'] as int,
      );

  final List<String> confirmados;
  final int publicadas;
  final int descartadas;
  final int duplicadas;
}

enum EstadoPermiso { concedido, denegado, denegadoSiempre, noAplica }

extension EstadoPermisoTexto on EstadoPermiso {
  bool get listo => this == EstadoPermiso.concedido || this == EstadoPermiso.noAplica;
}

/// Permisos que la emisión necesita (pantalla C-04).
class PermisosTelefono {
  const PermisosTelefono({
    required this.ubicacion,
    required this.notificaciones,
    required this.bateria,
  });

  /// Obligatorio: sin ubicación no se transmite (CU-02, flujo 4a).
  final EstadoPermiso ubicacion;

  /// Obligatorio desde Android 13: la notificación permanente N-01.
  final EstadoPermiso notificaciones;

  /// Recomendado: evita que el sistema detenga la emisión (CU-02, flujo 7a).
  final EstadoPermiso bateria;

  bool get obligatoriosListos => ubicacion.listo && notificaciones.listo;
}

// ---------------------------------------------------------------------------
// Contratos
// ---------------------------------------------------------------------------

/// Operaciones del conductor en el servicio (P06 Tablas 52 a 54).
abstract interface class ServicioConductor {
  Future<AccesoConductor> iniciarSesion(String usuario, String contrasena);

  Future<SesionConductor> abrirSesion(String token, Ramal ramal, Sentido sentido);

  Future<AcuseEnvio> enviarPosiciones(String token, String sesionId, List<Lectura> lote);

  Future<void> cerrarSesion(String token, String sesionId);
}

/// Lo que se guarda en el teléfono: el token en el almacenamiento seguro y la sesión y
/// la cola de posiciones para sobrevivir a un reinicio a mitad del turno (Figura 28).
abstract interface class AlmacenConductor {
  Future<AccesoConductor?> leerAcceso();
  Future<void> guardarAcceso(AccesoConductor? acceso);

  Future<SesionConductor?> leerSesion();
  Future<void> guardarSesion(SesionConductor? sesion);

  Future<List<Lectura>> leerCola();
  Future<void> guardarCola(List<Lectura> cola);
}

/// GPS, permisos y servicio en primer plano del teléfono (RF-011).
abstract interface class FuenteUbicacion {
  Future<PermisosTelefono> revisarPermisos();
  Future<void> pedirUbicacion();
  Future<void> pedirNotificaciones();
  Future<void> pedirSinRestriccionDeBateria();
  Future<void> abrirAjustes();

  /// Empieza a recibir posiciones con la notificación permanente N-01.
  Future<void> iniciar({required String textoNotificacion, required void Function(PosicionGps) alRecibir});

  Future<void> detener();
}
