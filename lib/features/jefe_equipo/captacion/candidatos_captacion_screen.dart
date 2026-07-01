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

  List<Map<String, dynamic>> candidatos = [];

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

  Future<void> cargarCandidatos() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          candidatos = [];
          loading = false;
        });
        return;
      }

      final data = await supabase
          .from('candidatos_captacion')
          .select()
          .eq('auth_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        candidatos = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ ERROR CARGANDO CANDIDATOS: $e");
      setState(() => loading = false);
    }
  }

  void calcularKPIs() {
    int proceso = 0;
    int fin = 0;

    for (final c in candidatos) {
      final estado = c['estado'];

      if (estado == 'INCORPORADO' || estado == 'DESCARTADO') {
        fin++;
      } else {
        proceso++;
      }
    }

    setState(() {
      total = candidatos.length;
      enProceso = proceso;
      finalizados = fin;
    });
  }

  List<Map<String, dynamic>> get candidatosFiltrados {
    return candidatos.where((c) {
      final estado = c['estado']?.toString() ?? '';

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

      return coincideBusqueda && coincideFiltro;
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
    final incorporados =
        candidatos.where((c) => c['estado'] == 'INCORPORADO').length;

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