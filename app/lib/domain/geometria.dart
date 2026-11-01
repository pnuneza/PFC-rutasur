/// Cálculos geográficos para dibujar la ruta. Funciones puras, sin Flutter.
library;

import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'modelos.dart';

const double _radioTerrestreM = 6371008.8;

/// Distancia en metros entre dos puntos (fórmula del semiverseno).
double distanciaM(LatLng a, LatLng b) {
  double rad(double grados) => grados * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h = pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
  return 2 * _radioTerrestreM * asin(sqrt(h));
}

LatLng _interpolar(LatLng a, LatLng b, double t) => LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );

/// Parte de un trazado comprendida entre dos distancias medidas desde su inicio.
List<LatLng> subtrazado(List<LatLng> trazado, double desdeM, double hastaM) {
  if (trazado.length < 2 || hastaM <= desdeM) return const [];

  final resultado = <LatLng>[];
  var acumulado = 0.0;
  for (var i = 0; i < trazado.length - 1; i++) {
    final a = trazado[i];
    final b = trazado[i + 1];
    final tramo = distanciaM(a, b);
    final inicio = acumulado;
    final fin = acumulado + tramo;
    acumulado = fin;

    if (tramo == 0 || fin < desdeM) continue;
    if (inicio > hastaM) break;

    if (resultado.isEmpty) {
      resultado.add(_interpolar(a, b, min(max((desdeM - inicio) / tramo, 0.0), 1.0)));
    }
    if (fin <= hastaM) {
      resultado.add(b);
    } else {
      resultado.add(_interpolar(a, b, min(max((hastaM - inicio) / tramo, 0.0), 1.0)));
      break;
    }
  }
  return resultado;
}

/// Trazado del tramo común a los dos ramales (RF-001: se distingue en el mapa).
///
/// Se obtiene del propio dato: es la parte de una variante comprendida entre su
/// primer y su último paradero marcado como «tramo común». Devuelve null si la
/// ruta no tiene al menos dos paraderos comunes.
List<LatLng>? tramoComun(Linea linea) {
  for (final variante in linea.variantes) {
    final comunes = variante.paraderos.where((p) => p.tramoComun).toList();
    if (comunes.length < 2) continue;
    final distancias = comunes.map((p) => p.distanciaDesdeInicioM);
    final tramo = subtrazado(variante.trazado, distancias.reduce(min), distancias.reduce(max));
    if (tramo.length >= 2) return tramo;
  }
  return null;
}

/// Distancia en metros de un punto al trazado más cercano (RN-003 en el formulario A-03a).
///
/// Proyecta sobre cada tramo en un plano local; para tramos de pocos cientos de metros
/// el error es de centímetros. El servidor vuelve a validar con PostGIS.
double distanciaAlTrazadoM(LatLng punto, List<LatLng> trazado) {
  if (trazado.isEmpty) return double.infinity;
  if (trazado.length == 1) return distanciaM(punto, trazado.first);
  final k = cos(punto.latitude * pi / 180);
  var minima = double.infinity;
  for (var i = 0; i < trazado.length - 1; i++) {
    final a = trazado[i];
    final b = trazado[i + 1];
    final ax = (a.longitude - punto.longitude) * k;
    final ay = a.latitude - punto.latitude;
    final dx = (b.longitude - a.longitude) * k;
    final dy = b.latitude - a.latitude;
    final largo = dx * dx + dy * dy;
    final t = largo == 0 ? 0.0 : (-(ax * dx + ay * dy) / largo).clamp(0.0, 1.0);
    final proyectado = LatLng(a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude));
    final d = distanciaM(punto, proyectado);
    if (d < minima) minima = d;
  }
  return minima;
}
