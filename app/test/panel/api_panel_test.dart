// Contrato del panel con la API: las muestras son respuestas reales de /api/v1/admin,
// capturadas del backend con los datos demo (test/panel/muestras_api_admin.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/data/api_panel.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/panel.dart';
import 'package:rutasur/domain/repositorio.dart';

final muestras = jsonDecode(File('test/panel/muestras_api_admin.json').readAsStringSync()) as Map<String, dynamic>;

const acceso = AccesoPanel(token: 'tok', usuario: 'admin.demo', rol: RolPanel.administrador);

http.Response json(Object cuerpo, [int estado = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      estado,
      headers: {'content-type': 'application/json'},
    );

/// Responde la muestra según el método y la ruta, y guarda las peticiones.
ApiPanel api(List<http.Request> peticiones) => ApiPanel(
      urlBase: 'http://servidor',
      cliente: MockClient((p) async {
        peticiones.add(p);
        final ruta = p.url.path.replaceFirst('/api/v1/admin', '');
        final clave = switch ((p.method, ruta)) {
          ('GET', '/fleet') => 'fleet',
          ('GET', '/variants') => 'variants',
          ('GET', '/stops') => 'stops',
          ('GET', '/units') => 'units',
          ('POST', '/driver-accounts') => 'driver',
          ('PUT', '/line') => 'line',
          ('GET', '/events') => 'events',
          ('GET', '/panel-accounts') => 'panel_accounts',
          _ => null,
        };
        if (clave == null) return json({'error': {'code': 'NOT_FOUND', 'message': 'x'}}, 404);
        return json(muestras[clave] as Object);
      }),
    );

void main() {
  test('flota: estados, posición y recorrido', () async {
    final peticiones = <http.Request>[];
    final flota = await api(peticiones).flota(acceso);
    final siete = flota.unidades.firstWhere((u) => u.etiqueta == '07');
    expect(siete.ramal, Ramal.mollebaya);
    expect(siete.ubicacion, isNotNull);
    expect(flota.unidades.firstWhere((u) => u.etiqueta == '12').estado, EstadoUnidad.inactiva);
    expect(flota.transmitiendo + flota.sinSenal + flota.inactivas, flota.unidades.length);
    expect(peticiones.single.headers['Authorization'], 'Bearer tok');
  });

  test('variantes, paraderos y unidades', () async {
    final a = api([]);
    final v = (await a.variantes(acceso)).single;
    expect(v.trazado, hasLength(3));
    expect(v.paraderos.first.orden, 1);
    expect(v.paraderos.map((p) => p.principal), [true, false]);
    final paraderos = await a.paraderos(acceso);
    expect(paraderos.first.codigo, startsWith('stp_'));
    expect(paraderos.map((p) => p.principal), [true, false]);
    expect((await a.unidades(acceso)).map((u) => u.etiqueta), containsAll(['07', '12']));
  });

  test('el formulario de paradero envía si es principal', () {
    const d = DatosParadero(
      nombre: 'Plaza Characato',
      referencia: null,
      ubicacion: LatLng(-16.47, -71.48),
      tramoComun: false,
      principal: true,
    );
    expect(d.toJson()['main'], isTrue);
  });

  test('crear una cuenta de conductor devuelve la contraseña temporal', () async {
    final peticiones = <http.Request>[];
    final creada = await api(peticiones).crearCuentaConductor(acceso, 'u15', 'unidad15');
    expect(creada.cuenta.usuario, 'unidad15');
    expect(creada.cuenta.etiquetaUnidad, '15');
    expect(creada.contrasenaTemporal, hasLength(12));
    expect(jsonDecode(peticiones.single.body), {'vehicle_id': 'u15', 'username': 'unidad15'});
  });

  test('el horario vuelve como HH:MM', () async {
    final h = await api([]).cambiarHorario(acceso, const HorarioLinea('05:00', '21:00'));
    expect((h.inicio, h.fin), ('05:00', '21:00'));
  });

  test('eventos: filtros en la consulta y paginación', () async {
    final peticiones = <http.Request>[];
    final pagina = await api(peticiones).eventos(
      acceso,
      FiltroEventos(
        desde: DateTime.utc(2026, 11, 1),
        hasta: DateTime.utc(2026, 11, 1, 23, 59, 59),
        tipo: TipoEvento.seguridad,
        unidad: '07',
        pagina: 2,
      ),
    );
    final q = peticiones.single.url.queryParameters;
    expect(q['type'], 'SEGURIDAD');
    expect(q['vehicle'], '07');
    expect(q['page'], '2');
    expect(q['from'], startsWith('2026-11-01T00:00:00'));
    expect(pagina.eventos.first.usuarioPanel, 'admin.demo');
    expect(pagina.retencionDias, greaterThan(0));
  });

  test('cuentas del panel', () async {
    final cuentas = await api([]).cuentasPanel(acceso);
    expect(cuentas.map((c) => c.rol), containsAll(['ADMINISTRADOR', 'MODERADOR']));
  });

  test('un rol sin permiso llega como ErrorServicio FORBIDDEN', () async {
    final a = ApiPanel(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => json({'error': {'code': 'FORBIDDEN', 'message': 'Su rol no tiene permiso'}}, 403)),
    );
    await expectLater(
      a.unidades(acceso),
      throwsA(isA<ErrorServicio>().having((e) => e.codigo, 'codigo', 'FORBIDDEN')),
    );
  });

  test('el panel rechaza una cuenta de conductor al ingresar', () async {
    final a = ApiPanel(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => json({
            'data': {'access_token': 't', 'token_type': 'bearer', 'expires_in': 43200, 'role': 'CONDUCTOR', 'vehicle_label': '07'},
            'meta': {'timestamp': '2026-11-01T00:00:00Z'},
          })),
    );
    await expectLater(a.iniciarSesion('unidad07', 'rutasur-demo'), throwsA(isA<ErrorServicio>()));
  });
}
