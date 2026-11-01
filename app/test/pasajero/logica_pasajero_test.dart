// Paradero cercano, favoritos, búsqueda y textos del pasajero (RF-005, RF-006, RF-007).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/pasajero.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/pasajero/controlador_busqueda.dart';
import 'package:rutasur/features/pasajero/controlador_mapa.dart';
import 'package:rutasur/features/pasajero/formato.dart';

import '../fakes.dart';

/// Cerca del segundo paradero de la línea de prueba (Plaza Characato, -16.46).
const cercaDeLaPlaza = LatLng(-16.4612, -71.5003);

ControladorMapa controladorCon({PreferenciasEnMemoria? preferencias, UbicacionFalsa? ubicacion}) =>
    ControladorMapa(
      RepositorioFalso(linea: lineaDePrueba(), unidades: [unidadDePrueba()]),
      intervalo: const Duration(hours: 1),
      preferencias: preferencias,
      ubicacion: ubicacion,
    );

void main() {
  group('Paradero más cercano (RF-006)', () {
    test('elige el de menor distancia y la calcula en el teléfono', () {
      final cercano = paraderoMasCercano(paraderosUnicos(lineaDePrueba()), cercaDeLaPlaza)!;
      expect(cercano.paradero.nombre, 'Plaza Characato');
      expect(cercano.distanciaM, closeTo(150, 20));
    });

    test('sin paraderos no propone nada', () {
      expect(paraderoMasCercano(const [], cercaDeLaPlaza), isNull);
    });

    test('con el permiso ya concedido se propone al abrir el mapa', () async {
      final c = controladorCon(ubicacion: UbicacionFalsa(concedido: true, posicion: cercaDeLaPlaza));
      addTearDown(c.dispose);
      await c.iniciar();
      await Future<void>.delayed(Duration.zero);
      expect(c.cercano?.paradero.nombre, 'Plaza Characato');
      expect(c.posicionUsuario, cercaDeLaPlaza);
    });

    test('«Mi ubicación» pide el permiso solo si falta', () async {
      final ubicacion = UbicacionFalsa(posicion: cercaDeLaPlaza);
      final c = controladorCon(ubicacion: ubicacion);
      addTearDown(c.dispose);
      await c.iniciar();
      expect(c.cercano, isNull);

      expect(await c.usarMiUbicacion(), cercaDeLaPlaza);
      expect(c.cercano?.paradero.nombre, 'Plaza Characato');
      await c.usarMiUbicacion();
      expect(ubicacion.pedidos, 1);
    });

    test('si el pasajero niega el permiso, no se propone paradero', () async {
      final c = controladorCon(ubicacion: UbicacionFalsa(concederAlPedir: false, posicion: cercaDeLaPlaza));
      addTearDown(c.dispose);
      await c.iniciar();
      expect(await c.usarMiUbicacion(), isNull);
      expect(c.cercano, isNull);
      expect(c.ubicacionConcedida, isFalse);
    });
  });

  group('Favoritos (RF-007)', () {
    test('se guardan en el teléfono y se recuperan al volver a abrir', () async {
      final preferencias = PreferenciasEnMemoria();
      final c = controladorCon(preferencias: preferencias);
      addTearDown(c.dispose);
      await c.iniciar();
      await c.alternarFavorito('stp_002');
      expect(preferencias.codigos, ['stp_002']);
      expect(c.favoritos.single.nombre, 'Plaza Characato');

      final otraVez = controladorCon(preferencias: preferencias);
      addTearDown(otraVez.dispose);
      await otraVez.iniciar();
      expect(otraVez.esFavorito('stp_002'), isTrue);
    });

    test('tocar de nuevo la estrella lo quita', () async {
      final c = controladorCon(preferencias: PreferenciasEnMemoria());
      addTearDown(c.dispose);
      await c.iniciar();
      await c.alternarFavorito('stp_002');
      await c.alternarFavorito('stp_002');
      expect(c.favoritos, isEmpty);
    });

    test('como máximo 10', () async {
      final preferencias = PreferenciasEnMemoria();
      final c = controladorCon(preferencias: preferencias);
      addTearDown(c.dispose);
      await c.iniciar();
      c.codigosFavoritos = [for (var i = 0; i < 10; i++) 'stp_9$i'];
      expect(await c.alternarFavorito('stp_001'), isFalse);
      expect(c.codigosFavoritos, hasLength(10));
      expect(preferencias.codigos, isEmpty); // no se guardó nada
    });

    test('olvida los favoritos de paraderos que ya no están en la ruta', () async {
      final preferencias = PreferenciasEnMemoria()..codigos = ['stp_999', 'stp_003'];
      final c = controladorCon(preferencias: preferencias);
      addTearDown(c.dispose);
      await c.iniciar();
      expect(c.codigosFavoritos, ['stp_003']);
    });
  });

  group('Búsqueda (RF-005)', () {
    test('no consulta con menos de 2 letras', () async {
      final repo = RepositorioFalso(linea: lineaDePrueba());
      final b = ControladorBusqueda(repo, espera: Duration.zero);
      addTearDown(b.dispose);
      b.escribir('p');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(repo.busquedas, isEmpty);
      expect(b.activa, isFalse);
    });

    test('espera a que se deje de escribir y muestra los resultados', () async {
      final repo = RepositorioFalso(linea: lineaDePrueba());
      final b = ControladorBusqueda(repo, espera: const Duration(milliseconds: 20));
      addTearDown(b.dispose);
      b
        ..escribir('pl')
        ..escribir('pla')
        ..escribir('plaza ');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repo.busquedas, ['plaza']);
      expect(b.resultados.single.nombre, 'Plaza Characato');
      expect(b.buscando, isFalse);
    });

    test('sin conexión lo dice', () async {
      final repo = RepositorioFalso(linea: lineaDePrueba())..fallo = const SinConexion();
      final b = ControladorBusqueda(repo, espera: Duration.zero);
      addTearDown(b.dispose);
      b.escribir('plaza');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(b.error, contains('No hay conexión'));
    });
  });

  test('lee un resultado de GET /stops con sus ramales', () {
    final p = ParaderoEncontrado.fromJson({
      'code': 'stp_010',
      'name': 'Plaza de Characato (Calle Yumina)',
      'reference': 'Calle Yumina y Plaza de Characato',
      'lat': -16.469,
      'lon': -71.4837,
      'branches': ['MOLLEBAYA', 'CERRILLO'],
    });
    expect(p.ramales, {Ramal.mollebaya, Ramal.cerrillo});
    expect(p.comoParaderoEnMapa().tramoComun, isTrue);
  });

  test('textos de sentido y distancia a pie', () {
    expect(textoSentido(Ramal.mollebaya, Sentido.ida), 'Bajada · hacia el Centro');
    expect(textoSentido(Ramal.cerrillo, Sentido.vuelta), 'Subida · hacia Cerrillo');
    expect(textoDistanciaAPie(347), 'a 350 m');
    expect(textoDistanciaAPie(1240), 'a 1,2 km');
  });
}
