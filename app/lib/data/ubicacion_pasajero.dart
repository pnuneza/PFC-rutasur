/// Ubicación del pasajero (RF-006): solo mientras usa la app y nunca sale del teléfono.
library;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../domain/pasajero.dart';

class UbicacionGeolocator implements UbicacionPasajero {
  @override
  Future<bool> permisoConcedido() async {
    final permiso = await Geolocator.checkPermission();
    return permiso == LocationPermission.whileInUse || permiso == LocationPermission.always;
  }

  @override
  Future<bool> pedirPermiso() async {
    final actual = await Geolocator.checkPermission();
    if (actual == LocationPermission.deniedForever) return false; // el sistema ya no pregunta
    final permiso = await Geolocator.requestPermission();
    return permiso == LocationPermission.whileInUse || permiso == LocationPermission.always;
  }

  @override
  Future<LatLng?> posicionActual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null; // sin señal o sin permiso: simplemente no se propone paradero
    }
  }
}
