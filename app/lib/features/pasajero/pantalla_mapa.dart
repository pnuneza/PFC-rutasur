/// P-01 Mapa principal: pantalla central del pasajero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/tema.dart';
import '../../domain/modelos.dart';
import '../../domain/pasajero.dart';
import '../../domain/repositorio.dart';
import 'controlador_mapa.dart';
import 'formato.dart';
import 'hoja_llegadas.dart';
import 'hoja_unidad.dart';
import 'pantalla_busqueda.dart';
import 'widgets/etiqueta_estado.dart';
import 'widgets/mapa_ruta.dart';
import 'widgets/paneles.dart';

class PantallaMapa extends StatefulWidget {
  const PantallaMapa({
    super.key,
    required this.repositorio,
    this.preferencias,
    this.ubicacion,
    this.mostrarTeselas = true,
  });

  final RepositorioRutaSur repositorio;
  final PreferenciasPasajero? preferencias;
  final UbicacionPasajero? ubicacion;
  final bool mostrarTeselas;

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

class _PantallaMapaState extends State<PantallaMapa> {
  late final ControladorMapa _controlador = ControladorMapa(
    widget.repositorio,
    preferencias: widget.preferencias,
    ubicacion: widget.ubicacion,
  );
  final MapController _mapa = MapController();

  /// Abre P-03 de un paradero, con la estrella de favorito (RF-007).
  void _abrirLlegadas(ParaderoEnMapa paradero) {
    final linea = _controlador.linea;
    if (linea == null) return;
    mostrarLlegadas(
      context,
      repositorio: widget.repositorio,
      paradero: paradero,
      horario: linea.horario,
      esFavorito: _controlador.esFavorito(paradero.codigo),
      alAlternarFavorito: () => _controlador.alternarFavorito(paradero.codigo),
    );
  }

  Future<void> _buscar() async {
    final elegido = await Navigator.of(context).push<ParaderoEnMapa>(
      MaterialPageRoute(
        builder: (_) => PantallaBusqueda(repositorio: widget.repositorio, mapa: _controlador),
      ),
    );
    if (elegido != null && mounted) {
      _mapa.move(elegido.ubicacion, 16);
      _abrirLlegadas(elegido);
    }
  }

  Future<void> _miUbicacion() async {
    final posicion = await _controlador.usarMiUbicacion();
    if (!mounted) return;
    if (posicion != null) {
      _mapa.move(posicion, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_controlador.ubicacionConcedida
            ? 'No pudimos obtener tu ubicación. Revisa que el GPS esté encendido.'
            : 'Sin permiso de ubicación no podemos proponerte el paradero más cercano. '
                'Puedes buscarlo por su nombre.'),
      ));
    }
  }

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
                onPressed: () => mostrarAyuda(context, linea: c.linea),
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
          ubicacionUsuario: c.posicionUsuario,
          controlador: _mapa,
          mostrarTeselas: widget.mostrarTeselas,
          alTocarParadero: _abrirLlegadas,
          alTocarUnidad: (unidad) => mostrarUnidad(context, unidad),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BarraBusqueda(alTocar: _buscar),
              const SizedBox(height: 8),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.ubicacion != null) ...[
                FloatingActionButton.extended(
                  key: const Key('mi-ubicacion'),
                  heroTag: null,
                  onPressed: _miUbicacion,
                  backgroundColor: Colors.white,
                  foregroundColor: ColoresRutaSur.primario,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Mi ubicación'),
                ),
                const SizedBox(height: 8),
              ],
              if (c.favoritos.isNotEmpty) ...[
                _Favoritos(paraderos: c.favoritos, alElegir: _abrirLlegadas),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: c.sinUnidadesEnCirculacion
                    ? TarjetaSinUnidades(horario: linea.horario, alReintentar: c.refrescarUnidades)
                    : c.cercano != null
                        ? _TarjetaCercano(cercano: c.cercano!, alVerLlegadas: _abrirLlegadas)
                        : const _Sugerencia(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// P-01 #1: campo de solo lectura que abre P-02.
class _BarraBusqueda extends StatelessWidget {
  const _BarraBusqueda({required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      color: Colors.white,
      child: InkWell(
        key: const Key('barra-busqueda'),
        borderRadius: BorderRadius.circular(28),
        onTap: alTocar,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, color: ColoresRutaSur.textoSecundario),
              SizedBox(width: 12),
              Text('Buscar paradero', style: TextStyle(color: ColoresRutaSur.textoSecundario)),
            ],
          ),
        ),
      ),
    );
  }
}

/// P-01 #7: favoritos como chips horizontales (hasta 10).
class _Favoritos extends StatelessWidget {
  const _Favoritos({required this.paraderos, required this.alElegir});

  final List<ParaderoEnMapa> paraderos;
  final ValueChanged<ParaderoEnMapa> alElegir;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paraderos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          key: Key('chip-${paraderos[i].codigo}'),
          avatar: const Icon(Icons.star, color: ColoresRutaSur.demoradoTexto),
          label: Text(paraderos[i].nombre),
          backgroundColor: Colors.white,
          onPressed: () => alElegir(paraderos[i]),
        ),
      ),
    );
  }
}

/// P-01 #5 y #6: paradero más cercano, calculado en el teléfono (RF-006).
class _TarjetaCercano extends StatelessWidget {
  const _TarjetaCercano({required this.cercano, required this.alVerLlegadas});

  final ParaderoCercano cercano;
  final ValueChanged<ParaderoEnMapa> alVerLlegadas;

  @override
  Widget build(BuildContext context) {
    final p = cercano.paradero;
    return Card(
      key: const Key('tarjeta-cercano'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tu paradero más cercano', style: TextStyle(color: ColoresRutaSur.textoSecundario)),
            const SizedBox(height: 4),
            Text(p.nombre, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${textoDistanciaAPie(cercano.distanciaM)} · ${p.ramales.map((r) => r.nombre).join(' y ')}',
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('ver-llegadas'),
                onPressed: () => alVerLlegadas(p),
                child: const Text('Ver próximas llegadas'),
              ),
            ),
          ],
        ),
      ),
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
