import 'dart:convert';

import 'package:rutasur/domain/conductor.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/conductor/controlador_conductor.dart';

/// Token con el vencimiento indicado (solo importa el reclamo «exp»).
String tokenQueVence(DateTime vence) {
  String parte(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${parte({'alg': 'HS256'})}.${parte({'exp': vence.millisecondsSinceEpoch ~/ 1000})}.firma';
}

final ahoraFijo = DateTime.utc(2026, 11, 2, 14);

AccesoConductor accesoVigente() =>
    AccesoConductor.desdeToken(tokenQueVence(ahoraFijo.add(const Duration(hours: 12))), '07');

class ServicioFalso implements ServicioConductor {
  Object? falloIngreso;
  Object? falloApertura;
  Object? falloEnvio;
  Object? falloCierre;

  /// Si se asigna, el servidor confirma solo estos identificadores.
  Set<String>? confirmarSolo;

  final List<List<Lectura>> lotes = [];
  final List<String> cerradas = [];
  int sesionesAbiertas = 0;

  @override
  Future<AccesoConductor> iniciarSesion(String usuario, String contrasena) async {
    if (falloIngreso != null) throw falloIngreso!;
    return accesoVigente();
  }

  @override
  Future<SesionConductor> abrirSesion(String token, Ramal ramal, Sentido sentido) async {
    if (falloApertura != null) throw falloApertura!;
    sesionesAbiertas++;
    return SesionConductor(
      id: 'sesion-$sesionesAbiertas',
      ramal: ramal,
      sentido: sentido,
      destino: sentido == Sentido.ida ? 'Centro (2 de Mayo)' : ramal.nombre,
      inicio: ahoraFijo,
    );
  }

  @override
  Future<AcuseEnvio> enviarPosiciones(String token, String sesionId, List<Lectura> lote) async {
    if (falloEnvio != null) throw falloEnvio!;
    lotes.add(List.of(lote));
    final ids = [for (final l in lote) if (confirmarSolo == null || confirmarSolo!.contains(l.id)) l.id];
    return AcuseEnvio(confirmados: ids, publicadas: ids.length, descartadas: 0, duplicadas: 0);
  }

  @override
  Future<void> cerrarSesion(String token, String sesionId) async {
    if (falloCierre != null) throw falloCierre!;
    cerradas.add(sesionId);
  }
}

class AlmacenEnMemoria implements AlmacenConductor {
  AccesoConductor? acceso;
  SesionConductor? sesion;
  List<Lectura> cola = [];

  @override
  Future<AccesoConductor?> leerAcceso() async => acceso;
  @override
  Future<void> guardarAcceso(AccesoConductor? a) async => acceso = a;
  @override
  Future<SesionConductor?> leerSesion() async => sesion;
  @override
  Future<void> guardarSesion(SesionConductor? s) async => sesion = s;
  @override
  Future<List<Lectura>> leerCola() async => List.of(cola);
  @override
  Future<void> guardarCola(List<Lectura> c) async => cola = List.of(c);
}

class GpsFalso implements FuenteUbicacion {
  PermisosTelefono permisos = const PermisosTelefono(
    ubicacion: EstadoPermiso.concedido,
    notificaciones: EstadoPermiso.concedido,
    bateria: EstadoPermiso.concedido,
  );
  void Function(PosicionGps)? _alRecibir;
  bool activo = false;
  String? textoNotificacion;

  void emitir({double lat = -16.47, double lon = -71.49, double precision = 8}) =>
      _alRecibir?.call(PosicionGps(lat: lat, lon: lon, precisionM: precision, velocidadMs: 10, rumbo: 359.6));

  @override
  Future<PermisosTelefono> revisarPermisos() async => permisos;
  @override
  Future<void> pedirUbicacion() async {}
  @override
  Future<void> pedirNotificaciones() async {}
  @override
  Future<void> pedirSinRestriccionDeBateria() async {}
  @override
  Future<void> abrirAjustes() async {}

  @override
  Future<void> iniciar({required String textoNotificacion, required void Function(PosicionGps) alRecibir}) async {
    activo = true;
    this.textoNotificacion = textoNotificacion;
    _alRecibir = alRecibir;
  }

  @override
  Future<void> detener() async {
    activo = false;
    _alRecibir = null;
  }
}

/// Reloj que la prueba hace avanzar.
class Reloj {
  DateTime ahora = ahoraFijo;
  DateTime call() => ahora;
  void avanzar(Duration d) => ahora = ahora.add(d);
}

class Escenario {
  Escenario() {
    var n = 0;
    controlador = ControladorConductor(
      servicio: servicio,
      almacen: almacen,
      gps: gps,
      nuevoId: () => 'pos-${++n}',
      reloj: reloj.call,
      usarTemporizadores: false,
    );
  }

  final servicio = ServicioFalso();
  final almacen = AlmacenEnMemoria();
  final gps = GpsFalso();
  final reloj = Reloj();
  late final ControladorConductor controlador;

  /// Deja la app transmitiendo con la sesión abierta.
  Future<void> transmitiendo() async {
    almacen.acceso = accesoVigente();
    await controlador.iniciar();
    await controlador.empezar(Ramal.mollebaya, Sentido.ida);
  }
}
