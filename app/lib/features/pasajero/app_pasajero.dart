import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/pasajero.dart';
import '../../domain/repositorio.dart';
import 'pantalla_bienvenida.dart';
import 'pantalla_mapa.dart';

/// Aplicación del pasajero. Recibe sus dependencias desde afuera (inyección de
/// dependencias), de modo que las pruebas pueden usar versiones falsas.
///
/// La bienvenida (P-00) aparece solo en la primera apertura (P06 Figura 27).
class AppPasajero extends StatelessWidget {
  const AppPasajero({
    super.key,
    required this.repositorio,
    this.preferencias,
    this.ubicacion,
    this.mostrarTeselas = true,
  });

  final RepositorioRutaSur repositorio;
  final PreferenciasPasajero? preferencias;
  final UbicacionPasajero? ubicacion;

  /// false en las pruebas, que no tienen internet para el fondo del mapa.
  final bool mostrarTeselas;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RutaSur',
      debugShowCheckedModeBanner: false,
      theme: temaRutaSur(),
      home: _Inicio(
        repositorio: repositorio,
        preferencias: preferencias,
        ubicacion: ubicacion,
        mostrarTeselas: mostrarTeselas,
      ),
    );
  }
}

class _Inicio extends StatefulWidget {
  const _Inicio({
    required this.repositorio,
    required this.mostrarTeselas,
    this.preferencias,
    this.ubicacion,
  });

  final RepositorioRutaSur repositorio;
  final PreferenciasPasajero? preferencias;
  final UbicacionPasajero? ubicacion;
  final bool mostrarTeselas;

  @override
  State<_Inicio> createState() => _InicioState();
}

class _InicioState extends State<_Inicio> {
  /// null mientras se lee la preferencia guardada
  bool? _mostrarBienvenida;

  @override
  void initState() {
    super.initState();
    final preferencias = widget.preferencias;
    if (preferencias == null) {
      _mostrarBienvenida = false;
    } else {
      preferencias.bienvenidaVista().then((vista) {
        if (mounted) setState(() => _mostrarBienvenida = !vista);
      });
    }
  }

  Future<void> _terminarBienvenida({required bool usarUbicacion}) async {
    if (usarUbicacion) await widget.ubicacion?.pedirPermiso(); // se pide una sola vez
    await widget.preferencias?.marcarBienvenidaVista();
    if (mounted) setState(() => _mostrarBienvenida = false);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_mostrarBienvenida) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      true => PantallaBienvenida(
          alUsarUbicacion: () => _terminarBienvenida(usarUbicacion: true),
          alOmitir: () => _terminarBienvenida(usarUbicacion: false),
        ),
      false => PantallaMapa(
          repositorio: widget.repositorio,
          preferencias: widget.preferencias,
          ubicacion: widget.ubicacion,
          mostrarTeselas: widget.mostrarTeselas,
        ),
    };
  }
}
