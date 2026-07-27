import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/nuevo_candidato_screen.dart';
import 'detalle_candidato_screen.dart';

class CandidatosCaptacionScreen extends StatefulWidget {
  const CandidatosCaptacionScreen({super.key});

  @override
  State<CandidatosCaptacionScreen> createState() =>
      _CandidatosCaptacionScreenState();
}

class _CandidatosCaptacionScreenState extends State<CandidatosCaptacionScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String filtroActivo = 'TODOS';
  String busqueda = '';

  String rolLogueado = '';
  String? figuraSeleccionada;
  String? authIdSeleccionado;
  DateTime? fechaDesde;
  DateTime? fechaHasta;

  List<Map<String, dynamic>> candidatos = [];
  List<Map<String, dynamic>> usuariosEstructura = [];

  int total = 0;
  int enProceso = 0;
  int finalizados = 0;

  final TextEditingController searchController = TextEditingController();

  final List<String> flujo = const [
    'CV_RECIBIDO',
    'CONTACTADO',
    'ENTREVISTA_CONCERTADA',
    'ENTREVISTA_REALIZADA',
    'SELECCIONADO',
    'INCORPORADO',
  ];

  @override
  void initState() {
    super.initState();
    cargarTodo();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> cargarTodo() async {
    await cargarCandidatos();
    calcularKPIs();
  }

  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  int _nivelRol(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 5;
      case 'director_zona':
        return 4;
      case 'jefe_ventas':
        return 3;
      case 'jefe_equipo':
        return 2;
      case 'agente':
        return 1;
      default:
        return 0;
    }
  }

  bool get puedeFiltrarEstructura {
    return rolLogueado == 'jefe_ventas' ||
        rolLogueado == 'director_zona' ||
        rolLogueado == 'director_nacional';
  }

  String _nombreCompleto(Map<String, dynamic> usuario) {
    final nombre = usuario['nombre']?.toString().trim() ?? '';
    final apellidos = usuario['apellidos']?.toString().trim() ?? '';
    final completo = '$nombre $apellidos'.trim();
    return completo.isEmpty ? 'Usuario sin nombre' : completo;
  }

  String _rolVisible(String rol) {
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
      default:
        return 'Sin figura';
    }
  }

  Future<List<Map<String, dynamic>>> _cargarUsuariosPermitidos(
    String authIdLogueado,
  ) async {
    final data = await supabase.from('usuarios').select(
          'id, auth_id, parent_id, rol_usuario, nombre, apellidos',
        );

    final usuarios = List<Map<String, dynamic>>.from(data).map((u) {
      return <String, dynamic>{
        'id': u['id']?.toString().trim() ?? '',
        'auth_id': u['auth_id']?.toString().trim() ?? '',
        'parent_id': u['parent_id']?.toString().trim() ?? '',
        'rol_usuario': _normalizarRol(u['rol_usuario']),
        'nombre': u['nombre']?.toString() ?? '',
        'apellidos': u['apellidos']?.toString() ?? '',
      };
    }).toList();

    final yo = usuarios.firstWhere(
      (u) => u['auth_id'] == authIdLogueado,
      orElse: () => <String, dynamic>{},
    );

    if (yo.isEmpty) {
      rolLogueado = '';
      return <Map<String, dynamic>>[
        {
          'id': '',
          'auth_id': authIdLogueado,
          'parent_id': '',
          'rol_usuario': '',
          'nombre': '',
          'apellidos': '',
        }
      ];
    }

    rolLogueado = _normalizarRol(yo['rol_usuario']);

    if (rolLogueado == 'director_nacional') {
      return usuarios
          .where((u) =>
              (u['auth_id']?.toString().isNotEmpty ?? false) &&
              u['auth_id'].toString().toLowerCase() != 'null')
          .toList();
    }

    final hijosPorParentId = <String, List<Map<String, dynamic>>>{};

    for (final usuario in usuarios) {
      final parentId = usuario['parent_id']?.toString().trim() ?? '';
      if (parentId.isEmpty || parentId.toLowerCase() == 'null') continue;

      hijosPorParentId
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final id = actual['id']?.toString().trim() ?? '';
      final nivelActual = _nivelRol(actual['rol_usuario']?.toString() ?? '');

      if (id.isEmpty || visitados.contains(id)) return;
      visitados.add(id);
      resultado.add(actual);

      for (final hijo
          in hijosPorParentId[id] ?? <Map<String, dynamic>>[]) {
        final nivelHijo =
            _nivelRol(hijo['rol_usuario']?.toString() ?? '');

        if (nivelHijo > 0 && nivelHijo < nivelActual) {
          recorrer(hijo);
        }
      }
    }

    recorrer(yo);
    return resultado;
  }

  Set<String> _authIdsSubestructura(String authIdRaiz) {
    final usuarioRaiz = usuariosEstructura.firstWhere(
      (u) => u['auth_id'] == authIdRaiz,
      orElse: () => <String, dynamic>{},
    );

    if (usuarioRaiz.isEmpty) return <String>{authIdRaiz};

    final hijosPorParentId = <String, List<Map<String, dynamic>>>{};
    for (final usuario in usuariosEstructura) {
      final parentId = usuario['parent_id']?.toString().trim() ?? '';
      if (parentId.isEmpty) continue;
      hijosPorParentId
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }

    final resultado = <String>{};
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final id = actual['id']?.toString().trim() ?? '';
      final authId = actual['auth_id']?.toString().trim() ?? '';

      if (id.isEmpty || visitados.contains(id)) return;
      visitados.add(id);

      if (authId.isNotEmpty) resultado.add(authId);

      for (final hijo
          in hijosPorParentId[id] ?? <Map<String, dynamic>>[]) {
        recorrer(hijo);
      }
    }

    recorrer(usuarioRaiz);
    return resultado;
  }

  Future<void> cargarCandidatos() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          candidatos = [];
          loading = false;
        });
        return;
      }

      final usuariosPermitidos =
          await _cargarUsuariosPermitidos(user.id);

      final authIds = usuariosPermitidos
          .map((u) => u['auth_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty && id.toLowerCase() != 'null')
          .toSet()
          .toList();

      if (authIds.isEmpty) {
        if (!mounted) return;

        setState(() {
          usuariosEstructura = usuariosPermitidos;
          candidatos = [];
          loading = false;
        });
        return;
      }

      final asignadosData = await supabase
          .from('candidatos_captacion')
          .select()
          .inFilter('asignado_auth_id', authIds)
          .order('created_at', ascending: false);

      final antiguosData = await supabase
          .from('candidatos_captacion')
          .select()
          .inFilter('auth_id', authIds)
          .filter('asignado_auth_id', 'is', null)
          .order('created_at', ascending: false);

      final unicos = <String, Map<String, dynamic>>{};

      for (final item
          in List<Map<String, dynamic>>.from(asignadosData)) {
        final id = item['id']?.toString() ??
            'asignado_${unicos.length}_${item['created_at']}';
        unicos[id] = item;
      }

      for (final item
          in List<Map<String, dynamic>>.from(antiguosData)) {
        final id = item['id']?.toString() ??
            'antiguo_${unicos.length}_${item['created_at']}';
        unicos[id] = item;
      }

      final lista = unicos.values.toList()
        ..sort((a, b) {
          final fechaA =
              DateTime.tryParse(a['created_at']?.toString() ?? '');
          final fechaB =
              DateTime.tryParse(b['created_at']?.toString() ?? '');

          if (fechaA == null && fechaB == null) return 0;
          if (fechaA == null) return 1;
          if (fechaB == null) return -1;

          return fechaB.compareTo(fechaA);
        });

      if (!mounted) return;

      setState(() {
        usuariosEstructura = usuariosPermitidos;
        candidatos = lista;
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ ERROR CARGANDO CANDIDATOS: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  void calcularKPIs() {
    int proceso = 0;
    int fin = 0;

    for (final c in candidatosFiltrados) {
      final estado = c['estado'];

      if (estado == 'INCORPORADO' || estado == 'DESCARTADO') {
        fin++;
      } else {
        proceso++;
      }
    }

    setState(() {
      total = candidatosFiltrados.length;
      enProceso = proceso;
      finalizados = fin;
    });
  }

  DateTime? _fechaCandidato(Map<String, dynamic> candidato) {
    final value = candidato['created_at'] ?? candidato['fecha'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _authIdResponsableCandidato(
    Map<String, dynamic> candidato,
  ) {
    final asignado =
        candidato['asignado_auth_id']?.toString().trim() ?? '';

    if (asignado.isNotEmpty && asignado.toLowerCase() != 'null') {
      return asignado;
    }

    return candidato['auth_id']?.toString().trim() ?? '';
  }

  List<Map<String, dynamic>> get candidatosFiltrados {
    Set<String>? authIdsPermitidosPorFiltro;

    if (puedeFiltrarEstructura && authIdSeleccionado != null) {
      authIdsPermitidosPorFiltro =
          _authIdsSubestructura(authIdSeleccionado!);
    }

    return candidatos.where((c) {
      final estado = c['estado']?.toString() ?? '';
      final authIdResponsable = _authIdResponsableCandidato(c);

      final nombre = c['nombre']?.toString().toLowerCase() ?? '';
      final telefono = c['telefono']?.toString().toLowerCase() ?? '';
      final email = c['email']?.toString().toLowerCase() ?? '';
      final origen = c['origen']?.toString().toLowerCase() ?? '';

      final texto = busqueda.toLowerCase();

      final coincideBusqueda = texto.isEmpty ||
          nombre.contains(texto) ||
          telefono.contains(texto) ||
          email.contains(texto) ||
          origen.contains(texto);

      final coincideFiltro =
          filtroActivo == 'TODOS' || estado == filtroActivo;

      final usuarioResponsable = usuariosEstructura.firstWhere(
        (u) => u['auth_id'] == authIdResponsable,
        orElse: () => <String, dynamic>{},
      );

      final coincideFigura = figuraSeleccionada == null ||
          _normalizarRol(usuarioResponsable['rol_usuario']) ==
              figuraSeleccionada;

      final coincideEstructura =
          authIdsPermitidosPorFiltro == null ||
              authIdsPermitidosPorFiltro.contains(authIdResponsable);

      final fecha = _fechaCandidato(c);
      final desde = fechaDesde == null
          ? null
          : DateTime(
              fechaDesde!.year,
              fechaDesde!.month,
              fechaDesde!.day,
            );
      final hasta = fechaHasta == null
          ? null
          : DateTime(
              fechaHasta!.year,
              fechaHasta!.month,
              fechaHasta!.day,
              23,
              59,
              59,
              999,
            );

      final coincideDesde =
          desde == null || (fecha != null && !fecha.isBefore(desde));
      final coincideHasta =
          hasta == null || (fecha != null && !fecha.isAfter(hasta));

      return coincideBusqueda &&
          coincideFiltro &&
          coincideFigura &&
          coincideEstructura &&
          coincideDesde &&
          coincideHasta;
    }).toList();
  }

  List<Map<String, dynamic>> candidatosPorEstado(String estado) {
    return candidatosFiltrados.where((c) {
      if (estado == 'ENTREVISTAS') {
        return c['estado'] == 'ENTREVISTA_CONCERTADA' ||
            c['estado'] == 'ENTREVISTA_REALIZADA';
      }

      return c['estado'] == estado;
    }).toList();
  }

  Color estadoColor(String estado) {
    switch (estado) {
      case 'CV_RECIBIDO':
        return const Color(0xFF2563EB);
      case 'CONTACTADO':
        return const Color(0xFFF97316);
      case 'ENTREVISTA_CONCERTADA':
        return const Color(0xFFEAB308);
      case 'ENTREVISTA_REALIZADA':
        return const Color(0xFF8B5CF6);
      case 'SELECCIONADO':
        return const Color(0xFF22C55E);
      case 'INCORPORADO':
        return const Color(0xFF14B8A6);
      case 'DESCARTADO':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String estadoTexto(String estado) {
    switch (estado) {
      case 'CV_RECIBIDO':
        return 'CV recibido';
      case 'CONTACTADO':
        return 'Contactado';
      case 'ENTREVISTA_CONCERTADA':
        return 'Entrevista concertada';
      case 'ENTREVISTA_REALIZADA':
        return 'Entrevista realizada';
      case 'SELECCIONADO':
        return 'Seleccionado';
      case 'INCORPORADO':
        return 'Incorporado';
      case 'DESCARTADO':
        return 'Descartado';
      default:
        return 'Sin estado';
    }
  }

  double progresoEstado(String estado) {
    final i = flujo.indexOf(estado);
    if (i == -1) return 0;
    return (i + 1) / flujo.length;
  }

  Future<void> avanzar(Map<String, dynamic> c) async {
    final actual = c['estado'];
    final i = flujo.indexOf(actual);

    if (i == -1 || i == flujo.length - 1) return;

    await supabase.from('candidatos_captacion').update({
      'estado': flujo[i + 1],
    }).eq('id', c['id']);

    cargarTodo();
  }

  Future<void> abrirNuevoCandidato() async {
    final r = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NuevoCandidatoScreen(),
      ),
    );

    if (r == true) cargarTodo();
  }

  Future<void> abrirDetalle(Map<String, dynamic> candidato) async {
    final r = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCandidatoScreen(
          candidato: candidato,
        ),
      ),
    );

    if (r == true) cargarTodo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 8,
        onPressed: abrirNuevoCandidato,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          "Nuevo candidato",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          const _TalentBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF111827),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF111827),
                    onRefresh: cargarTodo,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _topBar(),
                                const SizedBox(height: 24),
                                _heroTalent(),
                                const SizedBox(height: 20),
                                _searchBox(),
                                const SizedBox(height: 16),
                                _filters(),
                                if (puedeFiltrarEstructura) ...[
                                  const SizedBox(height: 16),
                                  _filtrosEstructura(),
                                ],
                                const SizedBox(height: 18),
                                _pipelineResumen(),
                                const SizedBox(height: 22),
                                _sectionTitle(),
                              ],
                            ),
                          ),
                        ),
                        if (candidatosFiltrados.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _emptyState(),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate(
                                [
                                  _grupoEstado(
                                    titulo: "CV recibidos",
                                    estado: "CV_RECIBIDO",
                                    icon: Icons.description_rounded,
                                  ),
                                  _grupoEstado(
                                    titulo: "Contactados",
                                    estado: "CONTACTADO",
                                    icon: Icons.phone_in_talk_rounded,
                                  ),
                                  _grupoEstado(
                                    titulo: "Entrevistas",
                                    estado: "ENTREVISTAS",
                                    icon: Icons.event_available_rounded,
                                  ),
                                  _grupoEstado(
                                    titulo: "Seleccionados",
                                    estado: "SELECCIONADO",
                                    icon: Icons.star_rounded,
                                  ),
                                  _grupoEstado(
                                    titulo: "Incorporados",
                                    estado: "INCORPORADO",
                                    icon: Icons.badge_rounded,
                                  ),
                                  _grupoEstado(
                                    titulo: "Descartados",
                                    estado: "DESCARTADO",
                                    icon: Icons.close_rounded,
                                  ),
                                ],
                              ),
                            ),
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
  return Row(
    children: [

      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context),
            child: Ink(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF111827),
                size: 18,
              ),
            ),
          ),
        ),
      ),

      const SizedBox(width: 14),

      const Expanded(
        child: Text(
          "Talent Hub",
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: cargarTodo,
            child: Ink(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

  Widget _heroTalent() {
    final incorporados = candidatosFiltrados
        .where((c) => c['estado'] == 'INCORPORADO')
        .length;

    final ratio = total == 0 ? 0.0 : incorporados / total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF111827),
            Color(0xFF2563EB),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -35,
            child: Icon(
              Icons.people_alt_rounded,
              size: 160,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "CAPTACIÓN DE TALENTO",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Gestiona candidatos como un portal profesional.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Pipeline completo para captar, contactar, entrevistar, seleccionar e incorporar comerciales.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _heroKpi("Total", total.toString()),
                  const SizedBox(width: 10),
                  _heroKpi("Proceso", enProceso.toString()),
                  const SizedBox(width: 10),
                  _heroKpi(
                    "Éxito",
                    "${(ratio * 100).toStringAsFixed(0)}%",
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroKpi(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: searchController,
        onChanged: (v) {
          setState(() => busqueda = v);
          calcularKPIs();
        },
        decoration: InputDecoration(
          icon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
          ),
          hintText: "Buscar por nombre, teléfono, email u origen...",
          hintStyle: TextStyle(
            color: Colors.black.withOpacity(0.38),
            fontSize: 13,
          ),
          border: InputBorder.none,
          suffixIcon: busqueda.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    searchController.clear();
                    setState(() => busqueda = '');
                    calcularKPIs();
                  },
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
        ),
      ),
    );
  }

  Widget _filters() {
    final filtros = [
      ['TODOS', 'Todos'],
      ['CV_RECIBIDO', 'CV'],
      ['CONTACTADO', 'Contactados'],
      ['ENTREVISTA_CONCERTADA', 'Entrevistas'],
      ['SELECCIONADO', 'Selección'],
      ['INCORPORADO', 'Incorporados'],
      ['DESCARTADO', 'Descartados'],
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filtros.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final id = filtros[i][0];
          final label = filtros[i][1];
          final selected = filtroActivo == id;
          final color = id == 'TODOS'
              ? const Color(0xFF111827)
              : estadoColor(id);

          return GestureDetector(
            onTap: () {
              setState(() => filtroActivo = id);
              calcularKPIs();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? color : Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected
                      ? color
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<String> get _figurasDisponibles {
    final figuras = usuariosEstructura
        .map((u) => _normalizarRol(u['rol_usuario']))
        .where((rol) => rol.isNotEmpty)
        .toSet()
        .toList();

    figuras.sort((a, b) => _nivelRol(b).compareTo(_nivelRol(a)));
    return figuras;
  }

  List<Map<String, dynamic>> get _usuariosParaSelector {
    final lista = usuariosEstructura.where((usuario) {
      if (figuraSeleccionada == null) return true;
      return _normalizarRol(usuario['rol_usuario']) ==
          figuraSeleccionada;
    }).toList();

    lista.sort(
      (a, b) => _nombreCompleto(a).compareTo(_nombreCompleto(b)),
    );

    return lista;
  }

  Future<void> _seleccionarFecha({required bool desde}) async {
    final inicial = desde
        ? (fechaDesde ?? DateTime.now())
        : (fechaHasta ?? DateTime.now());

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: desde ? 'Fecha desde' : 'Fecha hasta',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (seleccionada == null || !mounted) return;

    setState(() {
      if (desde) {
        fechaDesde = seleccionada;
        if (fechaHasta != null && fechaHasta!.isBefore(seleccionada)) {
          fechaHasta = seleccionada;
        }
      } else {
        fechaHasta = seleccionada;
        if (fechaDesde != null && fechaDesde!.isAfter(seleccionada)) {
          fechaDesde = seleccionada;
        }
      }
    });

    calcularKPIs();
  }

  String _fechaVisible(DateTime? fecha, String placeholder) {
    if (fecha == null) return placeholder;
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  void _limpiarFiltrosEstructura() {
    setState(() {
      figuraSeleccionada = null;
      authIdSeleccionado = null;
      fechaDesde = null;
      fechaHasta = null;
    });
    calcularKPIs();
  }

  Widget _filtrosEstructura() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.filter_alt_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtros de estructura',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Figura, responsable y periodo',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _limpiarFiltrosEstructura,
                child: const Text(
                  'Limpiar',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            value: figuraSeleccionada,
            isExpanded: true,
            decoration: _decoracionFiltro(
              'Figura',
              Icons.badge_outlined,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Todas las figuras'),
              ),
              ..._figurasDisponibles.map(
                (rol) => DropdownMenuItem<String?>(
                  value: rol,
                  child: Text(_rolVisible(rol)),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                figuraSeleccionada = value;
                authIdSeleccionado = null;
              });
              calcularKPIs();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _usuariosParaSelector.any(
              (u) => u['auth_id'] == authIdSeleccionado,
            )
                ? authIdSeleccionado
                : null,
            isExpanded: true,
            decoration: _decoracionFiltro(
              'Persona o estructura',
              Icons.account_tree_outlined,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Toda mi estructura'),
              ),
              ..._usuariosParaSelector.map(
                (usuario) => DropdownMenuItem<String?>(
                  value: usuario['auth_id']?.toString(),
                  child: Text(
                    '${_nombreCompleto(usuario)} · '
                    '${_rolVisible(usuario['rol_usuario']?.toString() ?? '')}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => authIdSeleccionado = value);
              calcularKPIs();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _botonFecha(
                  titulo: _fechaVisible(fechaDesde, 'Desde'),
                  icono: Icons.calendar_today_outlined,
                  onTap: () => _seleccionarFecha(desde: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _botonFecha(
                  titulo: _fechaVisible(fechaHasta, 'Hasta'),
                  icono: Icons.event_available_outlined,
                  onTap: () => _seleccionarFecha(desde: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoracionFiltro(
    String label,
    IconData icono,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, color: const Color(0xFF2563EB)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.black.withOpacity(0.07),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF2563EB),
        ),
      ),
    );
  }

  Widget _botonFecha({
    required String titulo,
    required IconData icono,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.black.withOpacity(0.07),
            ),
          ),
          child: Row(
            children: [
              Icon(icono, color: const Color(0xFF2563EB), size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pipelineResumen() {
    final items = [
      ['CV', candidatosPorEstado('CV_RECIBIDO').length, const Color(0xFF2563EB)],
      ['Contacto', candidatosPorEstado('CONTACTADO').length, const Color(0xFFF97316)],
      ['Entrev.', candidatosPorEstado('ENTREVISTAS').length, const Color(0xFFEAB308)],
      ['Selec.', candidatosPorEstado('SELECCIONADO').length, const Color(0xFF22C55E)],
      ['Incorp.', candidatosPorEstado('INCORPORADO').length, const Color(0xFF14B8A6)],
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: items.map((item) {
          final label = item[0] as String;
          final value = item[1] as int;
          final color = item[2] as Color;

          return Expanded(
            child: Column(
              children: [
                Container(
                  height: 8,
                  width: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value.toString(),
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.45),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            "Pipeline de candidatos",
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          "${candidatosFiltrados.length} visibles",
          style: TextStyle(
            color: Colors.black.withOpacity(0.45),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _grupoEstado({
    required String titulo,
    required String estado,
    required IconData icon,
  }) {
    final lista = candidatosPorEstado(estado);
    final color = estado == 'ENTREVISTAS'
        ? const Color(0xFFEAB308)
        : estadoColor(estado);

    if (lista.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: const Color(0xFF111827),
          collapsedIconColor: const Color(0xFF111827),
          title: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  "${lista.length}",
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          children: lista.map(_candidateCard).toList(),
        ),
      ),
    );
  }

  Widget _candidateCard(Map<String, dynamic> c) {
  final estado = c['estado']?.toString() ?? '';
  final color = estadoColor(estado);
  final nombre = c['nombre']?.toString() ?? 'Candidato sin nombre';
  final telefono = c['telefono']?.toString() ?? 'Sin teléfono';
  final email = c['email']?.toString() ?? '';
  final origen = c['origen']?.toString() ?? 'Sin origen';
  final progreso = progresoEstado(estado);
  final puedeAvanzar = flujo.contains(estado) && estado != 'INCORPORADO';
  final responsableNombre =
      c['asignado_nombre']?.toString().trim() ?? '';
  final responsableRol =
      c['asignado_rol']?.toString().trim() ?? '';

  return _HoverCandidateCard(
    color: color,
    onTap: () => abrirDetalle(c),
    child: Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color,
                      color.withOpacity(0.65),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    nombre.trim().isNotEmpty
                        ? nombre.trim()[0].toUpperCase()
                        : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_rounded,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            telefono,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.50),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.mail_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.38),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (responsableNombre.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.assignment_ind_rounded,
                            size: 13,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              responsableRol.isEmpty
                                  ? responsableNombre
                                  : '$responsableNombre · '
                                      '${_rolVisible(responsableRol)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withOpacity(0.05),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 9,
                    backgroundColor: Colors.black.withOpacity(0.06),
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "${(progreso * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              _miniChip(estadoTexto(estado), color),
              const SizedBox(width: 8),
              _miniChip(origen, const Color(0xFF64748B)),
              const Spacer(),
              if (puedeAvanzar)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      splashColor: Colors.white.withOpacity(0.20),
                      highlightColor: Colors.white.withOpacity(0.08),
                      onTap: () => avanzar(c),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.16),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Avanzar",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _miniChip(String text, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.11),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 92,
            width: 92,
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_search_rounded,
              color: Color(0xFF111827),
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "No hay candidatos visibles",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Cambia el filtro, borra la búsqueda o añade un nuevo candidato al proceso.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withOpacity(0.48),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: abrirNuevoCandidato,
            icon: const Icon(Icons.add_rounded),
            label: const Text("Añadir candidato"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverCandidateCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color color;

  const _HoverCandidateCard({
    required this.child,
    required this.onTap,
    required this.color,
  });

  @override
  State<_HoverCandidateCard> createState() => _HoverCandidateCardState();
}

class _HoverCandidateCardState extends State<_HoverCandidateCard> {
  bool hovering = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = pressing
        ? 0.985
        : hovering
            ? 1.018
            : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) {
        setState(() {
          hovering = false;
          pressing = false;
        });
      },
      child: Listener(
        onPointerDown: (_) => setState(() => pressing = true),
        onPointerUp: (_) => setState(() => pressing = false),
        onPointerCancel: (_) => setState(() => pressing = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: hovering
                      ? widget.color.withOpacity(0.24)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: hovering ? 28 : 14,
                  offset: Offset(0, hovering ? 16 : 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                splashColor: widget.color.withOpacity(0.14),
                highlightColor: widget.color.withOpacity(0.06),
                hoverColor: widget.color.withOpacity(0.03),
                mouseCursor: SystemMouseCursors.click,
                onTap: widget.onTap,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TalentBackground extends StatelessWidget {
  const _TalentBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: _bubble(const Color(0xFF00C2FF), 250),
        ),
        Positioned(
          top: 260,
          left: -150,
          child: _bubble(const Color(0xFF8B5CF6), 280),
        ),
        Positioned(
          bottom: -150,
          right: -90,
          child: _bubble(const Color(0xFF22C55E), 260),
        ),
      ],
    );
  }

  Widget _bubble(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.13),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}