/// P-01 Mapa principal: pantalla central del pasajero.
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/repositorio.dart';
import 'controlador_mapa.dart';
import 'hoja_llegadas.dart';
import 'hoja_unidad.dart';
import 'widgets/etiqueta_estado.dart';
import 'widgets/mapa_ruta.dart';
import 'widgets/paneles.dart';

class PantallaMapa extends StatefulWidget {
  const PantallaMapa({super.key, required this.repositorio});

  final RepositorioRutaSur repositorio;

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

class _PantallaMapaState extends State<PantallaMapa> {
  late final ControladorMapa _controlador = ControladorMapa(widget.repositorio);

  @override
  void initState() {
    super.initState();
    _controlador.iniciar();
  }

  @override
  void dispose() {
    _controlador.dispose(); // detiene la consulta periódica
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controlador,
      builder: (context, _) {
        final c = _controlador;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: ColoresRutaSur.primario,
            foregroundColor: Colors.white,
            title: Text(c.linea == null ? 'RutaSur' : 'RutaSur · Línea ${c.linea!.codigo}'),
            actions: [
              IconButton(
                tooltip: 'Ayuda',
                icon: const Icon(Icons.help_outline),
                onPressed: () => mostrarAyuda(context),
              ),
            ],
          ),
          body: _cuerpo(context, c),
        );
      },
    );
  }

  Widget _cuerpo(BuildContext context, ControladorMapa c) {
    final linea = c.linea;
    if (linea == null) {
      if (c.cargandoLinea) return const Center(child: CircularProgressIndicator());
      return _ErrorDeCarga(mensaje: c.errorLinea ?? 'No se pudo cargar la ruta.', alReintentar: c.iniciar);
    }

    return Stack(
      children: [
        MapaRuta(
          linea: linea,
          paraderos: c.paraderos,
          unidades: c.unidades,
          atenuarUnidades: c.sinConexion,
          alTocarParadero: (paradero) => mostrarLlegadas(
            context,
            repositorio: widget.repositorio,
            paradero: paradero,
            horario: linea.horario,
          ),
          alTocarUnidad: (unidad) => mostrarUnidad(context, unidad),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IndicadorActualizacion(controlador: c),
              if (c.sinConexion) ...[
                const SizedBox(height: 8),
                const EtiquetaEstado(
                  texto: 'No hay conexión a internet. Las unidades se muestran con su último dato conocido.',
                  colorTexto: ColoresRutaSur.noConfiableTexto,
                  colorFondo: ColoresRutaSur.noConfiableFondo,
                  icono: Icons.cloud_off,
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 28,
          child: c.sinUnidadesEnCirculacion
              ? TarjetaSinUnidades(horario: linea.horario, alReintentar: c.refrescarUnidades)
              : const _Sugerencia(),
        ),
      ],
    );
  }
}

class _Sugerencia extends StatelessWidget {
  const _Sugerencia();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined, color: ColoresRutaSur.primario),
            SizedBox(width: 8),
            Expanded(child: Text('Toca un paradero para ver qué unidades llegan y en cuántos minutos.')),
          ],
        ),
      ),
    );
  }
}

class _ErrorDeCarga extends StatelessWidget {
  const _ErrorDeCarga({required this.mensaje, required this.alReintentar});

  final String mensaje;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: ColoresRutaSur.noConfiableTexto),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: alReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
