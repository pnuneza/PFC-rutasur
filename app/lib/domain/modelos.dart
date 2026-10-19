/// Modelos del dominio que muestra la aplicación del pasajero
/// (paquete domain, Tabla 32 de P05). No dependen de Flutter.
library;

import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Enumeraciones
// ---------------------------------------------------------------------------

enum Ramal {
  mollebaya('MOLLEBAYA', 'Mollebaya'),
  cerrillo('CERRILLO', 'Cerrillo');

  const Ramal(this.codigoApi, this.nombre);

  final String codigoApi;
  final String nombre;

  static Ramal desdeApi(String codigo) => Ramal.values.firstWhere(
        (r) => r.codigoApi == codigo,
        orElse: () => throw FormatException('Ramal desconocido: $codigo'),
      );
}

enum Sentido {
  ida('IDA', 'Hacia el Centro'),
  vuelta('VUELTA', 'Hacia el ramal');

  const Sentido(this.codigoApi, this.descripcion);

  final String codigoApi;
  final String descripcion;

  static Sentido desdeApi(String codigo) => Sentido.values.firstWhere(
        (s) => s.codigoApi == codigo,
        orElse: () => throw FormatException('Sentido desconocido: $codigo'),
      );
}

/// Estados de la frescura del dato (P05, Figura 26; regla RN-005).
enum Frescura {
  vigente('Vigente'),
  demorado('Demorado'),
  noConfiable('No confiable');

  const Frescura(this.etiqueta);

  final String etiqueta;

  /// Vigente hasta 30 s, demorado hasta 90 s y no confiable después.
  static Frescura desdeAntiguedad(int segundos) {
    if (segundos <= 30) return Frescura.vigente;
    if (segundos <= 90) return Frescura.demorado;
    return Frescura.noConfiable;
  }
}

// ---------------------------------------------------------------------------
// Ruta: línea, variantes y paraderos (RF-001)
// ---------------------------------------------------------------------------

class ParaderoDeVariante {
  const ParaderoDeVariante({
    required this.codigo,
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.orden,
    required this.distanciaDesdeInicioM,
    required this.tramoComun,
  });

  factory ParaderoDeVariante.fromJson(Map<String, dynamic> json) => ParaderoDeVariante(
        codigo: json['code'] as String,
        nombre: json['name'] as String,
        referencia: json['reference'] as String?,
        ubicacion: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
        orden: json['order'] as int,
        distanciaDesdeInicioM: (json['distance_from_start_m'] as num).toDouble(),
        tramoComun: json['shared_trunk'] as bool,
      );

  final String codigo;
  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final int orden;
  final double distanciaDesdeInicioM;
  final bool tramoComun;
}

class Variante {
  const Variante({
    required this.ramal,
    required this.sentido,
    required this.destino,
    required this.longitudM,
    required this.trazado,
    required this.paraderos,
  });

  factory Variante.fromJson(Map<String, dynamic> json) => Variante(
        ramal: Ramal.desdeApi(json['branch'] as String),
        sentido: Sentido.desdeApi(json['direction'] as String),
        destino: json['destination'] as String,
        longitudM: (json['length_m'] as num).toDouble(),
        trazado: [
          for (final par in json['shape'] as List<dynamic>)
            LatLng(((par as List<dynamic>)[0] as num).toDouble(), (par[1] as num).toDouble()),
        ],
        paraderos: [
          for (final p in json['stops'] as List<dynamic>)
            ParaderoDeVariante.fromJson(p as Map<String, dynamic>),
        ],
      );

  final Ramal ramal;
  final Sentido sentido;
  final String destino;
  final double longitudM;
  final List<LatLng> trazado;
  final List<ParaderoDeVariante> paraderos;
}

class Linea {
  const Linea({
    required this.codigo,
    required this.nombre,
    required this.horaInicio,
    required this.horaFin,
    required this.variantes,
  });

  factory Linea.fromJson(Map<String, dynamic> json) => Linea(
        codigo: json['code'] as String,
        nombre: json['name'] as String,
        horaInicio: json['service_start'] as String,
        horaFin: json['service_end'] as String,
        variantes: [
          for (final v in json['variants'] as List<dynamic>)
            Variante.fromJson(v as Map<String, dynamic>),
        ],
      );

  final String codigo;
  final String nombre;
  final String horaInicio;
  final String horaFin;
  final List<Variante> variantes;

  /// Horario referencial del servicio (RN-009), por ejemplo «05:00 a 21:00».
  String get horario => '$horaInicio a $horaFin';
}

/// Paradero tal como se dibuja en el mapa: uno solo aunque pertenezca a
/// varias variantes, con todos los ramales que pasan por él.
class ParaderoEnMapa {
  const ParaderoEnMapa({
    required this.codigo,
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.tramoComun,
    required this.ramales,
  });

  final String codigo;
  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final bool tramoComun;
  final Set<Ramal> ramales;
}

/// Une los paraderos de todas las variantes en una lista sin repetidos.
List<ParaderoEnMapa> paraderosUnicos(Linea linea) {
  final porCodigo = <String, ParaderoEnMapa>{};
  for (final variante in linea.variantes) {
    for (final p in variante.paraderos) {
      final previo = porCodigo[p.codigo];
      porCodigo[p.codigo] = ParaderoEnMapa(
        codigo: p.codigo,
        nombre: p.nombre,
        referencia: p.referencia,
        ubicacion: p.ubicacion,
        tramoComun: p.tramoComun,
        ramales: {...?previo?.ramales, variante.ramal},
      );
    }
  }
  return porCodigo.values.toList();
}

// ---------------------------------------------------------------------------
// Unidades en servicio (RF-002, RF-003, RF-008)
// ---------------------------------------------------------------------------

class UnidadActiva {
  const UnidadActiva({
    required this.etiqueta,
    required this.ramal,
    required this.sentido,
    required this.destino,
    required this.ubicacion,
    required this.rumbo,
    required this.antiguedadS,
  });

  factory UnidadActiva.fromJson(Map<String, dynamic> json) => UnidadActiva(
        etiqueta: json['vehicle_label'] as String,
        ramal: Ramal.desdeApi(json['branch'] as String),
        sentido: Sentido.desdeApi(json['direction'] as String),
        destino: json['destination'] as String,
        ubicacion: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
        rumbo: json['heading'] as int?,
        antiguedadS: json['position_age_s'] as int,
      );

  final String etiqueta;
  final Ramal ramal;
  final Sentido sentido;
  final String destino;
  final LatLng ubicacion;

  /// Dirección de avance en grados (0 = norte). Puede faltar.
  final int? rumbo;
  final int antiguedadS;

  Frescura get frescura => Frescura.desdeAntiguedad(antiguedadS);
}

// ---------------------------------------------------------------------------
// Llegadas a un paradero (RF-004)
// ---------------------------------------------------------------------------

class Llegada {
  const Llegada({
    required this.etiqueta,
    required this.ramal,
    required this.destino,
    required this.etaS,
    required this.distanciaM,
    required this.antiguedadS,
  });

  factory Llegada.fromJson(Map<String, dynamic> json) => Llegada(
        etiqueta: json['vehicle_label'] as String,
        ramal: Ramal.desdeApi(json['branch'] as String),
        destino: json['destination'] as String,
        etaS: json['eta_seconds'] as int,
        distanciaM: json['distance_m'] as int,
        antiguedadS: json['position_age_s'] as int,
      );

  final String etiqueta;
  final Ramal ramal;
  final String destino;
  final int etaS;
  final int distanciaM;
  final int antiguedadS;

  Frescura get frescura => Frescura.desdeAntiguedad(antiguedadS);
}
