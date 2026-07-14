import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DirectorNacionalKpisScreen extends StatefulWidget {
  const DirectorNacionalKpisScreen({super.key});

  @override
  State<DirectorNacionalKpisScreen> createState() =>
      _DirectorNacionalKpisScreenState();
}

class _DirectorNacionalKpisScreenState
    extends State<DirectorNacionalKpisScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  Map<String, dynamic>? usuarioLogueado;

  // Datos máximos permitidos por el usuario conectado.
  List<Map<String, dynamic>> usuariosPermitidosBase = [];
  List<Map<String, dynamic>> ventasPermitidasBase = [];
  List<Map<String, dynamic>> clientesPermitidosBase = [];

  // Datos efectivos después de aplicar el filtro de estructura.
  List<Map<String, dynamic>> usuariosEstructura = [];
  List<Map<String, dynamic>> ventas = [];
  List<Map<String, dynamic>> clientes = [];

  String selectedYear = 'Todos';
  String selectedMonth = 'Todos';

  DateTime? selectedDateFrom;
  DateTime? selectedDateTo;

  String selectedStructureRole = 'Todos';
  String selectedStructureUserId = 'Todos';

  List<String> years = ['Todos'];

  final List<String> months = const [
    'Todos',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  final List<String> monthNames = const [
    '',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String? _rolHijoEsperado(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'director_zona';
      case 'director_zona':
        return 'jefe_ventas';
      case 'jefe_ventas':
        return 'jefe_equipo';
      case 'jefe_equipo':
        return 'agente';
      default:
        return null;
    }
  }

  Future<void> cargarDatos() async {
    try {
      if (mounted) {
        setState(() {
          loading = true;
          error = null;
        });
      }

      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = 'No hay ningún usuario conectado.';
        });
        return;
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = 'No se encontró el perfil del usuario conectado.';
        });
        return;
      }

      final perfil = Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          );

      final todosUsuarios = List<Map<String, dynamic>>.from(usuariosData);

      final estructura = _obtenerUsuariosPermitidos(
        perfil: perfil,
        todosUsuarios: todosUsuarios,
      );

      final authIds = estructura
          .map((u) => u['auth_id']?.toString())
          .where(
            (id) =>
                id != null &&
                id.trim().isNotEmpty &&
                id.toLowerCase() != 'null',
          )
          .cast<String>()
          .toSet()
          .toList();

      List<Map<String, dynamic>> ventasEstructura = [];
      List<Map<String, dynamic>> clientesEstructura = [];

      if (authIds.isNotEmpty) {
        final ventasData = await supabase
            .from('ventas')
            .select()
            .inFilter('agente_auth_id', authIds)
            .order('created_at', ascending: false);

        final clientesData = await supabase
            .from('clientes')
            .select()
            .inFilter('auth_id', authIds)
            .order('created_at', ascending: false);

        ventasEstructura = List<Map<String, dynamic>>.from(ventasData);
        clientesEstructura = List<Map<String, dynamic>>.from(clientesData);
      }

      usuarioLogueado = perfil;
      usuariosPermitidosBase = estructura;
      ventasPermitidasBase = ventasEstructura;
      clientesPermitidosBase = clientesEstructura;

      selectedStructureRole = 'Todos';
      selectedStructureUserId = 'Todos';

      _aplicarFiltroEstructura();
      _buildYears();

      debugPrint('=========================================');
      debugPrint('KPIS ESTRUCTURA REAL');
      debugPrint('USUARIO: ${_nombreCompleto(perfil)}');
      debugPrint('ROL: ${perfil['rol_usuario']}');
      debugPrint('ID: ${perfil['id']}');
      debugPrint('PERSONAS INCLUIDAS: ${estructura.length}');
      debugPrint('VENTAS INCLUIDAS: ${ventas.length}');
      debugPrint('CLIENTES INCLUIDOS: ${clientes.length}');
      for (final u in estructura) {
        debugPrint(
          '- ${_nombreCompleto(u)} | ${u['rol_usuario']} | parent=${u['parent_id']}',
        );
      }
      debugPrint('=========================================');

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR KPIS ESTRUCTURA: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        usuarioLogueado = null;
        usuariosPermitidosBase = [];
        ventasPermitidasBase = [];
        clientesPermitidosBase = [];
        usuariosEstructura = [];
        ventas = [];
        clientes = [];
        loading = false;
        error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _obtenerUsuariosPermitidos({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolPerfil = _normalizarRol(perfil['rol_usuario']);

    if (rolPerfil == 'administracion') {
      return todosUsuarios.where((u) {
        final authId = u['auth_id']?.toString().trim() ?? '';
        return authId.isNotEmpty && authId.toLowerCase() != 'null';
      }).toList();
    }

    final porParentId = <String, List<Map<String, dynamic>>>{};

    for (final usuario in todosUsuarios) {
      final parentId = usuario['parent_id']?.toString().trim();

      if (parentId == null ||
          parentId.isEmpty ||
          parentId.toLowerCase() == 'null') {
        continue;
      }

      porParentId
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> padre) {
      final padreId = padre['id']?.toString().trim() ?? '';

      if (padreId.isEmpty || visitados.contains(padreId)) return;

      visitados.add(padreId);
      resultado.add(padre);

      final rolPadre = _normalizarRol(padre['rol_usuario']);
      final rolHijo = _rolHijoEsperado(rolPadre);

      if (rolHijo == null) return;

      final hijos = (porParentId[padreId] ?? <Map<String, dynamic>>[])
          .where(
            (u) => _normalizarRol(u['rol_usuario']) == rolHijo,
          )
          .toList();

      for (final hijo in hijos) {
        recorrer(hijo);
      }
    }

    recorrer(perfil);

    return resultado;
  }

  List<String> get rolesEstructuraDisponibles {
    const orden = [
      'director_nacional',
      'director_zona',
      'jefe_ventas',
      'jefe_equipo',
      'agente',
    ];

    final existentes = usuariosPermitidosBase
        .map((u) => _normalizarRol(u['rol_usuario']))
        .where((rol) => rol.isNotEmpty)
        .toSet();

    return [
      'Todos',
      ...orden.where(existentes.contains),
    ];
  }

  List<Map<String, dynamic>> get personasFiltroEstructura {
    if (selectedStructureRole == 'Todos') {
      return [];
    }

    final personas = usuariosPermitidosBase.where((u) {
      return _normalizarRol(u['rol_usuario']) == selectedStructureRole;
    }).toList();

    personas.sort((a, b) {
      return _nombreCompleto(a)
          .toLowerCase()
          .compareTo(_nombreCompleto(b).toLowerCase());
    });

    return personas;
  }

  void _aplicarFiltroEstructura() {
    if (usuariosPermitidosBase.isEmpty) {
      usuariosEstructura = [];
      ventas = [];
      clientes = [];
      return;
    }

    final idsIncluidos = <String>{};
    final seleccionados = <Map<String, dynamic>>[];

    if (selectedStructureUserId != 'Todos') {
      final persona = usuariosPermitidosBase.firstWhere(
        (u) => u['id']?.toString() == selectedStructureUserId,
        orElse: () => <String, dynamic>{},
      );

      if (persona.isNotEmpty) {
        seleccionados.add(persona);
      }
    } else if (selectedStructureRole != 'Todos') {
      seleccionados.addAll(
        usuariosPermitidosBase.where(
          (u) =>
              _normalizarRol(u['rol_usuario']) ==
              selectedStructureRole,
        ),
      );
    } else {
      seleccionados.addAll(usuariosPermitidosBase);
    }

    if (selectedStructureRole == 'Todos' &&
        selectedStructureUserId == 'Todos') {
      for (final usuario in usuariosPermitidosBase) {
        final id = usuario['id']?.toString();
        if (id != null && id.isNotEmpty) idsIncluidos.add(id);
      }
    } else {
      for (final raiz in seleccionados) {
        final subestructura = _obtenerUsuariosPermitidos(
          perfil: raiz,
          todosUsuarios: usuariosPermitidosBase,
        );

        for (final usuario in subestructura) {
          final id = usuario['id']?.toString();
          if (id != null && id.isNotEmpty) idsIncluidos.add(id);
        }
      }
    }

    usuariosEstructura = usuariosPermitidosBase.where((u) {
      final id = u['id']?.toString();
      return id != null && idsIncluidos.contains(id);
    }).toList();

    final authIds = usuariosEstructura
        .map((u) => u['auth_id']?.toString())
        .where(
          (id) =>
              id != null &&
              id.isNotEmpty &&
              id.toLowerCase() != 'null',
        )
        .cast<String>()
        .toSet();

    ventas = ventasPermitidasBase.where((v) {
      return authIds.contains(v['agente_auth_id']?.toString());
    }).toList();

    clientes = clientesPermitidosBase.where((c) {
      return authIds.contains(c['auth_id']?.toString());
    }).toList();

    debugPrint('======= FILTRO ESTRUCTURA KPIS =======');
    debugPrint('FIGURA: $selectedStructureRole');
    debugPrint('PERSONA: $selectedStructureUserId');
    debugPrint('PERSONAS INCLUIDAS: ${usuariosEstructura.length}');
    debugPrint('VENTAS INCLUIDAS: ${ventas.length}');
    debugPrint('CLIENTES INCLUIDOS: ${clientes.length}');
    debugPrint('======================================');
  }

  String _fechaTexto(DateTime? fecha) {
    if (fecha == null) return 'Sin seleccionar';

    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  Future<void> _seleccionarFechaDesde() async {
    final now = DateTime.now();

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: selectedDateFrom ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Selecciona la fecha desde',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (seleccionada == null || !mounted) return;

    setState(() {
      selectedDateFrom = DateTime(
        seleccionada.year,
        seleccionada.month,
        seleccionada.day,
      );

      if (selectedDateTo != null &&
          selectedDateTo!.isBefore(selectedDateFrom!)) {
        selectedDateTo = selectedDateFrom;
      }
    });
  }

  Future<void> _seleccionarFechaHasta() async {
    final now = DateTime.now();

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: selectedDateTo ?? now,
      firstDate: selectedDateFrom ?? DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Selecciona la fecha hasta',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (seleccionada == null || !mounted) return;

    setState(() {
      selectedDateTo = DateTime(
        seleccionada.year,
        seleccionada.month,
        seleccionada.day,
        23,
        59,
        59,
        999,
      );
    });
  }

  void _limpiarFiltrosAvanzados() {
    setState(() {
      selectedDateFrom = null;
      selectedDateTo = null;
      selectedYear = 'Todos';
      selectedMonth = 'Todos';
      selectedStructureRole = 'Todos';
      selectedStructureUserId = 'Todos';
      _aplicarFiltroEstructura();
    });
  }

  void _buildYears() {
    final set = <String>{};

    for (final venta in ventas) {
      final fecha = _parseDate(venta);
      if (fecha != null) set.add(fecha.year.toString());
    }

    final ordenados = set.toList()..sort((a, b) => b.compareTo(a));
    years = ['Todos', ...ordenados];

    if (!years.contains(selectedYear)) {
      selectedYear = 'Todos';
    }
  }

  DateTime? _parseDate(Map<String, dynamic> row) {
    final posibles = [
      row['fecha'],
      row['FECHA'],
      row['fecha_efecto'],
      row['created_at'],
      row['fecha_registro'],
      row['FECHA REGISTRO'],
    ];

    for (final value in posibles) {
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }

    return null;
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;

    final normalizado = raw.contains(',') && raw.contains('.')
        ? raw.replaceAll('.', '').replaceAll(',', '.')
        : raw.replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  double _primaNeta(Map<String, dynamic> venta) {
    return _money(
      venta['prima_anual_neta'] ??
          venta['prima_neta'] ??
          venta['PRIMA_ANUAL_NETA'] ??
          venta['PRIMA NETA'] ??
          0,
    );
  }

  int _intValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _cumpleFiltroFecha(Map<String, dynamic> row) {
    final fecha = _parseDate(row);

    final okYear = selectedYear == 'Todos' ||
        (fecha != null && fecha.year.toString() == selectedYear);

    final okMonth = selectedMonth == 'Todos' ||
        (fecha != null && monthNames[fecha.month] == selectedMonth);

    final okDesde = selectedDateFrom == null ||
        (fecha != null && !fecha.isBefore(selectedDateFrom!));

    final okHasta = selectedDateTo == null ||
        (fecha != null && !fecha.isAfter(selectedDateTo!));

    return okYear && okMonth && okDesde && okHasta;
  }

  List<Map<String, dynamic>> get ventasFiltradas {
    return ventas.where(_cumpleFiltroFecha).toList();
  }

  List<Map<String, dynamic>> get clientesFiltrados {
    return clientes.where(_cumpleFiltroFecha).toList();
  }

  double get primaNetaTotal {
    return ventasFiltradas.fold<double>(
      0,
      (sum, venta) => sum + _primaNeta(venta),
    );
  }

  int get aseguradosTotal {
    return ventasFiltradas.fold<int>(
      0,
      (sum, venta) => sum + _intValue(venta['numero_asegurados']),
    );
  }

  int get agentesEstructura {
    return usuariosEstructura
        .where((u) => _normalizarRol(u['rol_usuario']) == 'agente')
        .length;
  }

  int get agentesActivos {
    final authAgentes = usuariosEstructura
        .where((u) => _normalizarRol(u['rol_usuario']) == 'agente')
        .map((u) => u['auth_id']?.toString())
        .where((id) => id != null && id.isNotEmpty && id != 'null')
        .cast<String>()
        .toSet();

    final authConVenta = ventasFiltradas
        .map((v) => v['agente_auth_id']?.toString())
        .where(
          (id) =>
              id != null &&
              id.isNotEmpty &&
              id != 'null' &&
              authAgentes.contains(id),
        )
        .cast<String>()
        .toSet();

    return authConVenta.length;
  }

  Map<String, double> get primasPorRol {
    final rolPorAuth = <String, String>{};

    for (final usuario in usuariosEstructura) {
      final authId = usuario['auth_id']?.toString();
      if (authId == null || authId.isEmpty || authId == 'null') continue;

      rolPorAuth[authId] = _normalizarRol(usuario['rol_usuario']);
    }

    final result = <String, double>{};

    for (final venta in ventasFiltradas) {
      final authId = venta['agente_auth_id']?.toString();
      if (authId == null) continue;

      final rol = rolPorAuth[authId] ?? 'sin_rol';
      result[rol] = (result[rol] ?? 0) + _primaNeta(venta);
    }

    return result;
  }

  List<_AgenteRanking> get rankingAgentes {
    final agentes = usuariosEstructura
        .where((u) => _normalizarRol(u['rol_usuario']) == 'agente')
        .toList();

    final primasPorAuth = <String, double>{};
    final ventasPorAuth = <String, int>{};

    for (final agente in agentes) {
      final authId = agente['auth_id']?.toString();
      if (authId == null || authId.isEmpty || authId == 'null') continue;

      primasPorAuth[authId] = 0;
      ventasPorAuth[authId] = 0;
    }

    for (final venta in ventasFiltradas) {
      final authId = venta['agente_auth_id']?.toString();
      if (authId == null || !primasPorAuth.containsKey(authId)) continue;

      primasPorAuth[authId] =
          (primasPorAuth[authId] ?? 0) + _primaNeta(venta);
      ventasPorAuth[authId] = (ventasPorAuth[authId] ?? 0) + 1;
    }

    final ranking = agentes.map((agente) {
      final authId = agente['auth_id']?.toString() ?? '';

      return _AgenteRanking(
        nombre: _nombreCompleto(agente),
        primaNeta: primasPorAuth[authId] ?? 0,
        ventas: ventasPorAuth[authId] ?? 0,
      );
    }).toList();

    ranking.sort((a, b) {
      final porPrima = b.primaNeta.compareTo(a.primaNeta);
      if (porPrima != 0) return porPrima;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    return ranking;
  }

  List<double> get primasPorMes {
    final data = List<double>.filled(12, 0);

    for (final venta in ventas) {
      final fecha = _parseDate(venta);
      if (fecha == null) continue;

      if (!_cumpleFiltroFecha(venta)) continue;

      data[fecha.month - 1] += _primaNeta(venta);
    }

    return data;
  }

  double get objetivoPeriodo {
    final rol = _normalizarRol(usuarioLogueado?['rol_usuario']);

    double objetivoMensual;

    switch (rol) {
      case 'agente':
        objetivoMensual = 5000;
        break;
      case 'jefe_equipo':
        objetivoMensual = 12500;
        break;
      case 'jefe_ventas':
        objetivoMensual = 20832;
        break;
      case 'director_zona':
        objetivoMensual = 41664;
        break;
      case 'director_nacional':
      case 'administracion':
        objetivoMensual = 100000;
        break;
      default:
        objetivoMensual = 5000;
    }

    if (selectedDateFrom != null || selectedDateTo != null) {
      final desde = selectedDateFrom ??
          ventas.map(_parseDate).whereType<DateTime>().fold<DateTime?>(
                null,
                (minimo, fecha) =>
                    minimo == null || fecha.isBefore(minimo) ? fecha : minimo,
              ) ??
          DateTime.now();

      final hasta = selectedDateTo ?? DateTime.now();

      final meses = math.max(
        1,
        ((hasta.year - desde.year) * 12) +
            hasta.month -
            desde.month +
            1,
      );

      return objetivoMensual * meses;
    }

    if (selectedMonth != 'Todos') return objetivoMensual;

    if (selectedYear != 'Todos') return objetivoMensual * 12;

    final mesesConDatos = ventas
        .map(_parseDate)
        .whereType<DateTime>()
        .map((f) => '${f.year}-${f.month}')
        .toSet()
        .length;

    return objetivoMensual * math.max(1, mesesConDatos);
  }

  double get cumplimientoObjetivo {
    if (objetivoPeriodo <= 0) return 0;
    return primaNetaTotal / objetivoPeriodo;
  }

  String _nombreCompleto(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Sin nombre';

    final nombre = usuario['nombre']?.toString().trim() ?? '';
    final apellidos = usuario['apellidos']?.toString().trim() ?? '';
    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;

    return usuario['email']?.toString().trim().isNotEmpty == true
        ? usuario['email'].toString()
        : 'Sin nombre';
  }

  String _rolTexto(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente';
      case 'administracion':
        return 'Administración';
      default:
        return rol.replaceAll('_', ' ');
    }
  }

  String _formatearEuros(double value, {int decimales = 0}) {
    final negativo = value < 0;
    final absoluto = value.abs();
    final partes = absoluto.toStringAsFixed(decimales).split('.');
    final enteros = partes.first;
    final buffer = StringBuffer();

    for (int i = 0; i < enteros.length; i++) {
      final posicionDesdeFinal = enteros.length - i;
      buffer.write(enteros[i]);

      if (posicionDesdeFinal > 1 && posicionDesdeFinal % 3 == 1) {
        buffer.write('.');
      }
    }

    final decimal = decimales > 0 ? ',${partes.last}' : '';
    return '${negativo ? '-' : ''}${buffer.toString()}$decimal €';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _DirectorBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF071A3A),
                    onRefresh: cargarDatos,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _topBar()),
                        if (error != null)
                          SliverToBoxAdapter(child: _errorCard())
                        else ...[
                          SliverToBoxAdapter(child: _hero()),
                          SliverToBoxAdapter(child: _filters()),
                          SliverToBoxAdapter(child: _kpiGrid()),
                          SliverToBoxAdapter(child: _chartCard()),
                          SliverToBoxAdapter(child: _rolesCard()),
                          SliverToBoxAdapter(child: _rankingCard()),
                        ],
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            elevation: 6,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                width: 50,
                height: 50,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF020617),
                  size: 30,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'KPIs de mi estructura',
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargarDatos,
            icon: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF22D3EE),
                    Color(0xFF2563EB),
                    Color(0xFF7C3AED),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    final progresoReal = cumplimientoObjetivo;
    final progresoVisual = progresoReal.clamp(0.0, 1.0);
    final nombre = _nombreCompleto(usuarioLogueado);
    final rol = _rolTexto(
      usuarioLogueado?['rol_usuario']?.toString() ?? '',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF22D3EE).withOpacity(0.22),
                  const Color(0xFF071A3A).withOpacity(0.94),
                  const Color(0xFF020617).withOpacity(0.96),
                ],
              ),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$rol · ${usuariosEstructura.length} personas en la selección',
                  style: TextStyle(
                    color: Colors.cyanAccent.withOpacity(0.86),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Los datos de esta pantalla incluyen únicamente tus cifras propias y las de todos los usuarios que dependen de ti.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progresoVisual,
                          minHeight: 11,
                          backgroundColor: Colors.white.withOpacity(0.10),
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(progresoReal * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Objetivo del periodo: ${_formatearEuros(objetivoPeriodo)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    final personas = personasFiltroEstructura;

    final personaValida = selectedStructureUserId == 'Todos' ||
        personas.any(
          (u) => u['id']?.toString() == selectedStructureUserId,
        );

    if (!personaValida) {
      selectedStructureUserId = 'Todos';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(const Color(0xFF22D3EE)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Colors.cyanAccent,
                ),
                SizedBox(width: 8),
                Text(
                  'Filtros avanzados',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            LayoutBuilder(
              builder: (context, constraints) {
                final estrecho = constraints.maxWidth < 560;

                final year = _filter(
                  value: selectedYear,
                  items: years,
                  icon: Icons.date_range_rounded,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedYear = value);
                  },
                );

                final month = _filter(
                  value: selectedMonth,
                  items: months,
                  icon: Icons.calendar_month_rounded,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedMonth = value);
                  },
                );

                if (estrecho) {
                  return Column(
                    children: [
                      year,
                      const SizedBox(height: 10),
                      month,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: year),
                    const SizedBox(width: 10),
                    Expanded(child: month),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final estrecho = constraints.maxWidth < 560;

                final desde = _dateFilterButton(
                  title: 'Desde',
                  value: _fechaTexto(selectedDateFrom),
                  icon: Icons.first_page_rounded,
                  onTap: _seleccionarFechaDesde,
                  onClear: selectedDateFrom == null
                      ? null
                      : () => setState(() => selectedDateFrom = null),
                );

                final hasta = _dateFilterButton(
                  title: 'Hasta',
                  value: _fechaTexto(selectedDateTo),
                  icon: Icons.last_page_rounded,
                  onTap: _seleccionarFechaHasta,
                  onClear: selectedDateTo == null
                      ? null
                      : () => setState(() => selectedDateTo = null),
                );

                if (estrecho) {
                  return Column(
                    children: [
                      desde,
                      const SizedBox(height: 10),
                      hasta,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: desde),
                    const SizedBox(width: 10),
                    Expanded(child: hasta),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),

            _filter(
              value: selectedStructureRole,
              items: rolesEstructuraDisponibles,
              icon: Icons.account_tree_rounded,
              displayText: (value) => value == 'Todos'
                  ? 'Toda mi estructura'
                  : _rolTexto(value),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  selectedStructureRole = value;
                  selectedStructureUserId = 'Todos';
                  _aplicarFiltroEstructura();
                });
              },
            ),

            const SizedBox(height: 10),

            _personFilter(
              personas: personas,
              enabled: selectedStructureRole != 'Todos',
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text(
                    '${usuariosEstructura.length} personas · '
                    '${ventasFiltradas.length} pólizas filtradas',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.56),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _limpiarFiltrosAvanzados,
                  icon: const Icon(
                    Icons.filter_alt_off_rounded,
                    size: 18,
                  ),
                  label: const Text('Limpiar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateFilterButton({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.18),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Quitar fecha',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                )
              else
                const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white38,
                  size: 17,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personFilter({
    required List<Map<String, dynamic>> personas,
    required bool enabled,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: enabled
            ? Colors.white.withOpacity(0.075)
            : Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? Colors.purpleAccent.withOpacity(0.25)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search_rounded,
            color: enabled ? Colors.purpleAccent : Colors.white30,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedStructureUserId,
                isExpanded: true,
                dropdownColor: const Color(0xFF071A3A),
                iconEnabledColor:
                    enabled ? Colors.purpleAccent : Colors.white30,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w800,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: 'Todos',
                    child: Text(
                      enabled
                          ? 'Todas las personas de esta figura'
                          : 'Primero elige una figura',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...personas.map(
                    (persona) => DropdownMenuItem<String>(
                      value: persona['id']?.toString(),
                      child: Text(
                        _nombreCompleto(persona),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: !enabled
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          selectedStructureUserId = value;
                          _aplicarFiltroEstructura();
                        });
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filter({
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    String Function(String value)? displayText,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : 'Todos',
                isExpanded: true,
                dropdownColor: const Color(0xFF071A3A),
                iconEnabledColor: Colors.cyanAccent,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
                items: items
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(
                          displayText?.call(item) ?? item,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        children: [
          _kpiCard(
            'Prima neta',
            _formatearEuros(primaNetaTotal),
            Icons.euro_rounded,
            Colors.amberAccent,
          ),
          _kpiCard(
            'Pólizas',
            ventasFiltradas.length.toString(),
            Icons.receipt_long_rounded,
            Colors.cyanAccent,
          ),
          _kpiCard(
            'Clientes',
            clientesFiltrados.length.toString(),
            Icons.groups_rounded,
            Colors.greenAccent,
          ),
          _kpiCard(
            'Agentes activos',
            '$agentesActivos / $agentesEstructura',
            Icons.verified_user_rounded,
            Colors.purpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bubble(icon, color),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final data = primasPorMes;
    final totalGrafico = data.fold<double>(0, (a, b) => a + b);
    final mejorMes = data.isEmpty
        ? 0
        : data.indexOf(data.reduce(math.max));

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: _cardDecoration(const Color(0xFF22D3EE)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evolución mensual de primas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              selectedYear == 'Todos'
                  ? 'Prima neta acumulada por mes en todos los años'
                  : 'Prima neta mensual durante $selectedYear',
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _chartStat(
                  'Total',
                  _formatearEuros(totalGrafico),
                  Colors.cyanAccent,
                ),
                const SizedBox(width: 10),
                _chartStat(
                  'Mejor mes',
                  totalGrafico == 0
                      ? 'Sin datos'
                      : monthNames[mejorMes + 1],
                  Colors.amberAccent,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 265,
              width: double.infinity,
              child: CustomPaint(
                painter: _PremiumLineChartPainter(
                  values: data,
                  labels: List.generate(
                    12,
                    (i) => monthNames[i + 1].substring(0, 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartStat(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rolesCard() {
    final roles = primasPorRol.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = roles.fold<double>(0, (sum, item) => sum + item.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(const Color(0xFFA855F7)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Primas por figura',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (roles.isEmpty)
              Text(
                'Sin primas en el periodo seleccionado.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...roles.map((item) {
                final progress = total == 0 ? 0.0 : item.value / total;

                return _roleLine(
                  _rolTexto(item.key),
                  item.value,
                  progress.clamp(0.0, 1.0),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _roleLine(String title, double value, double progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _formatearEuros(value),
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.10),
              color: Colors.purpleAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankingCard() {
    final ranking = rankingAgentes;
    final maxPrima = ranking.isEmpty ? 0.0 : ranking.first.primaNeta;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(const Color(0xFFFFB020)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top agentes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Todos los agentes de tu estructura, ordenados por prima neta.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            if (ranking.isEmpty)
              Text(
                'No hay agentes en la estructura del usuario conectado.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...List.generate(ranking.length, (index) {
                final agente = ranking[index];
                final progreso = maxPrima <= 0
                    ? 0.0
                    : (agente.primaNeta / maxPrima).clamp(0.0, 1.0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 11),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: index == 0
                          ? Colors.amberAccent.withOpacity(0.28)
                          : Colors.white.withOpacity(0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? Colors.amberAccent.withOpacity(0.22)
                              : Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                              color: index == 0
                                  ? Colors.amberAccent
                                  : Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              agente.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: progreso,
                                minHeight: 6,
                                backgroundColor:
                                    Colors.white.withOpacity(0.08),
                                color: index == 0
                                    ? Colors.amberAccent
                                    : Colors.cyanAccent,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${agente.ventas} pólizas',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatearEuros(agente.primaNeta),
                        style: TextStyle(
                          color: index == 0
                              ? Colors.amberAccent
                              : Colors.cyanAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(Colors.redAccent),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 52,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar los KPIs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Icon(icon, color: color),
    );
  }

  BoxDecoration _cardDecoration(Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withOpacity(0.20),
          const Color(0xFF071A3A).withOpacity(0.92),
          const Color(0xFF020617).withOpacity(0.96),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: color.withOpacity(0.30)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.10),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}

class _AgenteRanking {
  final String nombre;
  final double primaNeta;
  final int ventas;

  const _AgenteRanking({
    required this.nombre,
    required this.primaNeta,
    required this.ventas,
  });
}

class _PremiumLineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  const _PremiumLineChartPainter({
    required this.values,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const right = 8.0;
    const top = 22.0;
    const bottom = 34.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    final maxValue = values.isEmpty
        ? 1.0
        : math.max(
            1.0,
            values.reduce(math.max) * 1.15,
          );

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = top + chartHeight * (i / 4);
      canvas.drawLine(
        Offset(left, y),
        Offset(left + chartWidth, y),
        gridPaint,
      );
    }

    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final x = values.length <= 1
          ? left
          : left + chartWidth * (i / (values.length - 1));
      final normalized = values[i] / maxValue;
      final y = top + chartHeight * (1 - normalized);
      points.add(Offset(x, y));
    }

    if (points.isNotEmpty) {
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);

      for (int i = 1; i < points.length; i++) {
        final previous = points[i - 1];
        final current = points[i];
        final controlX = (previous.dx + current.dx) / 2;

        linePath.cubicTo(
          controlX,
          previous.dy,
          controlX,
          current.dy,
          current.dx,
          current.dy,
        );
      }

      final areaPath = Path.from(linePath)
        ..lineTo(points.last.dx, top + chartHeight)
        ..lineTo(points.first.dx, top + chartHeight)
        ..close();

      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF22D3EE).withOpacity(0.30),
            const Color(0xFF2563EB).withOpacity(0.08),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromLTWH(left, top, chartWidth, chartHeight),
        );

      canvas.drawPath(areaPath, areaPaint);

      final glowPaint = Paint()
        ..color = const Color(0xFF22D3EE).withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawPath(linePath, glowPaint);

      final linePaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF67E8F9),
            Color(0xFF22D3EE),
            Color(0xFF2563EB),
            Color(0xFFA855F7),
          ],
        ).createShader(
          Rect.fromLTWH(left, top, chartWidth, chartHeight),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(linePath, linePaint);

      for (int i = 0; i < points.length; i++) {
        final point = points[i];

        canvas.drawCircle(
          point,
          6,
          Paint()..color = const Color(0xFF061329),
        );

        canvas.drawCircle(
          point,
          4,
          Paint()..color = const Color(0xFF67E8F9),
        );

        if (values[i] > 0) {
          final valueText = _compactMoney(values[i]);

          final valuePainter = TextPainter(
            text: TextSpan(
              text: valueText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final valueX = (point.dx - valuePainter.width / 2)
              .clamp(0.0, size.width - valuePainter.width);

          valuePainter.paint(
            canvas,
            Offset(valueX, math.max(0, point.dy - 19)),
          );
        }
      }
    }

    for (int i = 0; i < labels.length; i++) {
      final x = labels.length <= 1
          ? left
          : left + chartWidth * (i / (labels.length - 1));

      final labelPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white.withOpacity(0.48),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelX = (x - labelPainter.width / 2)
          .clamp(0.0, size.width - labelPainter.width);

      labelPainter.paint(
        canvas,
        Offset(labelX, size.height - bottom + 12),
      );
    }
  }

  String _compactMoney(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _PremiumLineChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.labels != labels;
  }
}

class _DirectorBackground extends StatelessWidget {
  const _DirectorBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF020617)),
        Positioned(
          top: -120,
          right: -90,
          child: _glow(const Color(0xFF22D3EE), 300),
        ),
        Positioned(
          top: 300,
          left: -140,
          child: _glow(const Color(0xFF7C3AED), 320),
        ),
        Positioned(
          bottom: -140,
          right: -110,
          child: _glow(const Color(0xFFFFB020), 300),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
    );
  }
}