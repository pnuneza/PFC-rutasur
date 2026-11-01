// Pantallas nuevas del pasajero: P-00 bienvenida, P-01 con búsqueda, favoritos y
// paradero cercano, P-02 buscar paradero y la estrella de P-03. Sin red ni fondo de mapa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/core/tema.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/pasajero/app_pasajero.dart';
import 'package:rutasur/features/pasajero/controlador_mapa.dart';
import 'package:rutasur/features/pasajero/hoja_llegadas.dart';
import 'package:rutasur/features/pasajero/pantalla_busqueda.dart';

import '../fakes.dart';

const cercaDeLaPlaza = LatLng(-16.4612, -71.5003);

void tamanoTelefono(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

RepositorioFalso repositorioConUnidad() =>
    RepositorioFalso(linea: lineaDePrueba(), unidades: [unidadDePrueba()]);

Future<void> abrirApp(
  WidgetTester tester, {
  required PreferenciasEnMemoria preferencias,
  UbicacionFalsa? ubicacion,
  RepositorioFalso? repositorio,
}) async {
  tamanoTelefono(tester);
  await tester.pumpWidget(AppPasajero(
    repositorio: repositorio ?? repositorioConUnidad(),
    preferencias: preferencias,
    ubicacion: ubicacion ?? UbicacionFalsa(),
    mostrarTeselas: false,
  ));
  await tester.pumpAndSettle();
}

/// Desmonta la app para detener la consulta periódica de unidades.
Future<void> cerrar(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('P-00 Bienvenida', () {
    testWidgets('aparece la primera vez y «Usar mi ubicación» pide el permiso una vez',
        (tester) async {
      final preferencias = PreferenciasEnMemoria();
      final ubicacion = UbicacionFalsa(posicion: cercaDeLaPlaza);
      await abrirApp(tester, preferencias: preferencias, ubicacion: ubicacion);

      expect(find.text('Mira cuándo llega tu bus'), findsOneWidget);
      await tester.tap(find.byKey(const Key('usar-ubicacion')));
      await tester.pumpAndSettle();

      expect(ubicacion.pedidos, 1);
      expect(preferencias.vista, isTrue);
      expect(find.byKey(const Key('barra-busqueda')), findsOneWidget); // ya está en P-01
      await cerrar(tester);
    });

    testWidgets('«Ahora no» entra al mapa sin pedir permisos', (tester) async {
      final preferencias = PreferenciasEnMemoria();
      final ubicacion = UbicacionFalsa();
      await abrirApp(tester, preferencias: preferencias, ubicacion: ubicacion);

      await tester.tap(find.byKey(const Key('ahora-no')));
      await tester.pumpAndSettle();

      expect(ubicacion.pedidos, 0);
      expect(preferencias.vista, isTrue);
      expect(find.byKey(const Key('barra-busqueda')), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('no vuelve a aparecer en las siguientes aperturas', (tester) async {
      await abrirApp(tester, preferencias: PreferenciasEnMemoria()..vista = true);

      expect(find.text('Mira cuándo llega tu bus'), findsNothing);
      expect(find.byKey(const Key('barra-busqueda')), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('P-01 Mapa', () {
    testWidgets('con permiso propone el paradero más cercano y abre sus llegadas (RF-006)',
        (tester) async {
      await abrirApp(
        tester,
        preferencias: PreferenciasEnMemoria()..vista = true,
        ubicacion: UbicacionFalsa(concedido: true, posicion: cercaDeLaPlaza),
      );

      expect(find.byKey(const Key('tarjeta-cercano')), findsOneWidget);
      expect(find.text('Tu paradero más cercano'), findsOneWidget);
      expect(find.textContaining('a 140 m'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ver-llegadas')));
      await tester.pumpAndSettle();
      expect(find.byType(HojaLlegadas), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('«Mi ubicación» sin permiso explica que se puede buscar por nombre',
        (tester) async {
      await abrirApp(
        tester,
        preferencias: PreferenciasEnMemoria()..vista = true,
        ubicacion: UbicacionFalsa(concederAlPedir: false),
      );

      await tester.tap(find.byKey(const Key('mi-ubicacion')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Puedes buscarlo por su nombre'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta-cercano')), findsNothing);
      await cerrar(tester);
    });

    testWidgets('los favoritos aparecen como accesos directos (RF-007)', (tester) async {
      await abrirApp(tester, preferencias: PreferenciasEnMemoria()
        ..vista = true
        ..codigos = ['stp_002']);

      await tester.tap(find.byKey(const Key('chip-stp_002')));
      await tester.pumpAndSettle();

      expect(find.byType(HojaLlegadas), findsOneWidget);
      expect(find.text('Favorito'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('buscar, elegir un resultado y ver sus llegadas (CU-03)', (tester) async {
      await abrirApp(tester, preferencias: PreferenciasEnMemoria()..vista = true);

      await tester.tap(find.byKey(const Key('barra-busqueda')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-busqueda')), 'plaza');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resultado-stp_002')));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaBusqueda), findsNothing);
      expect(find.byType(HojaLlegadas), findsOneWidget);
      expect(find.text('Plaza Characato'), findsWidgets);
      await cerrar(tester);
    });
  });

  group('P-02 Buscar paradero', () {
    Future<(ControladorMapa, RepositorioFalso, PreferenciasEnMemoria)> abrirBusqueda(
      WidgetTester tester, {
      PreferenciasEnMemoria? preferencias,
    }) async {
      tamanoTelefono(tester);
      final repositorio = RepositorioFalso(linea: lineaDePrueba());
      final prefs = preferencias ?? PreferenciasEnMemoria();
      // Solo la ruta: sin consulta periódica de unidades que deje temporizadores pendientes
      final mapa = ControladorMapa(repositorio, preferencias: prefs);
      await mapa.cargarLinea();
      await tester.pumpWidget(MaterialApp(
        theme: temaRutaSur(),
        home: PantallaBusqueda(repositorio: repositorio, mapa: mapa),
      ));
      return (mapa, repositorio, prefs);
    }

    testWidgets('con 1 letra no consulta y muestra la ayuda', (tester) async {
      final (_, repositorio, _) = await abrirBusqueda(tester);

      await tester.enterText(find.byKey(const Key('campo-busqueda')), 'p');
      await tester.pump(const Duration(milliseconds: 350));

      expect(repositorio.busquedas, isEmpty);
      expect(find.textContaining('Escribe al menos 2 letras'), findsOneWidget);
    });

    testWidgets('sin resultados sugiere otra palabra', (tester) async {
      await abrirBusqueda(tester);

      await tester.enterText(find.byKey(const Key('campo-busqueda')), 'xyz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byKey(const Key('mensaje-busqueda')), findsOneWidget);
      expect(find.textContaining('No encontramos paraderos con «xyz»'), findsOneWidget);
    });

    testWidgets('la estrella guarda el favorito y luego aparece sin escribir', (tester) async {
      final (mapa, _, preferencias) = await abrirBusqueda(tester);

      await tester.enterText(find.byKey(const Key('campo-busqueda')), 'plaza');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('1 paradero'), findsOneWidget);

      await tester.tap(find.byKey(const Key('estrella-stp_002')));
      await tester.pump();
      expect(mapa.esFavorito('stp_002'), isTrue);
      expect(preferencias.codigos, ['stp_002']);

      await tester.enterText(find.byKey(const Key('campo-busqueda')), '');
      await tester.pump();
      expect(find.text('Tus favoritos'), findsOneWidget);
      expect(find.byKey(const Key('resultado-stp_002')), findsOneWidget);
    });
  });
}
