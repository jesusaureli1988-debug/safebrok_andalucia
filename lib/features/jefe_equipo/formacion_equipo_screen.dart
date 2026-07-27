import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/formacion_agente_screen.dart';

class FormacionEquipoScreen extends StatefulWidget {
  const FormacionEquipoScreen({super.key});

  @override
  State<FormacionEquipoScreen> createState() =>
      _FormacionEquipoScreenState();
}

class _FormacionEquipoScreenState
    extends State<FormacionEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  String filtroEstado = 'todos';
  String busqueda = '';

  final TextEditingController searchController =
      TextEditingController();

  Map<String, dynamic>? usuarioLogueado;

  List<Map<String, dynamic>> usuariosEstructura = [];
  List<Map<String, dynamic>> agentes = [];
  List<Map<String, dynamic>> formaciones = [];

  static const int totalModulos = 9;

  @override
  void initState() {
    super.initState();
    cargarAgentes();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _idTexto(dynamic value) {
    final id = (value ?? '').toString().trim();

    if (id.isEmpty || id.toLowerCase() == 'null') {
      return '';
    }

    return id;
  }

  String _nombreCompleto(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Sin nombre';

    final nombre =
        usuario['nombre']?.toString().trim() ?? '';

    final apellidos =
        usuario['apellidos']?.toString().trim() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;

    final email =
        usuario['email']?.toString().trim() ?? '';

    return email.isNotEmpty ? email : 'Sin nombre';
  }

  int _nivelRol(dynamic rol) {
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

  bool _relacionPermitida({
    required String rolPadre,
    required String rolHijo,
  }) {
    final padre = _normalizarRol(rolPadre);
    final hijo = _normalizarRol(rolHijo);

    switch (padre) {
      case 'director_nacional':
        return hijo == 'director_zona' ||
            hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'director_zona':
        return hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_ventas':
        return hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_equipo':
        return hijo == 'agente';

      default:
        return false;
    }
  }

  List<Map<String, dynamic>> _construirEstructura({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolPerfil =
        _normalizarRol(perfil['rol_usuario']);

    if (rolPerfil == 'administracion' ||
        rolPerfil == 'administrador' ||
        rolPerfil == 'admin') {
      return todosUsuarios.where((usuario) {
        return _idTexto(usuario['id']).isNotEmpty &&
            _idTexto(usuario['auth_id']).isNotEmpty;
      }).toList();
    }

    final hijosPorParentId =
        <String, List<Map<String, dynamic>>>{};

    for (final usuario in todosUsuarios) {
      final parentId =
          _idTexto(usuario['parent_id']);

      if (parentId.isEmpty) continue;

      hijosPorParentId
          .putIfAbsent(
            parentId,
            () => <Map<String, dynamic>>[],
          )
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final idActual = _idTexto(actual['id']);

      if (idActual.isEmpty ||
          visitados.contains(idActual)) {
        return;
      }

      visitados.add(idActual);
      resultado.add(actual);

      final rolActual =
          _normalizarRol(actual['rol_usuario']);

      final hijos = hijosPorParentId[idActual] ??
          const <Map<String, dynamic>>[];

      for (final hijo in hijos) {
        final rolHijo =
            _normalizarRol(hijo['rol_usuario']);

        if (!_relacionPermitida(
          rolPadre: rolActual,
          rolHijo: rolHijo,
        )) {
          debugPrint(
            'FORMACIÓN: usuario bloqueado '
            '${_nombreCompleto(hijo)} '
            '| rol=$rolHijo '
            '| parent=${hijo['parent_id']} '
            '| padre=$rolActual',
          );

          continue;
        }

        recorrer(hijo);
      }
    }

    recorrer(perfil);

    return resultado;
  }

  Future<void> cargarAgentes() async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = 'No hay ningún usuario conectado.';
        agentes = [];
        usuariosEstructura = [];
        formaciones = [];
      });

      return;
    }

    try {
      if (mounted) {
        setState(() {
          loading = true;
          error = null;
        });
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception(
          'No se encontró el perfil del usuario conectado.',
        );
      }

      final perfil =
          Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          );

      final todosUsuarios =
          List<Map<String, dynamic>>.from(
        usuariosData,
      );

      final estructura = _construirEstructura(
        perfil: perfil,
        todosUsuarios: todosUsuarios,
      );

      /*
       * La pantalla de formación solo muestra agentes.
       *
       * Como la estructura empieza exclusivamente en el usuario
       * conectado, aquí nunca entran:
       * - superiores;
       * - compañeros del mismo rango;
       * - otras zonas;
       * - otras ramas.
       *
       * Sí entran correctamente:
       * - agentes directos del usuario;
       * - agentes de sus jefes de ventas;
       * - agentes de sus jefes de equipo;
       * - agentes que dependan directamente de un director de zona.
       */
      final agentesPermitidos = estructura.where(
        (usuario) =>
            _normalizarRol(usuario['rol_usuario']) ==
            'agente',
      ).toList();

      final agentesIds = agentesPermitidos
          .map((agente) => agente['id'])
          .where((id) => id != null)
          .toList();

      List<Map<String, dynamic>> formacionData = [];

      if (agentesIds.isNotEmpty) {
        final response = await supabase
            .from('formacion_agentes')
            .select()
            .inFilter('agente_id', agentesIds);

        formacionData =
            List<Map<String, dynamic>>.from(response);
      }

      agentesPermitidos.sort((a, b) {
        return _nombreCompleto(a)
            .toLowerCase()
            .compareTo(
              _nombreCompleto(b).toLowerCase(),
            );
      });

      debugPrint(
        '======= FORMACIÓN ESTRUCTURA REAL =======',
      );

      debugPrint(
        'USUARIO: ${_nombreCompleto(perfil)}',
      );

      debugPrint(
        'ROL: ${perfil['rol_usuario']}',
      );

      debugPrint(
        'PERSONAS EN ESTRUCTURA: ${estructura.length}',
      );

      debugPrint(
        'AGENTES PERMITIDOS: ${agentesPermitidos.length}',
      );

      for (final agente in agentesPermitidos) {
        debugPrint(
          '- ${_nombreCompleto(agente)} '
          '| id=${agente['id']} '
          '| parent=${agente['parent_id']} '
          '| auth_id=${agente['auth_id']}',
        );
      }

      debugPrint(
        '=========================================',
      );

      if (!mounted) return;

      setState(() {
        usuarioLogueado = perfil;
        usuariosEstructura = estructura;
        agentes = agentesPermitidos;
        formaciones = formacionData;
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR CARGAR FORMACIÓN EQUIPO: $e',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        loading = false;
        error = e.toString();
        agentes = [];
        usuariosEstructura = [];
        formaciones = [];
      });
    }
  }

  Map<String, dynamic>? obtenerFormacion(
    dynamic agenteId,
  ) {
    try {
      return formaciones.firstWhere(
        (formacion) =>
            formacion['agente_id']?.toString() ==
            agenteId?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  int calcularProgreso(
    Map<String, dynamic>? formacion,
  ) {
    if (formacion == null) return 0;

    int total = 0;

    if (formacion['habilidades_comerciales'] == true) {
      total++;
    }

    if (formacion['decesos'] == true) total++;
    if (formacion['hogar'] == true) total++;
    if (formacion['vida'] == true) total++;
    if (formacion['accidente'] == true) total++;
    if (formacion['auto'] == true) total++;
    if (formacion['comunidad'] == true) total++;
    if (formacion['salud'] == true) total++;

    if (formacion['comercio_pymes'] == true) {
      total++;
    }

    return total;
  }

  List<Map<String, dynamic>> get agentesFiltrados {
    final texto =
        busqueda.trim().toLowerCase();

    return agentes.where((agente) {
      final nombre =
          _nombreCompleto(agente).toLowerCase();

      final email =
          agente['email']?.toString().toLowerCase() ??
              '';

      final formacion =
          obtenerFormacion(agente['id']);

      final progreso =
          calcularProgreso(formacion);

      final coincideBusqueda =
          texto.isEmpty ||
          nombre.contains(texto) ||
          email.contains(texto);

      final coincideEstado = switch (filtroEstado) {
        'completados' => progreso == totalModulos,
        'enCurso' =>
          progreso > 0 && progreso < totalModulos,
        'pendientes' => progreso == 0,
        _ => true,
      };

      return coincideBusqueda && coincideEstado;
    }).toList();
  }

  int get totalCompletados {
    return agentes.where((agente) {
      final progreso = calcularProgreso(
        obtenerFormacion(agente['id']),
      );

      return progreso == totalModulos;
    }).length;
  }

  int get totalEnCurso {
    return agentes.where((agente) {
      final progreso = calcularProgreso(
        obtenerFormacion(agente['id']),
      );

      return progreso > 0 &&
          progreso < totalModulos;
    }).length;
  }

  int get totalPendientes {
    return agentes.where((agente) {
      final progreso = calcularProgreso(
        obtenerFormacion(agente['id']),
      );

      return progreso == 0;
    }).length;
  }

  double get progresoEquipo {
    if (agentes.isEmpty) return 0;

    final realizado =
        agentes.fold<int>(0, (total, agente) {
      return total +
          calcularProgreso(
            obtenerFormacion(agente['id']),
          );
    });

    return realizado /
        (agentes.length * totalModulos);
  }

  Color colorProgreso(int progreso) {
    if (progreso == totalModulos) {
      return const Color(0xFF16A34A);
    }

    if (progreso >= 5) {
      return const Color(0xFFF59E0B);
    }

    if (progreso > 0) {
      return const Color(0xFF2563EB);
    }

    return const Color(0xFF64748B);
  }

  String textoEstado(int progreso) {
    if (progreso == totalModulos) {
      return 'Completado';
    }

    if (progreso == 0) {
      return 'Pendiente';
    }

    return 'En formación';
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = agentesFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          const _FormationBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF111827),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF111827),
                    onRefresh: cargarAgentes,
                    child: CustomScrollView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(
                              18,
                              12,
                              18,
                              10,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _topBar(),
                                const SizedBox(height: 24),
                                _heroFormation(),
                                const SizedBox(height: 20),
                                _searchBox(),
                                const SizedBox(height: 16),
                                _filters(),
                                const SizedBox(height: 18),
                                _summaryPipeline(),
                                const SizedBox(height: 22),
                                _sectionTitle(
                                  filtrados.length,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (error != null)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _errorState(),
                          )
                        else if (filtrados.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _emptyState(),
                          )
                        else
                          SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(
                              18,
                              0,
                              18,
                              32,
                            ),
                            sliver: SliverList.builder(
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final agente =
                                    filtrados[index];

                                final progreso =
                                    calcularProgreso(
                                  obtenerFormacion(
                                    agente['id'],
                                  ),
                                );

                                return Padding(
                                  padding:
                                      const EdgeInsets.only(
                                    bottom: 14,
                                  ),
                                  child: _agentCard(
                                    agente: agente,
                                    progreso: progreso,
                                  ),
                                );
                              },
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
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 5,
          shadowColor:
              Colors.black.withOpacity(0.10),
          child: InkWell(
            onTap: () =>
                Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF111827),
                size: 29,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Formación del equipo',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Desarrollo y capacitación',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: cargarAgentes,
          icon: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF111827)
                      .withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroFormation() {
    final porcentaje =
        (progresoEquipo * 100).round();

    final nombre =
        _nombreCompleto(usuarioLogueado);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
            Color(0xFFF59E0B),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF111827),
              Color(0xFF1E293B),
              Color(0xFF172554),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -14,
              child: Icon(
                Icons.school_rounded,
                color: Colors.white.withOpacity(0.09),
                size: 130,
              ),
            ),
            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'CRECIMIENTO DEL EQUIPO',
                  style: TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Formar hoy es\nvender mejor mañana.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$nombre · ${agentes.length} agentes '
                  'de tu estructura',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progresoEquipo,
                    minHeight: 11,
                    backgroundColor:
                        Colors.white.withOpacity(0.13),
                    color: const Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$porcentaje% de la formación completada',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: TextField(
        controller: searchController,
        onChanged: (value) {
          setState(() {
            busqueda = value;
          });
        },
        style: const TextStyle(
          color: Color(0xFF111827),
          fontWeight: FontWeight.w700,
        ),
        cursorColor: const Color(0xFF2563EB),
        decoration: InputDecoration(
          hintText:
              'Buscar agente por nombre o email...',
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
          ),
          suffixIcon: busqueda.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    searchController.clear();

                    setState(() {
                      busqueda = '';
                    });
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: Colors.black.withOpacity(0.045),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: Color(0xFF2563EB),
              width: 1.5,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: 'Todos',
            value: 'todos',
            icon: Icons.groups_rounded,
          ),
          _filterChip(
            label: 'Completados',
            value: 'completados',
            icon: Icons.verified_rounded,
          ),
          _filterChip(
            label: 'En curso',
            value: 'enCurso',
            icon: Icons.auto_stories_rounded,
          ),
          _filterChip(
            label: 'Pendientes',
            value: 'pendientes',
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final selected = filtroEstado == value;

    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(
          icon,
          size: 17,
          color: selected
              ? Colors.white
              : const Color(0xFF64748B),
        ),
        label: Text(label),
        onSelected: (_) {
          setState(() {
            filtroEstado = value;
          });
        },
        selectedColor: const Color(0xFF111827),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : const Color(0xFF475569),
          fontWeight: FontWeight.w900,
        ),
        side: BorderSide(
          color: selected
              ? const Color(0xFF111827)
              : Colors.black.withOpacity(0.055),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _summaryPipeline() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.black.withOpacity(0.045),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 22,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              title: 'Completados',
              value: totalCompletados,
              icon: Icons.verified_rounded,
              color: const Color(0xFF16A34A),
            ),
          ),
          _separator(),
          Expanded(
            child: _summaryItem(
              title: 'En curso',
              value: totalEnCurso,
              icon: Icons.menu_book_rounded,
              color: const Color(0xFFF59E0B),
            ),
          ),
          _separator(),
          Expanded(
            child: _summaryItem(
              title: 'Pendientes',
              value: totalPendientes,
              icon: Icons.schedule_rounded,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _separator() {
    return Container(
      width: 1,
      height: 54,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _summaryItem({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 23),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: TextStyle(
            color: color,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(int total) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                const Color(0xFF2563EB).withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Agentes en formación',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$total agentes encontrados',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agentCard({
    required Map<String, dynamic> agente,
    required int progreso,
  }) {
    final porcentaje =
        progreso / totalModulos;

    final color = colorProgreso(progreso);
    final nombre = _nombreCompleto(agente);

    final email =
        agente['email']?.toString().trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FormacionAgenteScreen(
                agente: agente,
              ),
            ),
          );

          await cargarAgentes();
        },
        child: Ink(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.black.withOpacity(0.045),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.055),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 57,
                height: 57,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: color.withOpacity(0.22),
                  ),
                ),
                child: progreso == totalModulos
                    ? Icon(
                        Icons.verified_rounded,
                        color: color,
                        size: 29,
                      )
                    : Center(
                        child: Text(
                          '$progreso',
                          style: TextStyle(
                            color: color,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 11),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: porcentaje,
                        minHeight: 7,
                        backgroundColor:
                            const Color(0xFFE2E8F0),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '$progreso/$totalModulos módulos',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                color.withOpacity(0.10),
                            borderRadius:
                                BorderRadius.circular(99),
                          ),
                          child: Text(
                            textoEstado(progreso),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF94A3B8),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(24),
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
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.school_outlined,
                color: Color(0xFF94A3B8),
                size: 58,
              ),
              SizedBox(height: 14),
              Text(
                'No hay agentes con este filtro',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Solo aparecen agentes que dependen de ti '
                'o de responsables de tu estructura.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFFEF4444)
                  .withOpacity(0.20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 50,
              ),
              const SizedBox(height: 12),
              const Text(
                'No se pudo cargar la formación',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormationBackground extends StatelessWidget {
  const _FormationBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFFF4F6FB),
        ),
        Positioned(
          top: -110,
          right: -85,
          child: _Glow(
            color:
                const Color(0xFF2563EB).withOpacity(0.10),
            size: 270,
          ),
        ),
        Positioned(
          top: 310,
          left: -140,
          child: _Glow(
            color:
                const Color(0xFF7C3AED).withOpacity(0.07),
            size: 310,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _Glow(
            color:
                const Color(0xFFF59E0B).withOpacity(0.07),
            size: 290,
          ),
        ),
        BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: 55, sigmaY: 55),
          child: Container(
            color: Colors.white.withOpacity(0.02),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}