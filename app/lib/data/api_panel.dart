/// Operaciones del panel sobre la API REST de RutaSur (IAdministracion, P06 Tabla 66).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../domain/panel.dart';
import '../domain/repositorio.dart';

class ApiPanel implements ServicioPanel {
  ApiPanel({http.Client? cliente, String? urlBase})
      : _cliente = cliente ?? http.Client(),
        _urlBase = urlBase ?? Config.urlApi;

  final http.Client _cliente;
  final String _urlBase;

  @override
  Future<AccesoPanel> iniciarSesion(String usuario, String contrasena) async {
    final datos = await _pedir('POST', '/auth/login', null, {'username': usuario, 'password': contrasena})
        as Map<String, dynamic>;
    final rol = datos['role'] as String;
    if (rol == 'CONDUCTOR') {
      throw const ErrorServicio(
        estado: 403,
        codigo: 'FORBIDDEN',
        mensaje: 'Esta cuenta es de conductor: se usa en la app del conductor, no en el panel.',
      );
    }
    return AccesoPanel(
      token: datos['access_token'] as String,
      usuario: usuario,
      rol: RolPanel.desdeApi(rol),
    );
  }

  @override
  Future<EstadoFlota> flota(AccesoPanel a) async =>
      EstadoFlota.fromJson(await _pedir('GET', '/admin/fleet', a) as Map<String, dynamic>);

  @override
  Future<PaginaEventos> eventos(AccesoPanel a, FiltroEventos f) async {
    final consulta = Uri(queryParameters: {
      'from': f.desde.toUtc().toIso8601String(),
      'to': f.hasta.toUtc().toIso8601String(),
      if (f.tipo != null) 'type': f.tipo!.codigoApi,
      if (f.unidad != null && f.unidad!.isNotEmpty) 'vehicle': f.unidad!,
      'page': '${f.pagina}',
      'page_size': '${f.tamano}',
    }).query;
    return PaginaEventos.fromJson(await _pedir('GET', '/admin/events?$consulta', a) as Map<String, dynamic>);
  }

  @override
  Future<HorarioLinea> horario() async {
    final datos = await _pedir('GET', '/routes/lb', null) as Map<String, dynamic>;
    return HorarioLinea(datos['service_start'] as String, datos['service_end'] as String);
  }

  @override
  Future<HorarioLinea> cambiarHorario(AccesoPanel a, HorarioLinea h) async {
    final datos = await _pedir('PUT', '/admin/line', a, {'service_start': h.inicio, 'service_end': h.fin})
        as Map<String, dynamic>;
    String corto(String t) => t.substring(0, 5); // «05:00:00» → «05:00»
    return HorarioLinea(corto(datos['service_start'] as String), corto(datos['service_end'] as String));
  }

  @override
  Future<List<VarianteAdmin>> variantes(AccesoPanel a) async => [
        for (final v in await _pedir('GET', '/admin/variants', a) as List<dynamic>)
          VarianteAdmin.fromJson(v as Map<String, dynamic>),
      ];

  @override
  Future<VarianteAdmin> asignarParaderos(AccesoPanel a, String varianteId, List<String> codigos) async =>
      VarianteAdmin.fromJson(await _pedir(
        'PUT',
        '/admin/variants/${Uri.encodeComponent(varianteId)}/stops',
        a,
        {'codes': codigos},
      ) as Map<String, dynamic>);

  @override
  Future<List<ParaderoAdmin>> paraderos(AccesoPanel a) async => [
        for (final p in await _pedir('GET', '/admin/stops', a) as List<dynamic>)
          ParaderoAdmin.fromJson(p as Map<String, dynamic>),
      ];

  @override
  Future<ParaderoAdmin> crearParadero(AccesoPanel a, DatosParadero d) async {
    final cuerpo = d.toJson()..remove('active');
    return ParaderoAdmin.fromJson(await _pedir('POST', '/admin/stops', a, cuerpo) as Map<String, dynamic>);
  }

  @override
  Future<ParaderoAdmin> editarParadero(AccesoPanel a, String codigo, DatosParadero d) async =>
      ParaderoAdmin.fromJson(
        await _pedir('PUT', '/admin/stops/${Uri.encodeComponent(codigo)}', a, d.toJson())
            as Map<String, dynamic>,
      );

  @override
  Future<List<UnidadAdmin>> unidades(AccesoPanel a) async => [
        for (final u in await _pedir('GET', '/admin/units', a) as List<dynamic>)
          UnidadAdmin.fromJson(u as Map<String, dynamic>),
      ];

  @override
  Future<UnidadAdmin> registrarUnidad(AccesoPanel a, String etiqueta) async =>
      UnidadAdmin.fromJson(await _pedir('POST', '/admin/units', a, {'label': etiqueta}) as Map<String, dynamic>);

  @override
  Future<UnidadAdmin> habilitarUnidad(AccesoPanel a, String unidadId, bool activa) async =>
      UnidadAdmin.fromJson(
        await _pedir('PUT', '/admin/units/${Uri.encodeComponent(unidadId)}', a, {'active': activa})
            as Map<String, dynamic>,
      );

  @override
  Future<List<CuentaAdmin>> cuentasConductor(AccesoPanel a) => _cuentas('/admin/driver-accounts', a);

  @override
  Future<List<CuentaAdmin>> cuentasPanel(AccesoPanel a) => _cuentas('/admin/panel-accounts', a);

  Future<List<CuentaAdmin>> _cuentas(String ruta, AccesoPanel a) async => [
        for (final c in await _pedir('GET', ruta, a) as List<dynamic>)
          CuentaAdmin.fromJson(c as Map<String, dynamic>),
      ];

  @override
  Future<CuentaConClave> crearCuentaConductor(AccesoPanel a, String unidadId, String usuario) async =>
      _conClave(await _pedir('POST', '/admin/driver-accounts', a, {'vehicle_id': unidadId, 'username': usuario}));

  @override
  Future<CuentaConClave> crearCuentaPanel(AccesoPanel a, String usuario, RolPanel rol) async =>
      _conClave(await _pedir('POST', '/admin/panel-accounts', a, {'username': usuario, 'role': rol.codigoApi}));

  @override
  Future<CuentaConClave> actuarSobreCuenta(
    AccesoPanel a,
    String cuentaId,
    AccionCuenta accion, {
    required bool panel,
  }) async {
    final ruta = panel ? '/admin/panel-accounts' : '/admin/driver-accounts';
    return _conClave(
      await _pedir('PUT', '$ruta/${Uri.encodeComponent(cuentaId)}', a, {'action': accion.codigoApi}),
    );
  }

  CuentaConClave _conClave(Object? datos) {
    final j = datos as Map<String, dynamic>;
    return CuentaConClave(
      CuentaAdmin.fromJson(j['account'] as Map<String, dynamic>),
      j['temporary_password'] as String?,
    );
  }

  /// Petición JSON; devuelve `data` o lanza SinConexion / ErrorServicio (Tabla 55).
  Future<Object?> _pedir(String metodo, String ruta, AccesoPanel? acceso, [Object? cuerpo]) async {
    final peticion = http.Request(metodo, Uri.parse('$_urlBase/api/v1$ruta'))
      ..headers['Accept'] = 'application/json';
    if (acceso != null) peticion.headers['Authorization'] = 'Bearer ${acceso.token}';
    if (cuerpo != null) {
      peticion.headers['Content-Type'] = 'application/json';
      peticion.body = jsonEncode(cuerpo);
    }
    final http.Response respuesta;
    try {
      // El servicio gratuito tarda ~1 min en despertar si estaba apagado
      respuesta = await http.Response.fromStream(
        await _cliente.send(peticion).timeout(Config.tiempoEsperaConductor),
      );
    } on TimeoutException {
      throw const SinConexion();
    } on http.ClientException {
      throw const SinConexion();
    }

    Object? json;
    try {
      json = jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 && json is Map) {
      return json['data'];
    }
    final error = json is Map && json['error'] is Map ? json['error'] as Map : const {};
    final meta = json is Map && json['meta'] is Map ? json['meta'] as Map : const {};
    throw ErrorServicio(
      estado: respuesta.statusCode,
      codigo: error['code'] as String? ?? 'HTTP_ERROR',
      mensaje: error['message'] as String? ?? 'El servicio respondió con un error.',
      reintentarEnS: meta['retry_after_s'] as int?,
    );
  }
}
