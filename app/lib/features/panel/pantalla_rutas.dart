/// A-03 Rutas y paraderos y formulario A-03a (P06 Tabla 46; CU-14, RF-015, RN-003, RN-009).
///
/// El orden de los paraderos no se arrastra a mano: el servidor lo calcula a lo largo del
/// trazado, de modo que nunca queda con huecos ni repetidos. El administrador decide qué
/// paraderos tiene cada variante y edita sus datos; los cambios llegan a la app del
/// pasajero sin publicarla de nuevo.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/tema.dart';
import '../../domain/geometria.dart';
import '../../domain/panel.dart';
import 'comun.dart';

/// RN-003: un paradero debe quedar a 150 m o menos del trazado.
const double toleranciaCorredorM = 150;

class PantallaRutas extends StatefulWidget {
  const PantallaRutas({super.key, required this.contexto, this.mostrarTeselas = true});

  final ContextoPanel contexto;
  final bool mostrarTeselas;

  @override
  State<PantallaRutas> createState() => _PantallaRutasState();
}

class _PantallaRutasState extends State<PantallaRutas> {
  final MapController _mapa = MapController();
  List<VarianteAdmin> _variantes = const [];
  List<ParaderoAdmin> _paraderos = const [];
  HorarioLinea? _horario;
  int _actual = 0;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  /// Formulario A-03a abierto (null si está cerrado).
  _Edicion? _edicion;

  ContextoPanel get _c => widget.contexto;
  VarianteAdmin? get _variante => _variantes.isEmpty ? null : _variantes[_actual];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _edicion?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final datos = await _c.ejecutar((s, a) async =>
          (await s.variantes(a), await s.paraderos(a), await s.horario()));
      if (!mounted || datos == null) return;
      final (variantes, paraderos, horario) = datos;
      setState(() {
        _variantes = variantes;
        _paraderos = paraderos;
        _horario = horario;
        if (_actual >= _variantes.length) _actual = 0;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Ejecuta un cambio, avisa el resultado y recarga.
  Future<bool> _cambiar(String exito, Future<Object?> Function() cambio) async {
    setState(() => _guardando = true);
    try {
      final r = await cambio();
      if (r == null) return false; // la sesión venció
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exito)));
      }
      return true;
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------
  Future<void> _editarHorario() async {
    final h = _horario;
    if (h == null) return;
    final nuevo = await showDialog<HorarioLinea>(
      context: context,
      builder: (_) => _DialogoHorario(actual: h),
    );
    if (nuevo == null) return;
    await _cambiar(
      'Horario guardado: ${nuevo.inicio} a ${nuevo.fin}.',
      () => _c.ejecutar((s, a) => s.cambiarHorario(a, nuevo)),
    );
  }

  Future<void> _quitar(ParaderoDeVariante p) async {
    final v = _variante!;
    final ok = await confirmar(
      context,
      titulo: 'Quitar «${p.nombre}»',
      mensaje: 'El paradero deja de estar en ${v.nombre}. Sigue existiendo y puede volver a '
          'agregarse; si está en otras variantes, allí se mantiene.',
      accion: 'Quitar',
      peligrosa: true,
    );
    if (!ok) return;
    final codigos = [for (final x in v.paraderos) if (x.codigo != p.codigo) x.codigo];
    await _cambiar('«${p.nombre}» ya no está en ${v.nombre}.',
        () => _c.ejecutar((s, a) => s.asignarParaderos(a, v.id, codigos)));
  }

  Future<void> _agregarExistente() async {
    final v = _variante!;
    final enVariante = {for (final p in v.paraderos) p.codigo};
    final candidatos = [
      for (final p in _paraderos)
        if (p.activo &&
            !enVariante.contains(p.codigo) &&
            distanciaAlTrazadoM(p.ubicacion, v.trazado) <= toleranciaCorredorM)
          p,
    ];
    final elegido = await showDialog<ParaderoAdmin>(
      context: context,
      builder: (_) => _DialogoAgregar(variante: v, candidatos: candidatos),
    );
    if (elegido == null) return;
    await _cambiar('«${elegido.nombre}» se agregó a ${v.nombre}.',
        () => _c.ejecutar((s, a) => s.asignarParaderos(a, v.id, [...enVariante, elegido.codigo])));
  }

  void _abrirFormulario(ParaderoAdmin? paradero) {
    _edicion?.dispose();
    setState(() => _edicion = _Edicion(paradero));
    final ubicacion = paradero?.ubicacion;
    if (ubicacion != null) _mapa.move(ubicacion, 17);
  }

  void _cerrarFormulario() {
    _edicion?.dispose();
    setState(() => _edicion = null);
  }

  Future<void> _guardarFormulario() async {
    final e = _edicion!;
    final v = _variante!;
    final datos = e.datos;
    final bool ok;
    if (e.original == null) {
      ok = await _cambiar('Paradero creado.', () => _c.ejecutar((s, a) async {
            final creado = await s.crearParadero(a, datos);
            if (e.agregarAVariante) {
              await s.asignarParaderos(a, v.id, [...v.paraderos.map((p) => p.codigo), creado.codigo]);
            }
            return creado;
          }));
    } else {
      ok = await _cambiar('Cambios guardados.',
          () => _c.ejecutar((s, a) => s.editarParadero(a, e.original!.codigo, datos)));
    }
    if (ok && mounted) _cerrarFormulario();
  }

  // ------------------------------------------------------------------
  // Interfaz
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final v = _variante;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncabezadoPantalla(
          titulo: 'Rutas y paraderos',
          subtitulo: 'Los cambios llegan a la app del pasajero sin publicarla de nuevo.',
          acciones: [
            if (_horario != null)
              ActionChip(
                key: const Key('horario'),
                avatar: const Icon(Icons.schedule),
                label: Text('Horario: ${_horario!.inicio} a ${_horario!.fin}'),
                onPressed: _guardando ? null : _editarHorario,
              ),
            FilledButton.icon(
              key: const Key('nuevo-paradero'),
              onPressed: v == null || _guardando ? null : () => _abrirFormulario(null),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Nuevo paradero'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AvisoError(mensaje: _error!, alReintentar: _cargar),
          ),
        if (_cargando && v == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (v != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _variantes.length; i++)
                  ChoiceChip(
                    key: Key('variante-${_variantes[i].clave}'),
                    label: Text(_variantes[i].nombre),
                    selected: i == _actual,
                    onSelected: (_) => setState(() => _actual = i),
                  ),
              ],
            ),
          ),
          if (_guardando) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, limites) {
              final lista = _listaParaderos(v);
              final derecha = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_edicion != null) _formulario(v),
                  Expanded(child: _mapaVariante(v)),
                ],
              );
              if (limites.maxWidth >= 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 440, child: lista),
                    Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(0, 0, 24, 24), child: derecha)),
                  ],
                );
              }
              return ListView(children: [
                if (_edicion != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _formulario(v)),
                SizedBox(height: 360, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _mapaVariante(v))),
                SizedBox(height: 600, child: lista),
              ]);
            }),
          ),
        ],
      ],
    );
  }

  Widget _listaParaderos(VarianteAdmin v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${v.paraderos.length} paraderos · ${(v.longitudM / 1000).toStringAsFixed(1).replaceAll('.', ',')} km · va a ${v.destino}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                key: const Key('agregar-existente'),
                onPressed: _guardando ? null : _agregarExistente,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Agregar existente'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'El orden se calcula solo, a lo largo del trazado.',
            style: TextStyle(color: ColoresRutaSur.textoSecundario),
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('lista-paraderos'),
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 24),
            itemCount: v.paraderos.length,
            itemBuilder: (context, i) {
              final p = v.paraderos[i];
              final completo = _paraderos.where((x) => x.codigo == p.codigo).firstOrNull;
              return ListTile(
                key: Key('paradero-${p.codigo}'),
                leading: CircleAvatar(
                  backgroundColor: p.tramoComun ? ColoresRutaSur.tramoComun : ColoresRutaSur.deRamal(v.ramal),
                  foregroundColor: Colors.white,
                  child: Text('${p.orden}'),
                ),
                title: Text(p.nombre),
                subtitle: Text([
                  p.codigo,
                  'km ${(p.distanciaM / 1000).toStringAsFixed(2).replaceAll('.', ',')}',
                  if (p.tramoComun) 'tramo común',
                ].join(' · ')),
                onTap: completo == null ? null : () => _abrirFormulario(completo),
                trailing: IconButton(
                  key: Key('quitar-${p.codigo}'),
                  tooltip: 'Quitar de esta variante',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _guardando ? null : () => _quitar(p),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _formulario(VarianteAdmin v) {
    final e = _edicion!;
    final ubicacion = e.ubicacion;
    final distancia = ubicacion == null ? null : distanciaAlTrazadoM(ubicacion, v.trazado);
    final dentro = distancia != null && distancia <= toleranciaCorredorM;
    final valido = e.nombreValido && e.referenciaValida && dentro;
    return Card(
      key: const Key('formulario-paradero'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Builder(builder: (context) {
          void cambiar() => setState(() {});
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    e.original == null ? 'Nuevo paradero' : 'Editar ${e.original!.codigo}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(tooltip: 'Cerrar', onPressed: _cerrarFormulario, icon: const Icon(Icons.close)),
              ]),
              const Text('Toca el mapa para ubicar el paradero.',
                  style: TextStyle(color: ColoresRutaSur.textoSecundario)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: const Key('campo-nombre'),
                    controller: e.nombre,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      helperText: 'Como lo llama la gente, de 3 a 80 caracteres',
                      errorText: e.nombre.text.isEmpty || e.nombreValido ? null : 'De 3 a 80 caracteres',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => cambiar(),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: const Key('campo-referencia'),
                    controller: e.referencia,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Referencia (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => cambiar(),
                  ),
                ),
                SizedBox(width: 150, child: _campoCoordenada(e.lat, 'Latitud', cambiar, 'campo-lat')),
                SizedBox(width: 150, child: _campoCoordenada(e.lon, 'Longitud', cambiar, 'campo-lon')),
              ]),
              Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    key: const Key('campo-comun'),
                    value: e.tramoComun,
                    onChanged: (x) => setState(() => e.tramoComun = x ?? false),
                  ),
                  const Text('Tramo común de ambos ramales'),
                ]),
                if (e.original == null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                      key: const Key('campo-agregar'),
                      value: e.agregarAVariante,
                      onChanged: (x) => setState(() => e.agregarAVariante = x ?? false),
                    ),
                    Text('Agregar a ${v.nombre}'),
                  ])
                else
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                      key: const Key('campo-activo'),
                      value: e.activo,
                      onChanged: (x) => setState(() => e.activo = x ?? true),
                    ),
                    const Text('Activo (si se desactiva, sale de todas sus variantes)'),
                  ]),
              ]),
              const SizedBox(height: 8),
              Text(
                distancia == null
                    ? 'Falta ubicar el paradero.'
                    : dentro
                        ? 'A ${distancia.round()} m del trazado de ${v.nombre}.'
                        : 'Está a ${distancia.round()} m del trazado: debe estar a 150 m o menos (RN-003).',
                key: const Key('distancia-trazado'),
                style: TextStyle(
                  color: dentro ? ColoresRutaSur.vigenteTexto : ColoresRutaSur.noConfiableTexto,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('guardar-paradero'),
                  onPressed: valido && !_guardando ? _guardarFormulario : null,
                  child: const Text('Guardar'),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _campoCoordenada(TextEditingController c, String etiqueta, VoidCallback cambiar, String clave) {
    return TextField(
      key: Key(clave),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
      onChanged: (_) => cambiar(),
    );
  }

  Widget _mapaVariante(VarianteAdmin v) {
    final e = _edicion;
    final punto = e?.ubicacion;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        key: ValueKey('mapa-${v.clave}'),
        mapController: _mapa,
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(v.trazado),
            padding: const EdgeInsets.all(32),
          ),
          minZoom: 10,
          maxZoom: 19,
          onTap: e == null ? null : (_, p) => setState(() => e.moverA(p)),
        ),
        children: [
          if (widget.mostrarTeselas)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pe.edu.ucsm.rutasur',
            ),
          PolylineLayer(polylines: [
            Polyline(points: v.trazado, color: ColoresRutaSur.deRamal(v.ramal), strokeWidth: 5),
          ]),
          MarkerLayer(markers: [
            for (final p in v.paraderos)
              Marker(
                point: p.ubicacion,
                width: 28,
                height: 28,
                child: Tooltip(
                  message: '${p.orden}. ${p.nombre}',
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.tramoComun ? ColoresRutaSur.tramoComun : ColoresRutaSur.deRamal(v.ramal),
                        width: 4,
                      ),
                    ),
                  ),
                ),
              ),
            if (punto != null)
              Marker(
                point: punto,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, size: 40, color: Colors.black),
              ),
          ]),
          if (widget.mostrarTeselas) SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
        ],
      ),
    );
  }
}

/// Estado del formulario A-03a.
class _Edicion {
  _Edicion(this.original)
      : nombre = TextEditingController(text: original?.nombre ?? ''),
        referencia = TextEditingController(text: original?.referencia ?? ''),
        lat = TextEditingController(text: original?.ubicacion.latitude.toStringAsFixed(6) ?? ''),
        lon = TextEditingController(text: original?.ubicacion.longitude.toStringAsFixed(6) ?? ''),
        tramoComun = original?.tramoComun ?? false,
        activo = original?.activo ?? true;

  final ParaderoAdmin? original;
  final TextEditingController nombre;
  final TextEditingController referencia;
  final TextEditingController lat;
  final TextEditingController lon;
  bool tramoComun;
  bool activo;
  bool agregarAVariante = true;

  String get _nombreLimpio => nombre.text.trim().split(RegExp(r'\s+')).join(' ');

  bool get nombreValido => _nombreLimpio.length >= 3 && _nombreLimpio.length <= 80;

  bool get referenciaValida => referencia.text.trim().length <= 120;

  LatLng? get ubicacion {
    final a = double.tryParse(lat.text);
    final o = double.tryParse(lon.text);
    if (a == null || o == null || a.abs() > 90 || o.abs() > 180) return null;
    return LatLng(a, o);
  }

  void moverA(LatLng p) {
    lat.text = p.latitude.toStringAsFixed(6);
    lon.text = p.longitude.toStringAsFixed(6);
  }

  DatosParadero get datos => DatosParadero(
        nombre: _nombreLimpio,
        referencia: referencia.text.trim().isEmpty ? null : referencia.text.trim(),
        ubicacion: ubicacion!,
        tramoComun: tramoComun,
        activo: activo,
      );

  void dispose() {
    nombre.dispose();
    referencia.dispose();
    lat.dispose();
    lon.dispose();
  }
}

class _DialogoHorario extends StatefulWidget {
  const _DialogoHorario({required this.actual});

  final HorarioLinea actual;

  @override
  State<_DialogoHorario> createState() => _DialogoHorarioState();
}

class _DialogoHorarioState extends State<_DialogoHorario> {
  late final _inicio = TextEditingController(text: widget.actual.inicio);
  late final _fin = TextEditingController(text: widget.actual.fin);
  static final _formato = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  @override
  void dispose() {
    _inicio.dispose();
    _fin.dispose();
    super.dispose();
  }

  String? get _error {
    if (!_formato.hasMatch(_inicio.text) || !_formato.hasMatch(_fin.text)) {
      return 'Escribe las horas como 05:00.';
    }
    if (_fin.text.compareTo(_inicio.text) <= 0) {
      return 'La hora de fin debe ser posterior a la de inicio (RN-009).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Horario referencial de la línea'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('El pasajero lo ve cuando no hay unidades en circulación.'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('hora-inicio'),
                controller: _inicio,
                decoration: const InputDecoration(labelText: 'Desde', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('hora-fin'),
                controller: _fin,
                decoration: const InputDecoration(labelText: 'Hasta', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error, key: const Key('error-horario'), style: const TextStyle(color: ColoresRutaSur.noConfiableTexto)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('guardar-horario'),
          onPressed: error == null
              ? () => Navigator.of(context).pop(HorarioLinea(_inicio.text, _fin.text))
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DialogoAgregar extends StatefulWidget {
  const _DialogoAgregar({required this.variante, required this.candidatos});

  final VarianteAdmin variante;
  final List<ParaderoAdmin> candidatos;

  @override
  State<_DialogoAgregar> createState() => _DialogoAgregarState();
}

class _DialogoAgregarState extends State<_DialogoAgregar> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final f = _filtro.toLowerCase();
    final lista = [
      for (final p in widget.candidatos)
        if (f.isEmpty || p.nombre.toLowerCase().contains(f) || p.codigo.contains(f)) p,
    ];
    return AlertDialog(
      title: Text('Agregar a ${widget.variante.nombre}'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('filtro-agregar'),
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o código',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            const Text('Solo aparecen paraderos activos a 150 m o menos de este trazado.',
                style: TextStyle(color: ColoresRutaSur.textoSecundario)),
            Expanded(
              child: lista.isEmpty
                  ? const Center(child: Text('No hay paraderos para agregar.'))
                  : ListView(
                      children: [
                        for (final p in lista)
                          ListTile(
                            key: Key('candidato-${p.codigo}'),
                            title: Text(p.nombre),
                            subtitle: Text([p.codigo, ...p.variantes].join(' · ')),
                            onTap: () => Navigator.of(context).pop(p),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))],
    );
  }
}
