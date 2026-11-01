import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rutasur/data/api_rutasur.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/repositorio.dart';

/// Respuesta JSON en UTF-8, como la que envía el servidor.
http.Response respuestaJson(Object cuerpo, int estado) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), estado);

void main() {
  test('pide /api/v1/vehicles y lee el contenido de «data»', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((peticion) async {
        expect(peticion.url.toString(), 'http://servidor/api/v1/vehicles');
        return respuestaJson({
          'data': [
            {
              'vehicle_label': '12',
              'branch': 'CERRILLO',
              'direction': 'IDA',
              'destination': 'Centro (2 de Mayo)',
              'lat': -16.45,
              'lon': -71.5,
              'heading': 315,
              'position_age_s': 4,
              'freshness': 'VIGENTE',
            },
          ],
          'meta': {'timestamp': '2026-10-14T15:00:00Z', 'count': 1},
        }, 200);
      }),
    );

    final unidades = await api.unidadesActivas();

    expect(unidades.single.etiqueta, '12');
    expect(unidades.single.ramal, Ramal.cerrillo);
  });

  test('pide las llegadas del paradero indicado', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((peticion) async {
        expect(peticion.url.path, '/api/v1/stops/stp_001/arrivals');
        return respuestaJson({'data': <Object>[], 'meta': {'timestamp': 'x', 'count': 0}}, 200);
      }),
    );
    expect(await api.llegadas('stp_001'), isEmpty);
  });

  test('busca paraderos con el texto codificado en la consulta (RF-005)', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((peticion) async {
        expect(peticion.url.path, '/api/v1/stops');
        expect(peticion.url.queryParameters['q'], 'plaza characato');
        return respuestaJson({
          'data': [
            {
              'code': 'stp_010',
              'name': 'Plaza de Characato',
              'reference': null,
              'lat': -16.469,
              'lon': -71.4837,
              'branches': ['MOLLEBAYA'],
            },
          ],
          'meta': {'timestamp': 'x', 'count': 1},
        }, 200);
      }),
    );
    final encontrados = await api.buscarParaderos('plaza characato');
    expect(encontrados.single.codigo, 'stp_010');
    expect(encontrados.single.ramales, {Ramal.mollebaya});
  });

  test('un error del servicio conserva su código estable (P06, Tabla 55)', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => respuestaJson({
            'error': {'code': 'NOT_FOUND', 'message': 'El paradero stp_999 no existe o está inactivo'},
          }, 404)),
    );

    await expectLater(
      api.llegadas('stp_999'),
      throwsA(isA<ErrorServicio>()
          .having((e) => e.estado, 'estado', 404)
          .having((e) => e.codigo, 'código', 'NOT_FOUND')
          .having((e) => e.mensaje, 'mensaje', contains('stp_999'))),
    );
  });

  test('un error sin cuerpo JSON (por ejemplo, de un proxy) no rompe la app', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => http.Response('<html>502 Bad Gateway</html>', 502)),
    );
    await expectLater(
      api.unidadesActivas(),
      throwsA(isA<ErrorServicio>().having((e) => e.codigo, 'código', 'HTTP_ERROR')),
    );
  });

  test('sin red se informa como «sin conexión»', () async {
    final api = ApiRutaSur(
      urlBase: 'http://servidor',
      cliente: MockClient((_) async => throw http.ClientException('sin red')),
    );
    await expectLater(api.unidadesActivas(), throwsA(isA<SinConexion>()));
  });
}
