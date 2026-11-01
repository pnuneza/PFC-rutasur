/// C-02 Declarar recorrido (P06 Tabla 45, RF-013).
///
/// Los sentidos usan las palabras de los usuarios de la ruta: «bajada» hacia el Centro
/// y «subida» hacia el ramal (chat de la línea LB, 29/10/2026).
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/modelos.dart';
import '../pasajero/formato.dart';
import 'controlador_conductor.dart';

/// Destino que verán los pasajeros, igual que el que devuelve el servidor.
String destinoDe(Ramal ramal, Sentido sentido) =>
    sentido == Sentido.ida ? 'Centro (2 de Mayo)' : ramal.nombre;

class PantallaRecorrido extends StatefulWidget {
  const PantallaRecorrido({super.key, required this.controlador});

  final ControladorConductor controlador;

  @override
  State<PantallaRecorrido> createState() => _PantallaRecorridoState();
}

class _PantallaRecorridoState extends State<PantallaRecorrido> {
  Ramal? _ramal;
  Sentido? _sentido;

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    final listo = _ramal != null && _sentido != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ColoresRutaSur.primario,
        foregroundColor: Colors.white,
        title: Text('Unidad ${c.etiquetaUnidad ?? ''}'),
        actions: [
          TextButton(
            onPressed: c.ocupado ? null : c.salir,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Salir'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (c.aviso != null) ...[_Aviso(texto: c.aviso!), const SizedBox(height: 16)],
            Text('¿Qué recorrido vas a hacer?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('Ramal', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final ramal in Ramal.values)
              _Opcion(
                clave: Key('ramal-${ramal.codigoApi}'),
                texto: ramal.nombre,
                color: ColoresRutaSur.deRamal(ramal),
                elegida: _ramal == ramal,
                alElegir: () => setState(() => _ramal = ramal),
              ),
            const SizedBox(height: 16),
            const Text('Sentido', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final sentido in Sentido.values)
              _Opcion(
                clave: Key('sentido-${sentido.codigoApi}'),
                texto: textoSentido(_ramal, sentido),
                color: ColoresRutaSur.primario,
                elegida: _sentido == sentido,
                alElegir: () => setState(() => _sentido = sentido),
              ),
            const SizedBox(height: 20),
            if (listo)
              Text(
                'Los pasajeros verán: Unidad ${c.etiquetaUnidad ?? ''} · '
                'Va a ${destinoDe(_ramal!, _sentido!)}',
                key: const Key('resumen'),
                style: const TextStyle(color: ColoresRutaSur.textoSecundario),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: FilledButton.icon(
                key: const Key('empezar'),
                onPressed: listo && !c.ocupado ? () => c.empezar(_ramal!, _sentido!) : null,
                icon: c.ocupado
                    ? const SizedBox(
                        width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                    : const Icon(Icons.play_arrow),
                label: const Text('Empezar a transmitir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.clave,
    required this.texto,
    required this.color,
    required this.elegida,
    required this.alElegir,
  });

  final Key clave;
  final String texto;
  final Color color;
  final bool elegida;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: elegida ? color.withValues(alpha: 0.12) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: elegida ? color : Colors.black26, width: elegida ? 2 : 1),
        ),
        child: InkWell(
          key: clave,
          borderRadius: BorderRadius.circular(12),
          onTap: alElegir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(texto, style: const TextStyle(fontSize: 18))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ColoresRutaSur.demoradoFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: ColoresRutaSur.demoradoTexto),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(color: ColoresRutaSur.demoradoTexto))),
        ],
      ),
    );
  }
}
