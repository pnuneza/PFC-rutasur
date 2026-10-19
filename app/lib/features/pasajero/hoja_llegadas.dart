/// P-03 Llegadas al paradero: respuesta al caso de uso principal CU-01 (RF-004, RF-008).
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/modelos.dart';
import '../../domain/repositorio.dart';
import 'controlador_llegadas.dart';
import 'formato.dart';
import 'widgets/etiqueta_estado.dart';

/// Abre la hoja de llegadas sobre la parte inferior del mapa.
Future<void> mostrarLlegadas(
  BuildContext context, {
  required RepositorioRutaSur repositorio,
  required ParaderoEnMapa paradero,
  required String horario,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.6,
      child: HojaLlegadas(repositorio: repositorio, paradero: paradero, horario: horario),
    ),
  );
}

class HojaLlegadas extends StatefulWidget {
  const HojaLlegadas({
    super.key,
    required this.repositorio,
    required this.paradero,
    required this.horario,
  });

  final RepositorioRutaSur repositorio;
  final ParaderoEnMapa paradero;
  final String horario;

  @override
  State<HojaLlegadas> createState() => _HojaLlegadasState();
}

class _HojaLlegadasState extends State<HojaLlegadas> {
  late final ControladorLlegadas _controlador =
      ControladorLlegadas(widget.repositorio, widget.paradero.codigo);

  @override
  void initState() {
    super.initState();
    _controlador.iniciar(); // se actualiza sola cada 15 s mientras la hoja está abierta
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paradero;
    return ListenableBuilder(
      listenable: _controlador,
      builder: (context, _) {
        final c = _controlador;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.nombre, style: Theme.of(context).textTheme.titleLarge),
              if (p.referencia != null)
                Text(p.referencia!, style: const TextStyle(color: ColoresRutaSur.textoSecundario)),
              const SizedBox(height: 4),
              Text(
                'Pasan por aquí: ${p.ramales.map((r) => r.nombre).join(' y ')}',
                style: const TextStyle(color: ColoresRutaSur.textoSecundario),
              ),
              const SizedBox(height: 12),
              if (c.sinConexion) ...[
                const _AvisoSinConexion(),
                const SizedBox(height: 8),
              ],
              Expanded(child: _contenido(c)),
            ],
          ),
        );
      },
    );
  }

  Widget _contenido(ControladorLlegadas c) {
    if (c.cargando) return const Center(child: CircularProgressIndicator());
    if (c.error != null) return _MensajeCentrado(texto: c.error!);
    if (c.llegadas.isEmpty) {
      return _MensajeCentrado(
        texto: 'No hay unidades que lleguen en los próximos 60 minutos.',
        detalle: 'Horario referencial del servicio: ${widget.horario}.',
      );
    }
    return ListView.separated(
      itemCount: c.llegadas.length,
      separatorBuilder: (context, indice) => const SizedBox(height: 8),
      itemBuilder: (context, indice) => TarjetaLlegada(llegada: c.llegadas[indice]),
    );
  }
}

/// Tarjeta de una llegada: ETA en números grandes, unidad, destino, distancia y frescura.
class TarjetaLlegada extends StatelessWidget {
  const TarjetaLlegada({super.key, required this.llegada});

  final Llegada llegada;

  @override
  Widget build(BuildContext context) {
    final l = llegada;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Column(
                children: [
                  Text(
                    minutosEta(l.etaS),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: l.etaS < 60 ? 18 : 34,
                      fontWeight: FontWeight.w800,
                      color: ColoresRutaSur.texto,
                    ),
                  ),
                  const Text('min', style: TextStyle(color: ColoresRutaSur.textoSecundario)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unidad ${l.etiqueta}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  EtiquetaDestino(ramal: l.ramal, destino: l.destino),
                  const SizedBox(height: 4),
                  Text(
                    'A ${textoDistancia(l.distanciaM)} del paradero',
                    style: const TextStyle(color: ColoresRutaSur.textoSecundario),
                  ),
                  const SizedBox(height: 4),
                  EtiquetaEstado.frescura(l.frescura, textoFrescura(l.frescura, l.antiguedadS)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion();

  @override
  Widget build(BuildContext context) {
    return const EtiquetaEstado(
      texto: 'No hay conexión a internet. Las llegadas se muestran con su último dato conocido.',
      colorTexto: ColoresRutaSur.noConfiableTexto,
      colorFondo: ColoresRutaSur.noConfiableFondo,
      icono: Icons.cloud_off,
    );
  }
}

class _MensajeCentrado extends StatelessWidget {
  const _MensajeCentrado({required this.texto, this.detalle});

  final String texto;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_bus_outlined, size: 40, color: ColoresRutaSur.textoSecundario),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          if (detalle != null) ...[
            const SizedBox(height: 4),
            Text(
              detalle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ColoresRutaSur.textoSecundario),
            ),
          ],
        ],
      ),
    );
  }
}
