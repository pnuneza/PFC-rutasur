/// P-02 Buscar paradero (P06 Tabla 44; RF-005, RF-007).
///
/// Muestra primero los favoritos y, al escribir, los resultados con sus ramales y la
/// distancia al pasajero si se conoce su ubicación. Devuelve el paradero elegido.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/tema.dart';
import '../../domain/geometria.dart';
import '../../domain/modelos.dart';
import '../../domain/repositorio.dart';
import 'controlador_busqueda.dart';
import 'controlador_mapa.dart';
import 'formato.dart';

class PantallaBusqueda extends StatefulWidget {
  const PantallaBusqueda({super.key, required this.repositorio, required this.mapa});

  final RepositorioRutaSur repositorio;

  /// Favoritos, posición del pasajero y paraderos del mapa.
  final ControladorMapa mapa;

  @override
  State<PantallaBusqueda> createState() => _PantallaBusquedaState();
}

class _PantallaBusquedaState extends State<PantallaBusqueda> {
  late final ControladorBusqueda _busqueda = ControladorBusqueda(widget.repositorio);

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _elegir(ParaderoEnMapa paradero) => Navigator.of(context).pop(paradero);

  Future<void> _alternar(String codigo) async {
    final ok = await widget.mapa.alternarFavorito(codigo);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Puedes guardar hasta 10 favoritos. Quita uno para agregar otro.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_busqueda, widget.mapa]),
      builder: (context, _) {
        final b = _busqueda;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: ColoresRutaSur.primario,
            foregroundColor: Colors.white,
            title: TextField(
              key: const Key('campo-busqueda'),
              autofocus: true,
              maxLength: 40,
              onChanged: b.escribir,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                hintText: 'Nombre del paradero',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
          body: _cuerpo(b),
        );
      },
    );
  }

  Widget _cuerpo(ControladorBusqueda b) {
    final mapa = widget.mapa;
    if (!b.activa) {
      final favoritos = mapa.favoritos;
      return ListView(
        children: [
          if (favoritos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Escribe al menos 2 letras, por ejemplo «plaza» o «characato».\n\n'
                'Toca la estrella de un paradero para tenerlo aquí y en el mapa.',
                style: TextStyle(color: ColoresRutaSur.textoSecundario),
              ),
            )
          else ...[
            const _Titulo('Tus favoritos'),
            for (final p in favoritos) _fila(p.codigo, p.nombre, p.ramales, p.ubicacion, () => _elegir(p)),
          ],
        ],
      );
    }
    if (b.buscando && b.resultados.isEmpty) return const Center(child: CircularProgressIndicator());
    if (b.error != null) return _Mensaje(b.error!);
    if (b.resultados.isEmpty) {
      return _Mensaje('No encontramos paraderos con «${b.texto.trim()}». '
          'Prueba con otra palabra, por ejemplo «plaza».');
    }
    return ListView(
      children: [
        _Titulo('${b.resultados.length} ${b.resultados.length == 1 ? 'paradero' : 'paraderos'}'),
        for (final r in b.resultados)
          _fila(
            r.codigo,
            r.nombre,
            r.ramales,
            r.ubicacion,
            () => _elegir(mapa.paraderoPorCodigo(r.codigo) ?? r.comoParaderoEnMapa()),
          ),
      ],
    );
  }

  Widget _fila(String codigo, String nombre, Set<Ramal> ramales, LatLng ubicacion, VoidCallback alTocar) {
    final posicion = widget.mapa.posicionUsuario;
    final favorito = widget.mapa.esFavorito(codigo);
    final detalle = [
      ramales.map((r) => r.nombre).join(' y '),
      if (posicion != null) textoDistanciaAPie(distanciaM(posicion, ubicacion)),
    ].join(' · ');
    return ListTile(
      key: Key('resultado-$codigo'),
      onTap: alTocar,
      leading: const Icon(Icons.place_outlined, color: ColoresRutaSur.primario),
      title: Text(nombre),
      subtitle: Text(detalle),
      trailing: IconButton(
        key: Key('estrella-$codigo'),
        tooltip: favorito ? 'Quitar de favoritos' : 'Agregar a favoritos',
        icon: Icon(favorito ? Icons.star : Icons.star_border, color: ColoresRutaSur.demoradoTexto),
        onPressed: () => _alternar(codigo),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _Mensaje extends StatelessWidget {
  const _Mensaje(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(texto, key: const Key('mensaje-busqueda'), textAlign: TextAlign.center),
      );
}
