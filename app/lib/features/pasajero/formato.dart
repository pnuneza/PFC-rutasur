/// Textos que ve el pasajero, según las reglas de presentación de P06
/// (Tabla 46 y Tabla 47). Funciones puras, probadas en `test/`.
library;

import '../../domain/modelos.dart';

/// Minutos del ETA, redondeados hacia arriba; «menos de 1» si faltan menos de 60 s.
String minutosEta(int segundos) => segundos < 60 ? 'menos de 1' : '${(segundos / 60).ceil()}';

/// ETA completo, por ejemplo «14 min» o «menos de 1 min».
String textoEta(int segundos) => '${minutosEta(segundos)} min';

/// Antigüedad del dato, en segundos hasta los dos minutos y en minutos después.
String textoAntiguedad(int segundos) {
  if (segundos < 120) return 'hace $segundos s';
  return 'hace ${segundos ~/ 60} min';
}

/// Distancia legible: «850 m» o «6,8 km».
String textoDistancia(int metros) {
  if (metros < 1000) return '$metros m';
  return '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Estado del dato con su antigüedad, por ejemplo «No confiable · hace 95 s» (Tabla 47).
String textoFrescura(Frescura frescura, int antiguedadS) =>
    '${frescura.etiqueta} · ${textoAntiguedad(antiguedadS)}';

/// Destino con verbo, para no depender solo del color (P06, P-04 #2).
String textoDestino(String destino) => 'Va a $destino';

/// Sentido con las palabras de los usuarios de la ruta (chat de la línea LB):
/// «bajada» hacia el Centro y «subida» hacia el ramal.
/// Lo usan también las pantallas del conductor (C-02 y C-03), para que ambos lean lo mismo.
String textoSentido(Ramal? ramal, Sentido sentido) => sentido == Sentido.ida
    ? 'Bajada · hacia el Centro'
    : 'Subida · hacia ${ramal?.nombre ?? 'el ramal'}';

/// Distancia a pie redondeada, para el paradero más cercano: «a 350 m», «a 1,2 km».
String textoDistanciaAPie(double metros) {
  if (metros < 1000) return 'a ${(metros / 10).round() * 10} m';
  return 'a ${textoDistancia(metros.round())}';
}
