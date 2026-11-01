// Servicio del panel en memoria: responde como la API, sin red.
import 'package:latlong2/latlong.dart';
import 'package:rutasur/domain/modelos.dart';
import 'package:rutasur/domain/panel.dart';
import 'package:rutasur/domain/repositorio.dart';

const claveDemo = 'rutasur-demo';
final ahoraPrueba = DateTime.utc(2026, 11, 1, 13);

/// Trazado recto de norte a sur, de -16.45 a -16.47 (unos 2,2 km).
const trazadoPrueba = [LatLng(-16.45, -71.5), LatLng(-16.46, -71.5), LatLng(-16.47, -71.5)];

class ServicioPanelFalso implements ServicioPanel {
  final Map<String, (String clave, String rol)> cuentas = {
    'admin.demo': (claveDemo, 'ADMINISTRADOR'),
    'moderador.demo': (claveDemo, 'MODERADOR'),
    'unidad07': (claveDemo, 'CONDUCTOR'),
  };

  /// Si se asigna, la próxima operación (que no sea el ingreso) lanza esta excepción.
  Exception? fallo;
  final List<String> llamadas = [];

  HorarioLinea horarioActual = const HorarioLinea('05:00', '21:00');

  List<UnidadAdmin> unidadesActuales = [
    const UnidadAdmin(id: 'u07', etiqueta: '07', activa: true, usuario: 'unidad07'),
    const UnidadAdmin(id: 'u12', etiqueta: '12', activa: true, usuario: null),
  ];

  List<CuentaAdmin> conductores = [
    const CuentaAdmin(
      id: 'c07',
      usuario: 'unidad07',
      rol: 'CONDUCTOR',
      activa: true,
      bloqueadaHasta: null,
      etiquetaUnidad: '07',
    ),
  ];

  List<CuentaAdmin> panel = [
    const CuentaAdmin(
      id: 'p1',
      usuario: 'admin.demo',
      rol: 'ADMINISTRADOR',
      activa: true,
      bloqueadaHasta: null,
      etiquetaUnidad: null,
    ),
  ];

  List<ParaderoAdmin> paraderosActuales = [
    for (final (i, p) in trazadoPrueba.indexed)
      ParaderoAdmin(
        codigo: 'stp_00${i + 1}',
        nombre: ['Santa Ana', 'Plaza Characato', 'Centro'][i],
        referencia: null,
        ubicacion: p,
        tramoComun: i > 0,
        activo: true,
        variantes: const ['MOLLEBAYA-IDA'],
      ),
    const ParaderoAdmin(
      codigo: 'stp_004',
      nombre: 'Mercado',
      referencia: 'Frente al mercado',
      ubicacion: LatLng(-16.455, -71.5005),
      tramoComun: false,
      activo: true,
      variantes: [],
    ),
  ];

  late Map<String, List<String>> asignados = {
    'v1': ['stp_001', 'stp_002', 'stp_003'],
  };

  void _registrar(String llamada) {
    llamadas.add(llamada);
    final f = fallo;
    if (f != null) {
      fallo = null;
      throw f;
    }
  }

  @override
  Future<AccesoPanel> iniciarSesion(String usuario, String contrasena) async {
    llamadas.add('ingresar $usuario');
    final cuenta = cuentas[usuario];
    if (cuenta == null || cuenta.$1 != contrasena) {
      throw const ErrorServicio(estado: 401, codigo: 'INVALID_CREDENTIALS', mensaje: 'Usuario o contraseña incorrectos');
    }
    if (cuenta.$2 == 'CONDUCTOR') {
      throw const ErrorServicio(
        estado: 403,
        codigo: 'FORBIDDEN',
        mensaje: 'Esta cuenta es de conductor: se usa en la app del conductor, no en el panel.',
      );
    }
    return AccesoPanel(token: 't', usuario: usuario, rol: RolPanel.desdeApi(cuenta.$2));
  }

  @override
  Future<EstadoFlota> flota(AccesoPanel a) async {
    _registrar('flota');
    return EstadoFlota(
      transmitiendo: 1,
      sinSenal: 0,
      inactivas: 1,
      unidades: [
        UnidadFlota(
          id: 'u07',
          etiqueta: '07',
          usuario: 'unidad07',
          estado: EstadoUnidad.transmitiendo,
          desde: ahoraPrueba.subtract(const Duration(minutes: 40)),
          antiguedadS: 8,
          ubicacion: const LatLng(-16.455, -71.5),
          rumbo: 180,
          ramal: Ramal.mollebaya,
          sentido: Sentido.ida,
          destino: 'Centro (2 de Mayo)',
        ),
        UnidadFlota(
          id: 'u12',
          etiqueta: '12',
          usuario: null,
          estado: EstadoUnidad.inactiva,
          desde: ahoraPrueba.subtract(const Duration(days: 2)),
          antiguedadS: null,
          ubicacion: null,
          rumbo: null,
          ramal: null,
          sentido: null,
          destino: null,
        ),
      ],
    );
  }

  FiltroEventos? ultimoFiltro;

  @override
  Future<PaginaEventos> eventos(AccesoPanel a, FiltroEventos f) async {
    _registrar('eventos ${f.pagina}');
    ultimoFiltro = f;
    return PaginaEventos(
      eventos: [
        EventoPanel(
          id: 3,
          fecha: ahoraPrueba,
          tipo: TipoEvento.seguridad,
          origen: 'panel',
          unidad: null,
          usuarioPanel: 'admin.demo',
          codigoHttp: null,
          detalle: const {'accion': 'crear_unidad', 'unidad': '15'},
        ),
      ],
      total: 120,
      pagina: f.pagina,
      tamano: 50,
      retencionDias: 14,
    );
  }

  @override
  Future<HorarioLinea> horario() async => horarioActual;

  @override
  Future<HorarioLinea> cambiarHorario(AccesoPanel a, HorarioLinea h) async {
    _registrar('horario ${h.inicio}-${h.fin}');
    return horarioActual = h;
  }

  VarianteAdmin _variante() {
    final codigos = asignados['v1']!;
    final lista = [for (final p in paraderosActuales) if (codigos.contains(p.codigo)) p]
      ..sort((x, y) => y.ubicacion.latitude.compareTo(x.ubicacion.latitude));
    return VarianteAdmin(
      id: 'v1',
      ramal: Ramal.mollebaya,
      sentido: Sentido.ida,
      destino: 'Centro (2 de Mayo)',
      longitudM: 2224,
      trazado: trazadoPrueba,
      paraderos: [
        for (final (i, p) in lista.indexed)
          ParaderoDeVariante(
            codigo: p.codigo,
            nombre: p.nombre,
            referencia: p.referencia,
            ubicacion: p.ubicacion,
            orden: i + 1,
            distanciaM: (-16.45 - p.ubicacion.latitude).abs() * 111195,
            tramoComun: p.tramoComun,
          ),
      ],
    );
  }

  @override
  Future<List<VarianteAdmin>> variantes(AccesoPanel a) async {
    _registrar('variantes');
    return [_variante()];
  }

  @override
  Future<VarianteAdmin> asignarParaderos(AccesoPanel a, String varianteId, List<String> codigos) async {
    _registrar('asignar ${codigos.join(',')}');
    asignados[varianteId] = codigos;
    return _variante();
  }

  @override
  Future<List<ParaderoAdmin>> paraderos(AccesoPanel a) async => paraderosActuales;

  @override
  Future<ParaderoAdmin> crearParadero(AccesoPanel a, DatosParadero d) async {
    _registrar('crear ${d.nombre}');
    final nuevo = ParaderoAdmin(
      codigo: 'stp_010',
      nombre: d.nombre,
      referencia: d.referencia,
      ubicacion: d.ubicacion,
      tramoComun: d.tramoComun,
      activo: true,
      variantes: const [],
    );
    paraderosActuales = [...paraderosActuales, nuevo];
    return nuevo;
  }

  @override
  Future<ParaderoAdmin> editarParadero(AccesoPanel a, String codigo, DatosParadero d) async {
    _registrar('editar $codigo ${d.nombre}');
    return paraderosActuales.firstWhere((p) => p.codigo == codigo);
  }

  @override
  Future<List<UnidadAdmin>> unidades(AccesoPanel a) async {
    _registrar('unidades');
    return unidadesActuales;
  }

  @override
  Future<UnidadAdmin> registrarUnidad(AccesoPanel a, String etiqueta) async {
    _registrar('registrar $etiqueta');
    final u = UnidadAdmin(id: 'u$etiqueta', etiqueta: etiqueta, activa: true, usuario: null);
    unidadesActuales = [...unidadesActuales, u];
    return u;
  }

  @override
  Future<UnidadAdmin> habilitarUnidad(AccesoPanel a, String unidadId, bool activa) async {
    _registrar('unidad $unidadId $activa');
    return unidadesActuales.firstWhere((u) => u.id == unidadId);
  }

  @override
  Future<List<CuentaAdmin>> cuentasConductor(AccesoPanel a) async => conductores;

  @override
  Future<List<CuentaAdmin>> cuentasPanel(AccesoPanel a) async => panel;

  @override
  Future<CuentaConClave> crearCuentaConductor(AccesoPanel a, String unidadId, String usuario) async {
    _registrar('cuenta conductor $unidadId $usuario');
    final c = CuentaAdmin(
      id: 'c-$usuario',
      usuario: usuario,
      rol: 'CONDUCTOR',
      activa: true,
      bloqueadaHasta: null,
      etiquetaUnidad: '12',
    );
    conductores = [...conductores, c];
    return CuentaConClave(c, 'Xk7mQ2pR9tWz');
  }

  @override
  Future<CuentaConClave> crearCuentaPanel(AccesoPanel a, String usuario, RolPanel rol) async {
    _registrar('cuenta panel $usuario ${rol.codigoApi}');
    final c = CuentaAdmin(
      id: 'p-$usuario',
      usuario: usuario,
      rol: rol.codigoApi,
      activa: true,
      bloqueadaHasta: null,
      etiquetaUnidad: null,
    );
    panel = [...panel, c];
    return CuentaConClave(c, 'Ab3dEf5hJk7m');
  }

  @override
  Future<CuentaConClave> actuarSobreCuenta(
    AccesoPanel a,
    String cuentaId,
    AccionCuenta accion, {
    required bool panel,
  }) async {
    _registrar('accion $cuentaId ${accion.codigoApi}');
    final lista = panel ? this.panel : conductores;
    final c = lista.firstWhere((x) => x.id == cuentaId);
    return CuentaConClave(c, accion == AccionCuenta.restablecer ? 'Nm4pQr6sTu8v' : null);
  }
}
