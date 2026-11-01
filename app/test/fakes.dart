import 'package:latlong2/latlong.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/pasajero.dart';
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

  /// Búsquedas recibidas, para comprobar que no se consulta con menos de 2 letras.
  final List<String> busquedas = [];

  @override
  Future<List<ParaderoEncontrado>> buscarParaderos(String texto) async {
    busquedas.add(texto);
    if (fallo != null) throw fallo!;
    final buscado = texto.trim().toLowerCase();
    return [
      for (final p in paraderosUnicos(linea ?? lineaDePrueba()))
        if (p.nombre.toLowerCase().contains(buscado))
          ParaderoEncontrado(
            codigo: p.codigo,
            nombre: p.nombre,
            referencia: p.referencia,
            ubicacion: p.ubicacion,
            ramales: p.ramales,
          ),
    ];
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


class PreferenciasEnMemoria implements PreferenciasPasajero {
  bool vista = false;
  List<String> codigos = [];

  @override
  Future<bool> bienvenidaVista() async => vista;
  @override
  Future<void> marcarBienvenidaVista() async => vista = true;
  @override
  Future<List<String>> favoritos() async => List.of(codigos);
  @override
  Future<void> guardarFavoritos(List<String> c) async => codigos = List.of(c);
}

class UbicacionFalsa implements UbicacionPasajero {
  UbicacionFalsa({this.concedido = false, this.posicion, this.concederAlPedir = true});

  bool concedido;
  bool concederAlPedir;
  LatLng? posicion;
  int pedidos = 0;

  @override
  Future<bool> permisoConcedido() async => concedido;
  @override
  Future<bool> pedirPermiso() async {
    pedidos++;
    concedido = concederAlPedir;
    return concedido;
  }

  @override
  Future<LatLng?> posicionActual() async => concedido ? posicion : null;
}
