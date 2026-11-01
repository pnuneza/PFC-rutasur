// 0.6.1: mapa más claro tras la prueba con usuario del 01/11/2026.
// - Con el mapa alejado solo se ven los paraderos principales, los favoritos y el más cercano.
// - El pasajero elige ver la bajada, la subida o ambos, y la app lo recuerda.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/core/tema.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/pasajero/app_pasajero.dart';
import 'package:rutasur/features/pasajero/controlador_mapa.dart';
import 'package:rutasur/features/pasajero/widgets/mapa_ruta.dart';
import 'package:rutasur/features/pasajero/widgets/marcadores.dart';

import '../fakes.dart';

const _trazadoIda = [LatLng(-16.40, -71.50), LatLng(-16.45, -71.50), LatLng(-16.50, -71.50)];

ParaderoDeVariante _p(String codigo, double lat, int orden, {bool principal = false}) => ParaderoDeVariante(
      codigo: codigo,
      nombre: 'Paradero $codigo',
      referencia: null,
      ubicacion: LatLng(lat, -71.5),
      orden: orden,
      distanciaDesdeInicioM: (lat + 16.40).abs() * 111195,
      tramoComun: false,
      principal: principal,
    );

/// Línea de 11 km con bajada (IDA) y subida (VUELTA); en cada una, los extremos son principales.
Linea lineaConSentidos() => Linea(
      codigo: 'LB',
      nombre: 'Línea de prueba',
      horaInicio: '05:00',
      horaFin: '21:00',
      variantes: [
        Variante(
          ramal: Ramal.mollebaya,
          sentido: Sentido.ida,
          destino: 'Centro (2 de Mayo)',
          longitudM: 11119,
          trazado: _trazadoIda,
          paraderos: [
            _p('stp_001', -16.40, 1, principal: true),
            _p('stp_002', -16.43, 2),
            _p('stp_003', -16.46, 3),
            _p('stp_004', -16.50, 4, principal: true),
          ],
        ),
        Variante(
          ramal: Ramal.mollebaya,
          sentido: Sentido.vuelta,
          destino: 'Mollebaya',
          longitudM: 11119,
          trazado: _trazadoIda.reversed.toList(),
          paraderos: [
            _p('stp_011', -16.4999, 1, principal: true),
            _p('stp_012', -16.4401, 2),
            _p('stp_013', -16.4001, 3, principal: true),
          ],
        ),
      ],
    );

UnidadActiva unidad(String etiqueta, Sentido sentido) => UnidadActiva(
      etiqueta: etiqueta,
      ramal: Ramal.mollebaya,
      sentido: sentido,
      destino: sentido == Sentido.ida ? 'Centro (2 de Mayo)' : 'Mollebaya',
      ubicacion: const LatLng(-16.45, -71.5),
      rumbo: 180,
      antiguedadS: 10,
    );

Finder marcador(String codigo) => find.byKey(ValueKey('marcador-$codigo'));

void telefono(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('Datos de la ruta', () {
    test('cada paradero del mapa sabe sus sentidos y si es principal', () {
      final porCodigo = {for (final p in paraderosUnicos(lineaConSentidos())) p.codigo: p};
      expect(porCodigo['stp_001']!.sentidos, {Sentido.ida});
      expect(porCodigo['stp_001']!.principal, isTrue);
      expect(porCodigo['stp_002']!.principal, isFalse);
      expect(porCodigo['stp_012']!.enSentido(Sentido.ida), isFalse);
      expect(porCodigo['stp_012']!.enSentido(null), isTrue);
    });

    test('un servidor anterior a la 0.6.1 no envía «main»: nada es principal', () {
      final p = ParaderoDeVariante.fromJson(const {
        'code': 'stp_001',
        'name': 'Santa Ana',
        'reference': null,
        'lat': -16.4,
        'lon': -71.5,
        'order': 1,
        'distance_from_start_m': 0,
        'shared_trunk': false,
      });
      expect(p.principal, isFalse);
    });

    test('soloSentido deja solo las variantes de ese sentido', () {
      final l = lineaConSentidos();
      expect(l.soloSentido(Sentido.vuelta).variantes.single.destino, 'Mollebaya');
      expect(l.soloSentido(null).variantes, hasLength(2));
    });
  });

  group('Filtro de sentido en el controlador', () {
    ControladorMapa controlador(PreferenciasEnMemoria preferencias) => ControladorMapa(
          RepositorioFalso(
            linea: lineaConSentidos(),
            unidades: [unidad('07', Sentido.ida), unidad('12', Sentido.vuelta)],
          ),
          intervalo: const Duration(hours: 1),
          preferencias: preferencias,
          ubicacion: UbicacionFalsa(concedido: true, posicion: const LatLng(-16.44, -71.5003)),
        );

    test('la bajada muestra solo sus paraderos y buses, y propone su paradero más cercano', () async {
      final preferencias = PreferenciasEnMemoria();
      final c = controlador(preferencias);
      addTearDown(c.dispose);
      await c.iniciar();
      await c.usarMiUbicacion();
      expect(c.cercano!.paradero.codigo, 'stp_012'); // con ambos sentidos, el de la subida

      await c.elegirSentido(Sentido.ida);
      expect(c.unidadesVisibles.map((u) => u.etiqueta), ['07']);
      expect(c.paraderosVisibles.map((p) => p.codigo), ['stp_001', 'stp_002', 'stp_003', 'stp_004']);
      expect(c.lineaVisible!.variantes.single.sentido, Sentido.ida);
      expect(c.cercano!.paradero.codigo, 'stp_002');
      expect(preferencias.sentido, Sentido.ida);
    });

    test('la elección se recuerda al volver a abrir la app', () async {
      final c = controlador(PreferenciasEnMemoria()..sentido = Sentido.vuelta);
      addTearDown(c.dispose);
      await c.iniciar();
      expect(c.sentido, Sentido.vuelta);
      expect(c.unidadesVisibles.map((u) => u.etiqueta), ['12']);
    });
  });

  group('Paraderos según el zoom', () {
    Future<MapController> abrirMapa(WidgetTester tester, {Set<String> siempre = const {}}) async {
      telefono(tester);
      final mapa = MapController();
      final linea = lineaConSentidos();
      await tester.pumpWidget(MaterialApp(
        theme: temaRutaSur(),
        home: Scaffold(
          body: MapaRuta(
            linea: linea,
            paraderos: paraderosUnicos(linea),
            unidades: const [],
            atenuarUnidades: false,
            alTocarParadero: (_) {},
            alTocarUnidad: (_) {},
            controlador: mapa,
            mostrarTeselas: false,
            siempreVisibles: siempre,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return mapa;
    }

    testWidgets('con la ruta completa en pantalla solo se ven los principales', (tester) async {
      final mapa = await abrirMapa(tester);
      expect(mapa.camera.zoom, lessThan(zoomTodosLosParaderos));
      expect(marcador('stp_001'), findsOneWidget);
      expect(marcador('stp_004'), findsOneWidget);
      expect(marcador('stp_002'), findsNothing);
      expect(marcador('stp_012'), findsNothing);
    });

    testWidgets('al acercarse aparecen todos', (tester) async {
      final mapa = await abrirMapa(tester);
      mapa.move(const LatLng(-16.44, -71.5), 15);
      await tester.pumpAndSettle();
      expect(marcador('stp_012'), findsOneWidget);
      expect(find.byType(MarcadorParadero), findsWidgets);
    });

    testWidgets('un favorito o el más cercano se ve aunque el mapa esté alejado', (tester) async {
      await abrirMapa(tester, siempre: {'stp_003'});
      expect(marcador('stp_003'), findsOneWidget);
      expect(marcador('stp_002'), findsNothing);
    });
  });

  group('Filtro de sentido en P-01', () {
    testWidgets('elegir «Subida» oculta los buses de bajada y se recuerda', (tester) async {
      telefono(tester);
      final preferencias = PreferenciasEnMemoria()..vista = true;
      await tester.pumpWidget(AppPasajero(
        repositorio: RepositorioFalso(
          linea: lineaConSentidos(),
          unidades: [unidad('07', Sentido.ida), unidad('12', Sentido.vuelta)],
        ),
        preferencias: preferencias,
        mostrarTeselas: false,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(MarcadorUnidad), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('sentido-subida')));
      await tester.pumpAndSettle();
      expect(find.byType(MarcadorUnidad), findsOneWidget);
      expect(find.textContaining('12 →'), findsOneWidget);
      expect(preferencias.sentido, Sentido.vuelta);

      await tester.tap(find.byKey(const Key('sentido-ambos')));
      await tester.pumpAndSettle();
      expect(find.byType(MarcadorUnidad), findsNWidgets(2));
      expect(preferencias.sentido, isNull);
      await tester.pumpWidget(const SizedBox()); // detiene la consulta periódica
    });
  });
}
