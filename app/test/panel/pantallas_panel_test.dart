// Panel administrativo (A-01 a A-05) contra un servicio falso, en una ventana de escritorio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/panel.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/panel/app_panel.dart';

import 'fakes_panel.dart';

void escritorio(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<ServicioPanelFalso> abrirPanel(
  WidgetTester tester, {
  String usuario = 'admin.demo',
  ServicioPanelFalso? servicio,
}) async {
  escritorio(tester);
  final s = servicio ?? ServicioPanelFalso();
  await tester.pumpWidget(AppPanel(servicio: s, mostrarTeselas: false));
  await tester.enterText(find.byKey(const Key('usuario')), usuario);
  await tester.enterText(find.byKey(const Key('clave')), claveDemo);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ingresar')));
  await tester.pumpAndSettle();
  return s;
}

Future<void> ir(WidgetTester tester, String seccion) async {
  await tester.tap(find.byKey(Key('ir-$seccion')));
  await tester.pumpAndSettle();
}

/// Desmonta el panel para detener la actualización periódica de la flota.
Future<void> cerrar(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('A-01 Inicio de sesión (RF-014)', () {
    testWidgets('el administrador ve las cuatro secciones', (tester) async {
      await abrirPanel(tester);
      expect(find.text('admin.demo · Administrador'), findsOneWidget);
      for (final s in ['flota', 'rutas', 'cuentas', 'eventos']) {
        expect(find.byKey(Key('ir-$s')), findsOneWidget);
      }
      await cerrar(tester);
    });

    testWidgets('el moderador solo ve la flota y los eventos', (tester) async {
      await abrirPanel(tester, usuario: 'moderador.demo');
      expect(find.byKey(const Key('ir-flota')), findsOneWidget);
      expect(find.byKey(const Key('ir-eventos')), findsOneWidget);
      expect(find.byKey(const Key('ir-rutas')), findsNothing);
      expect(find.byKey(const Key('ir-cuentas')), findsNothing);
      await cerrar(tester);
    });

    testWidgets('una cuenta de conductor no entra al panel', (tester) async {
      await abrirPanel(tester, usuario: 'unidad07');
      expect(find.textContaining('app del conductor'), findsOneWidget);
      expect(find.byKey(const Key('ir-flota')), findsNothing);
    });

    testWidgets('con la contraseña incorrecta lo dice sin revelar más', (tester) async {
      escritorio(tester);
      await tester.pumpWidget(AppPanel(servicio: ServicioPanelFalso(), mostrarTeselas: false));
      await tester.enterText(find.byKey(const Key('usuario')), 'admin.demo');
      await tester.enterText(find.byKey(const Key('clave')), 'otra-clave');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ingresar')));
      await tester.pumpAndSettle();
      expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('si la sesión vence, vuelve al ingreso con un aviso', (tester) async {
      final s = ServicioPanelFalso();
      await abrirPanel(tester, servicio: s);
      s.fallo = const ErrorServicio(estado: 401, codigo: 'TOKEN_MISSING_OR_EXPIRED', mensaje: 'vencido');
      await tester.tap(find.byKey(const Key('actualizar-flota')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aviso-sesion')), findsOneWidget);
      expect(find.byKey(const Key('ingresar')), findsOneWidget);
    });

    testWidgets('«Salir» cierra la sesión', (tester) async {
      await abrirPanel(tester);
      await tester.tap(find.byKey(const Key('salir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ingresar')), findsOneWidget);
    });
  });

  group('A-02 Estado de la flota (RF-017)', () {
    testWidgets('indicadores, tabla con estados y nota', (tester) async {
      await abrirPanel(tester, usuario: 'moderador.demo');
      expect(
        find.descendant(of: find.byKey(const Key('indicador-transmitiendo')), matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byKey(const Key('tabla-flota')), matching: find.text('07')), findsOneWidget);
      expect(find.text('Transmitiendo'), findsWidgets);
      expect(find.text('Inactiva'), findsOneWidget);
      expect(find.text('Mollebaya · va a Centro (2 de Mayo)'), findsOneWidget);
      expect(find.text('hace 8 s'), findsOneWidget);
      expect(find.byKey(const Key('nota-estados')), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('sin conexión muestra el aviso y deja reintentar', (tester) async {
      final s = ServicioPanelFalso()..fallo = const SinConexion();
      await abrirPanel(tester, servicio: s);
      expect(find.byKey(const Key('aviso-error')), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tabla-flota')), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('A-03 Rutas y paraderos (RF-015)', () {
    testWidgets('lista los paraderos en orden y quita uno con confirmación', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'rutas');
      expect(find.byKey(const Key('variante-MOLLEBAYA-IDA')), findsOneWidget);
      expect(find.byKey(const Key('paradero-stp_002')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quitar-stp_002')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('asignar stp_001,stp_003'));
      expect(find.byKey(const Key('paradero-stp_002')), findsNothing);
      await cerrar(tester);
    });

    testWidgets('agrega un paradero existente que está cerca del trazado', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'rutas');
      await tester.tap(find.byKey(const Key('agregar-existente')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('candidato-stp_004')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('asignar stp_001,stp_002,stp_003,stp_004'));
      await cerrar(tester);
    });

    testWidgets('«Guardar» solo se habilita a 150 m o menos del trazado (RN-003)', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'rutas');
      await tester.tap(find.byKey(const Key('nuevo-paradero')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Posta de salud');
      await tester.enterText(find.byKey(const Key('campo-lat')), '-16.4555');
      // Unos 320 m al este del trazado
      await tester.enterText(find.byKey(const Key('campo-lon')), '-71.497');
      await tester.pump();
      expect(find.textContaining('debe estar a 150 m o menos'), findsOneWidget);
      FilledButton guardar() => tester.widget<FilledButton>(find.byKey(const Key('guardar-paradero')));
      expect(guardar().onPressed, isNull);

      // Unos 50 m: ya se puede guardar, y se agrega a la variante
      await tester.enterText(find.byKey(const Key('campo-lon')), '-71.4995');
      await tester.pump();
      expect(find.textContaining('del trazado de Mollebaya → Centro'), findsOneWidget);
      expect(guardar().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('guardar-paradero')));
      await tester.pumpAndSettle();
      expect(s.llamadas, containsAllInOrder(['crear Posta de salud', 'asignar stp_001,stp_002,stp_003,stp_010']));
      expect(find.byKey(const Key('formulario-paradero')), findsNothing);
      await cerrar(tester);
    });

    testWidgets('el horario se valida antes de enviarlo (RN-009)', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'rutas');
      await tester.tap(find.byKey(const Key('horario')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hora-fin')), '04:00');
      await tester.pump();
      expect(find.byKey(const Key('error-horario')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('hora-fin')), '22:30');
      await tester.pump();
      await tester.tap(find.byKey(const Key('guardar-horario')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('horario 05:00-22:30'));
      expect(find.text('Horario: 05:00 a 22:30'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('si la base rechaza el cambio, se muestra su mensaje', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'rutas');
      s.fallo = const ErrorServicio(
        estado: 422,
        codigo: 'OUT_OF_CORRIDOR',
        mensaje: 'El paradero stp_002 está a 900 m del trazado',
      );
      await tester.tap(find.byKey(const Key('quitar-stp_002')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('El paradero stp_002 está a 900 m del trazado'), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('A-04 Unidades y cuentas (RF-016)', () {
    testWidgets('alta de cuenta de conductor: solo unidades sin cuenta y clave visible una vez', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'cuentas');
      await tester.tap(find.byKey(const Key('pestana-conductores')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nueva-cuenta-conductor')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aviso-privacidad')), findsOneWidget);
      await tester.tap(find.byKey(const Key('campo-unidad')));
      await tester.pumpAndSettle();
      expect(find.text('Unidad 07'), findsNothing); // ya tiene cuenta (RN-001)
      await tester.tap(find.text('Unidad 12').last);
      await tester.pumpAndSettle();
      expect(find.text('unidad12'), findsOneWidget); // usuario sugerido
      await tester.tap(find.byKey(const Key('crear-cuenta')));
      await tester.pumpAndSettle();

      expect(s.llamadas, contains('cuenta conductor u12 unidad12'));
      expect(find.byKey(const Key('clave-temporal')), findsOneWidget);
      expect(find.text('Xk7mQ2pR9tWz'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cerrar-clave')));
      await tester.pumpAndSettle();
      expect(find.text('Xk7mQ2pR9tWz'), findsNothing);
    });

    testWidgets('desactivar pide confirmación y cancelar no hace nada', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'cuentas');
      await tester.tap(find.byKey(const Key('pestana-conductores')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desactivar-unidad07')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelar')));
      await tester.pumpAndSettle();
      expect(s.llamadas.where((l) => l.startsWith('accion')), isEmpty);

      await tester.tap(find.byKey(const Key('restablecer-unidad07')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('accion c07 RESET_PASSWORD'));
      expect(find.text('Nm4pQr6sTu8v'), findsOneWidget);
    });

    testWidgets('registrar una unidad y crear un moderador', (tester) async {
      final s = await abrirPanel(tester);
      await ir(tester, 'cuentas');
      await tester.tap(find.byKey(const Key('registrar-unidad')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-etiqueta')), '15');
      await tester.pump();
      await tester.tap(find.byKey(const Key('guardar-unidad')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('registrar 15'));

      await tester.tap(find.byKey(const Key('pestana-panel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nueva-cuenta-panel')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-usuario')), 'ana.moderadora');
      await tester.pump();
      await tester.tap(find.byKey(const Key('crear-cuenta')));
      await tester.pumpAndSettle();
      expect(s.llamadas, contains('cuenta panel ana.moderadora MODERADOR'));
      expect(find.text('Ab3dEf5hJk7m'), findsOneWidget);
    });
  });

  group('A-05 Registro de eventos (RF-020)', () {
    testWidgets('muestra los eventos, el total, la retención y pagina', (tester) async {
      final s = await abrirPanel(tester, usuario: 'moderador.demo');
      await ir(tester, 'eventos');
      expect(find.text('Seguridad'), findsWidgets);
      expect(find.text('120 eventos · página 1 de 3 · se conservan 14 días'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pagina-siguiente')));
      await tester.pumpAndSettle();
      expect(s.llamadas.last, 'eventos 2');
      expect(find.textContaining('página 2 de 3'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('filtra por tipo y unidad', (tester) async {
      final s = await abrirPanel(tester, usuario: 'moderador.demo');
      await ir(tester, 'eventos');
      await tester.tap(find.byKey(const Key('filtro-tipo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Posición descartada').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('filtro-unidad')), '07');
      await tester.tap(find.byKey(const Key('buscar-eventos')));
      await tester.pumpAndSettle();
      expect(s.ultimoFiltro?.tipo, TipoEvento.posicionDescartada);
      expect(s.ultimoFiltro?.unidad, '07');
      await cerrar(tester);
    });
  });
}
