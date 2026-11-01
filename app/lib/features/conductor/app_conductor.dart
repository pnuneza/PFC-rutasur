import 'package:flutter/material.dart';

import '../../core/tema.dart';
import 'controlador_conductor.dart';
import 'pantalla_ingreso.dart';
import 'pantalla_permisos.dart';
import 'pantalla_recorrido.dart';
import 'pantalla_transmision.dart';

/// Aplicación del conductor (rutasur-conductor). La pantalla la decide el controlador
/// según lo que encuentra guardado en el teléfono (P06 Figura 28).
class AppConductor extends StatefulWidget {
  const AppConductor({super.key, required this.controlador});

  final ControladorConductor controlador;

  @override
  State<AppConductor> createState() => _AppConductorState();
}

class _AppConductorState extends State<AppConductor> {
  @override
  void initState() {
    super.initState();
    widget.controlador.iniciar();
  }

  @override
  void dispose() {
    widget.controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RutaSur Conductor',
      debugShowCheckedModeBanner: false,
      theme: temaRutaSur(),
      home: ListenableBuilder(
        listenable: widget.controlador,
        builder: (context, _) {
          final c = widget.controlador;
          return switch (c.etapa) {
            Etapa.cargando => const Scaffold(body: Center(child: CircularProgressIndicator())),
            Etapa.ingreso => PantallaIngreso(controlador: c),
            Etapa.recorrido => PantallaRecorrido(controlador: c),
            Etapa.permisos => PantallaPermisos(controlador: c),
            Etapa.transmision => PantallaTransmision(controlador: c),
          };
        },
      ),
    );
  }
}
