import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'integracion_agente_detalle_screen.dart';

class IntegracionEquipoScreen extends StatefulWidget {
  const IntegracionEquipoScreen({super.key});

  @override
  State<IntegracionEquipoScreen> createState() => _IntegracionEquipoScreenState();
}

class _IntegracionEquipoScreenState extends State<IntegracionEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String filtro = 'todos';

  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> agentes = [];
  List<Map<String, dynamic>> integraciones = [];

  static const int totalPasos = 5;

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> cargarDatos() async {
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
          .select()
          .eq('parent_id', jefeId)
          .eq('rol_usuario', 'agente')
          .order('nombre', ascending: true);

      final integracionData = await supabase
          .from('integracion_agentes')
          .select();

      if (!mounted) return;

      setState(() {
        agentes = List<Map<String, dynamic>>.from(agentesData);
        integraciones = List<Map<String, dynamic>>.from(integracionData);
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR CARGANDO INTEGRACIÓN: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Map<String, dynamic>? obtenerIntegracion(dynamic agenteId) {
    try {
      return integraciones.firstWhere((x) => x['agente_id'] == agenteId);
    } catch (_) {
      return null;
    }
  }

  int calcularIntegracion(Map<String, dynamic>? data) {
    if (data == null) return 0;

    int total = 0;

    if (data['bienvenida'] == true) total++;
    if (data['alta_sistema'] == true) total++;
    if (data['grupo_whatsapp'] == true) total++;
    if (data['primera_reunion'] == true) total++;
    if (data['primera_venta'] == true) total++;

    return total;
  }

  List<Map<String, dynamic>> get agentesFiltrados {
    final query = searchController.text.trim().toLowerCase();

    return agentes.where((a) {
      final nombre = "${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}".toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();

      final progreso = calcularIntegracion(obtenerIntegracion(a['id']));

      final coincideBusqueda = nombre.contains(query) || email.contains(query);

      final coincideFiltro = switch (filtro) {
        'pendientes' => progreso == 0,
        'progreso' => progreso > 0 && progreso < totalPasos,
        'completados' => progreso == totalPasos,
        _ => true,
      };

      return coincideBusqueda && coincideFiltro;
    }).toList();
  }

  int get completados {
    return agentes.where((a) {
      return calcularIntegracion(obtenerIntegracion(a['id'])) == totalPasos;
    }).length;
  }

  int get enProgreso {
    return agentes.where((a) {
      final p = calcularIntegracion(obtenerIntegracion(a['id']));
      return p > 0 && p < totalPasos;
    }).length;
  }

  int get pendientes {
    return agentes.where((a) {
      return calcularIntegracion(obtenerIntegracion(a['id'])) == 0;
    }).length;
  }

  double get progresoEquipo {
    if (agentes.isEmpty) return 0;

    final totalRealizado = agentes.fold<int>(0, (sum, a) {
      return sum + calcularIntegracion(obtenerIntegracion(a['id']));
    });

    return totalRealizado / (agentes.length * totalPasos);
  }

  Color colorEstado(int progreso) {
    if (progreso == totalPasos) return const Color(0xFF16A34A);
    if (progreso == 0) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String textoEstado(int progreso) {
    if (progreso == totalPasos) return "Completado";
    if (progreso == 0) return "Pendiente";
    return "En progreso";
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = agentesFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF0F172A),
        title: const Text(
          "Integración del equipo",
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: cargarDatos,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2563EB),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargarDatos,
              color: const Color(0xFF2563EB),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroPanel(),
                          const SizedBox(height: 18),
                          _buscador(),
                          const SizedBox(height: 12),
                          _filtros(),
                          const SizedBox(height: 18),
                          Text(
                            "${filtrados.length} agentes",
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w800,
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
                        final integracion = obtenerIntegracion(agente['id']);
                        final progreso = calcularIntegracion(integracion);

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

  Widget _heroPanel() {
    final porcentaje = (progresoEquipo * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1E40AF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.rocket_launch_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            "Onboarding comercial",
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Controla que cada agente tenga completados los pasos clave de integración.",
            style: TextStyle(
              color: Colors.white70,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progresoEquipo,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.25),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "$porcentaje% de integración global",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _kpiBox(
                  titulo: "Completados",
                  valor: "$completados",
                  icono: Icons.verified_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpiBox(
                  titulo: "En curso",
                  valor: "$enProgreso",
                  icono: Icons.timelapse_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpiBox(
                  titulo: "Pendientes",
                  valor: "$pendientes",
                  icono: Icons.flag_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiBox({
    required String titulo,
    required String valor,
    required IconData icono,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Colors.white, size: 20),
          const SizedBox(height: 8),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
      decoration: InputDecoration(
        hintText: "Buscar agente por nombre o email...",
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _filtros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip("Todos", "todos"),
          _chip("Pendientes", "pendientes"),
          _chip("En progreso", "progreso"),
          _chip("Completados", "completados"),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final activo = filtro == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: activo,
        label: Text(label),
        onSelected: (_) => setState(() => filtro = value),
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: activo ? Colors.white : const Color(0xFF475569),
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide(
          color: activo ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _tarjetaAgente({
    required Map<String, dynamic> agente,
    required int progreso,
  }) {
    final color = colorEstado(progreso);
    final nombre = "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();
    final email = agente['email'] ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IntegracionAgenteDetalleScreen(
                agente: agente,
              ),
            ),
          );

          if (result == true) {
            await cargarDatos();
          }
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    "$progreso/$totalPasos",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
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
                      nombre.isEmpty ? "Agente sin nombre" : nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progreso / totalPasos,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE2E8F0),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
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
              ),

              const SizedBox(width: 12),

              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoVacio() {
    return const Center(
      child: Text(
        "No hay agentes con este filtro.",
        style: TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}