/// C-04 Permisos del teléfono (P06 Tabla 45; CU-02, flujos 4a y 7a).
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/conductor.dart';
import 'controlador_conductor.dart';

class PantallaPermisos extends StatefulWidget {
  const PantallaPermisos({super.key, required this.controlador});

  final ControladorConductor controlador;

  @override
  State<PantallaPermisos> createState() => _PantallaPermisosState();
}

class _PantallaPermisosState extends State<PantallaPermisos> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del sistema, se revisa otra vez qué se concedió.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) widget.controlador.revisarPermisos();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    final p = c.permisos;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ColoresRutaSur.primario,
        foregroundColor: Colors.white,
        title: const Text('Permisos del teléfono'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Para que los pasajeros vean la unidad con la pantalla apagada, '
                      'RutaSur necesita estos permisos.'),
                  const SizedBox(height: 16),
                  _Tarjeta(
                    clave: const Key('permiso-ubicacion'),
                    titulo: 'Ubicación precisa',
                    explicacion: 'Obligatorio. Sin permiso de ubicación no se puede transmitir. '
                        'Si Android lo ofrece, elige «Permitir todo el tiempo».',
                    estado: p?.ubicacion,
                    alPedir: c.pedirUbicacion,
                  ),
                  _Tarjeta(
                    clave: const Key('permiso-notificaciones'),
                    titulo: 'Notificaciones',
                    explicacion: 'Obligatorio. Muestra el aviso permanente de que la unidad está '
                        'transmitiendo.',
                    estado: p?.notificaciones,
                    alPedir: c.pedirNotificaciones,
                  ),
                  _Tarjeta(
                    clave: const Key('permiso-bateria'),
                    titulo: 'Sin restricción de batería',
                    explicacion: 'Recomendado. Evita que el teléfono detenga la transmisión para '
                        'ahorrar batería.',
                    estado: p?.bateria,
                    alPedir: c.pedirBateria,
                  ),
                  if (p?.ubicacion == EstadoPermiso.denegadoSiempre)
                    TextButton(
                      onPressed: c.abrirAjustes,
                      child: const Text('Abrir los ajustes de la aplicación'),
                    ),
                ],
              ),
            ),
            // Fijo abajo: siempre visible aunque las tarjetas no quepan en la pantalla
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const Key('continuar'),
                  onPressed: (p?.obligatoriosListos ?? false) ? c.continuarDesdePermisos : null,
                  child: const Text('Continuar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.clave,
    required this.titulo,
    required this.explicacion,
    required this.estado,
    required this.alPedir,
  });

  final Key clave;
  final String titulo;
  final String explicacion;
  final EstadoPermiso? estado;
  final Future<void> Function() alPedir;

  @override
  Widget build(BuildContext context) {
    final listo = estado?.listo ?? false;
    final color = listo ? ColoresRutaSur.vigenteTexto : ColoresRutaSur.noConfiableTexto;
    return Card(
      key: clave,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(listo ? Icons.check_circle : Icons.cancel, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
                Text(
                  switch (estado) {
                    EstadoPermiso.concedido => 'Concedido',
                    EstadoPermiso.noAplica => 'No hace falta',
                    EstadoPermiso.denegadoSiempre => 'Bloqueado',
                    _ => 'Pendiente',
                  },
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(explicacion),
            if (!listo) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(onPressed: alPedir, child: const Text('Conceder')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
