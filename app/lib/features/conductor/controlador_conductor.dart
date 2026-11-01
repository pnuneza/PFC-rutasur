/// Estado y lógica de la aplicación del conductor (CU-02, CU-08, CU-09, CU-10).
///
/// Decide la pantalla según lo guardado en el teléfono (P06 Figura 28): sin token
/// vigente, C-01; con token y sin sesión, C-02; con una sesión abierta, vuelve a C-03.
/// Durante la emisión toma una lectura cada 5 s, la guarda en la cola y envía la cola
/// cada 15 s; solo borra lo que el servidor confirmó (RF-011, RF-012).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../domain/conductor.dart';
import '../../domain/modelos.dart';
import '../../domain/repositorio.dart';

enum Etapa { cargando, ingreso, recorrido, permisos, transmision }

/// Indicador grande de C-03: verde, ámbar o rojo.
enum EstadoEmision { transmitiendo, sinConexion, sinGps }

class ControladorConductor extends ChangeNotifier {
  ControladorConductor({
    required ServicioConductor servicio,
    required AlmacenConductor almacen,
    required FuenteUbicacion gps,
    required String Function() nuevoId,
    DateTime Function()? reloj,
    this.usarTemporizadores = true,
  })  : _servicio = servicio,
        _almacen = almacen,
        _gps = gps,
        _nuevoId = nuevoId,
        _reloj = reloj ?? DateTime.now;

  final ServicioConductor _servicio;
  final AlmacenConductor _almacen;
  final FuenteUbicacion _gps;
  final String Function() _nuevoId;
  final DateTime Function() _reloj;

  /// En las pruebas se llama a capturar() y enviar() a mano.
  final bool usarTemporizadores;

  Etapa etapa = Etapa.cargando;
  AccesoConductor? acceso;
  SesionConductor? sesion;
  PermisosTelefono? permisos;

  /// Espera de una operación (indicador en los botones de C-01 y C-02).
  bool ocupado = false;

  /// Mensaje de error de C-01 (Tabla 47).
  String? errorIngreso;

  /// Aviso en C-02: por qué terminó una transmisión o por qué no pudo empezar.
  String? aviso;

  // --- C-03 ---
  EstadoEmision estado = EstadoEmision.transmitiendo;
  List<Lectura> cola = [];
  DateTime? ultimoEnvio;
  AcuseEnvio? ultimoAcuse;
  double? precisionGps;

  PosicionGps? _ultimaPosicion;
  DateTime? _ultimaPosicionEn;
  bool _sinRed = false;
  bool _enviando = false;
  bool _cerrado = false;
  Timer? _temporizadorCaptura;
  Timer? _temporizadorEnvio;

  String? get etiquetaUnidad => acceso?.etiquetaUnidad;
  int get pendientes => cola.length;

  // ------------------------------------------------------------------
  // Arranque
  // ------------------------------------------------------------------
  Future<void> iniciar() async {
    final guardado = await _almacen.leerAcceso();
    if (guardado == null || !guardado.vigenteEn(_reloj())) {
      await _almacen.guardarAcceso(null);
      _cambiar(Etapa.ingreso);
      return;
    }
    acceso = guardado;
    sesion = await _almacen.leerSesion();
    cola = await _almacen.leerCola();
    if (sesion == null) {
      _cambiar(Etapa.recorrido);
    } else {
      // El teléfono se reinició o se cerró la app a mitad del turno: se retoma
      await _arrancarEmisionSiHayPermisos();
    }
  }

  // ------------------------------------------------------------------
  // C-01 Inicio de sesión
  // ------------------------------------------------------------------
  Future<void> ingresar(String usuario, String contrasena) async {
    ocupado = true;
    errorIngreso = null;
    _notificar();
    try {
      final nuevo = await _servicio.iniciarSesion(usuario.trim(), contrasena);
      acceso = nuevo;
      await _almacen.guardarAcceso(nuevo);
      aviso = null;
      etapa = Etapa.recorrido;
    } on SinConexion {
      errorIngreso = 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
    } on ErrorServicio catch (e) {
      errorIngreso = mensajeDeIngreso(e);
    } finally {
      ocupado = false;
      _notificar();
    }
  }

  static String mensajeDeIngreso(ErrorServicio e) => switch (e.codigo) {
        'INVALID_CREDENTIALS' || 'FORBIDDEN' => 'Usuario o contraseña incorrectos. '
            'Tras 5 intentos fallidos la cuenta se bloquea 15 minutos.',
        'ACCOUNT_LOCKED' => 'Tu cuenta está bloqueada. Vuelve a intentarlo en '
            '${((e.reintentarEnS ?? 900) / 60).ceil()} minutos.',
        'RATE_LIMITED' => 'Demasiados intentos seguidos. Espera '
            '${e.reintentarEnS ?? 60} segundos e inténtalo de nuevo.',
        'VALIDATION_ERROR' => 'Revisa el usuario y la contraseña.',
        _ => 'Algo salió mal. Inténtalo de nuevo en unos segundos.',
      };

  /// «Salir» en C-02: borra el token y vuelve a C-01.
  Future<void> salir() async {
    await _detenerCaptura();
    acceso = null;
    await _almacen.guardarAcceso(null);
    _cambiar(Etapa.ingreso);
  }

  // ------------------------------------------------------------------
  // C-02 Declarar recorrido y C-04 Permisos
  // ------------------------------------------------------------------
  Future<void> revisarPermisos() async {
    permisos = await _gps.revisarPermisos();
    _notificar();
  }

  Future<void> pedirUbicacion() async {
    await _gps.pedirUbicacion();
    await revisarPermisos();
  }

  Future<void> pedirNotificaciones() async {
    await _gps.pedirNotificaciones();
    await revisarPermisos();
  }

  Future<void> pedirBateria() async {
    await _gps.pedirSinRestriccionDeBateria();
    await revisarPermisos();
  }

  Future<void> abrirAjustes() => _gps.abrirAjustes();

  /// «Empezar a transmitir»: verifica permisos, abre la sesión y arranca la emisión.
  Future<void> empezar(Ramal ramal, Sentido sentido) async {
    await revisarPermisos();
    if (!(permisos?.obligatoriosListos ?? false)) {
      _cambiar(Etapa.permisos);
      return;
    }
    ocupado = true;
    aviso = null;
    _notificar();
    try {
      final nueva = await _servicio.abrirSesion(acceso!.token, ramal, sentido);
      sesion = nueva;
      cola = []; // lo pendiente de un turno anterior ya no pertenece a esta sesión
      await _almacen.guardarSesion(nueva);
      await _almacen.guardarCola(cola);
      await _arrancarEmision();
    } on SinConexion {
      aviso = 'No hay conexión a internet. Para empezar a transmitir se necesita conexión; '
          'después, si se pierde la señal, las posiciones se guardan en el teléfono.';
    } on ErrorServicio catch (e) {
      await _atenderErrorDeServicio(e);
    } finally {
      ocupado = false;
      _notificar();
    }
  }

  /// «Continuar» en C-04: vuelve a C-02, o a C-03 si había una emisión que retomar.
  Future<void> continuarDesdePermisos() async {
    if (sesion != null) {
      await _arrancarEmisionSiHayPermisos();
    } else {
      _cambiar(Etapa.recorrido);
    }
  }

  // ------------------------------------------------------------------
  // C-03 Transmisión
  // ------------------------------------------------------------------
  Future<void> _arrancarEmisionSiHayPermisos() async {
    await revisarPermisos();
    if (permisos?.obligatoriosListos ?? false) {
      await _arrancarEmision();
    } else {
      _cambiar(Etapa.permisos);
    }
  }

  Future<void> _arrancarEmision() async {
    final s = sesion!;
    estado = EstadoEmision.transmitiendo;
    _sinRed = false;
    _ultimaPosicion = null;
    _ultimaPosicionEn = _reloj(); // se da un margen antes de declarar «Sin GPS»
    etapa = Etapa.transmision;
    _notificar();
    await _gps.iniciar(
      textoNotificacion: 'Unidad ${etiquetaUnidad ?? ''} · Va a ${s.destino}. Toca para abrir.',
      alRecibir: _alRecibirPosicion,
    );
    if (usarTemporizadores) {
      _temporizadorCaptura?.cancel();
      _temporizadorEnvio?.cancel();
      _temporizadorCaptura = Timer.periodic(Config.intervaloCaptura, (_) => capturar());
      _temporizadorEnvio = Timer.periodic(Config.intervaloEnvio, (_) => enviar());
    }
  }

  void _alRecibirPosicion(PosicionGps posicion) {
    _ultimaPosicion = posicion;
    _ultimaPosicionEn = _reloj();
    precisionGps = posicion.precisionM;
  }

  /// Toma la última posición del GPS como lectura y la guarda en la cola (cada 5 s).
  Future<void> capturar() async {
    if (sesion == null || _cerrado) return;
    final posicion = _ultimaPosicion;
    final desde = _ultimaPosicionEn;
    if (desde == null || _reloj().difference(desde) > Config.sinGpsDespuesDe) {
      _cambiarEstado(EstadoEmision.sinGps); // el GPS dejó de dar posiciones
      return;
    }
    if (posicion == null) return; // todavía esperando la primera posición
    final velocidad =
        posicion.velocidadMs == null ? null : (posicion.velocidadMs! * 3.6).clamp(0.0, 200.0);
    cola.add(Lectura(
      id: _nuevoId(),
      lat: posicion.lat,
      lon: posicion.lon,
      velocidadKmh: velocidad?.toDouble(),
      rumbo: posicion.rumbo == null ? null : posicion.rumbo!.round() % 360,
      precisionM: posicion.precisionM < 0 ? 0 : posicion.precisionM,
      capturada: _reloj().toUtc(),
    ));
    if (cola.length > Config.colaMaxima) {
      cola.removeRange(0, cola.length - Config.colaMaxima); // se pierde lo más antiguo
    }
    await _almacen.guardarCola(cola);
    _cambiarEstado(_sinRed ? EstadoEmision.sinConexion : EstadoEmision.transmitiendo);
  }

  /// Envía hasta 200 lecturas de la cola y borra solo las confirmadas (cada 15 s).
  Future<void> enviar() async {
    final s = sesion;
    final token = acceso?.token;
    if (s == null || token == null || cola.isEmpty || _enviando || _cerrado) return;
    _enviando = true;
    final lote = cola.take(Config.loteMaximo).toList();
    try {
      final acuse = await _servicio.enviarPosiciones(token, s.id, lote);
      final confirmados = acuse.confirmados.toSet();
      cola.removeWhere((l) => confirmados.contains(l.id));
      await _almacen.guardarCola(cola);
      ultimoAcuse = acuse;
      ultimoEnvio = _reloj();
      _sinRed = false;
      if (estado != EstadoEmision.sinGps) estado = EstadoEmision.transmitiendo;
    } on SinConexion {
      _sinRed = true; // la cola se conserva y se reenvía en el siguiente ciclo
      if (estado != EstadoEmision.sinGps) estado = EstadoEmision.sinConexion;
    } on ErrorServicio catch (e) {
      if (e.codigo == 'VALIDATION_ERROR') {
        // Un lote que el servidor nunca aceptará (por ejemplo, el reloj del teléfono
        // muy adelantado) no debe trabar la cola para siempre
        final rechazados = lote.map((l) => l.id).toSet();
        cola.removeWhere((l) => rechazados.contains(l.id));
        await _almacen.guardarCola(cola);
      } else {
        await _atenderErrorDeServicio(e);
      }
    } finally {
      _enviando = false;
      _notificar();
    }
  }

  /// «Terminar turno» en D-01: envía lo pendiente si puede y cierra la sesión.
  Future<void> detener() async {
    final s = sesion;
    final token = acceso?.token;
    ocupado = true;
    _notificar();
    await _detenerCaptura();
    if (s != null && token != null) {
      try {
        await enviar();
        await _servicio.cerrarSesion(token, s.id);
      } on SinConexion {
        // Sin red: el servidor la cerrará solo por inactividad (RN-010)
      } on ErrorServicio {
        // Ya estaba cerrada o la cuenta cambió: igual se termina en el teléfono
      }
    }
    await _terminarEnTelefono(aviso: 'Turno terminado. La unidad ya no se ve en el mapa.');
    ocupado = false;
    _notificar();
  }

  Future<void> _atenderErrorDeServicio(ErrorServicio e) async {
    switch (e.codigo) {
      case 'SESSION_NOT_ACTIVE':
        await _detenerCaptura();
        await _terminarEnTelefono(
          aviso: 'La transmisión se cerró porque la unidad estuvo 10 minutos sin moverse '
              'o se abrió otra sesión para la misma unidad. Vuelve a empezar para seguir.',
        );
      case 'TOKEN_MISSING_OR_EXPIRED':
        await _detenerCaptura();
        await _terminarEnTelefono();
        acceso = null;
        await _almacen.guardarAcceso(null);
        errorIngreso = 'Tu sesión venció. Vuelve a ingresar.';
        etapa = Etapa.ingreso;
      case 'UNIT_INACTIVE':
        aviso = 'Tu unidad no está habilitada. Comunícate con el administrador.';
      case 'FORBIDDEN' || 'NOT_FOUND':
        await _detenerCaptura();
        await _terminarEnTelefono(aviso: 'La sesión ya no existe. Vuelve a empezar.');
      case 'RATE_LIMITED':
        break; // se reintenta en el siguiente ciclo
      default:
        if (etapa != Etapa.transmision) {
          aviso = 'Algo salió mal. Inténtalo de nuevo en unos segundos.';
        }
    }
  }

  Future<void> _detenerCaptura() async {
    _temporizadorCaptura?.cancel();
    _temporizadorEnvio?.cancel();
    _temporizadorCaptura = null;
    _temporizadorEnvio = null;
    await _gps.detener();
  }

  Future<void> _terminarEnTelefono({String? aviso}) async {
    sesion = null;
    cola = [];
    ultimoEnvio = null;
    ultimoAcuse = null;
    await _almacen.guardarSesion(null);
    await _almacen.guardarCola(cola);
    this.aviso = aviso;
    etapa = acceso == null ? Etapa.ingreso : Etapa.recorrido;
  }

  // ------------------------------------------------------------------
  void _cambiar(Etapa nueva) {
    etapa = nueva;
    _notificar();
  }

  void _cambiarEstado(EstadoEmision nuevo) {
    if (estado == nuevo) return;
    estado = nuevo;
    _notificar();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _temporizadorCaptura?.cancel();
    _temporizadorEnvio?.cancel();
    super.dispose();
  }
}
