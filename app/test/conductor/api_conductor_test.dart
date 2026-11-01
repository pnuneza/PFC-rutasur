import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rutasur/data/api_conductor.dart';
import 'package:rutasur/domain/conductor.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/repositorio.dart';

import 'fakes_conductor.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), estado);

void main() {
  test('login envía usuario y contraseña y lee el token y la unidad', () async {
    final token = tokenQueVence(DateTime.utc(2026, 11, 3));
    final api = ApiConductor(
      urlBase: 'http://servidor',
      cliente: MockClient((p) async {
        expect(p.method, 'POST');
        expect(p.url.path, '/api/v1/auth/login');
        expect(jsonDecode(p.body), {'username': 'unidad07', 'password': 'rutasur-demo'});
        return json({
          'data': {
            'access_token': token,
            'token_type': 'bearer',
            'expires_in': 43200,
            'role': 'CONDUCTOR',
            'vehicle_label': '07',
          },
          'meta': {'timestamp': 'x'},
        }, 200);
      }),
    );
    final acceso = await api.iniciarSesion('unidad07', 'rutasur-demo');
    expect(acceso.etiquetaUnidad, '07');
    expect(acceso.vence, DateTime.utc(2026, 11, 3));
  });

  test('una cuenta del panel no puede usar la app del conductor', () async {
    final api = ApiConductor(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => json({
            'data': {'access_token': 'x', 'role': 'ADMINISTRADOR', 'vehicle_label': null, 'expires_in': 1},
            'meta': {'timestamp': 'x'},
          }, 200)),
    );
    expect(() => api.iniciarSesion('pierre.admin', 'clave-larga'), throwsA(isA<ErrorServicio>()));
  });

  test('cuenta bloqueada: lee el código y meta.retry_after_s', () async {
    final api = ApiConductor(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => json({
            'error': {'code': 'ACCOUNT_LOCKED', 'message': 'bloqueada'},
            'meta': {'retry_after_s': 900},
          }, 403)),
    );
    try {
      await api.iniciarSesion('unidad07', 'rutasur-demo');
      fail('debía lanzar ErrorServicio');
    } on ErrorServicio catch (e) {
      expect((e.codigo, e.reintentarEnS), ('ACCOUNT_LOCKED', 900));
    }
  });

  test('abrir sesión y enviar posiciones llevan el token y el formato del contrato', () async {
    final api = ApiConductor(
      urlBase: 'http://servidor',
      cliente: MockClient((p) async {
        expect(p.headers['Authorization'], 'Bearer tkn');
        if (p.url.path == '/api/v1/sessions') {
          expect(jsonDecode(p.body), {'branch': 'MOLLEBAYA', 'direction': 'VUELTA'});
          return json({
            'data': {
              'session_id': 's-1',
              'variant': 'MOLLEBAYA-VUELTA',
              'destination': 'Mollebaya',
              'started_at': '2026-11-02T14:00:00Z',
            },
            'meta': {'timestamp': 'x'},
          }, 201);
        }
        expect(p.url.path, '/api/v1/sessions/s-1/positions');
        final posicion = (jsonDecode(p.body)['positions'] as List).single as Map;
        expect(posicion.keys, containsAll(['id', 'lat', 'lon', 'accuracy_m', 'captured_at']));
        expect(posicion['captured_at'], '2026-11-02T14:00:05.000Z');
        return json({
          'data': {'confirmed': ['p-1'], 'published': 1, 'discarded': 0, 'duplicates': 0},
          'meta': {'timestamp': 'x'},
        }, 200);
      }),
    );
    final sesion = await api.abrirSesion('tkn', Ramal.mollebaya, Sentido.vuelta);
    expect((sesion.id, sesion.destino), ('s-1', 'Mollebaya'));
    final acuse = await api.enviarPosiciones('tkn', 's-1', [
      Lectura(
        id: 'p-1', lat: -16.4, lon: -71.5, velocidadKmh: 30, rumbo: 90, precisionM: 8,
        capturada: DateTime.utc(2026, 11, 2, 14, 0, 5),
      ),
    ]);
    expect(acuse.confirmados, ['p-1']);
  });

  test('sin red lanza SinConexion', () async {
    final api = ApiConductor(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => throw http.ClientException('sin red')),
    );
    expect(() => api.cerrarSesion('tkn', 's-1'), throwsA(isA<SinConexion>()));
  });
}
