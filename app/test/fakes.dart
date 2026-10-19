import 'package:latlong2/latlong.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/repositorio.dart';

/// Repositorio falso: responde lo que la prueba le indica, sin red.
class RepositorioFalso implements RepositorioRutaSur {
  RepositorioFalso({this.linea, this.unidades = const [], this.llegadasPorParadero = const {}});

  Linea? linea;
  List<UnidadActiva> unidades;
  Map<String, List<Llegada>> llegadasPorParadero;

  /// Si se asigna, todas las consultas lanzan esta excepción.
  Exception? fallo;
  int consultasUnidades = 0;

  @override
  Future<Linea> obtenerLinea() async {
    if (fallo != null) throw fallo!;
    return linea!;
  }

  @override
  Future<List<UnidadActiva>> unidadesActivas() async {
    consultasUnidades++;
    if (fallo != null) throw fallo!;
    return unidades;
  }

  @override
  Future<List<Llegada>> llegadas(String codigoParadero) async {
    if (fallo != null) throw fallo!;
    return llegadasPorParadero[codigoParadero] ?? const [];
  }
}

/// Línea recta norte–sur de unos 2,2 km con tres paraderos, dos de ellos en el tramo común.
Linea lineaDePrueba() => const Linea(
      codigo: 'LB',
      nombre: 'Línea de prueba',
      horaInicio: '05:00',
      horaFin: '21:00',
      variantes: [
        Variante(
          ramal: Ramal.mollebaya,
          sentido: Sentido.ida,
          destino: 'Centro (2 de Mayo)',
          longitudM: 2223.9,
          trazado: [LatLng(-16.45, -71.5), LatLng(-16.46, -71.5), LatLng(-16.47, -71.5)],
          paraderos: [
            ParaderoDeVariante(
              codigo: 'stp_001',
              nombre: 'Inicio del ramal',
              referencia: null,
              ubicacion: LatLng(-16.45, -71.5),
              orden: 1,
              distanciaDesdeInicioM: 0,
              tramoComun: false,
            ),
            ParaderoDeVariante(
              codigo: 'stp_002',
              nombre: 'Plaza Characato',
              referencia: 'Frente a la iglesia',
              ubicacion: LatLng(-16.46, -71.5),
              orden: 2,
              distanciaDesdeInicioM: 1111.9,
              tramoComun: true,
            ),
            ParaderoDeVariante(
              codigo: 'stp_003',
              nombre: 'Centro (2 de Mayo)',
              referencia: null,
              ubicacion: LatLng(-16.47, -71.5),
              orden: 3,
              distanciaDesdeInicioM: 2223.9,
              tramoComun: true,
            ),
          ],
        ),
      ],
    );

UnidadActiva unidadDePrueba({String etiqueta = '07', int antiguedadS = 10}) => UnidadActiva(
      etiqueta: etiqueta,
      ramal: Ramal.mollebaya,
      sentido: Sentido.ida,
      destino: 'Centro (2 de Mayo)',
      ubicacion: const LatLng(-16.455, -71.5),
      rumbo: 180,
      antiguedadS: antiguedadS,
    );
