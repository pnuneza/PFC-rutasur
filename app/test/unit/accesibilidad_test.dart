// D-07 (leyenda según los ramales activos) y D-10 (texto informativo de 16 sp o más).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/core/tema.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/pasajero/widgets/paneles.dart';

import '../fakes.dart';

/// La línea de prueba con una segunda variante del ramal indicado, mismo trazado.
Linea conOtroRamal(Ramal ramal) {
  final base = lineaDePrueba();
  final v = base.variantes.first;
  return Linea(
    codigo: base.codigo,
    nombre: base.nombre,
    horaInicio: base.horaInicio,
    horaFin: base.horaFin,
    variantes: [
      v,
      Variante(
        ramal: ramal,
        sentido: Sentido.ida,
        destino: v.destino,
        longitudM: v.longitudM,
        trazado: v.trazado,
        paraderos: v.paraderos,
      ),
    ],
  );
}

void main() {
  group('Leyenda de la ayuda (D-07)', () {
    test('con un solo ramal activo no muestra el otro ni el tramo común', () {
      final textos = entradasLeyenda(lineaDePrueba()).map((e) => e.texto);
      expect(textos, ['Ramal Mollebaya']);
    });

    test('con ambos ramales muestra los dos y el tramo común', () {
      final textos = entradasLeyenda(conOtroRamal(Ramal.cerrillo)).map((e) => e.texto);
      expect(textos, ['Ramal Mollebaya', 'Ramal Cerrillo', 'Tramo común hasta 2 de Mayo']);
    });

    test('cada ramal se muestra con su color', () {
      final leyenda = entradasLeyenda(conOtroRamal(Ramal.cerrillo));
      expect(leyenda[0].color, ColoresRutaSur.mollebaya);
      expect(leyenda[1].color, ColoresRutaSur.cerrillo);
    });

    test('sin línea cargada la leyenda queda vacía', () {
      expect(entradasLeyenda(null), isEmpty);
    });
  });

  group('Texto mínimo de 16 sp (D-10)', () {
    testWidgets('todos los estilos de cuerpo, etiquetas y títulos miden 16 sp o más',
        (tester) async {
      // Se mide el tema ya aplicado, con los tamaños que Flutter agrega al pintar
      late TextTheme t;
      await tester.pumpWidget(MaterialApp(
        theme: temaRutaSur(),
        home: Builder(builder: (context) {
          t = Theme.of(context).textTheme;
          return const SizedBox();
        }),
      ));
      final estilos = {
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
        'titleSmall': t.titleSmall,
        'titleMedium': t.titleMedium,
        'titleLarge': t.titleLarge,
      };
      estilos.forEach((nombre, estilo) {
        expect(estilo?.fontSize, greaterThanOrEqualTo(tamanoTextoMinimo), reason: nombre);
      });
      expect(t.titleLarge?.fontSize, 22, reason: 'los títulos grandes no se achican');
    });

    test('no achica los estilos que ya eran grandes', () {
      const base = TextTheme(titleLarge: TextStyle(fontSize: 22));
      expect(conTextoMinimo(base).titleLarge?.fontSize, 22);
    });
  });
}
