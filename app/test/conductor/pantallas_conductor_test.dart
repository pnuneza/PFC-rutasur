// Pantallas C-01 a C-04 y D-01 (P06 Tabla 45), con el controlador y piezas falsas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/conductor.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/conductor/app_conductor.dart';
import 'package:rutasur/features/conductor/controlador_conductor.dart';

import 'fakes_conductor.dart';

Future<Escenario> abrirApp(WidgetTester tester, {Escenario? escenario}) async {
  // Pantalla de un teléfono común (360 × 800 dp), no la de 800 × 600 de las pruebas
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final e = escenario ?? Escenario();
  await tester.pumpWidget(AppConductor(controlador: e.controlador));
  await tester.pumpAndSettle();
  return e;
}

FilledButton boton(WidgetTester tester, String clave) =>
    tester.widget<FilledButton>(find.byKey(Key(clave)));

void main() {
  testWidgets('C-01: «Ingresar» se habilita solo con usuario y contraseña válidos', (tester) async {
    await abrirApp(tester);
    expect(find.text('RutaSur · Conductor'), findsOneWidget);
    expect(boton(tester, 'ingresar').onPressed, isNull);

    await tester.enterText(find.byKey(const Key('usuario')), 'Unidad 07');
    await tester.enterText(find.byKey(const Key('clave')), 'corta');
    await tester.pump();
    // Se quitan espacios y mayúsculas mientras se escribe
    final usuario = tester.widget<TextField>(find.byKey(const Key('usuario')));
    expect(usuario.controller!.text, 'unidad07');
    expect(boton(tester, 'ingresar').onPressed, isNull);

    await tester.enterText(find.byKey(const Key('clave')), 'rutasur-demo');
    await tester.pump();
    expect(boton(tester, 'ingresar').onPressed, isNotNull);
  });

  testWidgets('C-01: muestra el error y, al ingresar bien, pasa a C-02', (tester) async {
    final e = await abrirApp(tester);
    e.servicio.falloIngreso = const ErrorServicio(estado: 401, codigo: 'INVALID_CREDENTIALS', mensaje: 'x');
    await tester.enterText(find.byKey(const Key('usuario')), 'unidad07');
    await tester.enterText(find.byKey(const Key('clave')), 'clave-mala-1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingresar')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Usuario o contraseña incorrectos'), findsOneWidget);

    e.servicio.falloIngreso = null;
    await tester.tap(find.byKey(const Key('ingresar')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué recorrido vas a hacer?'), findsOneWidget);
    expect(find.text('Unidad 07'), findsOneWidget);
  });

  testWidgets('C-02: «Empezar» exige ramal y sentido; los sentidos usan bajada y subida', (tester) async {
    await abrirApp(tester, escenario: Escenario()..almacen.acceso = accesoVigente());
    expect(boton(tester, 'empezar').onPressed, isNull);
    expect(find.text('Subida · hacia el ramal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ramal-CERRILLO')));
    await tester.pump();
    expect(find.text('Subida · hacia Cerrillo'), findsOneWidget);
    expect(boton(tester, 'empezar').onPressed, isNull);

    await tester.tap(find.byKey(const Key('sentido-VUELTA')));
    await tester.pump();
    expect(find.text('Los pasajeros verán: Unidad 07 · Va a Cerrillo'), findsOneWidget);
    expect(boton(tester, 'empezar').onPressed, isNotNull);
  });

  testWidgets('C-02 → C-04 sin permisos; «Continuar» solo con los obligatorios', (tester) async {
    final e = Escenario()
      ..almacen.acceso = accesoVigente()
      ..gps.permisos = const PermisosTelefono(
        ubicacion: EstadoPermiso.denegado,
        notificaciones: EstadoPermiso.concedido,
        bateria: EstadoPermiso.denegado,
      );
    await abrirApp(tester, escenario: e);
    await tester.tap(find.byKey(const Key('ramal-MOLLEBAYA')));
    await tester.tap(find.byKey(const Key('sentido-IDA')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('empezar')));
    await tester.pumpAndSettle();

    expect(find.text('Permisos del teléfono'), findsOneWidget);
    expect(boton(tester, 'continuar').onPressed, isNull);

    e.gps.permisos = const PermisosTelefono(
      ubicacion: EstadoPermiso.concedido,
      notificaciones: EstadoPermiso.concedido,
      bateria: EstadoPermiso.denegado, // recomendado, no obligatorio
    );
    await e.controlador.revisarPermisos();
    await tester.pump();
    expect(boton(tester, 'continuar').onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('continuar')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué recorrido vas a hacer?'), findsOneWidget);
  });

  testWidgets('C-03 muestra el estado de un vistazo y D-01 pide confirmar', (tester) async {
    final e = Escenario();
    await e.transmitiendo();
    await abrirApp(tester, escenario: e);
    expect(find.text('TRANSMITIENDO'), findsOneWidget);
    expect(find.text('Detener transmisión'), findsOneWidget);

    e.servicio.falloEnvio = const SinConexion();
    e.gps.emitir();
    await e.controlador.capturar();
    await e.controlador.enviar();
    await tester.pump();
    expect(find.text('SIN CONEXIÓN'), findsOneWidget);
    expect(find.textContaining('guardando posiciones en el teléfono'), findsOneWidget);

    // D-01: cancelar no detiene nada
    await tester.tap(find.byKey(const Key('detener')));
    await tester.pumpAndSettle();
    expect(find.text('¿Terminar el turno?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelar-fin')));
    await tester.pumpAndSettle();
    expect(e.controlador.etapa, Etapa.transmision);

    // Confirmar termina el turno y vuelve a C-02
    e.servicio.falloEnvio = null;
    await tester.tap(find.byKey(const Key('detener')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar-fin')));
    await tester.pumpAndSettle();
    expect(e.servicio.cerradas, ['sesion-1']);
    expect(find.textContaining('Turno terminado'), findsOneWidget);
  });
}
