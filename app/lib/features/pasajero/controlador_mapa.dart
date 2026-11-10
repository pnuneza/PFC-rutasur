/// Estado de la pantalla del mapa (P-01).
///
/// Separa la lógica de la interfaz: el widget solo dibuja lo que este
/// controlador expone, y el controlador puede probarse sin Flutter ni red.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:latlong2/latlong.dart';

import '../../core/config.dart';
import '../../domain/modelos.dart';
import '../../domain/pasajero.dart';
import '../../domain/repositorio.dart';

class ControladorMapa extends ChangeNotifier {
  ControladorMapa(
    this._repositorio, {
    DateTime Function()? reloj,
    Duration intervalo = Config.intervaloConsulta,
    Duration reintento = Config.reintentoConsulta,
    PreferenciasPasajero? preferencias,
    UbicacionPasajero? ubicacion,
  })  : _reloj = reloj ?? DateTime.now,
        _intervalo = intervalo,
        _reintento = reintento,
        _preferencias = preferencias,
        _ubicacion = ubicacion;

  final RepositorioRutaSur _repositorio;
  final PreferenciasPasajero? _preferencias;
  final UbicacionPasajero? _ubicacion;
  final DateTime Function() _reloj;
  final Duration _intervalo;
  final Duration _reintento;
  Timer? _temporizador;
  Timer? _temporizadorReintento;
  bool _cerrado = false;
  bool _pausado = false;
  bool _consultando = false;
  int _fallosSeguidos = 0;

  // Ruta (se descarga una vez)
  Linea? linea;
  List<ParaderoEnMapa> paraderos = const [];
  bool cargandoLinea = true;
  String? errorLinea;

  // Unidades (se consultan cada 15 s, RF-002)
  List<UnidadActiva> unidades = const [];
  DateTime? ultimaActualizacion;
  bool sinConexion = false;

  // Favoritos y paradero cercano (RF-006, RF-007): solo en el teléfono
  List<String> codigosFavoritos = const [];
  LatLng? posicionUsuario;
  ParaderoCercano? cercano;
  bool ubicacionConcedida = false;

  /// Sentido que el pasajero eligió ver: bajada, subida o ambos (null). 0.6.1.
  Sentido? sentido;

  /// La línea solo con las variantes del sentido elegido.
  Linea? get lineaVisible => linea?.soloSentido(sentido);

  /// Paraderos del sentido elegido.
  List<ParaderoEnMapa> get paraderosVisibles =>
      sentido == null ? paraderos : [for (final p in paraderos) if (p.enSentido(sentido)) p];

  /// Unidades que van en el sentido elegido.
  List<UnidadActiva> get unidadesVisibles =>
      sentido == null ? unidades : [for (final u in unidades) if (u.sentido == sentido) u];

  /// Cambia el sentido del mapa, lo recuerda y vuelve a proponer el paradero más cercano.
  Future<void> elegirSentido(Sentido? nuevo) async {
    sentido = nuevo;
    final posicion = posicionUsuario;
    if (posicion != null) cercano = paraderoMasCercano(paraderosVisibles, posicion);
    _notificar();
    await _preferencias?.guardarSentido(nuevo);
  }

  /// Descarga la ruta, consulta las unidades y programa la consulta periódica.
  Future<void> iniciar() async {
    await cargarLinea();
    if (linea == null) return;
    // Se descartan los favoritos de paraderos que ya no están en la ruta
    final guardados = await _preferencias?.favoritos() ?? const <String>[];
    codigosFavoritos = [for (final c in guardados) if (paraderoPorCodigo(c) != null) c];
    sentido = await _preferencias?.sentidoElegido();
    if (await _ubicacion?.permisoConcedido() ?? false) {
      ubicacionConcedida = true;
      unawaited(actualizarUbicacion());
    }
    await refrescarUnidades();
    _programarConsultas();
  }

  void _programarConsultas() {
    _temporizador?.cancel();
    _temporizador = Timer.periodic(_intervalo, (_) => refrescarUnidades());
  }

  /// La app pasó a segundo plano: deja de consultar (Android corta la red y cada
  /// consulta fallaría). D-20.
  void pausar() {
    _pausado = true;
    _temporizador?.cancel();
    _temporizadorReintento?.cancel();
  }

  /// La app volvió al frente: consulta de inmediato, sin esperar los 15 s, y
  /// vuelve a programar la consulta periódica. D-20.
  Future<void> reanudar() async {
    if (!_pausado) return;
    _pausado = false;
    if (linea == null) return; // la pantalla muestra el error de la ruta y su botón
    // Lo ocurrido en segundo plano no cuenta: la red puede tardar en volver
    _fallosSeguidos = 0;
    _programarConsultas();
    await refrescarUnidades();
  }

  Future<void> cargarLinea() async {
    cargandoLinea = true;
    errorLinea = null;
    _notificar();
    try {
      final descargada = await _repositorio.obtenerLinea();
      linea = descargada;
      paraderos = paraderosUnicos(descargada);
    } on SinConexion {
      errorLinea = 'No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo.';
    } on ErrorServicio catch (e) {
      errorLinea = e.mensaje;
    }
    cargandoLinea = false;
    _notificar();
  }

  // ------------------------------------------------------------------
  // Ubicación del pasajero (RF-006)
  // ------------------------------------------------------------------

  /// «Mi ubicación»: pide el permiso si hace falta y propone el paradero más cercano.
  /// Devuelve la posición, para centrar el mapa en ella.
  Future<LatLng?> usarMiUbicacion() async {
    final u = _ubicacion;
    if (u == null) return null;
    ubicacionConcedida = await u.permisoConcedido() || await u.pedirPermiso();
    _notificar();
    if (!ubicacionConcedida) return null;
    return actualizarUbicacion();
  }

  Future<LatLng?> actualizarUbicacion() async {
    final posicion = await _ubicacion?.posicionActual();
    if (posicion != null) {
      posicionUsuario = posicion;
      cercano = paraderoMasCercano(paraderosVisibles, posicion);
      _notificar();
    }
    return posicion;
  }

  // ------------------------------------------------------------------
  // Favoritos (RF-007): hasta 10, por código de paradero
  // ------------------------------------------------------------------
  bool esFavorito(String codigo) => codigosFavoritos.contains(codigo);

  List<ParaderoEnMapa> get favoritos => [
        for (final codigo in codigosFavoritos)
          for (final p in paraderos)
            if (p.codigo == codigo) p,
      ];

  /// Agrega o quita un favorito. Devuelve false si ya hay 10 y no se pudo agregar.
  Future<bool> alternarFavorito(String codigo) async {
    final lista = List.of(codigosFavoritos);
    if (!lista.remove(codigo)) {
      if (lista.length >= maximoFavoritos) return false;
      lista.add(codigo);
    }
    codigosFavoritos = lista;
    _notificar();
    await _preferencias?.guardarFavoritos(lista);
    return true;
  }

  /// Paradero del mapa por su código (los de la búsqueda llegan con su código).
  ParaderoEnMapa? paraderoPorCodigo(String codigo) {
    for (final p in paraderos) {
      if (p.codigo == codigo) return p;
    }
    return null;
  }

  /// Consulta las unidades. Si falla, conserva las últimas conocidas (P06, P-01).
  ///
  /// Con unidades ya en pantalla, un fallo aislado no se anuncia: se reintenta a los
  /// 3 s y el aviso «Sin conexión» aparece solo tras [Config.fallosParaAviso] fallos
  /// seguidos (D-20). Si nunca hubo datos, se avisa desde el primer fallo.
  Future<void> refrescarUnidades() async {
    if (_consultando || _cerrado) return;
    _consultando = true;
    _temporizadorReintento?.cancel();
    try {
      unidades = await _repositorio.unidadesActivas();
      ultimaActualizacion = _reloj();
      _fallosSeguidos = 0;
      sinConexion = false;
    } on SinConexion {
      _registrarFallo();
    } on ErrorServicio {
      _registrarFallo();
    } finally {
      _consultando = false;
    }
    _notificar();
  }

  void _registrarFallo() {
    _fallosSeguidos++;
    sinConexion = ultimaActualizacion == null || _fallosSeguidos >= Config.fallosParaAviso;
    if (!_pausado && !_cerrado) {
      _temporizadorReintento = Timer(_reintento, refrescarUnidades);
    }
  }

  /// Segundos desde la última consulta exitosa (indicador de P-01).
  int? segundosDesdeActualizacion() {
    final ultima = ultimaActualizacion;
    return ultima == null ? null : _reloj().difference(ultima).inSeconds;
  }

  /// No hay unidades transmitiendo y el servicio sí respondió (P-05, RNF-04).
  bool get sinUnidadesEnCirculacion =>
      ultimaActualizacion != null && !sinConexion && unidades.isEmpty;

  @override
  void dispose() {
    _cerrado = true;
    _temporizador?.cancel();
    _temporizadorReintento?.cancel();
    super.dispose();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }
}
