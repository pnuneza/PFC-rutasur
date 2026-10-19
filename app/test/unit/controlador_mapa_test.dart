import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/pasajero/controlador_mapa.dart';

import '../fakes.dart';

void main() {
  late RepositorioFalso repositorio;
  late DateTime ahora;
  late ControladorMapa controlador;

  setUp(() {
    repositorio = RepositorioFalso(linea: lineaDePrueba(), unidades: [unidadDePrueba()]);
    ahora = DateTime(2026, 10, 14, 10);
    controlador = ControladorMapa(
      repositorio,
      reloj: () => ahora,
      intervalo: const Duration(hours: 1), // la prueba controla cuándo se refresca
    );
  });

  tearDown(() => controlador.dispose());

  test('al iniciar descarga la ruta y las unidades', () async {
    await controlador.iniciar();

    expect(controlador.linea, isNotNull);
    expect(controlador.paraderos, hasLength(3));
    expect(controlador.unidades.single.etiqueta, '07');
    expect(controlador.sinConexion, isFalse);
  });

  test('cuenta los segundos desde la última consulta exitosa', () async {
    await controlador.iniciar();
    ahora = ahora.add(const Duration(seconds: 8));
    expect(controlador.segundosDesdeActualizacion(), 8);
  });

  test('sin conexión conserva las últimas unidades conocidas (P06, P-01)', () async {
    await controlador.iniciar();
    repositorio.fallo = const SinConexion();

    await controlador.refrescarUnidades();

    expect(controlador.sinConexion, isTrue);
    expect(controlador.unidades.single.etiqueta, '07');
  });

  test('al volver la conexión se actualiza y se quita el aviso', () async {
    await controlador.iniciar();
    repositorio.fallo = const SinConexion();
    await controlador.refrescarUnidades();

    repositorio.fallo = null;
    repositorio.unidades = [unidadDePrueba(etiqueta: '12')];
    await controlador.refrescarUnidades();

    expect(controlador.sinConexion, isFalse);
    expect(controlador.unidades.single.etiqueta, '12');
  });

  test('lista vacía con el servicio respondiendo = «sin unidades en circulación» (P-05)', () async {
    repositorio.unidades = const [];
    await controlador.iniciar();
    expect(controlador.sinUnidadesEnCirculacion, isTrue);
  });

  test('una falla de red NO se confunde con «sin unidades en circulación» (RNF-04)', () async {
    repositorio.unidades = const [];
    await controlador.cargarLinea();
    repositorio.fallo = const SinConexion();
    await controlador.refrescarUnidades();
    expect(controlador.sinUnidadesEnCirculacion, isFalse);
  });

  test('si la ruta no se puede descargar, informa el error y no consulta unidades', () async {
    repositorio.fallo = const SinConexion();

    await controlador.iniciar();

    expect(controlador.linea, isNull);
    expect(controlador.errorLinea, contains('conexión'));
    expect(repositorio.consultasUnidades, 0);
  });
}
