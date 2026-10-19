import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/modelos.dart';

import '../fakes.dart';

void main() {
  group('Frescura del dato (RN-005: 30 s y 90 s, igual que el servidor)', () {
    test('límites exactos', () {
      expect(Frescura.desdeAntiguedad(0), Frescura.vigente);
      expect(Frescura.desdeAntiguedad(30), Frescura.vigente);
      expect(Frescura.desdeAntiguedad(31), Frescura.demorado);
      expect(Frescura.desdeAntiguedad(90), Frescura.demorado);
      expect(Frescura.desdeAntiguedad(91), Frescura.noConfiable);
    });
  });

  group('Lectura de las respuestas de la API (contrato de P06, Tablas 50 y 51)', () {
    test('unidad activa', () {
      final u = UnidadActiva.fromJson({
        'vehicle_label': '12',
        'branch': 'CERRILLO',
        'direction': 'IDA',
        'destination': 'Centro (2 de Mayo)',
        'lat': -16.4521,
        'lon': -71.493,
        'heading': 140,
        'position_age_s': 12,
        'freshness': 'VIGENTE',
      });
      expect(u.etiqueta, '12');
      expect(u.ramal, Ramal.cerrillo);
      expect(u.sentido, Sentido.ida);
      expect(u.ubicacion.latitude, -16.4521);
      expect(u.rumbo, 140);
      expect(u.frescura, Frescura.vigente);
    });

    test('unidad sin rumbo conocido', () {
      final u = UnidadActiva.fromJson({
        'vehicle_label': '07',
        'branch': 'MOLLEBAYA',
        'direction': 'VUELTA',
        'destination': 'Mollebaya',
        'lat': -16.45,
        'lon': -71.5,
        'heading': null,
        'position_age_s': 200,
        'freshness': 'NO_CONFIABLE',
      });
      expect(u.rumbo, isNull);
      expect(u.frescura, Frescura.noConfiable);
    });

    test('llegada', () {
      final l = Llegada.fromJson({
        'vehicle_label': '12',
        'branch': 'CERRILLO',
        'destination': 'Centro (2 de Mayo)',
        'eta_seconds': 781,
        'distance_m': 6825,
        'position_age_s': 9,
        'reliable': true,
      });
      expect(l.etaS, 781);
      expect(l.distanciaM, 6825);
      expect(l.frescura, Frescura.vigente);
    });

    test('línea con variantes, trazado como pares [lat, lon] y paraderos', () {
      final linea = Linea.fromJson({
        'code': 'LB',
        'name': 'Línea LB — Characato',
        'service_start': '05:00',
        'service_end': '21:00',
        'updated_at': '2026-10-14T15:00:00Z',
        'variants': [
          {
            'branch': 'MOLLEBAYA',
            'direction': 'IDA',
            'destination': 'Centro (2 de Mayo)',
            'length_m': 12449.0,
            'shape': [
              [-16.492, -71.47],
              [-16.4, -71.536],
            ],
            'stops': [
              {
                'code': 'stp_006',
                'name': 'Mollebaya (final)',
                'reference': null,
                'lat': -16.4918,
                'lon': -71.4702,
                'order': 1,
                'distance_from_start_m': 30.7,
                'shared_trunk': false,
              },
            ],
          },
        ],
      });
      expect(linea.horario, '05:00 a 21:00');
      final v = linea.variantes.single;
      expect(v.ramal, Ramal.mollebaya);
      expect(v.trazado.first.latitude, -16.492);
      expect(v.trazado.first.longitude, -71.47);
      expect(v.paraderos.single.codigo, 'stp_006');
    });

    test('un ramal desconocido se rechaza', () {
      expect(() => Ramal.desdeApi('TAXI'), throwsFormatException);
    });
  });

  test('un paradero compartido por dos variantes se dibuja una sola vez', () {
    final base = lineaDePrueba();
    final otra = Variante(
      ramal: Ramal.cerrillo,
      sentido: Sentido.ida,
      destino: 'Centro (2 de Mayo)',
      longitudM: 1,
      trazado: base.variantes.first.trazado,
      paraderos: base.variantes.first.paraderos.where((p) => p.tramoComun).toList(),
    );
    final linea = Linea(
      codigo: 'LB',
      nombre: 'x',
      horaInicio: '05:00',
      horaFin: '21:00',
      variantes: [...base.variantes, otra],
    );

    final paraderos = paraderosUnicos(linea);

    expect(paraderos.map((p) => p.codigo), unorderedEquals(['stp_001', 'stp_002', 'stp_003']));
    final plaza = paraderos.firstWhere((p) => p.codigo == 'stp_002');
    expect(plaza.ramales, {Ramal.mollebaya, Ramal.cerrillo});
    final inicio = paraderos.firstWhere((p) => p.codigo == 'stp_001');
    expect(inicio.ramales, {Ramal.mollebaya});
  });
}
