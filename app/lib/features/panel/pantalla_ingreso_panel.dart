/// A-01 Inicio de sesión del panel (P06 Tabla 46; CU-13, RF-014).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import '../../domain/panel.dart';
import '../../domain/repositorio.dart';
import 'comun.dart';

final _formatoUsuario = RegExp(r'^[a-z0-9._]{4,30}$');

class PantallaIngresoPanel extends StatefulWidget {
  const PantallaIngresoPanel({super.key, required this.servicio, required this.alIngresar, this.aviso});

  final ServicioPanel servicio;
  final ValueChanged<AccesoPanel> alIngresar;

  /// Por ejemplo, «Tu sesión terminó» al volver por un token vencido.
  final String? aviso;

  @override
  State<PantallaIngresoPanel> createState() => _PantallaIngresoPanelState();
}

class _PantallaIngresoPanelState extends State<PantallaIngresoPanel> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _ocupado = false;
  bool _mostrarClave = false;
  String? _error;

  bool get _completo =>
      _formatoUsuario.hasMatch(_usuario.text) && _clave.text.length >= 8 && _clave.text.length <= 64;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_completo || _ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final acceso = await widget.servicio.iniciarSesion(_usuario.text, _clave.text);
      widget.alIngresar(acceso);
    } on ErrorServicio catch (e) {
      setState(() => _error = switch (e.codigo) {
            'INVALID_CREDENTIALS' => 'Usuario o contraseña incorrectos.',
            'ACCOUNT_LOCKED' =>
              'La cuenta está bloqueada por 5 intentos fallidos. Vuelve a intentarlo en '
                  '${((e.reintentarEnS ?? 900) / 60).ceil()} min.',
            'RATE_LIMITED' => 'Demasiados intentos seguidos. Espera un minuto.',
            'FORBIDDEN' => e.mensaje,
            _ => mensajeDeError(e),
          });
    } on Object catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 56, color: ColoresRutaSur.primario),
                    const SizedBox(height: 8),
                    Text('RutaSur · Panel', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const Text('Línea LB · administración y moderación', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (widget.aviso != null) ...[
                      Text(widget.aviso!, key: const Key('aviso-sesion'), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: const Key('usuario'),
                      controller: _usuario,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(30),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      onChanged: (v) {
                        final minusculas = v.toLowerCase();
                        if (minusculas != v) {
                          _usuario.value = _usuario.value.copyWith(text: minusculas);
                        }
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('clave'),
                      controller: _clave,
                      obscureText: !_mostrarClave,
                      inputFormatters: [LengthLimitingTextInputFormatter(64)],
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _mostrarClave ? 'Ocultar contraseña' : 'Mostrar contraseña',
                          icon: Icon(_mostrarClave ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _mostrarClave = !_mostrarClave),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _ingresar(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AvisoError(mensaje: _error!),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('ingresar'),
                        onPressed: _completo && !_ocupado ? _ingresar : null,
                        child: _ocupado
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
                            : const Text('Ingresar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
