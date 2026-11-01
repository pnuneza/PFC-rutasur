// Lógica de la app del conductor sin teléfono ni red (CU-02, CU-08, RF-010 a RF-013).
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasur/domain/conductor.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/repositorio.dart';
import 'package:rutasur/features/conductor/controlador_conductor.dart';

import 'fakes_conductor.dart';

void main() {
  group('Pantalla inicial según lo guardado (P06 Figura 28)', () {
    test('sin token abre el inicio de sesión', () async {
      final e = Escenario();
      await e.controlador.iniciar();
      expect(e.controlador.etapa, Etapa.ingreso);
    });

    test('con un token vencido también, y lo borra', () async {
      final e = Escenario();
      e.almacen.acceso = AccesoConductor.desdeToken(
        tokenQueVence(ahoraFijo.subtract(const Duration(minutes: 5))),
        '07',
      );
      await e.controlador.iniciar();
      expect(e.controlador.etapa, Etapa.ingreso);
      expect(e.almacen.acceso, isNull);
    });

    test('con token vigente y sin sesión abre la declaración del recorrido', () async {
      final e = Escenario()..almacen.acceso = accesoVigente();
      await e.controlador.iniciar();
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.controlador.etiquetaUnidad, '07');
    });

    test('con una sesión abierta retoma la transmisión y su cola', () async {
      final e = Escenario()
        ..almacen.acceso = accesoVigente()
        ..almacen.sesion = SesionConductor(
          id: 's-1',
          ramal: Ramal.cerrillo,
          sentido: Sentido.vuelta,
          destino: 'Cerrillo',
          inicio: ahoraFijo,
        )
        ..almacen.cola = [
          Lectura(id: 'p', lat: 1, lon: 2, velocidadKmh: 0, rumbo: 0, precisionM: 5, capturada: ahoraFijo),
        ];
      await e.controlador.iniciar();
      expect(e.controlador.etapa, Etapa.transmision);
      expect(e.controlador.pendientes, 1);
      expect(e.gps.activo, isTrue);
    });

    test('si al retomar faltan permisos, pide los permisos', () async {
      final e = Escenario()
        ..almacen.acceso = accesoVigente()
        ..almacen.sesion = SesionConductor(
          id: 's-1', ramal: Ramal.cerrillo, sentido: Sentido.vuelta, destino: 'Cerrillo', inicio: ahoraFijo)
        ..gps.permisos = const PermisosTelefono(
          ubicacion: EstadoPermiso.denegado,
          notificaciones: EstadoPermiso.concedido,
          bateria: EstadoPermiso.concedido,
        );
      await e.controlador.iniciar();
      expect(e.controlador.etapa, Etapa.permisos);
    });
  });

  group('C-01 Inicio de sesión', () {
    test('un ingreso correcto guarda el token y abre C-02', () async {
      final e = Escenario();
      await e.controlador.iniciar();
      await e.controlador.ingresar('  unidad07 ', 'rutasur-demo');
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.almacen.acceso, isNotNull);
    });

    test('credenciales incorrectas: mensaje que no revela si el usuario existe', () async {
      final e = Escenario();
      e.servicio.falloIngreso = const ErrorServicio(estado: 401, codigo: 'INVALID_CREDENTIALS', mensaje: 'x');
      await e.controlador.ingresar('unidad07', 'otra-clave');
      expect(e.controlador.etapa, isNot(Etapa.recorrido));
      expect(e.controlador.errorIngreso, contains('Usuario o contraseña incorrectos'));
      expect(e.controlador.errorIngreso, contains('15 minutos'));
    });

    test('cuenta bloqueada informa los minutos de espera', () async {
      final e = Escenario();
      e.servicio.falloIngreso =
          const ErrorServicio(estado: 403, codigo: 'ACCOUNT_LOCKED', mensaje: 'x', reintentarEnS: 600);
      await e.controlador.ingresar('unidad07', 'otra-clave');
      expect(e.controlador.errorIngreso, 'Tu cuenta está bloqueada. Vuelve a intentarlo en 10 minutos.');
    });

    test('sin conexión lo dice', () async {
      final e = Escenario()..servicio.falloIngreso = const SinConexion();
      await e.controlador.ingresar('unidad07', 'rutasur-demo');
      expect(e.controlador.errorIngreso, contains('No hay conexión'));
    });

    test('«Salir» borra el token y vuelve a C-01', () async {
      final e = Escenario()..almacen.acceso = accesoVigente();
      await e.controlador.iniciar();
      await e.controlador.salir();
      expect(e.controlador.etapa, Etapa.ingreso);
      expect(e.almacen.acceso, isNull);
    });
  });

  group('C-02 y C-04: empezar a transmitir', () {
    test('sin permiso de ubicación lleva a C-04 y no abre sesión', () async {
      final e = Escenario()
        ..almacen.acceso = accesoVigente()
        ..gps.permisos = const PermisosTelefono(
          ubicacion: EstadoPermiso.denegado,
          notificaciones: EstadoPermiso.concedido,
          bateria: EstadoPermiso.denegado,
        );
      await e.controlador.iniciar();
      await e.controlador.empezar(Ramal.mollebaya, Sentido.ida);
      expect(e.controlador.etapa, Etapa.permisos);
      expect(e.servicio.sesionesAbiertas, 0);
    });

    test('la batería es recomendada, no obligatoria', () {
      const p = PermisosTelefono(
        ubicacion: EstadoPermiso.concedido,
        notificaciones: EstadoPermiso.noAplica,
        bateria: EstadoPermiso.denegado,
      );
      expect(p.obligatoriosListos, isTrue);
    });

    test('con permisos abre la sesión, arranca el GPS con la notificación N-01 y abre C-03', () async {
      final e = Escenario();
      await e.transmitiendo();
      expect(e.controlador.etapa, Etapa.transmision);
      expect(e.almacen.sesion?.id, 'sesion-1');
      expect(e.gps.activo, isTrue);
      expect(e.gps.textoNotificacion, contains('Unidad 07'));
      expect(e.gps.textoNotificacion, contains('Centro (2 de Mayo)'));
    });

    test('unidad deshabilitada: se queda en C-02 con el aviso', () async {
      final e = Escenario()..almacen.acceso = accesoVigente();
      e.servicio.falloApertura = const ErrorServicio(estado: 409, codigo: 'UNIT_INACTIVE', mensaje: 'x');
      await e.controlador.iniciar();
      await e.controlador.empezar(Ramal.mollebaya, Sentido.ida);
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.controlador.aviso, contains('no está habilitada'));
    });
  });

  group('C-03 Emisión: captura, cola y envío (RF-011, RF-012)', () {
    test('captura cada lectura del GPS y envía la cola; solo borra lo confirmado', () async {
      final e = Escenario();
      await e.transmitiendo();
      for (var i = 0; i < 3; i++) {
        e.gps.emitir(lat: -16.47 + i * 0.0003);
        await e.controlador.capturar();
        e.reloj.avanzar(const Duration(seconds: 5));
      }
      expect(e.controlador.pendientes, 3);
      expect(e.almacen.cola, hasLength(3)); // sobrevive a un reinicio

      e.servicio.confirmarSolo = {'pos-1', 'pos-2'};
      await e.controlador.enviar();
      expect(e.controlador.pendientes, 1);
      expect(e.controlador.cola.single.id, 'pos-3');
      expect(e.controlador.ultimoEnvio, isNotNull);
    });

    test('la lectura lleva velocidad en km/h, rumbo de 0 a 359 y hora UTC', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      final l = e.controlador.cola.single;
      expect(l.velocidadKmh, 36);
      expect(l.rumbo, 0); // 359,6° redondea a 360 → 0
      expect(l.capturada.isUtc, isTrue);
    });

    test('sin conexión guarda en el teléfono, muestra ámbar y reenvía todo al volver la red', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.servicio.falloEnvio = const SinConexion();
      for (var i = 0; i < 6; i++) {
        e.gps.emitir();
        await e.controlador.capturar();
        if (i % 3 == 2) await e.controlador.enviar();
      }
      expect(e.controlador.estado, EstadoEmision.sinConexion);
      expect(e.controlador.pendientes, 6);

      e.servicio.falloEnvio = null;
      await e.controlador.enviar();
      expect(e.servicio.lotes.single, hasLength(6));
      expect(e.controlador.pendientes, 0);
      expect(e.controlador.estado, EstadoEmision.transmitiendo);
    });

    test('si el GPS deja de dar posiciones, muestra «Sin GPS» y no inventa lecturas', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      e.reloj.avanzar(const Duration(seconds: 25));
      await e.controlador.capturar();
      expect(e.controlador.estado, EstadoEmision.sinGps);
      expect(e.controlador.pendientes, 1);
      e.gps.emitir();
      await e.controlador.capturar();
      expect(e.controlador.estado, EstadoEmision.transmitiendo);
    });

    test('antes de la primera posición no marca «Sin GPS» enseguida', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.reloj.avanzar(const Duration(seconds: 10));
      await e.controlador.capturar();
      expect(e.controlador.estado, EstadoEmision.transmitiendo);
      expect(e.controlador.pendientes, 0);
    });

    test('envía de a 200 como máximo', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      for (var i = 0; i < 250; i++) {
        await e.controlador.capturar();
      }
      await e.controlador.enviar();
      expect(e.servicio.lotes.single, hasLength(200));
      expect(e.controlador.pendientes, 50);
    });

    test('sesión cerrada en el servidor (RN-010): vuelve a C-02 con la explicación', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      e.servicio.falloEnvio = const ErrorServicio(estado: 409, codigo: 'SESSION_NOT_ACTIVE', mensaje: 'x');
      await e.controlador.enviar();
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.controlador.aviso, contains('10 minutos sin moverse'));
      expect(e.gps.activo, isFalse);
      expect(e.almacen.sesion, isNull);
    });

    test('token vencido durante el turno: vuelve a C-01', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      e.servicio.falloEnvio =
          const ErrorServicio(estado: 401, codigo: 'TOKEN_MISSING_OR_EXPIRED', mensaje: 'x');
      await e.controlador.enviar();
      expect(e.controlador.etapa, Etapa.ingreso);
      expect(e.controlador.errorIngreso, 'Tu sesión venció. Vuelve a ingresar.');
      expect(e.almacen.acceso, isNull);
    });

    test('un lote que el servidor nunca aceptará no traba la cola', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      e.servicio.falloEnvio = const ErrorServicio(estado: 400, codigo: 'VALIDATION_ERROR', mensaje: 'x');
      await e.controlador.enviar();
      expect(e.controlador.pendientes, 0);
      expect(e.controlador.etapa, Etapa.transmision);
    });
  });

  group('D-01 Terminar turno', () {
    test('envía lo pendiente, cierra la sesión y vuelve a C-02', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.gps.emitir();
      await e.controlador.capturar();
      await e.controlador.detener();
      expect(e.servicio.lotes, hasLength(1));
      expect(e.servicio.cerradas, ['sesion-1']);
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.controlador.aviso, contains('Turno terminado'));
      expect(e.gps.activo, isFalse);
    });

    test('sin conexión igual termina en el teléfono', () async {
      final e = Escenario();
      await e.transmitiendo();
      e.servicio.falloCierre = const SinConexion();
      await e.controlador.detener();
      expect(e.controlador.etapa, Etapa.recorrido);
      expect(e.almacen.sesion, isNull);
    });
  });

  test('el vencimiento se lee del propio token', () {
    final vence = DateTime.utc(2026, 11, 3, 2);
    expect(venceDelToken(tokenQueVence(vence)), vence);
    expect(venceDelToken('no-es-un-token').year, 1970);
  });
}
