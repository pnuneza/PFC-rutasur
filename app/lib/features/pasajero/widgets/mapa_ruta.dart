/// Mapa con el trazado, los paraderos y las unidades (P-01; RF-001, RF-002, RF-003).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/tema.dart';
import '../../../domain/geometria.dart';
import '../../../domain/modelos.dart';
import 'marcadores.dart';

class MapaRuta extends StatelessWidget {
  const MapaRuta({
    super.key,
    required this.linea,
    required this.paraderos,
    required this.unidades,
    required this.atenuarUnidades,
    required this.alTocarParadero,
    required this.alTocarUnidad,
    this.ubicacionUsuario,
    this.controlador,
    this.mostrarTeselas = true,
    this.siempreVisibles = const {},
    this.lineaCompleta,
  });

  final Linea linea;
  final List<ParaderoEnMapa> paraderos;
  final List<UnidadActiva> unidades;
  final bool atenuarUnidades;
  final ValueChanged<ParaderoEnMapa> alTocarParadero;
  final ValueChanged<UnidadActiva> alTocarUnidad;

  /// Punto azul del pasajero (RF-006); solo se dibuja, nunca se envía.
  final LatLng? ubicacionUsuario;

  /// Para centrar el mapa en el pasajero con «Mi ubicación».
  final MapController? controlador;

  /// Fondo de OpenStreetMap; las pruebas lo omiten porque no tienen internet.
  final bool mostrarTeselas;

  /// Paraderos que se ven a cualquier zoom aunque no sean principales: favoritos y el
  /// más cercano (0.6.1).
  final Set<String> siempreVisibles;

  /// Línea con todas sus variantes: fija el encuadre y el área permitida, que no deben
  /// cambiar al filtrar por sentido (la cámara quedaría fuera del área, D-14).
  final Linea? lineaCompleta;

  @override
  Widget build(BuildContext context) {
    final puntos = [for (final v in (lineaCompleta ?? linea).variantes) ...v.trazado];
    final limites = LatLngBounds.fromPoints(puntos);
    final comun = tramoComun(linea);

    return FlutterMap(
      mapController: controlador,
      options: MapOptions(
        // Con un controlador externo («Mi ubicación») la cámara inicial debe caer dentro
        // del corredor desde el principio; si no, flutter_map la rechaza (D-14).
        initialCenter: limites.center,
        initialCameraFit: CameraFit.bounds(
          bounds: limites,
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 140),
        ),
        minZoom: 11,
        maxZoom: 18,
        // Desplazamiento limitado al corredor de la línea (P06, P-01 #4)
        cameraConstraint: CameraConstraint.containCenter(bounds: _ampliar(limites)),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        if (mostrarTeselas)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'pe.edu.ucsm.rutasur',
          ),
        PolylineLayer(
          polylines: [
            // Cada variante con el color de su ramal...
            for (final variante in linea.variantes)
              Polyline(
                points: variante.trazado,
                color: ColoresRutaSur.deRamal(variante.ramal),
                strokeWidth: 5,
              ),
            // ...y el tramo común encima, en gris pizarra (RF-001)
            if (comun != null)
              Polyline(points: comun, color: ColoresRutaSur.tramoComun, strokeWidth: 7),
          ],
        ),
        _CapaParaderos(
          paraderos: paraderos,
          siempreVisibles: siempreVisibles,
          alTocar: alTocarParadero,
        ),
        if (ubicacionUsuario != null)
          MarkerLayer(
            markers: [
              Marker(
                point: ubicacionUsuario!,
                width: 24,
                height: 24,
                child: Semantics(
                  label: 'Tu ubicación',
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final unidad in unidades)
              Marker(
                point: unidad.ubicacion,
                width: MarcadorUnidad.ancho,
                height: MarcadorUnidad.alto,
                child: MarcadorUnidad(
                  unidad: unidad,
                  atenuada: atenuarUnidades,
                  alTocar: () => alTocarUnidad(unidad),
                ),
              ),
          ],
        ),
        // Atribución obligatoria por la política de uso de OpenStreetMap
        // El crédito acompaña al fondo de OpenStreetMap
        if (mostrarTeselas) SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
      ],
    );
  }

  /// Margen alrededor de la ruta para poder mover un poco el mapa.
  static LatLngBounds _ampliar(LatLngBounds b) => LatLngBounds(
        LatLng(b.south - 0.02, b.west - 0.02),
        LatLng(b.north + 0.02, b.east + 0.02),
      );
}

/// Zoom desde el que se ven todos los paraderos; más lejos, solo los principales (0.6.1).
const double zoomTodosLosParaderos = 14;

/// Con el mapa alejado solo se dibujan los paraderos principales (plazas, cruces,
/// terminales), los favoritos y el más cercano: con 80 paraderos a la vez, el mapa de
/// la ruta completa no se entendía (prueba con usuario del 01/11/2026).
class _CapaParaderos extends StatelessWidget {
  const _CapaParaderos({
    required this.paraderos,
    required this.siempreVisibles,
    required this.alTocar,
  });

  final List<ParaderoEnMapa> paraderos;
  final Set<String> siempreVisibles;
  final ValueChanged<ParaderoEnMapa> alTocar;

  @override
  Widget build(BuildContext context) {
    // Se reconstruye cada vez que cambia la cámara
    final cerca = MapCamera.of(context).zoom >= zoomTodosLosParaderos;
    return MarkerLayer(
      markers: [
        for (final paradero in paraderos)
          if (cerca || paradero.principal || siempreVisibles.contains(paradero.codigo))
            Marker(
              point: paradero.ubicacion,
              // Área táctil de 48 dp (pauta de Android); el círculo visible sigue de 18
              width: 48,
              height: 48,
              child: MarcadorParadero(
                key: ValueKey('marcador-${paradero.codigo}'),
                paradero: paradero,
                destacado: paradero.principal,
                alTocar: () => alTocar(paradero),
              ),
            ),
      ],
    );
  }
}
