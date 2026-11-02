/// Panel administrativo (Flutter Web): A-01 a A-05 (P06 Tablas 41 y 46).
///
/// Permisos (RF-014): el moderador ve la flota y el registro de eventos; el administrador,
/// además, las rutas y paraderos y las unidades y cuentas.
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/panel.dart';
import 'comun.dart';
import 'pantalla_cuentas.dart';
import 'pantalla_eventos.dart';
import 'pantalla_flota.dart';
import 'pantalla_ingreso_panel.dart';
import 'pantalla_rutas.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.servicio, this.mostrarTeselas = true});

  final ServicioPanel servicio;

  /// Fondo de OpenStreetMap; las pruebas lo omiten porque no tienen internet.
  final bool mostrarTeselas;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RutaSur · Panel',
      debugShowCheckedModeBanner: false,
      theme: temaRutaSur(),
      home: _RaizPanel(servicio: servicio, mostrarTeselas: mostrarTeselas),
    );
  }
}

class _RaizPanel extends StatefulWidget {
  const _RaizPanel({required this.servicio, required this.mostrarTeselas});

  final ServicioPanel servicio;
  final bool mostrarTeselas;

  @override
  State<_RaizPanel> createState() => _RaizPanelState();
}

class _RaizPanelState extends State<_RaizPanel> {
  AccesoPanel? _acceso;
  String? _aviso;

  void _salir([String? aviso]) => setState(() {
        _acceso = null;
        _aviso = aviso;
      });

  @override
  Widget build(BuildContext context) {
    final acceso = _acceso;
    if (acceso == null) {
      return PantallaIngresoPanel(
        servicio: widget.servicio,
        aviso: _aviso,
        alIngresar: (a) => setState(() {
          _acceso = a;
          _aviso = null;
        }),
      );
    }
    return EstructuraPanel(
      contexto: ContextoPanel(servicio: widget.servicio, acceso: acceso, alExpirar: _salir),
      alSalir: _salir,
      mostrarTeselas: widget.mostrarTeselas,
    );
  }
}

class _Seccion {
  const _Seccion(this.clave, this.titulo, this.icono, this.construir);

  final String clave;
  final String titulo;
  final IconData icono;
  final Widget Function() construir;
}

/// Navegación lateral con las secciones que permite el rol.
class EstructuraPanel extends StatefulWidget {
  const EstructuraPanel({
    super.key,
    required this.contexto,
    required this.alSalir,
    this.mostrarTeselas = true,
  });

  final ContextoPanel contexto;
  final VoidCallback alSalir;
  final bool mostrarTeselas;

  @override
  State<EstructuraPanel> createState() => _EstructuraPanelState();
}

class _EstructuraPanelState extends State<EstructuraPanel> {
  int _actual = 0;

  List<_Seccion> get _secciones {
    final c = widget.contexto;
    return [
      _Seccion('flota', 'Flota', Icons.directions_bus_outlined,
          () => PantallaFlota(contexto: c, mostrarTeselas: widget.mostrarTeselas)),
      if (c.acceso.esAdministrador) ...[
        _Seccion('rutas', 'Rutas y paraderos', Icons.alt_route,
            () => PantallaRutas(contexto: c, mostrarTeselas: widget.mostrarTeselas)),
        _Seccion('cuentas', 'Unidades y cuentas', Icons.manage_accounts_outlined,
            () => PantallaCuentas(contexto: c)),
      ],
      _Seccion('eventos', 'Registro de eventos', Icons.receipt_long_outlined, () => PantallaEventos(contexto: c)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final secciones = _secciones;
    final acceso = widget.contexto.acceso;
    final ancha = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ColoresRutaSur.primario,
        foregroundColor: Colors.white,
        title: Text('RutaSur · ${secciones[_actual].titulo}'),
        actions: [
          Center(child: Text('${acceso.usuario} · ${acceso.rol.nombre}', key: const Key('usuario-actual'))),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('salir'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: widget.alSalir,
            icon: const Icon(Icons.logout),
            label: const Text('Salir'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: ancha,
            selectedIndex: _actual,
            labelType: ancha ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _actual = i),
            destinations: [
              for (final s in secciones)
                NavigationRailDestination(
                  icon: Icon(s.icono, key: Key('ir-${s.clave}')),
                  label: Text(s.titulo),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: KeyedSubtree(key: ValueKey(secciones[_actual].clave), child: secciones[_actual].construir())),
        ],
      ),
    );
  }
}
