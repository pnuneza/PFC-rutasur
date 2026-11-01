// Accesibilidad de las pantallas del pasajero del Módulo 5 (RNF de usabilidad, P06 Tabla 49):
// botones de 48 dp o más con su etiqueta para TalkBack, contraste suficiente y nada cortado
// cuando el pasajero agranda la letra del teléfono (130 % y 200 %).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/core/tema.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/pasajero/app_pasajero.dart';
import 'package:rutasur/features/pasajero/controlador_mapa.dart';
import 'package:rutasur/features/pasajero/hoja_llegadas.dart';
import 'package:rutasur/features/pasajero/pantalla_bienvenida.dart';
import 'package:rutasur/features/pasajero/pantalla_busqueda.dart';

import '../fakes.dart';

const cercaDeLaPlaza = LatLng(-16.4612, -71.5003);

void telefono(WidgetTester tester, {double letra = 1.0}) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = letra;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> cumplePautas(WidgetTester tester) async {
  final semantica = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantica.dispose();
}

Widget enApp(Widget pantalla) => MaterialApp(theme: temaRutaSur(), home: pantalla);

Future<void> abrirBienvenida(WidgetTester tester) => tester.pumpWidget(enApp(
      PantallaBienvenida(alUsarUbicacion: () {}, alOmitir: () {}),
    ));

/// Mapa con la tarjeta del paradero cercano, un favorito y una unidad en circulación.
Future<void> abrirMapaCompleto(WidgetTester tester) async {
  await tester.pumpWidget(AppPasajero(
    repositorio: RepositorioFalso(linea: lineaDePrueba(), unidades: [unidadDePrueba()]),
    preferencias: PreferenciasEnMemoria()
      ..vista = true
      ..codigos = ['stp_002', 'stp_003'],
    ubicacion: UbicacionFalsa(concedido: true, posicion: cercaDeLaPlaza),
    mostrarTeselas: false,
  ));
  await tester.pumpAndSettle();
}

/// P-02 con un resultado y su estrella.
Future<void> abrirBusquedaConResultado(WidgetTester tester) async {
  final repositorio = RepositorioFalso(linea: lineaDePrueba());
  final mapa = ControladorMapa(repositorio, ubicacion: UbicacionFalsa(concedido: true, posicion: cercaDeLaPlaza));
  await mapa.cargarLinea();
  await mapa.actualizarUbicacion();
  await tester.pumpWidget(enApp(PantallaBusqueda(repositorio: repositorio, mapa: mapa)));
  await tester.enterText(find.byKey(const Key('campo-busqueda')), 'plaza');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> abrirLlegadasConEstrella(WidgetTester tester) async {
  await tester.pumpWidget(enApp(Scaffold(
    body: HojaLlegadas(
      repositorio: RepositorioFalso(),
      paradero: paraderosUnicos(lineaDePrueba())[1],
      horario: '05:00 a 21:00',
      esFavorito: true,
      alAlternarFavorito: () async => true,
    ),
  )));
  await tester.pump();
}

Future<void> cerrar(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('Botones, etiquetas y contraste', () {
    testWidgets('P-00 Bienvenida', (tester) async {
      telefono(tester);
      await abrirBienvenida(tester);
      await cumplePautas(tester);
    });

    testWidgets('P-01 Mapa con paradero cercano, favoritos y unidad', (tester) async {
      telefono(tester);
      await abrirMapaCompleto(tester);
      await cumplePautas(tester);
      await cerrar(tester);
    });

    testWidgets('P-02 Buscar paradero con resultado', (tester) async {
      telefono(tester);
      await abrirBusquedaConResultado(tester);
      await cumplePautas(tester);
    });

    testWidgets('P-03 Llegadas con la estrella de favorito', (tester) async {
      telefono(tester);
      await abrirLlegadasConEstrella(tester);
      await cumplePautas(tester);
      await cerrar(tester);
    });
  });

  // Un desborde de texto hace fallar la prueba: Flutter lo informa como error.
  for (final letra in [1.3, 2.0]) {
    final porcentaje = '${(letra * 100).round()} %';
    group('Letra del teléfono al $porcentaje', () {
      testWidgets('P-00 Bienvenida se lee completa y sus botones siguen visibles', (tester) async {
        telefono(tester, letra: letra);
        await abrirBienvenida(tester);
        await tester.scrollUntilVisible(find.byKey(const Key('ahora-no')), 100,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const Key('usar-ubicacion')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('P-01 Mapa completo', (tester) async {
        telefono(tester, letra: letra);
        await abrirMapaCompleto(tester);
        expect(find.byKey(const Key('tarjeta-cercano')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cerrar(tester);
      });

      testWidgets('P-02 Buscar paradero', (tester) async {
        telefono(tester, letra: letra);
        await abrirBusquedaConResultado(tester);
        expect(find.byKey(const Key('resultado-stp_002')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('P-03 Llegadas', (tester) async {
        telefono(tester, letra: letra);
        await abrirLlegadasConEstrella(tester);
        expect(find.byKey(const Key('favorito')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cerrar(tester);
      });
    });
  }
}
