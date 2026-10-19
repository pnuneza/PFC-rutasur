// Pruebas de widgets de la pantalla P-03 (llegadas al paradero), sin red ni mapa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/core/tema.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/pasajero/hoja_llegadas.dart';
import 'package:rutasur/features/pasajero/hoja_unidad.dart';

import 'fakes.dart';

const plaza = ParaderoEnMapa(
  codigo: 'stp_004',
  nombre: 'Plaza Characato',
  referencia: 'Frente a la iglesia',
  ubicacion: LatLng(-16.4688, -71.4902),
  tramoComun: true,
  ramales: {Ramal.mollebaya, Ramal.cerrillo},
);

Widget enApp(Widget hijo) => MaterialApp(theme: temaRutaSur(), home: Scaffold(body: hijo));

Future<void> abrirHoja(WidgetTester tester, RepositorioFalso repositorio) async {
  await tester.pumpWidget(enApp(
    HojaLlegadas(repositorio: repositorio, paradero: plaza, horario: '05:00 a 21:00'),
  ));
  await tester.pump(); // deja terminar la consulta
}

void main() {
  testWidgets('muestra las llegadas con ETA en minutos, destino y estado del dato (CU-01)',
      (tester) async {
    final repositorio = RepositorioFalso(llegadasPorParadero: {
      'stp_004': const [
        Llegada(
          etiqueta: '12',
          ramal: Ramal.cerrillo,
          destino: 'Centro (2 de Mayo)',
          etaS: 781,
          distanciaM: 6825,
          antiguedadS: 9,
        ),
        Llegada(
          etiqueta: '07',
          ramal: Ramal.mollebaya,
          destino: 'Centro (2 de Mayo)',
          etaS: 964,
          distanciaM: 8567,
          antiguedadS: 95,
        ),
      ],
    });

    await abrirHoja(tester, repositorio);

    expect(find.text('Plaza Characato'), findsOneWidget);
    expect(find.text('Unidad 12'), findsOneWidget);
    expect(find.text('14'), findsOneWidget); // 781 s → 14 min (redondeo hacia arriba)
    expect(find.text('Vigente · hace 9 s'), findsOneWidget);
    expect(find.text('No confiable · hace 95 s'), findsOneWidget); // texto de la Tabla 47
    expect(find.text('Va a Centro (2 de Mayo)'), findsNWidgets(2));
    expect(find.text('A 6,8 km del paradero'), findsOneWidget);
  });

  testWidgets('sin llegadas lo dice con claridad y muestra el horario referencial',
      (tester) async {
    await abrirHoja(tester, RepositorioFalso());

    expect(find.text('No hay unidades que lleguen en los próximos 60 minutos.'), findsOneWidget);
    expect(find.textContaining('05:00 a 21:00'), findsOneWidget);
  });

  testWidgets('sin conexión muestra el aviso en lugar de fallar', (tester) async {
    final repositorio = RepositorioFalso()..fallo = const SinConexion();

    await abrirHoja(tester, repositorio);

    expect(find.textContaining('No hay conexión a internet'), findsOneWidget);
  });

  testWidgets('el detalle de la unidad explica destino, sentido y estado (P-04)', (tester) async {
    await tester.pumpWidget(enApp(HojaUnidad(unidad: unidadDePrueba(antiguedadS: 45))));

    expect(find.text('Unidad 07'), findsOneWidget);
    expect(find.text('Va a Centro (2 de Mayo)'), findsOneWidget);
    expect(find.text('Hacia el Centro'), findsOneWidget);
    expect(find.text('Demorado · hace 45 s'), findsOneWidget);
  });
}
