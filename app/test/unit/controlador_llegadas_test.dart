import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/pasajero/controlador_llegadas.dart';

import '../fakes.dart';

/// D-20: la hoja de llegadas no anuncia «Sin conexión» por un fallo aislado.
void main() {
  late RepositorioFalso repositorio;
  late ControladorLlegadas controlador;

  setUp(() {
    repositorio = RepositorioFalso();
    controlador = ControladorLlegadas(
      repositorio,
      'stp_001',
      intervalo: const Duration(hours: 1),
      reintento: const Duration(milliseconds: 20),
    );
  });

  tearDown(() => controlador.dispose());

  test('sin datos previos, el primer fallo ya se avisa', () async {
    repositorio.fallo = const SinConexion();
    await controlador.iniciar();
    expect(controlador.sinConexion, isTrue);
    expect(controlador.cargando, isFalse);
  });

  test('con datos en pantalla, el aviso sale recién al segundo fallo seguido', () async {
    await controlador.iniciar();
    repositorio.fallo = const SinConexion();

    await controlador.refrescar();
    expect(controlador.sinConexion, isFalse);

    await controlador.refrescar();
    expect(controlador.sinConexion, isTrue);
  });

  test('tras un fallo reintenta solo y se recupera en pocos milisegundos', () async {
    await controlador.iniciar();
    repositorio.fallo = const SinConexion();
    await controlador.refrescar();

    repositorio.fallo = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controlador.sinConexion, isFalse);
  });

  test('al volver a la app consulta de inmediato y quita el aviso', () async {
    await controlador.iniciar();
    repositorio.fallo = const SinConexion();
    await controlador.refrescar();
    await controlador.refrescar();
    expect(controlador.sinConexion, isTrue);

    controlador.pausar();
    repositorio.fallo = null;
    await controlador.reanudar();

    expect(controlador.sinConexion, isFalse);
  });
}
