import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamAgentsScreen extends StatefulWidget {
  const TeamAgentsScreen({super.key});

  @override
  State<TeamAgentsScreen> createState() => _TeamAgentsScreenState();
}

class _TeamAgentsScreenState extends State<TeamAgentsScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> agents = [];
  bool loading = true;

  String search = '';

  static const Color bg = Color(0xFF07111D);
  static const Color card = Color(0xFF101C2B);
  static const Color card2 = Color(0xFF132437);
  static const Color blue = Color(0xFF2563EB);
  static const Color green = Color(0xFF22C55E);
  static const Color orange = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    loadAgents();
  }

  Future<void> loadAgents() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);

    try {
      final userData = await supabase
          .from('usuarios')
          .select('id, auth_id, rol_usuario')
          .eq('auth_id', user.id)
          .single();

      final myId = userData['id'];

      final response = await supabase
          .from('usuarios')
          .select('*')
          .eq('parent_id', myId)
          .order('nombre');

      setState(() {
        agents = List<Map<String, dynamic>>.from(response);
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR LOAD AGENTS: $e");
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get filteredAgents {
    if (search.trim().isEmpty) return agents;

    final q = search.trim().toLowerCase();

    return agents.where((a) {
      final nombre = (a['nombre'] ?? '').toString().toLowerCase();
      final apellidos = (a['apellidos'] ?? '').toString().toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();
      final telefono = (a['telefono'] ?? '').toString().toLowerCase();

      return nombre.contains(q) ||
          apellidos.contains(q) ||
          email.contains(q) ||
          telefono.contains(q);
    }).toList();
  }

  int get totalAgentes => agents.length;

  int get activos {
    return agents.where((a) {
      final status = (a['status'] ?? a['estado'] ?? '').toString().toLowerCase();
      return status == 'activo' || status == 'activa' || status == 'alta';
    }).length;
  }

  int get sinEstado {
    return agents.where((a) {
      final status = (a['status'] ?? a['estado'] ?? '').toString().trim();
      return status.isEmpty;
    }).length;
  }

  String fullName(Map<String, dynamic> a) {
    final n = (a['nombre'] ?? '').toString().trim();
    final ap = (a['apellidos'] ?? '').toString().trim();
    final full = "$n $ap".trim();
    return full.isEmpty ? "Agente sin nombre" : full;
  }

  String initials(Map<String, dynamic> a) {
    final name = fullName(a);
    final parts = name.split(' ').where((e) => e.trim().isNotEmpty).toList();

    if (parts.isEmpty) return "A";

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return "${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}"
        .toUpperCase();
  }

  String roleLabel(String? role) {
    switch (role) {
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente comercial';
      case 'director_zona':
        return 'Director de zona';
      default:
        return role ?? 'Sin rol';
    }
  }

  String statusLabel(Map<String, dynamic> a) {
    final value = (a['status'] ?? a['estado'] ?? '').toString().trim();

    if (value.isEmpty) return "Sin estado";

    return value;
  }

  Color statusColor(Map<String, dynamic> a) {
    final value = statusLabel(a).toLowerCase();

    if (value == 'activo' || value == 'activa' || value == 'alta') {
      return green;
    }

    if (value == 'pendiente' || value == 'proceso') {
      return orange;
    }

    if (value == 'sin estado') {
      return Colors.white38;
    }

    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final data = filteredAgents;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        title: const Text(
          "Mis Agentes",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: loadAgents,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: blue,
        onRefresh: loadAgents,
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: blue),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _kpiRow(),
                  const SizedBox(height: 16),
                  _searchBox(),
                  const SizedBox(height: 16),
                  _sectionHeader(data.length),
                  const SizedBox(height: 10),
                  if (data.isEmpty)
                    _emptyState()
                  else
                    ...data.map((a) => _agentCard(a)),
                ],
              ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF102A43),
            Color(0xFF0B1624),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.groups_2_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Panel de agentes",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "Control profesional de tu equipo comercial",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow() {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: "Total",
            value: totalAgentes.toString(),
            icon: Icons.people_alt_rounded,
            color: blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: "Activos",
            value: activos.toString(),
            icon: Icons.verified_rounded,
            color: green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: "Sin estado",
            value: sinEstado.toString(),
            icon: Icons.info_rounded,
            color: orange,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withOpacity(0.16),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextField(
        onChanged: (v) => setState(() => search = v),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          border: InputBorder.none,
          icon: Icon(
            Icons.search_rounded,
            color: Colors.white.withOpacity(0.55),
          ),
          hintText: "Buscar por nombre, email o teléfono",
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.42)),
        ),
      ),
    );
  }

  Widget _sectionHeader(int count) {
    return Row(
      children: [
        const Text(
          "Equipo asignado",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            "$count visibles",
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _agentCard(Map<String, dynamic> a) {
    final name = fullName(a);
    final email = (a['email'] ?? '').toString();
    final phone = (a['telefono'] ?? '').toString();
    final role = roleLabel(a['rol_usuario']);
    final status = statusLabel(a);
    final color = statusColor(a);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white54,
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: blue.withOpacity(0.22),
          child: Text(
            initials(a),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  role,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(status, color),
            ],
          ),
        ),
        children: [
          _detailRow(Icons.email_rounded, "Email", email.isEmpty ? "-" : email),
          _detailRow(Icons.phone_rounded, "Teléfono", phone.isEmpty ? "-" : phone),
          _detailRow(Icons.badge_rounded, "Rol", role),
          _detailRow(Icons.verified_user_rounded, "Estado", status),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: card2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            color: Colors.white.withOpacity(0.28),
            size: 76,
          ),
          const SizedBox(height: 14),
          const Text(
            "No hay agentes para mostrar",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            search.trim().isEmpty
                ? "Todavía no tienes agentes asignados a tu estructura."
                : "No hay resultados con ese filtro de búsqueda.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}