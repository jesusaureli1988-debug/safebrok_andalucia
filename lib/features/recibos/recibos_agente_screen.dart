import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class RecibosAgenteScreen extends StatefulWidget {
  const RecibosAgenteScreen({super.key});

  @override
  State<RecibosAgenteScreen> createState() => _RecibosAgenteScreenState();
}

class _RecibosAgenteScreenState extends State<RecibosAgenteScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool loading = true;
  String filtro = 'Todos';
  String searchText = '';

  List<Map<String, dynamic>> recibos = [];

  // Filtros avanzados. Solo contienen usuarios pertenecientes al alcance
  // real del usuario conectado.
  List<Map<String, dynamic>> usuariosEstructura = [];
  String filtroFigura = 'Todas';
  String filtroUsuarioAuthId = 'Todos';
  DateTime? fechaDesde;
  DateTime? fechaHasta;
  bool mostrarFiltrosAvanzados = false;

  @override
  void initState() {
    super.initState();
    cargarRecibos();
  }

  String _normalizarTexto(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
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

  Future<List<String>> _obtenerAuthIdsEstructura(
    String authIdLogueado,
  ) async {
    final usuariosData = await supabase.from('usuarios').select(
          'id, auth_id, parent_id, rol_usuario, nombre, apellidos',
        );

    final todosUsuarios =
        List<Map<String, dynamic>>.from(usuariosData).map((u) {
      return <String, dynamic>{
        'id': u['id']?.toString().trim() ?? '',
        'auth_id': u['auth_id']?.toString().trim() ?? '',
        'parent_id': u['parent_id']?.toString().trim() ?? '',
        'rol': _normalizarRol(u['rol_usuario']),
        'nombre': u['nombre']?.toString().trim() ?? '',
        'apellidos': u['apellidos']?.toString().trim() ?? '',
      };
    }).toList();

    final yo = todosUsuarios.firstWhere(
      (u) => u['auth_id'] == authIdLogueado,
      orElse: () => <String, dynamic>{},
    );

    if (yo.isEmpty) {
      debugPrint('RECIBOS: no se encontró el usuario conectado.');
      usuariosEstructura = <Map<String, dynamic>>[];
      return <String>[authIdLogueado];
    }

    final rolLogueado = _normalizarRol(yo['rol']);

    // Director nacional y administración pueden trabajar sobre toda la red.
    if (rolLogueado == 'director_nacional' ||
        rolLogueado == 'administracion' ||
        rolLogueado == 'administrador' ||
        rolLogueado == 'admin') {
      usuariosEstructura = todosUsuarios
          .where((u) {
            final authId = u['auth_id']?.toString().trim() ?? '';
            return authId.isNotEmpty && authId.toLowerCase() != 'null';
          })
          .toList()
        ..sort(_ordenarUsuarios);

      return usuariosEstructura
          .map((u) => u['auth_id'].toString())
          .toSet()
          .toList();
    }

    final hijosPorParentId = <String, List<Map<String, dynamic>>>{};

    for (final usuario in todosUsuarios) {
      final parentId = usuario['parent_id']?.toString().trim() ?? '';

      if (parentId.isEmpty || parentId.toLowerCase() == 'null') {
        continue;
      }

      hijosPorParentId
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }

    final usuariosPermitidos = <Map<String, dynamic>>[];
    final idsVisitados = <String>{};

    void recorrerEstructura(Map<String, dynamic> usuarioActual) {
      final id = usuarioActual['id']?.toString().trim() ?? '';
      final authId = usuarioActual['auth_id']?.toString().trim() ?? '';
      final rolActual = _normalizarRol(usuarioActual['rol']);

      if (id.isEmpty || idsVisitados.contains(id)) return;

      idsVisitados.add(id);

      if (authId.isNotEmpty && authId.toLowerCase() != 'null') {
        usuariosPermitidos.add(usuarioActual);
      }

      final nivelActual = _nivelRol(rolActual);
      final hijos =
          hijosPorParentId[id] ?? <Map<String, dynamic>>[];

      for (final hijo in hijos) {
        final nivelHijo = _nivelRol(_normalizarRol(hijo['rol']));

        // Respeta la dependencia real por parent_id y evita subir de nivel.
        if (nivelHijo <= 0 || nivelHijo >= nivelActual) {
          continue;
        }

        recorrerEstructura(hijo);
      }
    }

    recorrerEstructura(yo);

    usuariosEstructura = usuariosPermitidos
      ..sort(_ordenarUsuarios);

    final resultado = usuariosEstructura
        .map((u) => u['auth_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty && id.toLowerCase() != 'null')
        .toSet()
        .toList();

    if (!resultado.contains(authIdLogueado)) {
      resultado.add(authIdLogueado);
    }

    debugPrint('======= ESTRUCTURA RECIBOS =======');
    debugPrint('USUARIO: ${yo['nombre']} ${yo['apellidos']}');
    debugPrint('ROL: $rolLogueado');
    debugPrint('TOTAL PERSONAS: ${resultado.length}');
    debugPrint('==================================');

    return resultado;
  }

  int _ordenarUsuarios(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final nivelA = _nivelRol(a['rol']?.toString() ?? '');
    final nivelB = _nivelRol(b['rol']?.toString() ?? '');

    if (nivelA != nivelB) {
      return nivelB.compareTo(nivelA);
    }

    return _nombreCompletoUsuario(a)
        .toLowerCase()
        .compareTo(_nombreCompletoUsuario(b).toLowerCase());
  }

  String _nombreCompletoUsuario(Map<String, dynamic> usuario) {
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
      case 'administracion':
      case 'administrador':
      case 'admin':
        return 'Administración';
      default:
        return rol
            .replaceAll('_', ' ')
            .trim();
    }
  }

  List<String> get _figurasDisponibles {
    final roles = usuariosEstructura
        .map((u) => _normalizarRol(u['rol']))
        .where((rol) => rol.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => _nivelRol(b).compareTo(_nivelRol(a)));

    return <String>['Todas', ...roles];
  }

  List<Map<String, dynamic>> get _usuariosParaSelector {
    if (filtroFigura == 'Todas') {
      return List<Map<String, dynamic>>.from(usuariosEstructura);
    }

    return usuariosEstructura
        .where(
          (u) => _normalizarRol(u['rol']) == filtroFigura,
        )
        .toList();
  }

  Set<String> _authIdsDeEstructuraSeleccionada(String authId) {
    final seleccionado = usuariosEstructura.firstWhere(
      (u) => u['auth_id']?.toString() == authId,
      orElse: () => <String, dynamic>{},
    );

    if (seleccionado.isEmpty) return <String>{authId};

    final hijosPorParentId = <String, List<Map<String, dynamic>>>{};

    for (final usuario in usuariosEstructura) {
      final parentId = usuario['parent_id']?.toString().trim() ?? '';
      if (parentId.isEmpty || parentId.toLowerCase() == 'null') continue;

      hijosPorParentId
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }

    final resultado = <String>{};
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> usuario) {
      final id = usuario['id']?.toString().trim() ?? '';
      final auth = usuario['auth_id']?.toString().trim() ?? '';

      if (id.isEmpty || visitados.contains(id)) return;
      visitados.add(id);

      if (auth.isNotEmpty && auth.toLowerCase() != 'null') {
        resultado.add(auth);
      }

      for (final hijo
          in hijosPorParentId[id] ?? <Map<String, dynamic>>[]) {
        recorrer(hijo);
      }
    }

    recorrer(seleccionado);
    return resultado;
  }

  Future<void> cargarRecibos() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        recibos = [];
        loading = false;
      });
      return;
    }

    try {
      if (mounted) {
        setState(() => loading = true);
      }

      final authIdsEstructura =
          await _obtenerAuthIdsEstructura(user.id);

      if (authIdsEstructura.isEmpty) {
        if (!mounted) return;
        setState(() {
          recibos = [];
          loading = false;
        });
        return;
      }

      final data = await supabase
          .from('recibos')
          .select()
          .inFilter('agente', authIdsEstructura)
          .order('fecha', ascending: false);

      if (!mounted) return;

      setState(() {
        recibos = List<Map<String, dynamic>>.from(data);
        loading = false;
      });

      debugPrint('RECIBOS CARGADOS: ${recibos.length}');
      debugPrint('USUARIOS INCLUIDOS: ${authIdsEstructura.length}');
    } catch (e, stackTrace) {
      debugPrint('ERROR CARGANDO RECIBOS: $e');
      debugPrint('STACK RECIBOS: $stackTrace');

      if (!mounted) return;

      setState(() {
        recibos = [];
        loading = false;
      });

      _snack(
        'Error cargando recibos: $e',
        color: Colors.redAccent,
      );
    }
  }

  List<Map<String, dynamic>> get recibosConFiltrosAvanzados {
    Set<String>? authIdsPermitidos;

    if (filtroUsuarioAuthId != 'Todos') {
      authIdsPermitidos =
          _authIdsDeEstructuraSeleccionada(filtroUsuarioAuthId);
    } else if (filtroFigura != 'Todas') {
      authIdsPermitidos = usuariosEstructura
          .where(
            (u) => _normalizarRol(u['rol']) == filtroFigura,
          )
          .map((u) => u['auth_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    }

    return recibos.where((r) {
      final agente = r['agente']?.toString().trim() ?? '';

      final matchEstructura = authIdsPermitidos == null ||
          authIdsPermitidos.contains(agente);

      final fechaRecibo = _parseFechaRecibo(r['fecha']);

      final matchDesde = fechaDesde == null ||
          (fechaRecibo != null &&
              !fechaRecibo.isBefore(
                DateTime(
                  fechaDesde!.year,
                  fechaDesde!.month,
                  fechaDesde!.day,
                ),
              ));

      final limiteHasta = fechaHasta == null
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

      final matchHasta = limiteHasta == null ||
          (fechaRecibo != null &&
              !fechaRecibo.isAfter(limiteHasta));

      return matchEstructura && matchDesde && matchHasta;
    }).toList();
  }

  List<Map<String, dynamic>> get recibosFiltrados {
    final search = searchText.trim().toLowerCase();

    return recibosConFiltrosAvanzados.where((r) {
      final estado = _normalizarTexto(r['estado']);
      final poliza = _normalizarTexto(r['poliza']);
      final cliente = _normalizarTexto(r['cliente']);
      final compania = _normalizarTexto(r['compania']);
      final motivo = _normalizarTexto(r['motivo']);

      final matchSearch = search.isEmpty ||
          poliza.contains(search) ||
          cliente.contains(search) ||
          compania.contains(search) ||
          motivo.contains(search);

      bool matchFiltro;

      switch (filtro) {
        case 'Pendientes':
          matchFiltro = estado == 'pendiente' ||
              estado == 'devuelto' ||
              estado == 'impagado' ||
              estado == 'en gestión' ||
              estado == 'en gestion';
          break;
        case 'Cobrados':
          matchFiltro = estado == 'pagado' || estado == 'cobrado';
          break;
        case 'Para baja':
          matchFiltro = estado == 'para baja' ||
              estado == 'para_baja' ||
              estado == 'baja';
          break;
        default:
          matchFiltro = true;
      }

      return matchSearch && matchFiltro;
    }).toList();
  }

  DateTime? _parseFechaRecibo(dynamic value) {
    if (value == null) return null;

    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value.toString().replaceAll(',', '.'),
        ) ??
        0;
  }

  bool _esPendiente(Map<String, dynamic> r) {
    final estado = _normalizarTexto(r['estado']);

    return estado == 'pendiente' ||
        estado == 'devuelto' ||
        estado == 'impagado' ||
        estado == 'en gestión' ||
        estado == 'en gestion';
  }

  bool _esCobrado(Map<String, dynamic> r) {
    final estado = _normalizarTexto(r['estado']);
    return estado == 'pagado' || estado == 'cobrado';
  }

  bool _esParaBaja(Map<String, dynamic> r) {
    final estado = _normalizarTexto(r['estado']);
    return estado == 'para baja' ||
        estado == 'para_baja' ||
        estado == 'baja';
  }

  double get totalPendiente {
    return recibosConFiltrosAvanzados
        .where(_esPendiente)
        .fold(0.0, (sum, r) => sum + _money(r['importe']));
  }

  int get pendientes =>
      recibosConFiltrosAvanzados.where(_esPendiente).length;

  int get cobrados =>
      recibosConFiltrosAvanzados.where(_esCobrado).length;

  int get paraBaja =>
      recibosConFiltrosAvanzados.where(_esParaBaja).length;

  String _formatFecha(dynamic fecha) {
    if (fecha == null) return 'Sin fecha';

    try {
      final dt = DateTime.parse(fecha.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return fecha.toString();
    }
  }

  Color _estadoColor(String estado) {
    final e = _normalizarTexto(estado);

    if (e == 'pagado' || e == 'cobrado') {
      return const Color(0xFF4ADE80);
    }
    if (e == 'pendiente') {
      return const Color(0xFFFBBF24);
    }
    if (e == 'devuelto' || e == 'impagado') {
      return const Color(0xFFFB7185);
    }
    if (e == 'en gestión' || e == 'en gestion') {
      return const Color(0xFF22D3EE);
    }
    if (e == 'para baja' || e == 'para_baja' || e == 'baja') {
      return const Color(0xFFC084FC);
    }
    if (e == 'anulado') return Colors.white38;

    return Colors.white54;
  }

  IconData _estadoIcon(String estado) {
    final e = _normalizarTexto(estado);

    if (e == 'pagado' || e == 'cobrado') {
      return Icons.check_circle_rounded;
    }
    if (e == 'pendiente') return Icons.schedule_rounded;
    if (e == 'devuelto' || e == 'impagado') {
      return Icons.error_rounded;
    }
    if (e == 'en gestión' || e == 'en gestion') {
      return Icons.support_agent_rounded;
    }
    if (e == 'para baja' || e == 'para_baja' || e == 'baja') {
      return Icons.person_remove_rounded;
    }
    if (e == 'anulado') return Icons.block_rounded;

    return Icons.receipt_long_rounded;
  }

  String _estadoVisible(String estado) {
    final e = _normalizarTexto(estado);

    if (e == 'pagado' || e == 'cobrado') return 'Cobrado';
    if (e == 'para baja' || e == 'para_baja' || e == 'baja') {
      return 'Para baja';
    }
    if (e == 'en gestion') return 'En gestión';
    if (estado.trim().isEmpty) return 'Pendiente';

    return estado;
  }

  void _snack(
    String texto, {
    Color color = const Color(0xFF102331),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          texto,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050A11),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 6,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recibos',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
            Text(
              'Control y seguimiento de cobros',
              style: TextStyle(
                color: const Color(0x75FFFFFF),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargarRecibos,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF22D3EE),
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF102331),
              onRefresh: cargarRecibos,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _resumenPrincipal(),
                        const SizedBox(height: 14),
                        _kpis(),
                        const SizedBox(height: 16),
                        _buscador(),
                        const SizedBox(height: 12),
                        _filtrosAvanzados(),
                        const SizedBox(height: 12),
                        _filtros(),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'RECIBOS',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            Text(
                              '${recibosFiltrados.length} resultados',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ]),
                    ),
                  ),
                  if (recibosFiltrados.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                      sliver: SliverList.separated(
                        itemCount: recibosFiltrados.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          return _reciboCard(
                            recibosFiltrados[index],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _resumenPrincipal() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0C3B5B),
            Color(0xFF071A2B),
            Color(0xFF071019),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF22D3EE).withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Color(0xFF22D3EE),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Importe por gestionar',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${totalPendiente.toStringAsFixed(2)} €',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$pendientes recibos necesitan seguimiento',
                  style: const TextStyle(
                    color: Color(0xFF67E8F9),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis() {
    return Row(
      children: [
        Expanded(
          child: _kpiCompacto(
            titulo: 'Pendientes',
            valor: pendientes.toString(),
            icono: Icons.schedule_rounded,
            color: const Color(0xFFFBBF24),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _kpiCompacto(
            titulo: 'Cobrados',
            valor: cobrados.toString(),
            icono: Icons.check_circle_rounded,
            color: const Color(0xFF4ADE80),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _kpiCompacto(
            titulo: 'Para baja',
            valor: paraBaja.toString(),
            icono: Icons.person_remove_rounded,
            color: const Color(0xFFC084FC),
          ),
        ),
      ],
    );
  }

  Widget _kpiCompacto({
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
  }) {
    return Container(
      height: 94,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1620),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const Spacer(),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: const Color(0x75FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      onChanged: (v) => setState(() => searchText = v),
      decoration: InputDecoration(
        hintText: 'Buscar cliente, póliza o compañía',
        hintStyle: const TextStyle(
          color: Colors.white38,
          fontSize: 13,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF22D3EE),
        ),
        filled: true,
        fillColor: const Color(0xFF0B1620),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(19),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.07),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(19),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE),
          ),
        ),
      ),
    );
  }

  Widget _filtrosAvanzados() {
    final filtrosActivos = (filtroFigura != 'Todas' ? 1 : 0) +
        (filtroUsuarioAuthId != 'Todos' ? 1 : 0) +
        (fechaDesde != null ? 1 : 0) +
        (fechaHasta != null ? 1 : 0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1620),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: filtrosActivos > 0
              ? const Color(0xFF22D3EE).withOpacity(0.28)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              setState(() {
                mostrarFiltrosAvanzados = !mostrarFiltrosAvanzados;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22D3EE).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF22D3EE),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FILTROS AVANZADOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Figura, estructura y periodo',
                          style: TextStyle(
                            color: Color(0x75FFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (filtrosActivos > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$filtrosActivos',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  Icon(
                    mostrarFiltrosAvanzados
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: mostrarFiltrosAvanzados
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  Divider(
                    color: Colors.white.withOpacity(0.06),
                    height: 1,
                  ),
                  const SizedBox(height: 14),
                  _selectorFigura(),
                  const SizedBox(height: 10),
                  _selectorUsuarioEstructura(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _selectorFecha(
                          titulo: 'Desde',
                          fecha: fechaDesde,
                          onTap: () => _seleccionarFecha(true),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _selectorFecha(
                          titulo: 'Hasta',
                          fecha: fechaHasta,
                          onTap: () => _seleccionarFecha(false),
                        ),
                      ),
                    ],
                  ),
                  if (filtrosActivos > 0) ...[
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      height: 43,
                      child: OutlinedButton.icon(
                        onPressed: _limpiarFiltrosAvanzados,
                        icon: const Icon(
                          Icons.filter_alt_off_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'LIMPIAR FILTROS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF67E8F9),
                          side: BorderSide(
                            color: const Color(0xFF22D3EE)
                                .withOpacity(0.30),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorFigura() {
    return DropdownButtonFormField<String>(
      value: _figurasDisponibles.contains(filtroFigura)
          ? filtroFigura
          : 'Todas',
      dropdownColor: const Color(0xFF102331),
      iconEnabledColor: const Color(0xFF22D3EE),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      decoration: _decoracionFiltro(
        'Figura',
        Icons.badge_rounded,
      ),
      items: _figurasDisponibles.map((rol) {
        return DropdownMenuItem<String>(
          value: rol,
          child: Text(
            rol == 'Todas' ? 'Todas las figuras' : _rolVisible(rol),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          filtroFigura = value;
          filtroUsuarioAuthId = 'Todos';
        });
      },
    );
  }

  Widget _selectorUsuarioEstructura() {
    final usuarios = _usuariosParaSelector;
    final valorValido = filtroUsuarioAuthId == 'Todos' ||
        usuarios.any(
          (u) => u['auth_id']?.toString() == filtroUsuarioAuthId,
        );

    return DropdownButtonFormField<String>(
      value: valorValido ? filtroUsuarioAuthId : 'Todos',
      isExpanded: true,
      dropdownColor: const Color(0xFF102331),
      iconEnabledColor: const Color(0xFF22D3EE),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      decoration: _decoracionFiltro(
        'Persona o estructura',
        Icons.account_tree_rounded,
      ),
      items: [
        const DropdownMenuItem<String>(
          value: 'Todos',
          child: Text('Toda mi estructura'),
        ),
        ...usuarios.map((usuario) {
          final authId = usuario['auth_id']?.toString() ?? '';

          return DropdownMenuItem<String>(
            value: authId,
            child: Text(
              '${_nombreCompletoUsuario(usuario)} · '
              '${_rolVisible(usuario['rol']?.toString() ?? '')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => filtroUsuarioAuthId = value);
      },
    );
  }

  InputDecoration _decoracionFiltro(
    String label,
    IconData icono,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(
        icono,
        color: const Color(0xFF22D3EE),
        size: 20,
      ),
      filled: true,
      fillColor: Colors.black.withOpacity(0.16),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: Color(0xFF22D3EE),
        ),
      ),
    );
  }

  Widget _selectorFecha({
    required String titulo,
    required DateTime? fecha,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: fecha != null
                ? const Color(0xFF22D3EE).withOpacity(0.35)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF22D3EE),
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fecha == null
                        ? 'Sin fecha'
                        : _formatFechaCorta(fecha),
                    style: TextStyle(
                      color:
                          fecha == null ? Colors.white60 : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (fecha != null)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (titulo == 'Desde') {
                      fechaDesde = null;
                    } else {
                      fechaHasta = null;
                    }
                  });
                },
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white38,
                  size: 17,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha(bool esDesde) async {
    final inicial = esDesde
        ? (fechaDesde ?? DateTime.now())
        : (fechaHasta ?? fechaDesde ?? DateTime.now());

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: esDesde ? 'SELECCIONAR FECHA DESDE' : 'SELECCIONAR FECHA HASTA',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              onPrimary: Colors.black,
              surface: Color(0xFF0B1620),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0B1620),
          ),
          child: child!,
        );
      },
    );

    if (seleccionada == null || !mounted) return;

    if (esDesde &&
        fechaHasta != null &&
        seleccionada.isAfter(fechaHasta!)) {
      _snack(
        'La fecha desde no puede ser posterior a la fecha hasta.',
        color: const Color(0xFFF59E0B),
      );
      return;
    }

    if (!esDesde &&
        fechaDesde != null &&
        seleccionada.isBefore(fechaDesde!)) {
      _snack(
        'La fecha hasta no puede ser anterior a la fecha desde.',
        color: const Color(0xFFF59E0B),
      );
      return;
    }

    setState(() {
      if (esDesde) {
        fechaDesde = seleccionada;
      } else {
        fechaHasta = seleccionada;
      }
    });
  }

  String _formatFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  void _limpiarFiltrosAvanzados() {
    setState(() {
      filtroFigura = 'Todas';
      filtroUsuarioAuthId = 'Todos';
      fechaDesde = null;
      fechaHasta = null;
    });
  }

  Widget _filtros() {
    const filtros = [
      'Todos',
      'Pendientes',
      'Cobrados',
      'Para baja',
    ];

    return SizedBox(
      height: 41,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filtros.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = filtros[index];
          final selected = filtro == item;

          return InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => setState(() => filtro = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF22D3EE)
                    : const Color(0xFF0B1620),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF22D3EE)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Text(
                item,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _reciboCard(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? 'Pendiente').toString();
    final color = _estadoColor(estado);
    final importe = _money(r['importe']);
    final poliza = (r['poliza'] ?? 'Sin póliza').toString();
    final cliente = (r['cliente'] ?? 'Sin cliente').toString();
    final compania = (r['compania'] ?? 'Sin compañía').toString();
    final motivo = (r['motivo'] ?? '').toString();
    final fecha = _formatFecha(r['fecha']);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        borderRadius: BorderRadius.circular(23),
        onTap: () async {
          final actualizado = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => ReciboDetalleScreen(recibo: r),
            ),
          );

          if (actualizado == true || mounted) {
            await cargarRecibos();
          }
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1620),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(
              color: color.withOpacity(0.20),
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 45,
                    width: 45,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      _estadoIcon(estado),
                      color: color,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$compania · $poliza',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: const Color(0x75FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${importe.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _estadoChip(estado),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: Colors.white.withOpacity(0.35),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fecha,
                    style: const TextStyle(
                      color: const Color(0x75FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Abrir gestión',
                    style: TextStyle(
                      color: Color(0xFF67E8F9),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF67E8F9),
                    size: 16,
                  ),
                ],
              ),
              if (motivo.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFB7185).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    motivo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoChip(String estado) {
    final color = _estadoColor(estado);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _estadoVisible(estado),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 50, 30, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 40,
                color: Colors.white.withOpacity(0.20),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No hay recibos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'No existen recibos que coincidan con esta búsqueda o filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0x75FFFFFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReciboDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> recibo;

  const ReciboDetalleScreen({
    super.key,
    required this.recibo,
  });

  @override
  State<ReciboDetalleScreen> createState() =>
      _ReciboDetalleScreenState();
}

class _ReciboDetalleScreenState extends State<ReciboDetalleScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool loading = true;
  bool guardandoGestion = false;
  bool enviandoTpv = false;
  bool huboCambios = false;

  late Map<String, dynamic> reciboActual;

  List<Map<String, dynamic>> comentarios = [];
  List<Map<String, dynamic>> pagos = [];

  final TextEditingController comentarioController =
      TextEditingController();

  String? resultadoGestion;

  @override
  void initState() {
    super.initState();
    reciboActual = Map<String, dynamic>.from(widget.recibo);
    cargarDetalle();
  }

  @override
  void dispose() {
    comentarioController.dispose();
    super.dispose();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value.toString().replaceAll(',', '.'),
        ) ??
        0;
  }

  String _normalizar(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  String _formatFecha(dynamic fecha) {
    if (fecha == null) return 'Sin fecha';

    try {
      final dt = DateTime.parse(fecha.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} · '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha.toString();
    }
  }

  Color _estadoColor(String estado) {
    final e = _normalizar(estado);

    if (e == 'pagado' || e == 'cobrado') {
      return const Color(0xFF4ADE80);
    }
    if (e == 'pendiente') return const Color(0xFFFBBF24);
    if (e == 'devuelto' || e == 'impagado') {
      return const Color(0xFFFB7185);
    }
    if (e == 'en gestión' || e == 'en gestion') {
      return const Color(0xFF22D3EE);
    }
    if (e == 'para baja' || e == 'para_baja' || e == 'baja') {
      return const Color(0xFFC084FC);
    }

    return Colors.white54;
  }

  String _estadoVisible(String estado) {
    final e = _normalizar(estado);

    if (e == 'pagado' || e == 'cobrado') return 'Cobrado';
    if (e == 'para baja' || e == 'para_baja' || e == 'baja') {
      return 'Para baja';
    }
    if (e == 'en gestion') return 'En gestión';
    if (estado.trim().isEmpty) return 'Pendiente';

    return estado;
  }

  bool get accionesPermitidas {
    final estado = _normalizar(reciboActual['estado']);

    return estado == 'devuelto' ||
        estado == 'impagado' ||
        estado == 'pendiente' ||
        estado == 'en gestión' ||
        estado == 'en gestion';
  }

  Future<void> cargarDetalle() async {
    final poliza = reciboActual['poliza'];

    try {
      final resultados = await Future.wait([
        supabase
            .from('recibos_comentarios')
            .select()
            .eq('poliza', poliza)
            .order('created_at', ascending: false),
        supabase
            .from('recibos_pagos')
            .select()
            .eq('poliza', poliza)
            .order('created_at', ascending: false),
      ]);

      if (!mounted) return;

      setState(() {
        comentarios =
            List<Map<String, dynamic>>.from(resultados[0]);
        pagos = List<Map<String, dynamic>>.from(resultados[1]);
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR DETALLE RECIBO: $e');

      if (!mounted) return;

      setState(() => loading = false);
      _snack('No se pudo cargar el histórico.');
    }
  }

  Future<void> guardarGestion() async {
    final comentario = comentarioController.text.trim();

    if (comentario.isEmpty) {
      _snack(
        'Escribe primero el resultado de la gestión.',
        color: const Color(0xFFF59E0B),
      );
      return;
    }

    if (resultadoGestion == null) {
      _snack(
        'Selecciona: Cobrado, Pendiente o Para baja.',
        color: const Color(0xFFF59E0B),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    final poliza = reciboActual['poliza'];
    final nuevoEstado = resultadoGestion!;
    final usuario =
        user?.email ?? user?.id ?? 'Usuario';

    setState(() => guardandoGestion = true);

    try {
      await supabase.from('recibos_comentarios').insert({
        'poliza': poliza,
        'comentario':
            '[$nuevoEstado] $comentario',
        'usuario': usuario,
      });

      await supabase
          .from('recibos')
          .update({'estado': nuevoEstado})
          .eq('poliza', poliza);

      if (!mounted) return;

      setState(() {
        reciboActual['estado'] = nuevoEstado;
        comentarioController.clear();
        resultadoGestion = null;
        guardandoGestion = false;
        huboCambios = true;
      });

      await cargarDetalle();

      _snack(
        'Gestión guardada y recibo actualizado.',
        color: const Color(0xFF15803D),
      );
    } catch (e) {
      debugPrint('ERROR GUARDANDO GESTIÓN: $e');

      if (!mounted) return;

      setState(() => guardandoGestion = false);

      _snack(
        'No se pudo guardar la gestión: $e',
        color: const Color(0xFFBE123C),
      );
    }
  }

  Future<void> abrirModalEnviarTpv() async {
    if (!accionesPermitidas) {
      _accionNoPermitida();
      return;
    }

    final emailController = TextEditingController();

    final cliente =
        reciboActual['cliente']?.toString() ?? '';
    final poliza =
        reciboActual['poliza']?.toString() ?? '';
    final compania =
        reciboActual['compania']?.toString() ?? '';
    final importe = _money(reciboActual['importe']);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1722),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 14,
            bottom:
                MediaQuery.of(modalContext).viewInsets.bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Enviar enlace de pago',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'El envío quedará registrado automáticamente en el histórico.',
                  style: TextStyle(
                    color: const Color(0x75FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _modalInfo('Cliente', cliente),
                _modalInfo('Póliza', poliza),
                _modalInfo('Compañía', compania),
                _modalInfo(
                  'Importe',
                  '${importe.toStringAsFixed(2)} €',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration:
                      _inputDecoration('Email destinatario'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final email =
                          emailController.text.trim();

                      Navigator.pop(modalContext);
                      enviarEmailTpv(email);
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text(
                      'ENVIAR ENLACE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF22D3EE),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    emailController.dispose();
  }

  Future<void> enviarEmailTpv(String emailDestino) async {
    if (emailDestino.isEmpty ||
        !emailDestino.contains('@')) {
      _snack('Introduce un email válido.');
      return;
    }

    if (!accionesPermitidas) {
      _accionNoPermitida();
      return;
    }

    const url =
        'https://www.fiatc.es/atencion-cliente/pago-recibos';

    final poliza =
        reciboActual['poliza']?.toString() ?? '';
    final cliente =
        reciboActual['cliente']?.toString() ?? '';
    final importe = _money(reciboActual['importe']);

    setState(() => enviandoTpv = true);

    try {
      final response = await supabase.functions.invoke(
        'enviar-tpv-recibo',
        body: {
          'email': emailDestino,
          'cliente': cliente,
          'poliza': poliza,
          'importe': importe,
          'url': url,
        },
      );

      if (response.status != 200) {
        throw Exception(response.data);
      }

      await supabase.from('recibos_comentarios').insert({
        'poliza': poliza,
        'comentario':
            '[En gestión] Enlace TPV enviado a $emailDestino',
        'usuario': supabase.auth.currentUser?.email ??
            supabase.auth.currentUser?.id ??
            'Usuario',
      });

      await supabase
          .from('recibos')
          .update({'estado': 'En gestión'})
          .eq('poliza', poliza);

      if (!mounted) return;

      setState(() {
        reciboActual['estado'] = 'En gestión';
        enviandoTpv = false;
        huboCambios = true;
      });

      await cargarDetalle();

      _snack(
        'Email enviado correctamente.',
        color: const Color(0xFF15803D),
      );
    } catch (e) {
      debugPrint('ERROR ENVIANDO EMAIL TPV: $e');

      if (!mounted) return;

      setState(() => enviandoTpv = false);

      _snack(
        'No se pudo enviar el email.',
        color: const Color(0xFFBE123C),
      );
    }
  }

  Future<void> abrirTpvEnNavegador() async {
    final uri = Uri.parse(
      'https://www.fiatc.es/atencion-cliente/pago-recibos',
    );

    try {
      final abierto = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!abierto) {
        _snack('No se pudo abrir el enlace de pago.');
      }
    } catch (e) {
      _snack('No se pudo abrir el enlace de pago.');
    }
  }

  void _accionNoPermitida() {
    _snack(
      'Este recibo ya está cerrado y no admite nuevas acciones de cobro.',
    );
  }

  void _snack(
    String texto, {
    Color color = const Color(0xFF102331),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        content: Text(
          texto,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    Navigator.pop(context, huboCambios);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final estado =
        (reciboActual['estado'] ?? 'Pendiente').toString();
    final color = _estadoColor(estado);
    final importe = _money(reciboActual['importe']);
    final poliza =
        (reciboActual['poliza'] ?? '').toString();
    final cliente =
        (reciboActual['cliente'] ?? 'Sin cliente').toString();
    final compania =
        (reciboActual['compania'] ?? 'Sin compañía').toString();
    final motivo =
        (reciboActual['motivo'] ?? '').toString();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF050A11),
        appBar: AppBar(
          backgroundColor: const Color(0xFF050A11),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () =>
                Navigator.pop(context, huboCambios),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
          title: const Text(
            'Gestión del recibo',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF22D3EE),
                ),
              )
            : ListView(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  _cabeceraDetalle(
                    cliente: cliente,
                    poliza: poliza,
                    compania: compania,
                    importe: importe,
                    estado: estado,
                    color: color,
                    motivo: motivo,
                  ),
                  const SizedBox(height: 16),
                  _panelGestion(),
                  const SizedBox(height: 16),
                  _accionesCobro(),
                  const SizedBox(height: 16),
                  _historico(),
                ],
              ),
      ),
    );
  }

  Widget _cabeceraDetalle({
    required String cliente,
    required String poliza,
    required String compania,
    required double importe,
    required String estado,
    required Color color,
    required String motivo,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.18),
            const Color(0xFF0B1620),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  cliente,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _chipEstado(estado),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$compania · Póliza $poliza',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${importe.toStringAsFixed(2)} €',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
            ),
          ),
          if (motivo.trim().isNotEmpty) ...[
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFB7185).withOpacity(0.08),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color:
                      const Color(0xFFFB7185).withOpacity(0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFFB7185),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      motivo,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panelGestion() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1620),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: Color(0xFF22D3EE),
                size: 23,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'NUEVA GESTIÓN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Describe qué has hecho y selecciona el resultado. Ambos campos son obligatorios.',
            style: TextStyle(
              color: const Color(0x75FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: comentarioController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(
              'Ejemplo: He hablado con el cliente y...',
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'RESULTADO DE LA GESTIÓN',
            style: TextStyle(
              color: const Color(0x75FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _resultadoButton(
                  valor: 'Pagado',
                  titulo: 'Cobrado',
                  icono: Icons.check_circle_rounded,
                  color: const Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _resultadoButton(
                  valor: 'Pendiente',
                  titulo: 'Pendiente',
                  icono: Icons.schedule_rounded,
                  color: const Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _resultadoButton(
                  valor: 'Para baja',
                  titulo: 'Para baja',
                  icono: Icons.person_remove_rounded,
                  color: const Color(0xFFC084FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed:
                  guardandoGestion ? null : guardarGestion,
              icon: guardandoGestion
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                guardandoGestion
                    ? 'GUARDANDO...'
                    : 'GUARDAR GESTIÓN',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    const Color(0xFF22D3EE).withOpacity(0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultadoButton({
    required String valor,
    required String titulo,
    required IconData icono,
    required Color color,
  }) {
    final selected = resultadoGestion == valor;

    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () => setState(() => resultadoGestion = valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        height: 76,
        padding: const EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.18)
              : Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? color
                : Colors.white.withOpacity(0.08),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: color, size: 22),
            const SizedBox(height: 5),
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accionesCobro() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1620),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HERRAMIENTAS DE COBRO',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _accionRapida(
            icono: Icons.email_rounded,
            color: accionesPermitidas
                ? const Color(0xFF22D3EE)
                : Colors.grey,
            titulo: 'Enviar enlace TPV',
            subtitulo: accionesPermitidas
                ? 'Enviar al cliente por email'
                : 'No disponible para este estado',
            cargando: enviandoTpv,
            onTap: abrirModalEnviarTpv,
          ),
          const SizedBox(height: 9),
          _accionRapida(
            icono: Icons.open_in_new_rounded,
            color: const Color(0xFF60A5FA),
            titulo: 'Abrir plataforma de pago',
            subtitulo: 'Abrir la página TPV en el navegador',
            onTap: abrirTpvEnNavegador,
          ),
        ],
      ),
    );
  }

  Widget _historico() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1620),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'HISTÓRICO DE GESTIONES',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(
                Icons.history_rounded,
                color: Colors.white38,
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (comentarios.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Todavía no hay gestiones registradas.',
                  style: TextStyle(
                    color: const Color(0x75FFFFFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            ...comentarios.map((c) {
              final texto =
                  c['comentario']?.toString() ?? '';
              final color = texto.startsWith('[Pagado]')
                  ? const Color(0xFF4ADE80)
                  : texto.startsWith('[Para baja]')
                      ? const Color(0xFFC084FC)
                      : texto.startsWith('[Pendiente]')
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF22D3EE);

              return _historyRow(
                icono: Icons.chat_bubble_rounded,
                color: color,
                titulo: texto,
                subtitulo:
                    '${c['usuario'] ?? ''} · ${_formatFecha(c['created_at'])}',
              );
            }),
          if (pagos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
              color: Colors.white.withOpacity(0.06),
            ),
            const SizedBox(height: 8),
            const Text(
              'PAGOS REGISTRADOS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            ...pagos.map((p) {
              return _historyRow(
                icono: Icons.payments_rounded,
                color: const Color(0xFF4ADE80),
                titulo:
                    '${_money(p['importe']).toStringAsFixed(2)} € · ${p['metodo'] ?? ''}',
                subtitulo:
                    '${p['estado'] ?? ''} · ${_formatFecha(p['created_at'])}',
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _chipEstado(String estado) {
    final color = _estadoColor(estado);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _estadoVisible(estado),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _accionRapida({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    bool cargando = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: cargando ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.035),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 43,
                width: 43,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: cargando
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: const Color(0x75FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyRow({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icono, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modalInfo(String titulo, String valor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: const Color(0x75FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            valor.isEmpty ? 'Sin dato' : valor,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(
        color: Colors.white38,
        fontSize: 12,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      contentPadding: const EdgeInsets.all(14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF22D3EE),
        ),
      ),
    );
  }
}