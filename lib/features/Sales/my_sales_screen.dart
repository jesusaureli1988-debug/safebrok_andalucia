import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MySalesScreen extends StatefulWidget {
  const MySalesScreen({super.key});

  @override
  State<MySalesScreen> createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> ventas = [];
List<Map<String, dynamic>> usuariosPermitidos = [];

bool loading = true;

String? userRole;
String? userAuthId;
String? userInternalId;

DateTime? selectedDateFrom;
DateTime? selectedDateTo;

String selectedStructureMode = 'Toda mi estructura';
String selectedStructureUserId = 'Todos';

String selectedProduct = 'Todos';
String selectedCompany = 'Todos';

List<String> products = ['Todos'];
List<String> companies = ['Todos'];

final List<String> structureModes = const [
  'Toda mi estructura',
  'Solo mis ventas',
  'Persona individual',
  'Estructura de una persona',
];

  @override
  void initState() {
    super.initState();
    loadSales();
  }

  String _normalizarRol(dynamic rol) {
  return (rol ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

String _nombreCompleto(Map<String, dynamic>? usuario) {
  if (usuario == null) return 'Sin nombre';

  final nombre = usuario['nombre']?.toString().trim() ?? '';
  final apellidos = usuario['apellidos']?.toString().trim() ?? '';
  final completo = '$nombre $apellidos'.trim();

  if (completo.isNotEmpty) return completo;

  final email = usuario['email']?.toString().trim() ?? '';
  return email.isNotEmpty ? email : 'Sin nombre';
}

String _rolTexto(dynamic rol) {
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
      return rol?.toString().replaceAll('_', ' ') ?? '';
  }
}

List<Map<String, dynamic>> _obtenerUsuariosPermitidos({
  required Map<String, dynamic> perfil,
  required List<Map<String, dynamic>> todosUsuarios,
}) {
  String limpiarId(dynamic value) {
    final id = (value ?? '').toString().trim();
    if (id.isEmpty || id.toLowerCase() == 'null') return '';
    return id;
  }

  final rolPerfil = _normalizarRol(perfil['rol_usuario']);

  // Solo administración y dirección nacional pueden ver toda la compañía.
  if (rolPerfil == 'administracion' ||
      rolPerfil == 'administrador' ||
      rolPerfil == 'admin' ||
      rolPerfil == 'director_nacional') {
    return todosUsuarios.where((usuario) {
      return limpiarId(usuario['auth_id']).isNotEmpty;
    }).toList();
  }

  bool relacionPermitida({
    required String rolPadre,
    required String rolHijo,
  }) {
    final padre = _normalizarRol(rolPadre);
    final hijo = _normalizarRol(rolHijo);

    switch (padre) {
      case 'director_zona':
        return hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_ventas':
        return hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_equipo':
        return hijo == 'agente';

      case 'agente':
        return false;

      default:
        return false;
    }
  }

  final usuariosNormalizados =
      todosUsuarios.map((usuario) {
    return <String, dynamic>{
      ...usuario,
      'id': limpiarId(usuario['id']),
      'auth_id': limpiarId(usuario['auth_id']),
      'parent_id': limpiarId(usuario['parent_id']),
      'rol_usuario': _normalizarRol(usuario['rol_usuario']),
    };
  }).toList();

  final perfilNormalizado = <String, dynamic>{
    ...perfil,
    'id': limpiarId(perfil['id']),
    'auth_id': limpiarId(perfil['auth_id']),
    'parent_id': limpiarId(perfil['parent_id']),
    'rol_usuario': _normalizarRol(perfil['rol_usuario']),
  };

  final usuariosPorParentId =
      <String, List<Map<String, dynamic>>>{};

  for (final usuario in usuariosNormalizados) {
    final parentId = limpiarId(usuario['parent_id']);
    if (parentId.isEmpty) continue;

    usuariosPorParentId
        .putIfAbsent(
          parentId,
          () => <Map<String, dynamic>>[],
        )
        .add(usuario);
  }

  final resultado = <Map<String, dynamic>>[];
  final idsVisitados = <String>{};

  void recorrer(Map<String, dynamic> usuarioActual) {
    final idActual = limpiarId(usuarioActual['id']);
    final rolActual =
        _normalizarRol(usuarioActual['rol_usuario']);

    if (idActual.isEmpty || idsVisitados.contains(idActual)) {
      return;
    }

    idsVisitados.add(idActual);
    resultado.add(usuarioActual);

    final hijos = usuariosPorParentId[idActual] ??
        const <Map<String, dynamic>>[];

    for (final hijo in hijos) {
      final rolHijo =
          _normalizarRol(hijo['rol_usuario']);

      if (!relacionPermitida(
        rolPadre: rolActual,
        rolHijo: rolHijo,
      )) {
        debugPrint(
          'MIS VENTAS: usuario bloqueado '
          '${_nombreCompleto(hijo)} '
          '| rol=$rolHijo '
          '| parent_id=${hijo['parent_id']} '
          '| padre=$rolActual',
        );
        continue;
      }

      recorrer(hijo);
    }
  }

  // Punto de partida único: el usuario conectado.
  // Nunca se recorre hacia arriba ni hacia otras ramas.
  recorrer(perfilNormalizado);

  return resultado.where((usuario) {
    return limpiarId(usuario['auth_id']).isNotEmpty;
  }).toList();
}

  Future<void> loadSales() async {
  final user = supabase.auth.currentUser;

  if (user == null) {
    if (!mounted) return;

    setState(() {
      ventas = [];
      usuariosPermitidos = [];
      loading = false;
    });

    return;
  }

  try {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    final usuarioDb = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
        )
        .eq('auth_id', user.id)
        .single();

    final perfil = Map<String, dynamic>.from(usuarioDb);

    userRole = perfil['rol_usuario']?.toString();
    userAuthId = perfil['auth_id']?.toString();
    userInternalId = perfil['id']?.toString();

    final usuariosData = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
        );

    final todosUsuarios =
        List<Map<String, dynamic>>.from(usuariosData);

    final estructura = _obtenerUsuariosPermitidos(
      perfil: perfil,
      todosUsuarios: todosUsuarios,
    );

    final authIds = estructura
        .map(
          (usuario) =>
              usuario['auth_id']?.toString().trim() ?? '',
        )
        .where(
          (authId) =>
              authId.isNotEmpty &&
              authId.toLowerCase() != 'null',
        )
        .toSet()
        .toList();

    List<Map<String, dynamic>> ventasEncontradas = [];

    if (authIds.isNotEmpty) {
      final response = await supabase
          .from('ventas')
          .select('''
            id,
            created_at,
            agente_auth_id,
            producto,
            compania,
            precio,
            prima_anual_neta,
            numero_asegurados,
            forma_pago,
            fecha_efecto,
            numero_poliza,
            clientes (
              nombre,
              apellidos,
              telefono
            )
          ''')
          .inFilter('agente_auth_id', authIds)
          .order('created_at', ascending: false);

      ventasEncontradas =
          List<Map<String, dynamic>>.from(response);
    }

    usuariosPermitidos = estructura;
    ventas = ventasEncontradas;

    _buildFilters();

    debugPrint('====================================');
    debugPrint('MIS VENTAS - ESTRUCTURA');
    debugPrint('USUARIO: ${_nombreCompleto(perfil)}');
    debugPrint('ROL: $userRole');
    debugPrint('PERSONAS PERMITIDAS: ${estructura.length}');
    debugPrint('VENTAS ENCONTRADAS: ${ventas.length}');

    for (final usuario in estructura) {
      debugPrint(
        '- ${_nombreCompleto(usuario)} '
        '| rol=${usuario['rol_usuario']} '
        '| id=${usuario['id']} '
        '| parent=${usuario['parent_id']} '
        '| auth_id=${usuario['auth_id']}',
      );
    }

    debugPrint('====================================');

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  } catch (e, stackTrace) {
    debugPrint('ERROR LOAD SALES: $e');
    debugPrintStack(stackTrace: stackTrace);

    if (!mounted) return;

    setState(() {
      ventas = [];
      usuariosPermitidos = [];
      loading = false;
    });
  }
}

  Future<List<String>> getAgentesBajoUsuario(
  String internalId,
  String authId,
  String role,
) async {
  final rol = _normalizarRol(role);

  if (rol == 'agente') {
    return <String>[authId];
  }

  final usuariosData = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario');

  String limpiarId(dynamic value) {
    final id = (value ?? '').toString().trim();
    if (id.isEmpty || id.toLowerCase() == 'null') return '';
    return id;
  }

  final usuarios =
      List<Map<String, dynamic>>.from(usuariosData).map((u) {
    return <String, dynamic>{
      ...u,
      'id': limpiarId(u['id']),
      'auth_id': limpiarId(u['auth_id']),
      'parent_id': limpiarId(u['parent_id']),
      'rol_usuario': _normalizarRol(u['rol_usuario']),
    };
  }).toList();

  if (rol == 'administracion' ||
      rol == 'administrador' ||
      rol == 'admin' ||
      rol == 'director_nacional') {
    return usuarios
        .map((u) => limpiarId(u['auth_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  bool relacionPermitida(String rolPadre, String rolHijo) {
    switch (_normalizarRol(rolPadre)) {
      case 'director_zona':
        return rolHijo == 'jefe_ventas' ||
            rolHijo == 'jefe_equipo' ||
            rolHijo == 'agente';

      case 'jefe_ventas':
        return rolHijo == 'jefe_equipo' ||
            rolHijo == 'agente';

      case 'jefe_equipo':
        return rolHijo == 'agente';

      default:
        return false;
    }
  }

  final porParentId =
      <String, List<Map<String, dynamic>>>{};

  for (final usuario in usuarios) {
    final parentId = limpiarId(usuario['parent_id']);
    if (parentId.isEmpty) continue;

    porParentId
        .putIfAbsent(
          parentId,
          () => <Map<String, dynamic>>[],
        )
        .add(usuario);
  }

  final resultado = <String>{authId};
  final visitados = <String>{};

  void recorrer(String idActual, String rolActual) {
    if (idActual.isEmpty || visitados.contains(idActual)) return;

    visitados.add(idActual);

    final hijos =
        porParentId[idActual] ?? const <Map<String, dynamic>>[];

    for (final hijo in hijos) {
      final rolHijo =
          _normalizarRol(hijo['rol_usuario']);

      if (!relacionPermitida(rolActual, rolHijo)) {
        continue;
      }

      final authHijo = limpiarId(hijo['auth_id']);
      final idHijo = limpiarId(hijo['id']);

      if (authHijo.isNotEmpty) {
        resultado.add(authHijo);
      }

      recorrer(idHijo, rolHijo);
    }
  }

  recorrer(internalId, rol);

  return resultado.toList();
}

  void _buildFilters() {
  final productSet = <String>{};
  final companySet = <String>{};

  for (final venta in ventas) {
    final producto = venta['producto']?.toString().trim();
    final compania = venta['compania']?.toString().trim();

    if (producto != null && producto.isNotEmpty) {
      productSet.add(producto);
    }

    if (compania != null && compania.isNotEmpty) {
      companySet.add(compania);
    }
  }

  products = [
    'Todos',
    ...productSet.toList()..sort(),
  ];

  companies = [
    'Todos',
    ...companySet.toList()..sort(),
  ];

  if (!products.contains(selectedProduct)) {
    selectedProduct = 'Todos';
  }

  if (!companies.contains(selectedCompany)) {
    selectedCompany = 'Todos';
  }
}

Set<String> _authIdsSubestructura(String usuarioId) {
  final usuariosPorParentId =
      <String, List<Map<String, dynamic>>>{};

  for (final usuario in usuariosPermitidos) {
    final parentId =
        usuario['parent_id']?.toString().trim() ?? '';

    if (parentId.isEmpty || parentId.toLowerCase() == 'null') {
      continue;
    }

    usuariosPorParentId
        .putIfAbsent(
          parentId,
          () => <Map<String, dynamic>>[],
        )
        .add(usuario);
  }

  final authIds = <String>{};
  final visitados = <String>{};

  void recorrer(String id) {
    if (id.isEmpty || visitados.contains(id)) return;

    visitados.add(id);

    Map<String, dynamic>? usuarioActual;

    for (final usuario in usuariosPermitidos) {
      if (usuario['id']?.toString() == id) {
        usuarioActual = usuario;
        break;
      }
    }

    if (usuarioActual != null) {
      final authId =
          usuarioActual['auth_id']?.toString().trim() ?? '';

      if (authId.isNotEmpty && authId.toLowerCase() != 'null') {
        authIds.add(authId);
      }
    }

    final hijos = usuariosPorParentId[id] ??
        <Map<String, dynamic>>[];

    for (final hijo in hijos) {
      recorrer(hijo['id']?.toString() ?? '');
    }
  }

  recorrer(usuarioId);

  return authIds;
}

DateTime? _fechaVenta(Map<String, dynamic> venta) {
  return DateTime.tryParse(
    venta['created_at']?.toString() ?? '',
  );
}

List<Map<String, dynamic>> get filteredVentas {
  Set<String>? authIdsPermitidosFiltro;

  switch (selectedStructureMode) {
    case 'Solo mis ventas':
      authIdsPermitidosFiltro = {
        if (userAuthId != null && userAuthId!.isNotEmpty)
          userAuthId!,
      };
      break;

    case 'Persona individual':
      if (selectedStructureUserId != 'Todos') {
        final persona = usuariosPermitidos.firstWhere(
          (usuario) =>
              usuario['id']?.toString() ==
              selectedStructureUserId,
          orElse: () => <String, dynamic>{},
        );

        final authId =
            persona['auth_id']?.toString().trim() ?? '';

        authIdsPermitidosFiltro = {
          if (authId.isNotEmpty && authId.toLowerCase() != 'null')
            authId,
        };
      } else {
        authIdsPermitidosFiltro = <String>{};
      }
      break;

    case 'Estructura de una persona':
      if (selectedStructureUserId != 'Todos') {
        authIdsPermitidosFiltro = _authIdsSubestructura(
          selectedStructureUserId,
        );
      } else {
        authIdsPermitidosFiltro = <String>{};
      }
      break;

    case 'Toda mi estructura':
    default:
      authIdsPermitidosFiltro = null;
      break;
  }

  return ventas.where((venta) {
    final fecha = _fechaVenta(venta);
    final authIdVenta =
        venta['agente_auth_id']?.toString() ?? '';

    final okDesde = selectedDateFrom == null ||
        (fecha != null &&
            !fecha.isBefore(selectedDateFrom!));

    final okHasta = selectedDateTo == null ||
        (fecha != null &&
            !fecha.isAfter(selectedDateTo!));

    final okEstructura = authIdsPermitidosFiltro == null ||
        authIdsPermitidosFiltro.contains(authIdVenta);

    final okProduct = selectedProduct == 'Todos' ||
        selectedProduct ==
            venta['producto']?.toString();

    final okCompany = selectedCompany == 'Todos' ||
        selectedCompany ==
            venta['compania']?.toString();

    return okDesde &&
        okHasta &&
        okEstructura &&
        okProduct &&
        okCompany;
  }).toList();
}

Future<void> _seleccionarFechaDesde() async {
  final ahora = DateTime.now();

  final fecha = await showDatePicker(
    context: context,
    initialDate: selectedDateFrom ??
        DateTime(ahora.year, ahora.month, 1),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'Selecciona la fecha inicial',
    cancelText: 'Cancelar',
    confirmText: 'Aceptar',
  );

  if (fecha == null || !mounted) return;

  setState(() {
    selectedDateFrom = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    );

    if (selectedDateTo != null &&
        selectedDateTo!.isBefore(selectedDateFrom!)) {
      selectedDateTo = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        23,
        59,
        59,
        999,
      );
    }
  });
}

Future<void> _seleccionarFechaHasta() async {
  final ahora = DateTime.now();

  final fecha = await showDatePicker(
    context: context,
    initialDate: selectedDateTo ?? ahora,
    firstDate: selectedDateFrom ?? DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'Selecciona la fecha final',
    cancelText: 'Cancelar',
    confirmText: 'Aceptar',
  );

  if (fecha == null || !mounted) return;

  setState(() {
    selectedDateTo = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      23,
      59,
      59,
      999,
    );
  });
}

String _fechaTexto(DateTime? fecha) {
  if (fecha == null) return 'Sin límite';

  return '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/'
      '${fecha.year}';
}

void _limpiarFiltros() {
  setState(() {
    selectedDateFrom = null;
    selectedDateTo = null;
    selectedStructureMode = 'Toda mi estructura';
    selectedStructureUserId = 'Todos';
    selectedProduct = 'Todos';
    selectedCompany = 'Todos';
  });
}

List<Map<String, dynamic>> get personasDisponibles {
  final personas =
      List<Map<String, dynamic>>.from(usuariosPermitidos);

  personas.sort((a, b) {
    return _nombreCompleto(a)
        .toLowerCase()
        .compareTo(
          _nombreCompleto(b).toLowerCase(),
        );
  });

  return personas;
}

  int get totalAsegurados {
    return filteredVentas.fold<int>(
      0,
      (sum, v) => sum + ((v['numero_asegurados'] as num?)?.toInt() ?? 0),
    );
  }

  double _money(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    final texto = value.toString().trim();
    if (texto.isEmpty) return 0.0;

    final normalizado = texto.contains(',')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto;

    return double.tryParse(normalizado) ?? 0.0;
  }

  double get totalPrima {
    return filteredVentas.fold<double>(
      0.0,
      (sum, venta) =>
          sum + _money(venta['prima_anual_neta']),
    );
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF07111B),

    appBar: AppBar(
      backgroundColor: const Color(0xFF07111B).withOpacity(0.95),
      elevation: 0,
      scrolledUnderElevation: 0,

      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.35),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),

      leading: IconButton(
        splashRadius: 24,
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 22,
        ),
        onPressed: () => Navigator.pop(context),
      ),

      title: const Text(
        'Mis Ventas',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),

      centerTitle: false,
    ),

    body: Stack(
      children: [
        const _PremiumBackground(),

        if (loading)
          const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          )
        else if (ventas.isEmpty)
          _emptyState()
        else
          RefreshIndicator(
            color: Colors.cyanAccent,
            backgroundColor: const Color(0xFF102331),
            onRefresh: loadSales,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _filters()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: filteredVentas.length,
                    itemBuilder: (context, index) {
                      return _saleCard(filteredVentas[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard(
              'Ventas',
              filteredVentas.length.toString(),
              Icons.receipt_long_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Asegurados',
              totalAsegurados.toString(),
              Icons.groups_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Prima filtrada',
              '${totalPrima.toStringAsFixed(2)} €',
              Icons.euro_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 22),
              const SizedBox(height: 12),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

 Widget _filters() {
  final necesitaPersona =
      selectedStructureMode == 'Persona individual' ||
      selectedStructureMode == 'Estructura de una persona';

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dateFilter(
                  label: 'Desde',
                  value: _fechaTexto(selectedDateFrom),
                  icon: Icons.first_page_rounded,
                  onTap: _seleccionarFechaDesde,
                  onClear: selectedDateFrom == null
                      ? null
                      : () {
                          setState(() {
                            selectedDateFrom = null;
                          });
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateFilter(
                  label: 'Hasta',
                  value: _fechaTexto(selectedDateTo),
                  icon: Icons.last_page_rounded,
                  onTap: _seleccionarFechaHasta,
                  onClear: selectedDateTo == null
                      ? null
                      : () {
                          setState(() {
                            selectedDateTo = null;
                          });
                        },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          _filter(
            'Vista',
            selectedStructureMode,
            structureModes,
            (value) {
              if (value == null) return;

              setState(() {
                selectedStructureMode = value;
                selectedStructureUserId = 'Todos';
              });
            },
          ),

          if (necesitaPersona) ...[
            const SizedBox(height: 10),
            _personFilter(),
          ],

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _filter(
                  'Producto',
                  selectedProduct,
                  products,
                  (value) {
                    if (value == null) return;

                    setState(() {
                      selectedProduct = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _filter(
                  'Compañía',
                  selectedCompany,
                  companies,
                  (value) {
                    if (value == null) return;

                    setState(() {
                      selectedCompany = value;
                    });
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Text(
                  '${filteredVentas.length} ventas encontradas',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _limpiarFiltros,
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

Widget _dateFilter({
  required String label,
  required String value,
  required IconData icon,
  required VoidCallback onTap,
  VoidCallback? onClear,
}) {
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.cyanAccent,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 17,
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white38,
                size: 16,
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _personFilter() {
  final personas = personasDisponibles;

  final valorValido =
      selectedStructureUserId == 'Todos' ||
      personas.any(
        (usuario) =>
            usuario['id']?.toString() ==
            selectedStructureUserId,
      );

  if (!valorValido) {
    selectedStructureUserId = 'Todos';
  }

  return Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.purpleAccent.withOpacity(0.24),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.person_search_rounded,
          color: Colors.purpleAccent,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedStructureUserId,
              isExpanded: true,
              dropdownColor: const Color(0xFF102331),
              iconEnabledColor: Colors.purpleAccent,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: 'Todos',
                  child: Text(
                    'Selecciona una persona',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...personas.map(
                  (usuario) {
                    final nombre = _nombreCompleto(usuario);
                    final rol = _rolTexto(
                      usuario['rol_usuario'],
                    );

                    return DropdownMenuItem<String>(
                      value: usuario['id']?.toString(),
                      child: Text(
                        '$nombre · $rol',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  selectedStructureUserId = value;
                });
              },
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _filter(
  String label,
  String value,
  List<String> items,
  Function(String?) onChanged,
) {
  return Container(
    height: 56,
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.white.withOpacity(0.10),
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        dropdownColor: const Color(0xFF102331),
        iconEnabledColor: Colors.cyanAccent,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        items: items.map((item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(
              '$label: $item',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

  Widget _saleCard(Map<String, dynamic> venta) {
  final cliente = venta['clientes'];
  final nombre = cliente != null
      ? '${cliente['nombre'] ?? ''} ${cliente['apellidos'] ?? ''}'.trim()
      : 'Cliente sin vincular';

  final fecha = DateTime.tryParse(venta['created_at']?.toString() ?? '');
  final fechaTexto = fecha == null
      ? 'Sin fecha'
      : '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.cyanAccent.withOpacity(0.95),
                          Colors.blueAccent.withOpacity(0.80),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF07111B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nombre.isEmpty ? 'Cliente' : nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar venta',
                    onPressed: () => _openEditSaleSheet(venta),
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fechaTexto,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag(Icons.shield_rounded, venta['producto'] ?? 'Producto'),
                  _tag(Icons.business_rounded, venta['compania'] ?? 'Compañía'),
                  _tag(Icons.credit_card_rounded, venta['forma_pago'] ?? 'Forma pago'),
                  _tag(Icons.euro_rounded, '${venta['precio'] ?? 0} €'),
                  _tag(
                    Icons.groups_rounded,
                    '${venta['numero_asegurados'] ?? 0} asegurados',
                  ),
                  if (venta['fecha_efecto'] != null)
                    _tag(
                      Icons.event_available_rounded,
                      venta['fecha_efecto'].toString(),
                    ),
                  if (venta['numero_poliza'] != null)
                    _tag(
                      Icons.confirmation_number_rounded,
                      venta['numero_poliza'].toString(),
                    ),
                  if (cliente != null && cliente['telefono'] != null)
                    _tag(Icons.phone_rounded, cliente['telefono'].toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

 void _openEditSaleSheet(Map<String, dynamic> venta) {
  final productoController =
      TextEditingController(text: venta['producto']?.toString() ?? '');
  final companiaController =
      TextEditingController(text: venta['compania']?.toString() ?? '');
  final formaPagoController =
      TextEditingController(text: venta['forma_pago']?.toString() ?? '');
  final precioController =
      TextEditingController(text: venta['precio']?.toString() ?? '');
  final aseguradosController =
      TextEditingController(text: venta['numero_asegurados']?.toString() ?? '');
  final fechaEfectoController =
      TextEditingController(text: venta['fecha_efecto']?.toString() ?? '');
  final numeroPolizaController =
      TextEditingController(text: venta['numero_poliza']?.toString() ?? '');

  bool saving = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> guardarCambios() async {
            if (saving) return;

            final precioTexto = precioController.text.trim().replaceAll(',', '.');
final aseguradosTexto = aseguradosController.text.trim();

final precio = precioTexto.isEmpty
    ? null
    : double.tryParse(precioTexto);

final asegurados = aseguradosTexto.isEmpty
    ? null
    : int.tryParse(aseguradosTexto);

if (precioTexto.isNotEmpty && precio == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'El precio introducido no es válido.',
      ),
      backgroundColor: Colors.orangeAccent,
    ),
  );
  return;
}

if (aseguradosTexto.isNotEmpty && asegurados == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'El número de asegurados no es válido.',
      ),
      backgroundColor: Colors.orangeAccent,
    ),
  );
  return;
}

            try {
              setModalState(() => saving = true);

             await supabase.from('ventas').update({
  'producto': productoController.text.trim().isEmpty
      ? null
      : productoController.text.trim(),

  'compania': companiaController.text.trim().isEmpty
      ? null
      : companiaController.text.trim(),

  'forma_pago': formaPagoController.text.trim().isEmpty
      ? null
      : formaPagoController.text.trim(),

  'precio': precio,

  'numero_asegurados': asegurados,

  'fecha_efecto': fechaEfectoController.text.trim().isEmpty
      ? null
      : fechaEfectoController.text.trim(),

  'numero_poliza': numeroPolizaController.text.trim().isEmpty
      ? null
      : numeroPolizaController.text.trim(),
}).eq('id', venta['id']);

              if (!mounted) return;

              Navigator.pop(context);

              setState(() => loading = true);
              await loadSales();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Venta actualizada correctamente'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              setModalState(() => saving = false);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error al actualizar venta: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          Future<void> seleccionarFechaEfecto() async {
            final actual = DateTime.tryParse(fechaEfectoController.text.trim()) ??
                DateTime.now();

            final picked = await showDatePicker(
              context: context,
              initialDate: actual,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Colors.cyanAccent,
                      onPrimary: Color(0xFF07111B),
                      surface: Color(0xFF102331),
                      onSurface: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (picked != null) {
              fechaEfectoController.text =
                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102331).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Editar venta',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _editField(
                          controller: productoController,
                          label: 'Producto',
                          icon: Icons.shield_rounded,
                        ),
                        _editField(
                          controller: companiaController,
                          label: 'Compañía',
                          icon: Icons.business_rounded,
                        ),
                        _editField(
                          controller: formaPagoController,
                          label: 'Forma de pago',
                          icon: Icons.credit_card_rounded,
                        ),
                        _editField(
                          controller: precioController,
                          label: 'Precio mensual',
                          icon: Icons.euro_rounded,
                          keyboardType: TextInputType.number,
                        ),
                        _editField(
                          controller: aseguradosController,
                          label: 'Número de asegurados',
                          icon: Icons.groups_rounded,
                          keyboardType: TextInputType.number,
                        ),
                        GestureDetector(
                          onTap: seleccionarFechaEfecto,
                          child: AbsorbPointer(
                            child: _editField(
                              controller: fechaEfectoController,
                              label: 'Fecha de efecto',
                              icon: Icons.event_available_rounded,
                            ),
                          ),
                        ),
                        _editField(
                          controller: numeroPolizaController,
                          label: 'Número de póliza',
                          icon: Icons.confirmation_number_rounded,
                        ),

                        const SizedBox(height: 18),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: saving ? null : guardarCambios,
                            icon: saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              saving ? 'Guardando...' : 'Guardar cambios',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: const Color(0xFF07111B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.65)),
          prefixIcon: Icon(icon, color: Colors.cyanAccent),
          filled: true,
          fillColor: Colors.white.withOpacity(0.07),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.cyanAccent),
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              color: Colors.white.withOpacity(0.35),
              size: 64,
            ),
            const SizedBox(height: 18),
            const Text(
              'No hay ventas aún',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando se registren ventas en tu estructura aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF07111B),
                Color(0xFF102331),
                Color(0xFF16384D),
              ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: _GlowBall(color: Colors.cyanAccent.withOpacity(0.22)),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: _GlowBall(color: Colors.blueAccent.withOpacity(0.18)),
        ),
      ],
    );
  }
}

class _GlowBall extends StatelessWidget {
  final Color color;

  const _GlowBall({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      width: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}