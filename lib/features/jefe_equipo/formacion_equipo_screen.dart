import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/formacion_agente_screen.dart';

class FormacionEquipoScreen extends StatefulWidget {
  const FormacionEquipoScreen({super.key});

  @override
  State<FormacionEquipoScreen> createState() => _FormacionEquipoScreenState();
}

class _FormacionEquipoScreenState extends State<FormacionEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String filtroEstado = 'todos';

  final TextEditingController searchController = TextEditingController();

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

  Future<void> cargarAgentes() async {
    try {
      setState(() => loading = true);

      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => loading = false);
        return;
      }

      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      final jefeId = jefe['id'];

      final agentesData = await supabase
          .from('usuarios')
          .select('*')
          .eq('rol_usuario', 'agente')
          .eq('parent_id', jefeId)
          .order('nombre', ascending: true);

      final formacionData = await supabase
          .from('formacion_agentes')
          .select();

      if (!mounted) return;

      setState(() {
        agentes = List<Map<String, dynamic>>.from(agentesData);
        formaciones = List<Map<String, dynamic>>.from(formacionData);
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ ERROR cargar formación equipo: $e");
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Map<String, dynamic>? obtenerFormacion(dynamic agenteId) {
    try {
      return formaciones.firstWhere((f) => f['agente_id'] == agenteId);
    } catch (_) {
      return null;
    }
  }

  int calcularProgreso(Map<String, dynamic>? formacion) {
    if (formacion == null) return 0;

    int total = 0;

    if (formacion['habilidades_comerciales'] == true) total++;
    if (formacion['decesos'] == true) total++;
    if (formacion['hogar'] == true) total++;
    if (formacion['vida'] == true) total++;
    if (formacion['accidente'] == true) total++;
    if (formacion['auto'] == true) total++;
    if (formacion['comunidad'] == true) total++;
    if (formacion['salud'] == true) total++;
    if (formacion['comercio_pymes'] == true) total++;

    return total;
  }

  List<Map<String, dynamic>> get agentesFiltrados {
    final query = searchController.text.trim().toLowerCase();

    return agentes.where((agente) {
      final nombre = (agente['nombre'] ?? '').toString().toLowerCase();
      final email = (agente['email'] ?? '').toString().toLowerCase();

      final formacion = obtenerFormacion(agente['id']);
      final progreso = calcularProgreso(formacion);

      final coincideBusqueda =
          nombre.contains(query) || email.contains(query);

      final coincideEstado = switch (filtroEstado) {
        'completados' => progreso == totalModulos,
        'enCurso' => progreso > 0 && progreso < totalModulos,
        'pendientes' => progreso == 0,
        _ => true,
      };

      return coincideBusqueda && coincideEstado;
    }).toList();
  }

  int get totalCompletados {
    return agentes.where((a) {
      final progreso = calcularProgreso(obtenerFormacion(a['id']));
      return progreso == totalModulos;
    }).length;
  }

  int get totalEnCurso {
    return agentes.where((a) {
      final progreso = calcularProgreso(obtenerFormacion(a['id']));
      return progreso > 0 && progreso < totalModulos;
    }).length;
  }

  int get totalPendientes {
    return agentes.where((a) {
      final progreso = calcularProgreso(obtenerFormacion(a['id']));
      return progreso == 0;
    }).length;
  }

  double get progresoEquipo {
    if (agentes.isEmpty) return 0;

    final totalRealizado = agentes.fold<int>(0, (sum, agente) {
      return sum + calcularProgreso(obtenerFormacion(agente['id']));
    });

    return totalRealizado / (agentes.length * totalModulos);
  }

  Color colorProgreso(int progreso) {
    if (progreso == totalModulos) return const Color(0xFF22C55E);
    if (progreso >= 5) return const Color(0xFFF59E0B);
    if (progreso > 0) return const Color(0xFF38BDF8);
    return const Color(0xFF64748B);
  }

  String textoEstado(int progreso) {
    if (progreso == totalModulos) return 'Completado';
    if (progreso == 0) return 'Pendiente';
    return 'En formación';
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = agentesFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      appBar: AppBar(
        title: const Text(
          "Formación del equipo",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF061018),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: cargarAgentes,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF38BDF8),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargarAgentes,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _panelResumen(),
                          const SizedBox(height: 18),
                          _buscador(),
                          const SizedBox(height: 14),
                          _filtros(),
                          const SizedBox(height: 18),
                          Text(
                            "${filtrados.length} agentes encontrados",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (filtrados.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _estadoVacio(),
                    )
                  else
                    SliverList.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, i) {
                        final agente = filtrados[i];
                        final formacion = obtenerFormacion(agente['id']);
                        final progreso = calcularProgreso(formacion);

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _tarjetaAgente(
                            agente: agente,
                            progreso: progreso,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _panelResumen() {
    final porcentaje = (progresoEquipo * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F2537),
            Color(0xFF0B1722),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Estado general de formación",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Controla la evolución formativa de cada agente de tu equipo.",
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progresoEquipo,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.08),
              color: const Color(0xFF38BDF8),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            "$porcentaje% completado del equipo",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _miniKpi(
                  titulo: "Completados",
                  valor: "$totalCompletados",
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniKpi(
                  titulo: "En curso",
                  valor: "$totalEnCurso",
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniKpi(
                  titulo: "Pendientes",
                  valor: "$totalPendientes",
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniKpi({
    required String titulo,
    required String valor,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valor,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: searchController,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF38BDF8),
      decoration: InputDecoration(
        hintText: "Buscar agente por nombre o email...",
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF0E1A24),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF38BDF8)),
        ),
      ),
    );
  }

  Widget _filtros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chipFiltro("Todos", "todos"),
          _chipFiltro("Completados", "completados"),
          _chipFiltro("En curso", "enCurso"),
          _chipFiltro("Pendientes", "pendientes"),
        ],
      ),
    );
  }

  Widget _chipFiltro(String texto, String valor) {
    final activo = filtroEstado == valor;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: activo,
        label: Text(texto),
        onSelected: (_) {
          setState(() => filtroEstado = valor);
        },
        selectedColor: const Color(0xFF38BDF8),
        backgroundColor: const Color(0xFF0E1A24),
        labelStyle: TextStyle(
          color: activo ? const Color(0xFF061018) : Colors.white70,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(
          color: activo
              ? const Color(0xFF38BDF8)
              : Colors.white.withOpacity(0.08),
        ),
      ),
    );
  }

  Widget _tarjetaAgente({
    required Map<String, dynamic> agente,
    required int progreso,
  }) {
    final porcentaje = progreso / totalModulos;
    final color = colorProgreso(progreso);

    final nombre = agente['nombre'] ?? 'Sin nombre';
    final email = agente['email'] ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        hoverColor: Colors.white.withOpacity(0.04),
        splashColor: color.withOpacity(0.12),
        highlightColor: color.withOpacity(0.08),
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                  border: Border.all(color: color.withOpacity(0.7)),
                ),
                child: Center(
                  child: progreso == totalModulos
                      ? Icon(Icons.check_rounded, color: color, size: 28)
                      : Text(
                          "$progreso",
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    if (email.toString().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: porcentaje,
                        minHeight: 7,
                        backgroundColor: Colors.white.withOpacity(0.07),
                        color: color,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Row(
                      children: [
                        Text(
                          "$progreso/$totalModulos módulos",
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            textoEstado(progreso),
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
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
                color: Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoVacio() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          "No hay agentes con este filtro.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white60,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}