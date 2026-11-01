/// GPS, permisos y servicio en primer plano del teléfono (paquete data, RF-011).
///
/// En Android, geolocator inicia un servicio en primer plano con la notificación
/// permanente N-01: el sistema no detiene la emisión con la pantalla apagada o la
/// aplicación minimizada (Android Developers, s. f.).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permisos;

import '../core/config.dart';
import '../domain/conductor.dart';

class GpsGeolocator implements FuenteUbicacion {
  StreamSubscription<Position>? _suscripcion;

  bool get _esAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<PermisosTelefono> revisarPermisos() async {
    return PermisosTelefono(
      ubicacion: await _estadoUbicacion(),
      notificaciones: _esAndroid ? _desde(await permisos.Permission.notification.status) : EstadoPermiso.noAplica,
      bateria: _esAndroid
          ? _desde(await permisos.Permission.ignoreBatteryOptimizations.status)
          : EstadoPermiso.noAplica,
    );
  }

  Future<EstadoPermiso> _estadoUbicacion() async {
    if (!await Geolocator.isLocationServiceEnabled()) return EstadoPermiso.denegado;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always || LocationPermission.whileInUse => EstadoPermiso.concedido,
      LocationPermission.deniedForever => EstadoPermiso.denegadoSiempre,
      _ => EstadoPermiso.denegado,
    };
  }

  EstadoPermiso _desde(permisos.PermissionStatus estado) {
    if (estado.isGranted || estado.isLimited) return EstadoPermiso.concedido;
    if (estado.isPermanentlyDenied || estado.isRestricted) return EstadoPermiso.denegadoSiempre;
    return EstadoPermiso.denegado;
  }

  @override
  Future<void> pedirUbicacion() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings(); // el GPS está apagado
      return;
    }
    final actual = await Geolocator.checkPermission();
    if (actual == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }
    // Primero «mientras se usa»; si ya lo tiene, Android ofrece «todo el tiempo»
    await Geolocator.requestPermission();
  }

  @override
  Future<void> pedirNotificaciones() async {
    if (!_esAndroid) return;
    if (await permisos.Permission.notification.isPermanentlyDenied) {
      await permisos.openAppSettings();
    } else {
      await permisos.Permission.notification.request();
    }
  }

  @override
  Future<void> pedirSinRestriccionDeBateria() async {
    if (_esAndroid) await permisos.Permission.ignoreBatteryOptimizations.request();
  }

  @override
  Future<void> abrirAjustes() => Geolocator.openAppSettings();

  @override
  Future<void> iniciar({
    required String textoNotificacion,
    required void Function(PosicionGps) alRecibir,
  }) async {
    await detener();
    final LocationSettings ajustes = _esAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: Config.intervaloCaptura,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'RutaSur · transmitiendo',
              notificationText: textoNotificacion,
              enableWakeLock: true,
              setOngoing: true, // N-01: no puede descartarse mientras dure la emisión
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
    _suscripcion = Geolocator.getPositionStream(locationSettings: ajustes).listen(
      (p) => alRecibir(PosicionGps(
        lat: p.latitude,
        lon: p.longitude,
        precisionM: p.accuracy,
        velocidadMs: p.speed >= 0 ? p.speed : null,
        rumbo: p.heading >= 0 ? p.heading : null,
      )),
      onError: (Object _) {}, // sin señal GPS: C-03 lo muestra por falta de lecturas
    );
  }

  @override
  Future<void> detener() async {
    await _suscripcion?.cancel();
    _suscripcion = null;
  }
}
