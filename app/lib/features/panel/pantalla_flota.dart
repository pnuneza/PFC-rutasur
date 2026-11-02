/// A-02 Estado de la flota (P06 Tabla 46; CU-16, RF-017).
///
/// Indicadores y tabla se recalculan cada 15 s. Un clic en una fila centra la unidad en
/// el mapa, que muestra solo las unidades con sesión abierta.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config.dart';
import '../../core/tema.dart';
import '../../domain/panel.dart';
import 'comun.dart';

/// Centro aproximado de la línea LB, para abrir el mapa antes de tener unidades.
const _centroLinea = LatLng(-16.445, -71.505);

class PantallaFlota extends StatefulWidget {
  const PantallaFlota({super.key, required this.contexto, this.mostrarTeselas = true, DateTime Function()? reloj})
      : reloj = reloj ?? DateTime.now;

  final ContextoPanel contexto;
  final bool mostrarTeselas;
  final DateTime Function() reloj;

  @override
  State<PantallaFlota> createState() => _PantallaFlotaState();
}

enum _Orden { unidad, estado, desde }

class _PantallaFlotaState extends State<PantallaFlota> {
  final MapController _mapa = MapController();
  Timer? _temporizador;
  EstadoFlota? _flota;
  String? _error;
  bool _cargando = true;
  _Orden _orden = _Orden.estado;
  bool _ascendente = true;
  String? _seleccionada;

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(Config.intervaloConsulta, (_) => _cargar());
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final flota = await widget.contexto.ejecutar((s, a) => s.flota(a));
      if (!mounted || flota == null) return;
      setState(() {
        _flota = flota;
        _error = null;
        _cargando = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeDeError(e);
        _cargando = false;
      });
    }
  }

  List<UnidadFlota> get _ordenadas {
    final lista = [...?_flota?.unidades];
    int comparar(UnidadFlota a, UnidadFlota b) => switch (_orden) {
          _Orden.unidad => a.etiqueta.compareTo(b.etiqueta),
          _Orden.estado => a.estado.index.compareTo(b.estado.index),
          _Orden.desde => a.desde.compareTo(b.desde),
        };
    lista.sort((a, b) => _ascendente ? comparar(a, b) : comparar(b, a));
    return lista;
  }

  void _ordenarPor(_Orden orden, bool ascendente) => setState(() {
        _orden = orden;
        _ascendente = ascendente;
      });

  void _centrar(UnidadFlota u) {
    setState(() => _seleccionada = u.id);
    if (u.ubicacion != null) _mapa.move(u.ubicacion!, 16);
  }

  @override
  Widget build(BuildContext context) {
    final flota = _flota;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncabezadoPantalla(
          titulo: 'Estado de la flota',
          subtitulo: 'Se actualiza cada 15 segundos.',
          acciones: [
            OutlinedButton.icon(
              key: const Key('actualizar-flota'),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AvisoError(mensaje: _error!, alReintentar: _cargar),
          ),
        if (_cargando && flota == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (flota != null)
          Expanded(
            child: LayoutBuilder(
              builder: (context, limites) {
                final tabla = _tablaConIndicadores(flota);
                final mapa = _mapaFlota(flota);
                if (limites.maxWidth >= 1000) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: tabla),
                      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.fromLTRB(0, 0, 24, 24), child: mapa)),
                    ],
                  );
                }
                return ListView(
                  children: [
                    tabla,
                    Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: SizedBox(height: 360, child: mapa)),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _tablaConIndicadores(EstadoFlota flota) {
    final ahora = widget.reloj();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Indicador(
                clave: 'transmitiendo',
                titulo: 'Transmitiendo',
                valor: flota.transmitiendo,
                colorTexto: ColoresRutaSur.vigenteTexto,
                colorFondo: ColoresRutaSur.vigenteFondo,
              ),
              _Indicador(
                clave: 'sin-senal',
                titulo: 'Sin señal',
                valor: flota.sinSenal,
                colorTexto: ColoresRutaSur.demoradoTexto,
                colorFondo: ColoresRutaSur.demoradoFondo,
              ),
              _Indicador(
                clave: 'inactivas',
                titulo: 'Inactivas',
                valor: flota.inactivas,
                colorTexto: ColoresRutaSur.textoSecundario,
                colorFondo: const Color(0xFFE8ECEC),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (flota.unidades.isEmpty)
            const Text('No hay unidades registradas. Regístralas en «Unidades y cuentas».')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('tabla-flota'),
                showCheckboxColumn: false,
                sortColumnIndex: _orden.index,
                sortAscending: _ascendente,
                columns: [
                  DataColumn(label: const Text('Unidad'), onSort: (_, asc) => _ordenarPor(_Orden.unidad, asc)),
                  DataColumn(label: const Text('Estado'), onSort: (_, asc) => _ordenarPor(_Orden.estado, asc)),
                  DataColumn(label: const Text('Desde'), onSort: (_, asc) => _ordenarPor(_Orden.desde, asc)),
                  const DataColumn(label: Text('Recorrido')),
                  const DataColumn(label: Text('Última posición')),
                  const DataColumn(label: Text('Cuenta')),
                ],
                rows: [
                  for (final u in _ordenadas)
                    DataRow(
                      key: ValueKey('fila-${u.etiqueta}'),
                      selected: u.id == _seleccionada,
                      onSelectChanged: (_) => _centrar(u),
                      cells: [
                        DataCell(Text(u.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(_EtiquetaEstado(u.estado)),
                        DataCell(Text('${fechaHora(u.desde)} (${hace(u.desde, ahora)})')),
                        DataCell(Text(u.ramal == null ? '—' : '${u.ramal!.nombre} · va a ${u.destino}')),
                        DataCell(Text(u.antiguedadS == null ? '—' : 'hace ${u.antiguedadS} s')),
                        DataCell(Text(u.usuario ?? 'sin cuenta')),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Transmitiendo: envió una posición válida en los últimos 90 s. Sin señal: tiene el '
            'turno abierto, pero lleva más de 90 s sin posiciones válidas. Inactiva: no tiene '
            'turno abierto.',
            key: Key('nota-estados'),
            style: TextStyle(color: ColoresRutaSur.textoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _mapaFlota(EstadoFlota flota) {
    final enMapa = [for (final u in flota.unidades) if (u.ubicacion != null) u];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        mapController: _mapa,
        options: const MapOptions(initialCenter: _centroLinea, initialZoom: 12.5, minZoom: 10, maxZoom: 18),
        children: [
          if (widget.mostrarTeselas) ...[
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pe.edu.ucsm.rutasur',
            ),
          ],
          MarkerLayer(
            markers: [
              for (final u in enMapa)
                Marker(
                  point: u.ubicacion!,
                  width: 56,
                  height: 36,
                  child: Semantics(
                    label: 'Unidad ${u.etiqueta}, ${u.estado.nombre}',
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: u.ramal == null ? ColoresRutaSur.tramoComun : ColoresRutaSur.deRamal(u.ramal!),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: u.id == _seleccionada ? Colors.black : Colors.white,
                          width: 3,
                        ),
                      ),
                      child: Text(u.etiqueta,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.mostrarTeselas) SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
        ],
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.clave,
    required this.titulo,
    required this.valor,
    required this.colorTexto,
    required this.colorFondo,
  });

  final String clave;
  final String titulo;
  final int valor;
  final Color colorTexto;
  final Color colorFondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('indicador-$clave'),
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$valor', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: colorTexto)),
          Text(titulo, style: TextStyle(color: colorTexto, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  const _EtiquetaEstado(this.estado);

  final EstadoUnidad estado;

  @override
  Widget build(BuildContext context) => switch (estado) {
        EstadoUnidad.transmitiendo => Etiqueta(
            texto: estado.nombre,
            colorTexto: ColoresRutaSur.vigenteTexto,
            colorFondo: ColoresRutaSur.vigenteFondo,
          ),
        EstadoUnidad.sinSenal => Etiqueta(
            texto: estado.nombre,
            colorTexto: ColoresRutaSur.demoradoTexto,
            colorFondo: ColoresRutaSur.demoradoFondo,
          ),
        EstadoUnidad.inactiva => Etiqueta(
            texto: estado.nombre,
            colorTexto: ColoresRutaSur.textoSecundario,
            colorFondo: const Color(0xFFE8ECEC),
          ),
      };
}
