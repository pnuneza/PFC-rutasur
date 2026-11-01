/// A-04 Unidades y cuentas y formulario A-04a (P06 Tabla 46; CU-15, RF-016, RN-001, RN-011).
///
/// No existe ningún campo para nombre, DNI ni teléfono. La contraseña temporal se genera
/// en el servidor y se muestra una sola vez.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import '../../domain/panel.dart';
import 'comun.dart';

final _formatoUsuario = RegExp(r'^[a-z0-9._]{4,30}$');
final _formatoEtiqueta = RegExp(r'^[A-Za-z0-9-]{1,20}$');

class PantallaCuentas extends StatefulWidget {
  const PantallaCuentas({super.key, required this.contexto, DateTime Function()? reloj})
      : reloj = reloj ?? DateTime.now;

  final ContextoPanel contexto;
  final DateTime Function() reloj;

  @override
  State<PantallaCuentas> createState() => _PantallaCuentasState();
}

class _PantallaCuentasState extends State<PantallaCuentas> {
  List<UnidadAdmin> _unidades = const [];
  List<CuentaAdmin> _conductores = const [];
  List<CuentaAdmin> _panel = const [];
  String _filtro = '';
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;

  ContextoPanel get _c => widget.contexto;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final datos = await _c.ejecutar(
          (s, a) async => (await s.unidades(a), await s.cuentasConductor(a), await s.cuentasPanel(a)));
      if (!mounted || datos == null) return;
      final (unidades, conductores, panel) = datos;
      setState(() {
        _unidades = unidades;
        _conductores = conductores;
        _panel = panel;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<T?> _hacer<T>(String exito, Future<T?> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      final r = await accion();
      if (r == null) return null;
      await _cargar();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exito)));
      return r;
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  bool _coincide(String texto) => _filtro.isEmpty || texto.toLowerCase().contains(_filtro.toLowerCase());

  // ------------------------------------------------------------------
  // Unidades
  // ------------------------------------------------------------------
  Future<void> _registrarUnidad() async {
    final etiqueta = await showDialog<String>(context: context, builder: (_) => const _DialogoUnidad());
    if (etiqueta == null) return;
    await _hacer('Unidad $etiqueta registrada.', () => _c.ejecutar((s, a) => s.registrarUnidad(a, etiqueta)));
  }

  Future<void> _cambiarUnidad(UnidadAdmin u) async {
    if (u.activa) {
      final ok = await confirmar(
        context,
        titulo: 'Deshabilitar la unidad ${u.etiqueta}',
        mensaje: 'Si está transmitiendo, su turno se cierra y deja de verse en el mapa. Su '
            'cuenta de conductor no podrá ingresar hasta que la vuelvas a habilitar.',
        accion: 'Deshabilitar',
        peligrosa: true,
      );
      if (!ok) return;
    }
    await _hacer(u.activa ? 'Unidad ${u.etiqueta} deshabilitada.' : 'Unidad ${u.etiqueta} habilitada.',
        () => _c.ejecutar((s, a) => s.habilitarUnidad(a, u.id, !u.activa)));
  }

  // ------------------------------------------------------------------
  // Cuentas
  // ------------------------------------------------------------------
  Future<void> _nuevaCuentaConductor() async {
    final sinCuenta = [for (final u in _unidades) if (u.usuario == null && u.activa) u];
    final datos = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _DialogoCuentaConductor(unidades: sinCuenta),
    );
    if (datos == null) return;
    final (unidadId, usuario) = datos;
    final creada = await _hacer('Cuenta $usuario creada.',
        () => _c.ejecutar((s, a) => s.crearCuentaConductor(a, unidadId, usuario)));
    if (creada != null && mounted) {
      await mostrarClaveTemporal(context, usuario: usuario, clave: creada.contrasenaTemporal!);
    }
  }

  Future<void> _nuevaCuentaPanel() async {
    final datos = await showDialog<(String, RolPanel)>(context: context, builder: (_) => const _DialogoCuentaPanel());
    if (datos == null) return;
    final (usuario, rol) = datos;
    final creada = await _hacer('Cuenta $usuario creada.',
        () => _c.ejecutar((s, a) => s.crearCuentaPanel(a, usuario, rol)));
    if (creada != null && mounted) {
      await mostrarClaveTemporal(context, usuario: usuario, clave: creada.contrasenaTemporal!);
    }
  }

  Future<void> _actuar(CuentaAdmin cuenta, AccionCuenta accion, {required bool panel}) async {
    final (titulo, mensaje, boton, peligrosa) = switch (accion) {
      AccionCuenta.restablecer => (
          'Restablecer la contraseña de ${cuenta.usuario}',
          'Se genera una contraseña temporal nueva y la anterior deja de servir.',
          'Restablecer',
          false,
        ),
      AccionCuenta.desactivar => (
          'Desactivar ${cuenta.usuario}',
          'La cuenta no podrá ingresar hasta que la actives de nuevo.',
          'Desactivar',
          true,
        ),
      AccionCuenta.activar => ('Activar ${cuenta.usuario}', 'La cuenta podrá volver a ingresar.', 'Activar', false),
      AccionCuenta.desbloquear => (
          'Desbloquear ${cuenta.usuario}',
          'Se quita el bloqueo por intentos fallidos antes de los 15 minutos.',
          'Desbloquear',
          false,
        ),
    };
    if (!await confirmar(context, titulo: titulo, mensaje: mensaje, accion: boton, peligrosa: peligrosa)) {
      return;
    }
    final r = await _hacer('Listo: ${cuenta.usuario}.',
        () => _c.ejecutar((s, a) => s.actuarSobreCuenta(a, cuenta.id, accion, panel: panel)));
    final clave = r?.contrasenaTemporal;
    if (clave != null && mounted) await mostrarClaveTemporal(context, usuario: cuenta.usuario, clave: clave);
  }

  // ------------------------------------------------------------------
  // Interfaz
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EncabezadoPantalla(
            titulo: 'Unidades y cuentas',
            subtitulo: 'Sin datos personales: no se guarda nombre, DNI ni teléfono de nadie (RN-011).',
            acciones: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: const Key('buscador'),
                  decoration: const InputDecoration(
                    labelText: 'Buscar usuario o unidad',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filtro = v.trim()),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AvisoError(mensaje: _error!, alReintentar: _cargar),
            ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(key: Key('pestana-unidades'), text: 'Unidades'),
              Tab(key: Key('pestana-conductores'), text: 'Cuentas de conductor'),
              Tab(key: Key('pestana-panel'), text: 'Cuentas del panel'),
            ],
          ),
          if (_ocupado) const LinearProgressIndicator(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [_tablaUnidades(), _tablaConductores(), _tablaPanel()]),
          ),
        ],
      ),
    );
  }

  Widget _contenedor({required Widget boton, required Widget tabla}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          boton,
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabla),
        ],
      ),
    );
  }

  Widget _tablaUnidades() {
    return _contenedor(
      boton: FilledButton.icon(
        key: const Key('registrar-unidad'),
        onPressed: _ocupado ? null : _registrarUnidad,
        icon: const Icon(Icons.add),
        label: const Text('Registrar unidad'),
      ),
      tabla: DataTable(
        key: const Key('tabla-unidades'),
        columns: const [
          DataColumn(label: Text('Unidad')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Cuenta de conductor')),
          DataColumn(label: Text('Acciones')),
        ],
        rows: [
          for (final u in _unidades)
            if (_coincide(u.etiqueta) || _coincide(u.usuario ?? ''))
              DataRow(cells: [
                DataCell(Text(u.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(_estado(u.activa, 'Habilitada', 'Deshabilitada')),
                DataCell(Text(u.usuario ?? 'sin cuenta')),
                DataCell(TextButton(
                  key: Key('cambiar-unidad-${u.etiqueta}'),
                  onPressed: _ocupado ? null : () => _cambiarUnidad(u),
                  child: Text(u.activa ? 'Deshabilitar' : 'Habilitar'),
                )),
              ]),
        ],
      ),
    );
  }

  Widget _tablaConductores() {
    return _contenedor(
      boton: FilledButton.icon(
        key: const Key('nueva-cuenta-conductor'),
        onPressed: _ocupado ? null : _nuevaCuentaConductor,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nueva cuenta de conductor'),
      ),
      tabla: _tablaCuentas(
        [for (final c in _conductores) if (_coincide(c.usuario) || _coincide(c.etiquetaUnidad ?? '')) c],
        panel: false,
      ),
    );
  }

  Widget _tablaPanel() {
    return _contenedor(
      boton: FilledButton.icon(
        key: const Key('nueva-cuenta-panel'),
        onPressed: _ocupado ? null : _nuevaCuentaPanel,
        icon: const Icon(Icons.admin_panel_settings_outlined),
        label: const Text('Nueva cuenta del panel'),
      ),
      tabla: _tablaCuentas([for (final c in _panel) if (_coincide(c.usuario)) c], panel: true),
    );
  }

  Widget _tablaCuentas(List<CuentaAdmin> cuentas, {required bool panel}) {
    final ahora = widget.reloj();
    return DataTable(
      key: Key(panel ? 'tabla-panel' : 'tabla-conductores'),
      columns: [
        const DataColumn(label: Text('Usuario')),
        DataColumn(label: Text(panel ? 'Rol' : 'Unidad')),
        const DataColumn(label: Text('Estado')),
        const DataColumn(label: Text('Acciones')),
      ],
      rows: [
        for (final c in cuentas)
          DataRow(cells: [
            DataCell(Text(c.usuario, style: const TextStyle(fontWeight: FontWeight.w700))),
            DataCell(Text(panel ? (c.rol == 'ADMINISTRADOR' ? 'Administrador' : 'Moderador') : (c.etiquetaUnidad ?? '—'))),
            DataCell(c.bloqueada(ahora)
                ? Etiqueta(
                    texto: 'Bloqueada hasta ${fechaHora(c.bloqueadaHasta!).split(' ').last}',
                    colorTexto: ColoresRutaSur.demoradoTexto,
                    colorFondo: ColoresRutaSur.demoradoFondo,
                  )
                : _estado(c.activa, 'Activa', 'Desactivada')),
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                key: Key('restablecer-${c.usuario}'),
                onPressed: _ocupado ? null : () => _actuar(c, AccionCuenta.restablecer, panel: panel),
                child: const Text('Restablecer contraseña'),
              ),
              TextButton(
                key: Key('${c.activa ? 'desactivar' : 'activar'}-${c.usuario}'),
                onPressed: _ocupado
                    ? null
                    : () => _actuar(c, c.activa ? AccionCuenta.desactivar : AccionCuenta.activar, panel: panel),
                child: Text(c.activa ? 'Desactivar' : 'Activar'),
              ),
              if (c.bloqueada(ahora))
                TextButton(
                  key: Key('desbloquear-${c.usuario}'),
                  onPressed: _ocupado ? null : () => _actuar(c, AccionCuenta.desbloquear, panel: panel),
                  child: const Text('Desbloquear'),
                ),
            ])),
          ]),
      ],
    );
  }

  Widget _estado(bool activo, String si, String no) => activo
      ? Etiqueta(texto: si, colorTexto: ColoresRutaSur.vigenteTexto, colorFondo: ColoresRutaSur.vigenteFondo)
      : Etiqueta(texto: no, colorTexto: ColoresRutaSur.noConfiableTexto, colorFondo: ColoresRutaSur.noConfiableFondo);
}

const _avisoPrivacidad = Text(
  'Por privacidad no se registra el nombre, el DNI ni el teléfono de la persona (RN-011). '
  'Al crear la cuenta se genera una contraseña temporal que se muestra una sola vez.',
  key: Key('aviso-privacidad'),
  style: TextStyle(color: ColoresRutaSur.textoSecundario),
);

class _CampoUsuario extends StatelessWidget {
  const _CampoUsuario({required this.controlador, required this.alCambiar});

  final TextEditingController controlador;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final texto = controlador.text;
    return TextField(
      key: const Key('campo-usuario'),
      controller: controlador,
      autocorrect: false,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')), LengthLimitingTextInputFormatter(30)],
      decoration: InputDecoration(
        labelText: 'Usuario',
        helperText: 'De 4 a 30: minúsculas, números, punto o guion bajo',
        errorText: texto.isEmpty || _formatoUsuario.hasMatch(texto) ? null : 'Mínimo 4 caracteres',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => alCambiar(),
    );
  }
}

class _DialogoUnidad extends StatefulWidget {
  const _DialogoUnidad();

  @override
  State<_DialogoUnidad> createState() => _DialogoUnidadState();
}

class _DialogoUnidadState extends State<_DialogoUnidad> {
  final _etiqueta = TextEditingController();

  @override
  void dispose() {
    _etiqueta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valida = _formatoEtiqueta.hasMatch(_etiqueta.text);
    return AlertDialog(
      title: const Text('Registrar unidad'),
      content: TextField(
        key: const Key('campo-etiqueta'),
        controller: _etiqueta,
        autofocus: true,
        inputFormatters: [LengthLimitingTextInputFormatter(20)],
        decoration: const InputDecoration(
          labelText: 'Número de la unidad',
          helperText: 'Como se ve en el bus, por ejemplo 15',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('guardar-unidad'),
          onPressed: valida ? () => Navigator.of(context).pop(_etiqueta.text.trim()) : null,
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _DialogoCuentaConductor extends StatefulWidget {
  const _DialogoCuentaConductor({required this.unidades});

  /// Solo unidades habilitadas y sin cuenta: una cuenta por unidad (RN-001).
  final List<UnidadAdmin> unidades;

  @override
  State<_DialogoCuentaConductor> createState() => _DialogoCuentaConductorState();
}

class _DialogoCuentaConductorState extends State<_DialogoCuentaConductor> {
  final _usuario = TextEditingController();
  UnidadAdmin? _unidad;

  @override
  void dispose() {
    _usuario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valida = _unidad != null && _formatoUsuario.hasMatch(_usuario.text);
    return AlertDialog(
      title: const Text('Nueva cuenta de conductor'),
      content: SizedBox(
        width: 420,
        child: widget.unidades.isEmpty
            ? const Text('Todas las unidades habilitadas ya tienen cuenta. Registra primero una unidad nueva.',
                key: Key('sin-unidades-libres'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<UnidadAdmin>(
                    key: const Key('campo-unidad'),
                    initialValue: _unidad,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()),
                    items: [
                      for (final u in widget.unidades)
                        DropdownMenuItem(value: u, child: Text('Unidad ${u.etiqueta}')),
                    ],
                    onChanged: (u) => setState(() {
                      _unidad = u;
                      if (u != null && _usuario.text.isEmpty) _usuario.text = 'unidad${u.etiqueta.toLowerCase()}';
                    }),
                  ),
                  const SizedBox(height: 16),
                  _CampoUsuario(controlador: _usuario, alCambiar: () => setState(() {})),
                  const SizedBox(height: 12),
                  _avisoPrivacidad,
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('crear-cuenta'),
          onPressed: valida ? () => Navigator.of(context).pop((_unidad!.id, _usuario.text)) : null,
          child: const Text('Crear cuenta'),
        ),
      ],
    );
  }
}

class _DialogoCuentaPanel extends StatefulWidget {
  const _DialogoCuentaPanel();

  @override
  State<_DialogoCuentaPanel> createState() => _DialogoCuentaPanelState();
}

class _DialogoCuentaPanelState extends State<_DialogoCuentaPanel> {
  final _usuario = TextEditingController();
  RolPanel _rol = RolPanel.moderador;

  @override
  void dispose() {
    _usuario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valida = _formatoUsuario.hasMatch(_usuario.text);
    return AlertDialog(
      title: const Text('Nueva cuenta del panel'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CampoUsuario(controlador: _usuario, alCambiar: () => setState(() {})),
            const SizedBox(height: 16),
            SegmentedButton<RolPanel>(
              key: const Key('campo-rol'),
              segments: [
                for (final r in RolPanel.values) ButtonSegment(value: r, label: Text(r.nombre)),
              ],
              selected: {_rol},
              onSelectionChanged: (s) => setState(() => _rol = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _rol == RolPanel.moderador
                  ? 'El moderador ve la flota y el registro de eventos.'
                  : 'El administrador además edita rutas, paraderos, unidades y cuentas.',
              style: const TextStyle(color: ColoresRutaSur.textoSecundario),
            ),
            const SizedBox(height: 12),
            _avisoPrivacidad,
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('crear-cuenta'),
          onPressed: valida ? () => Navigator.of(context).pop((_usuario.text, _rol)) : null,
          child: const Text('Crear cuenta'),
        ),
      ],
    );
  }
}
