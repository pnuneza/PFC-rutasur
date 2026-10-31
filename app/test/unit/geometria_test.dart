import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasur/domain/geometria.dart';

import '../fakes.dart';

void main() {
  test('un milésimo de grado de latitud mide unos 111 m', () {
    expect(distanciaM(const LatLng(-16.45, -71.5), const LatLng(-16.451, -71.5)), closeTo(111.2, 0.2));
  });

  group('subtrazado', () {
    const recta = [LatLng(-16.45, -71.5), LatLng(-16.46, -71.5), LatLng(-16.47, -71.5)];

    test('recorta entre dos distancias interpolando los extremos', () {
      final parte = subtrazado(recta, 500, 1500);
      expect(distanciaM(recta.first, parte.first), closeTo(500, 1));
      expect(distanciaM(recta.first, parte.last), closeTo(1500, 1));
      // conserva el vértice intermedio que queda dentro del rango
      expect(parte, contains(recta[1]));
    });

    test('con un rango vacío no devuelve nada', () {
      expect(subtrazado(recta, 800, 800), isEmpty);
      expect(subtrazado(const [LatLng(0, 0)], 0, 10), isEmpty);
    });
  });

  test('el tramo común va del primer al último paradero común (RF-001)', () {
    final tramo = tramoComun(lineaDePrueba())!;
    // En la línea de prueba el tramo común empieza en el paradero 2 y termina en el 3
    expect(tramo.first.latitude, closeTo(-16.46, 0.0001));
    expect(tramo.last.latitude, closeTo(-16.47, 0.0001));
  });
}
