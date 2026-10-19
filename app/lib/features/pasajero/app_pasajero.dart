import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/repositorio.dart';
import 'pantalla_mapa.dart';

/// Aplicación del pasajero. Recibe el repositorio desde afuera (inyección de
/// dependencias), de modo que las pruebas pueden usar uno falso.
class AppPasajero extends StatelessWidget {
  const AppPasajero({super.key, required this.repositorio});

  final RepositorioRutaSur repositorio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RutaSur',
      debugShowCheckedModeBanner: false,
      theme: temaRutaSur(),
      home: PantallaMapa(repositorio: repositorio),
    );
  }
}
