import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/features/pasajero/formato.dart';

void main() {
  group('ETA en minutos (P06, P-03 #4: se redondea hacia arriba)', () {
    test('menos de 60 s se muestra como «menos de 1 min»', () {
      expect(textoEta(0), 'menos de 1 min');
      expect(textoEta(59), 'menos de 1 min');
    });

    test('desde 60 s se redondea hacia arriba', () {
      expect(textoEta(60), '1 min');
      expect(textoEta(61), '2 min');
      expect(textoEta(781), '14 min');
      expect(textoEta(3600), '60 min');
    });
  });

  group('Antigüedad del dato', () {
    test('en segundos hasta los dos minutos', () {
      expect(textoAntiguedad(9), 'hace 9 s');
      expect(textoAntiguedad(95), 'hace 95 s');
      expect(textoAntiguedad(119), 'hace 119 s');
    });

    test('en minutos después', () {
      expect(textoAntiguedad(120), 'hace 2 min');
      expect(textoAntiguedad(2199), 'hace 36 min');
    });
  });

  group('Distancia', () {
    test('en metros por debajo de un kilómetro', () {
      expect(textoDistancia(850), '850 m');
    });

    test('en kilómetros con un decimal y coma', () {
      expect(textoDistancia(6825), '6,8 km');
      expect(textoDistancia(1000), '1,0 km');
    });
  });

  test('mensaje de dato no confiable igual al de la Tabla 47 de P06', () {
    expect(textoFrescura(Frescura.noConfiable, 95), 'No confiable · hace 95 s');
  });

  test('el destino se escribe con verbo, no solo con color', () {
    expect(textoDestino('Mollebaya'), 'Va a Mollebaya');
  });
}
