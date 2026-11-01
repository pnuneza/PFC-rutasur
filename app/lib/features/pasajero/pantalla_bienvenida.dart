/// P-00 Bienvenida: solo en la primera apertura (P06 Tabla 44; RF-006, RNF-01, RNF-14).
///
/// Dos caminos con la misma visibilidad: usar la ubicación o seguir sin ella. Negarla
/// no limita nada esencial; solo impide proponer el paradero más cercano.
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import 'widgets/paneles.dart';

class PantallaBienvenida extends StatelessWidget {
  const PantallaBienvenida({super.key, required this.alUsarUbicacion, required this.alOmitir});

  final VoidCallback alUsarUbicacion;
  final VoidCallback alOmitir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.directions_bus, size: 72, color: ColoresRutaSur.primario),
                  const SizedBox(height: 16),
                  Text(
                    'Mira cuándo llega tu bus',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'RutaSur te muestra en el mapa dónde están los buses de la línea LB '
                    'y en cuántos minutos llegan a tu paradero.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  const _Compromiso(
                    icono: Icons.person_off_outlined,
                    texto: 'No necesitas crear una cuenta ni dar tus datos.',
                  ),
                  const _Compromiso(
                    icono: Icons.phone_android,
                    texto: 'Tu ubicación se usa solo en tu teléfono para buscar tu paradero '
                        'más cercano. Nunca se envía.',
                  ),
                  const _Compromiso(
                    icono: Icons.cell_tower,
                    texto: 'La posición de los buses la envían los teléfonos de sus conductores.',
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => mostrarAyuda(context, linea: null),
                      child: const Text('Política de privacidad'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      key: const Key('usar-ubicacion'),
                      onPressed: alUsarUbicacion,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Usar mi ubicación'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      key: const Key('ahora-no'),
                      onPressed: alOmitir,
                      child: const Text('Ahora no'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Compromiso extends StatelessWidget {
  const _Compromiso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: ColoresRutaSur.primario),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
