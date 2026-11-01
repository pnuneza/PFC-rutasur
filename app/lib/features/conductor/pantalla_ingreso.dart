/// C-01 Inicio de sesión del conductor (P06 Tabla 45).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import 'controlador_conductor.dart';

final _formatoUsuario = RegExp(r'^[a-z0-9._]{4,30}$');

class PantallaIngreso extends StatefulWidget {
  const PantallaIngreso({super.key, required this.controlador});

  final ControladorConductor controlador;

  @override
  State<PantallaIngreso> createState() => _PantallaIngresoState();
}

class _PantallaIngresoState extends State<PantallaIngreso> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _mostrarClave = false;

  bool get _completo =>
      _formatoUsuario.hasMatch(_usuario.text) && _clave.text.length >= 8 && _clave.text.length <= 64;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _ingresar() {
    if (_completo && !widget.controlador.ocupado) {
      widget.controlador.ingresar(_usuario.text, _clave.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.directions_bus, size: 64, color: ColoresRutaSur.primario),
            const SizedBox(height: 12),
            Text('RutaSur · Conductor',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Ingresa con el usuario de tu unidad.', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            TextField(
              key: const Key('usuario'),
              controller: _usuario,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              // Solo minúsculas, números, punto y guion bajo; sin espacios (Tabla 45)
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                _Minusculas(),
                LengthLimitingTextInputFormatter(30),
              ],
              decoration: const InputDecoration(
                labelText: 'Usuario',
                hintText: 'unidad07',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('clave'),
              controller: _clave,
              obscureText: !_mostrarClave,
              autocorrect: false,
              enableSuggestions: false,
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
            if (c.errorIngreso != null) ...[
              const SizedBox(height: 16),
              _MensajeError(texto: c.errorIngreso!),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('ingresar'),
                onPressed: _completo && !c.ocupado ? _ingresar : null,
                child: c.ocupado
                    ? const SizedBox(
                        width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                    : const Text('Ingresar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Minusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) =>
      nuevo.copyWith(text: nuevo.text.toLowerCase());
}

class _MensajeError extends StatelessWidget {
  const _MensajeError({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ColoresRutaSur.noConfiableFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: ColoresRutaSur.noConfiableTexto),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(color: ColoresRutaSur.noConfiableTexto)),
          ),
        ],
      ),
    );
  }
}
