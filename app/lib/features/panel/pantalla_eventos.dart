/// A-05 Registro de eventos (P06 Tabla 46; CU-17, RF-020, RN-012).
///
/// Filtros por fecha, tipo y unidad; del más reciente al más antiguo; paginado.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/panel.dart';
import 'comun.dart';

/// Máximo hacia atrás que permite el filtro (RN-012).
const int diasMaximosEventos = 30;

class PantallaEventos extends StatefulWidget {
  const PantallaEventos({super.key, required this.contexto, DateTime Function()? reloj})
      : reloj = reloj ?? DateTime.now;

  final ContextoPanel contexto;
  final DateTime Function() reloj;

  @override
  State<PantallaEventos> createState() => _PantallaEventosState();
}

class _PantallaEventosState extends State<PantallaEventos> {
  late DateTime _desde;
  late DateTime _hasta;
  TipoEvento? _tipo;
  final _unidad = TextEditingController();
  PaginaEventos? _pagina;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hoy = _soloFecha(widget.reloj());
    _desde = hoy.subtract(const Duration(days: 1));
    _hasta = hoy;
    _buscar();
  }

  @override
  void dispose() {
    _unidad.dispose();
    super.dispose();
  }

  static DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  /// El servidor cuenta los 30 días desde este momento, no desde la medianoche: el primer
  /// día completo que se puede pedir es el de hace 29 días.
  DateTime get _primerDiaPermitido =>
      _soloFecha(widget.reloj()).subtract(const Duration(days: diasMaximosEventos - 1));

  /// Error de los filtros, o null si son válidos (P06 A-05 #1).
  String? get _errorFiltros {
    if (_desde.isAfter(_hasta)) return 'La fecha inicial debe ser anterior o igual a la final.';
    final limite = _primerDiaPermitido;
    if (_desde.isBefore(limite)) {
      return 'Solo se pueden consultar los últimos $diasMaximosEventos días (RN-012).';
    }
    return null;
  }

  FiltroEventos _filtro(int pagina) => FiltroEventos(
        desde: _desde,
        // Hasta el final del día elegido
        hasta: _hasta.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
        tipo: _tipo,
        unidad: _unidad.text.trim().isEmpty ? null : _unidad.text.trim(),
        pagina: pagina,
      );

  Future<void> _buscar([int pagina = 1]) async {
    if (_errorFiltros != null) {
      setState(() {});
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await widget.contexto.ejecutar((s, a) => s.eventos(a, _filtro(pagina)));
      if (mounted && r != null) setState(() => _pagina = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirFecha({required bool inicial}) async {
    final hoy = _soloFecha(widget.reloj());
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial ? _desde : _hasta,
      firstDate: _primerDiaPermitido,
      lastDate: hoy,
    );
    if (elegida == null) return;
    setState(() => inicial ? _desde = elegida : _hasta = elegida);
  }

  String _fecha(DateTime d) => '${dosDigitos(d.day)}/${dosDigitos(d.month)}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final errorFiltros = _errorFiltros;
    final pagina = _pagina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoPantalla(
          titulo: 'Registro de eventos',
          subtitulo: 'Peticiones, errores, posiciones descartadas y eventos de seguridad.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('fecha-desde'),
                onPressed: () => _elegirFecha(inicial: true),
                icon: const Icon(Icons.event),
                label: Text('Desde ${_fecha(_desde)}'),
              ),
              OutlinedButton.icon(
                key: const Key('fecha-hasta'),
                onPressed: () => _elegirFecha(inicial: false),
                icon: const Icon(Icons.event),
                label: Text('Hasta ${_fecha(_hasta)}'),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<TipoEvento?>(
                  key: const Key('filtro-tipo'),
                  initialValue: _tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final t in TipoEvento.values) DropdownMenuItem(value: t, child: Text(t.nombre)),
                  ],
                  onChanged: (t) => setState(() => _tipo = t),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  key: const Key('filtro-unidad'),
                  controller: _unidad,
                  decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              FilledButton.icon(
                key: const Key('buscar-eventos'),
                onPressed: _cargando ? null : () => _buscar(),
                icon: const Icon(Icons.search),
                label: const Text('Buscar'),
              ),
            ],
          ),
        ),
        if (errorFiltros != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: AvisoError(mensaje: errorFiltros),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: AvisoError(mensaje: _error!, alReintentar: _buscar),
          ),
        if (_cargando) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        Expanded(
          child: pagina == null
              ? const SizedBox()
              : pagina.eventos.isEmpty
                  ? const Center(child: Text('No hay eventos con esos filtros.', key: Key('sin-eventos')))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          key: const Key('tabla-eventos'),
                          columns: const [
                            DataColumn(label: Text('Fecha')),
                            DataColumn(label: Text('Tipo')),
                            DataColumn(label: Text('Origen')),
                            DataColumn(label: Text('Unidad')),
                            DataColumn(label: Text('Usuario del panel')),
                            DataColumn(label: Text('HTTP')),
                            DataColumn(label: Text('Detalle')),
                          ],
                          rows: [
                            for (final e in pagina.eventos)
                              DataRow(cells: [
                                DataCell(Text(fechaHora(e.fecha))),
                                DataCell(Text(e.tipo.nombre)),
                                DataCell(Text(e.origen)),
                                DataCell(Text(e.unidad ?? '—')),
                                DataCell(Text(e.usuarioPanel ?? '—')),
                                DataCell(Text(e.codigoHttp?.toString() ?? '—')),
                                DataCell(ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 420),
                                  child: Text(
                                    e.detalle == null ? '—' : jsonEncode(e.detalle),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                              ]),
                          ],
                        ),
                      ),
                    ),
        ),
        if (pagina != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFDDE3E3)))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${pagina.total} ${pagina.total == 1 ? 'evento' : 'eventos'} · página '
                    '${pagina.pagina} de ${pagina.paginas} · se conservan ${pagina.retencionDias} días',
                    key: const Key('pie-eventos'),
                    style: const TextStyle(color: ColoresRutaSur.textoSecundario),
                  ),
                ),
                IconButton(
                  key: const Key('pagina-anterior'),
                  tooltip: 'Página anterior',
                  onPressed: pagina.pagina > 1 && !_cargando ? () => _buscar(pagina.pagina - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const Key('pagina-siguiente'),
                  tooltip: 'Página siguiente',
                  onPressed: pagina.pagina < pagina.paginas && !_cargando ? () => _buscar(pagina.pagina + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
