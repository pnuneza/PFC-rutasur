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

  // --- Aplicación del conductor (P06 Tabla 45, C-03) ---

  /// El servicio gratuito tarda alrededor de un minuto en despertar si estaba apagado.
  static const Duration tiempoEsperaConductor = Duration(seconds: 70);

  /// Una lectura del GPS cada 5 s y un envío cada 15 s (lotes de unas 3 lecturas).
  static const Duration intervaloCaptura = Duration(seconds: 5);
  static const Duration intervaloEnvio = Duration(seconds: 15);

  /// Sin una posición nueva en este tiempo, C-03 muestra «Sin GPS».
  static const Duration sinGpsDespuesDe = Duration(seconds: 20);

  /// Máximo por envío (P06 Tabla 54) y máximo guardado sin señal: unas 7 horas.
  static const int loteMaximo = 200;
  static const int colaMaxima = 5000;
}
