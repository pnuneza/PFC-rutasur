/// Configuración de la aplicación (paquete core, Tabla 32 de P05).
abstract final class Config {
  /// Dirección del servicio RutaSur.
  ///
  /// Se cambia sin tocar el código con `--dart-define=API_URL=...`.
  /// Por defecto apunta a la PC donde corre el backend vista desde el
  /// emulador de Android, que la expone en la dirección especial 10.0.2.2.
  static const String urlApi = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Frecuencia de consulta de unidades y llegadas (P05, Tabla 38: consulta periódica).
  static const Duration intervaloConsulta = Duration(seconds: 15);

  /// Tiempo máximo de espera de cada petición.
  static const Duration tiempoEspera = Duration(seconds: 10);
}
