/// Modelos del panel de administración (A-01 a A-05; P06 Tabla 46).
///
/// Las cuentas no tienen datos personales: solo usuario, rol o unidad y estado (RN-011).
library;

import 'package:latlong2/latlong.dart';

import 'modelos.dart';

enum RolPanel {
  administrador('ADMINISTRADOR', 'Administrador'),
  moderador('MODERADOR', 'Moderador');

  const RolPanel(this.codigoApi, this.nombre);

  final String codigoApi;
  final String nombre;

  static RolPanel desdeApi(String codigo) => RolPanel.values.firstWhere((r) => r.codigoApi == codigo);
}

/// Sesión del panel. El token vive solo en memoria: al recargar la página se vuelve a
/// ingresar, y nunca queda guardado en el navegador.
class AccesoPanel {
  const AccesoPanel({required this.token, required this.usuario, required this.rol});

  final String token;
  final String usuario;
  final RolPanel rol;

  bool get esAdministrador => rol == RolPanel.administrador;
}

// ---------------------------------------------------------------------------
// A-02 Estado de la flota (RF-017)
// ---------------------------------------------------------------------------
enum EstadoUnidad {
  transmitiendo('TRANSMITIENDO', 'Transmitiendo'),
  sinSenal('SIN_SENAL', 'Sin señal'),
  inactiva('INACTIVA', 'Inactiva');

  const EstadoUnidad(this.codigoApi, this.nombre);

  final String codigoApi;
  final String nombre;

  static EstadoUnidad desdeApi(String c) => EstadoUnidad.values.firstWhere((e) => e.codigoApi == c);
}

class UnidadFlota {
  const UnidadFlota({
    required this.id,
    required this.etiqueta,
    required this.usuario,
    required this.estado,
    required this.desde,
    required this.antiguedadS,
    required this.ubicacion,
    required this.rumbo,
    required this.ramal,
    required this.sentido,
    required this.destino,
  });

  factory UnidadFlota.fromJson(Map<String, dynamic> j) => UnidadFlota(
        id: j['vehicle_id'] as String,
        etiqueta: j['vehicle_label'] as String,
        usuario: j['username'] as String?,
        estado: EstadoUnidad.desdeApi(j['status'] as String),
        desde: DateTime.parse(j['since'] as String),
        antiguedadS: j['last_position_age_s'] as int?,
        ubicacion: j['lat'] == null
            ? null
            : LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        rumbo: j['heading'] as int?,
        ramal: j['branch'] == null ? null : Ramal.desdeApi(j['branch'] as String),
        sentido: j['direction'] == null ? null : Sentido.desdeApi(j['direction'] as String),
        destino: j['destination'] as String?,
      );

  final String id;
  final String etiqueta;
  final String? usuario;
  final EstadoUnidad estado;
  final DateTime desde;
  final int? antiguedadS;
  final LatLng? ubicacion;
  final int? rumbo;
  final Ramal? ramal;
  final Sentido? sentido;
  final String? destino;
}

class EstadoFlota {
  const EstadoFlota({
    required this.transmitiendo,
    required this.sinSenal,
    required this.inactivas,
    required this.unidades,
  });

  factory EstadoFlota.fromJson(Map<String, dynamic> j) {
    final resumen = j['summary'] as Map<String, dynamic>;
    return EstadoFlota(
      transmitiendo: resumen['transmitting'] as int,
      sinSenal: resumen['no_signal'] as int,
      inactivas: resumen['inactive'] as int,
      unidades: [
        for (final u in j['vehicles'] as List<dynamic>) UnidadFlota.fromJson(u as Map<String, dynamic>),
      ],
    );
  }

  final int transmitiendo;
  final int sinSenal;
  final int inactivas;
  final List<UnidadFlota> unidades;
}

// ---------------------------------------------------------------------------
// A-03 Rutas y paraderos (RF-015)
// ---------------------------------------------------------------------------
class ParaderoVarianteAdmin {
  const ParaderoVarianteAdmin({
    required this.codigo,
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.orden,
    required this.distanciaM,
    required this.tramoComun,
    this.principal = false,
  });

  factory ParaderoVarianteAdmin.fromJson(Map<String, dynamic> j) => ParaderoVarianteAdmin(
        codigo: j['code'] as String,
        nombre: j['name'] as String,
        referencia: j['reference'] as String?,
        ubicacion: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        orden: j['order'] as int,
        distanciaM: (j['distance_from_start_m'] as num).toDouble(),
        tramoComun: j['shared_trunk'] as bool,
        principal: j['main'] as bool? ?? false,
      );

  final String codigo;
  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final int orden;
  final double distanciaM;
  final bool tramoComun;

  /// Se ve en la app aunque el mapa esté alejado.
  final bool principal;
}

class VarianteAdmin {
  const VarianteAdmin({
    required this.id,
    required this.ramal,
    required this.sentido,
    required this.destino,
    required this.longitudM,
    required this.trazado,
    required this.paraderos,
  });

  factory VarianteAdmin.fromJson(Map<String, dynamic> j) => VarianteAdmin(
        id: j['id'] as String,
        ramal: Ramal.desdeApi(j['branch'] as String),
        sentido: Sentido.desdeApi(j['direction'] as String),
        destino: j['destination'] as String,
        longitudM: (j['length_m'] as num).toDouble(),
        trazado: [
          for (final p in j['shape'] as List<dynamic>)
            LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        paraderos: [
          for (final p in j['stops'] as List<dynamic>)
            ParaderoVarianteAdmin.fromJson(p as Map<String, dynamic>),
        ],
      );

  final String id;
  final Ramal ramal;
  final Sentido sentido;
  final String destino;
  final double longitudM;
  final List<LatLng> trazado;
  final List<ParaderoVarianteAdmin> paraderos;

  /// «Mollebaya → Centro», «Centro → Cerrillo».
  String get nombre =>
      sentido == Sentido.ida ? '${ramal.nombre} → Centro' : 'Centro → ${ramal.nombre}';

  String get clave => '${ramal.codigoApi}-${sentido.codigoApi}';
}

class ParaderoAdmin {
  const ParaderoAdmin({
    required this.codigo,
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.tramoComun,
    required this.activo,
    required this.variantes,
    this.principal = false,
  });

  factory ParaderoAdmin.fromJson(Map<String, dynamic> j) => ParaderoAdmin(
        codigo: j['code'] as String,
        nombre: j['name'] as String,
        referencia: j['reference'] as String?,
        ubicacion: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        tramoComun: j['shared_trunk'] as bool,
        activo: j['active'] as bool,
        variantes: [for (final v in j['variants'] as List<dynamic>) v as String],
        principal: j['main'] as bool? ?? false,
      );

  final String codigo;
  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final bool tramoComun;
  final bool activo;
  final List<String> variantes;
  final bool principal;
}

/// Lo que el formulario A-03a envía.
class DatosParadero {
  const DatosParadero({
    required this.nombre,
    required this.referencia,
    required this.ubicacion,
    required this.tramoComun,
    this.principal = false,
    this.activo = true,
  });

  final String nombre;
  final String? referencia;
  final LatLng ubicacion;
  final bool tramoComun;
  final bool principal;
  final bool activo;

  Map<String, Object?> toJson() => {
        'name': nombre,
        'reference': referencia,
        'lat': ubicacion.latitude,
        'lon': ubicacion.longitude,
        'shared_trunk': tramoComun,
        'main': principal,
        'active': activo,
      };
}

class HorarioLinea {
  const HorarioLinea(this.inicio, this.fin);

  /// «05:00»
  final String inicio;
  final String fin;
}

// ---------------------------------------------------------------------------
// A-04 Unidades y cuentas (RF-016)
// ---------------------------------------------------------------------------
class UnidadAdmin {
  const UnidadAdmin({
    required this.id,
    required this.etiqueta,
    required this.activa,
    required this.usuario,
  });

  factory UnidadAdmin.fromJson(Map<String, dynamic> j) => UnidadAdmin(
        id: j['id'] as String,
        etiqueta: j['label'] as String,
        activa: j['active'] as bool,
        usuario: j['username'] as String?,
      );

  final String id;
  final String etiqueta;
  final bool activa;
  final String? usuario;
}

enum AccionCuenta {
  restablecer('RESET_PASSWORD'),
  desactivar('DEACTIVATE'),
  activar('ACTIVATE'),
  desbloquear('UNLOCK');

  const AccionCuenta(this.codigoApi);

  final String codigoApi;
}

class CuentaAdmin {
  const CuentaAdmin({
    required this.id,
    required this.usuario,
    required this.rol,
    required this.activa,
    required this.bloqueadaHasta,
    required this.etiquetaUnidad,
  });

  factory CuentaAdmin.fromJson(Map<String, dynamic> j) => CuentaAdmin(
        id: j['id'] as String,
        usuario: j['username'] as String,
        rol: j['role'] as String,
        activa: j['active'] as bool,
        bloqueadaHasta: j['locked_until'] == null ? null : DateTime.parse(j['locked_until'] as String),
        etiquetaUnidad: j['vehicle_label'] as String?,
      );

  final String id;
  final String usuario;

  /// CONDUCTOR, ADMINISTRADOR o MODERADOR
  final String rol;
  final bool activa;
  final DateTime? bloqueadaHasta;
  final String? etiquetaUnidad;

  bool bloqueada(DateTime ahora) => bloqueadaHasta != null && bloqueadaHasta!.isAfter(ahora);
}

/// Cuenta recién creada o restablecida: la contraseña se muestra una sola vez.
class CuentaConClave {
  const CuentaConClave(this.cuenta, this.contrasenaTemporal);

  final CuentaAdmin cuenta;
  final String? contrasenaTemporal;
}

// ---------------------------------------------------------------------------
// A-05 Registro de eventos (RF-020)
// ---------------------------------------------------------------------------
enum TipoEvento {
  peticion('PETICION', 'Petición'),
  error('ERROR', 'Error'),
  posicionDescartada('POSICION_DESCARTADA', 'Posición descartada'),
  seguridad('SEGURIDAD', 'Seguridad'),
  tarea('TAREA', 'Tarea');

  const TipoEvento(this.codigoApi, this.nombre);

  final String codigoApi;
  final String nombre;

  static TipoEvento desdeApi(String c) => TipoEvento.values.firstWhere((t) => t.codigoApi == c);
}

class EventoPanel {
  const EventoPanel({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.origen,
    required this.unidad,
    required this.usuarioPanel,
    required this.codigoHttp,
    required this.detalle,
  });

  factory EventoPanel.fromJson(Map<String, dynamic> j) => EventoPanel(
        id: j['id'] as int,
        fecha: DateTime.parse(j['date'] as String),
        tipo: TipoEvento.desdeApi(j['type'] as String),
        origen: j['source'] as String,
        unidad: j['vehicle_label'] as String?,
        usuarioPanel: j['panel_user'] as String?,
        codigoHttp: j['http_status'] as int?,
        detalle: j['detail'] as Map<String, dynamic>?,
      );

  final int id;
  final DateTime fecha;
  final TipoEvento tipo;
  final String origen;
  final String? unidad;
  final String? usuarioPanel;
  final int? codigoHttp;
  final Map<String, dynamic>? detalle;
}

class FiltroEventos {
  const FiltroEventos({
    required this.desde,
    required this.hasta,
    this.tipo,
    this.unidad,
    this.pagina = 1,
    this.tamano = 50,
  });

  final DateTime desde;
  final DateTime hasta;
  final TipoEvento? tipo;
  final String? unidad;
  final int pagina;
  final int tamano;

  FiltroEventos enPagina(int nueva) =>
      FiltroEventos(desde: desde, hasta: hasta, tipo: tipo, unidad: unidad, pagina: nueva, tamano: tamano);
}

class PaginaEventos {
  const PaginaEventos({
    required this.eventos,
    required this.total,
    required this.pagina,
    required this.tamano,
    required this.retencionDias,
  });

  factory PaginaEventos.fromJson(Map<String, dynamic> j) => PaginaEventos(
        eventos: [
          for (final e in j['events'] as List<dynamic>) EventoPanel.fromJson(e as Map<String, dynamic>),
        ],
        total: j['total'] as int,
        pagina: j['page'] as int,
        tamano: j['page_size'] as int,
        retencionDias: j['retention_days'] as int,
      );

  final List<EventoPanel> eventos;
  final int total;
  final int pagina;
  final int tamano;
  final int retencionDias;

  int get paginas => total == 0 ? 1 : (total + tamano - 1) ~/ tamano;
}

// ---------------------------------------------------------------------------
// Contrato con el servicio (se cumple con ApiPanel; en las pruebas, con un falso)
// ---------------------------------------------------------------------------
abstract interface class ServicioPanel {
  Future<AccesoPanel> iniciarSesion(String usuario, String contrasena);

  Future<EstadoFlota> flota(AccesoPanel acceso);

  Future<PaginaEventos> eventos(AccesoPanel acceso, FiltroEventos filtro);

  Future<HorarioLinea> horario();

  Future<HorarioLinea> cambiarHorario(AccesoPanel acceso, HorarioLinea horario);

  Future<List<VarianteAdmin>> variantes(AccesoPanel acceso);

  Future<VarianteAdmin> asignarParaderos(AccesoPanel acceso, String varianteId, List<String> codigos);

  Future<List<ParaderoAdmin>> paraderos(AccesoPanel acceso);

  Future<ParaderoAdmin> crearParadero(AccesoPanel acceso, DatosParadero datos);

  Future<ParaderoAdmin> editarParadero(AccesoPanel acceso, String codigo, DatosParadero datos);

  Future<List<UnidadAdmin>> unidades(AccesoPanel acceso);

  Future<UnidadAdmin> registrarUnidad(AccesoPanel acceso, String etiqueta);

  Future<UnidadAdmin> habilitarUnidad(AccesoPanel acceso, String unidadId, bool activa);

  Future<List<CuentaAdmin>> cuentasConductor(AccesoPanel acceso);

  Future<List<CuentaAdmin>> cuentasPanel(AccesoPanel acceso);

  Future<CuentaConClave> crearCuentaConductor(AccesoPanel acceso, String unidadId, String usuario);

  Future<CuentaConClave> crearCuentaPanel(AccesoPanel acceso, String usuario, RolPanel rol);

  Future<CuentaConClave> actuarSobreCuenta(
    AccesoPanel acceso,
    String cuentaId,
    AccionCuenta accion, {
    required bool panel,
  });
}
