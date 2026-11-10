/// C-03 Transmisión activa y D-01 Confirmar fin de turno (P06 Tabla 45).
///
/// Se entiende de un vistazo, sin leer: un círculo grande verde, ámbar o rojo.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../pasajero/formato.dart';
import 'controlador_conductor.dart';

class PantallaTransmision extends StatefulWidget {
  const PantallaTransmision({super.key, required this.controlador, DateTime Function()? reloj})
      : reloj = reloj ?? DateTime.now;

  final ControladorConductor controlador;
  final DateTime Function() reloj;

  @override
  State<PantallaTransmision> createState() => _PantallaTransmisionState();
}

class _PantallaTransmisionState extends State<PantallaTransmision> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // Refresca «hace N s» cada segundo
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _confirmarFin() async {
    final terminar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Terminar el turno?'),
        content: const Text('La unidad dejará de verse en el mapa de los pasajeros.'),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            key: const Key('cancelar-fin'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirmar-fin'),
            style: FilledButton.styleFrom(backgroundColor: ColoresRutaSur.noConfiableTexto),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terminar turno'),
          ),
        ],
      ),
    );
    if (terminar == true) await widget.controlador.detener();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    final s = c.sesion;
    final (color, fondo, titulo, mensaje) = switch (c.estado) {
      EstadoEmision.conectando => (
          ColoresRutaSur.demoradoTexto,
          ColoresRutaSur.demoradoFondo,
          'CONECTANDO…',
          'Todavía no llega ninguna posición al servidor: los pasajeros aún no ven la unidad. '
              'Espera unos segundos con la pantalla encendida.',
        ),
      EstadoEmision.transmitiendo => (
          ColoresRutaSur.vigenteTexto,
          ColoresRutaSur.vigenteFondo,
          'TRANSMITIENDO',
          'Los pasajeros ven la unidad en el mapa. Puedes apagar la pantalla.',
        ),
      EstadoEmision.sinConexion => (
          ColoresRutaSur.demoradoTexto,
          ColoresRutaSur.demoradoFondo,
          'SIN CONEXIÓN',
          'Sin conexión: guardando posiciones en el teléfono. '
              'Se enviarán solas cuando vuelva la señal.',
        ),
      EstadoEmision.sinGps => (
          ColoresRutaSur.noConfiableTexto,
          ColoresRutaSur.noConfiableFondo,
          'SIN GPS',
          'El teléfono no está recibiendo su ubicación. Revisa que el GPS esté encendido '
              'y que el teléfono no esté cubierto.',
        ),
      EstadoEmision.sinPermisos => (
          ColoresRutaSur.noConfiableTexto,
          ColoresRutaSur.noConfiableFondo,
          'SIN PERMISOS',
          'Falta el permiso de ubicación o de notificaciones. Sin él, los pasajeros no ven '
              'la unidad.',
        ),
    };
    return PopScope(
      canPop: false, // salir no detiene el turno: para eso está el botón rojo
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: ColoresRutaSur.primario,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Text('Unidad ${c.etiquetaUnidad ?? ''}'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (s != null) ...[
                      _Recorrido(
                        texto: '${s.ramal.nombre} · ${textoSentido(s.ramal, s.sentido)}',
                        destino: s.destino,
                      ),
                      const SizedBox(height: 20),
                    ],
                    Center(
                      child: Container(
                        key: const Key('indicador'),
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: fondo,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          titulo,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(mensaje, textAlign: TextAlign.center, key: const Key('mensaje')),
                    if (c.estado == EstadoEmision.sinPermisos) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton.icon(
                          key: const Key('revisar-permisos'),
                          onPressed: c.irAPermisos,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Revisar permisos'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _Dato('Última posición enviada', _hace(c.ultimoEnvio)),
                    _Dato('Pendientes en el teléfono', '${c.pendientes}'),
                    _Dato(
                      'Precisión del GPS',
                      c.precisionGps == null ? 'esperando…' : '± ${c.precisionGps!.round()} m',
                    ),
                    if (s != null) _Dato('Inicio del turno', _hora(s.inicio)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    key: const Key('detener'),
                    style: FilledButton.styleFrom(backgroundColor: ColoresRutaSur.noConfiableTexto),
                    onPressed: c.ocupado ? null : _confirmarFin,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Detener transmisión', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hace(DateTime? momento) {
    if (momento == null) return 'todavía no';
    final s = widget.reloj().difference(momento).inSeconds;
    if (s < 60) return 'hace ${s < 0 ? 0 : s} s';
    return 'hace ${(s / 60).floor()} min';
  }

  String _hora(DateTime momento) {
    final local = momento.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(local.hour)}:${dos(local.minute)}';
  }
}

/// Ramal y sentido en grande: si el conductor eligió mal, lo nota de inmediato (D-22).
class _Recorrido extends StatelessWidget {
  const _Recorrido({required this.texto, required this.destino});

  final String texto;
  final String destino;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recorrido'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresRutaSur.primario.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ColoresRutaSur.primario, width: 2),
      ),
      child: Column(
        children: [
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ColoresRutaSur.primario),
          ),
          const SizedBox(height: 4),
          Text(textoDestino(destino), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(color: ColoresRutaSur.textoSecundario))),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
