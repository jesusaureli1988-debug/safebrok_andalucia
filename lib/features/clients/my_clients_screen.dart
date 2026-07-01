import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clients/client_detail_screen.dart';


class MyClientsScreen extends StatefulWidget {
  const MyClientsScreen({super.key});

  @override
  State<MyClientsScreen> createState() => _MyClientsScreenState();
}

class _MyClientsScreenState extends State<MyClientsScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> clients = [];
  bool loading = true;

  String? userRole;
  String? userAuthId;

  String selectedYear = 'Todos';
  String selectedMonth = 'Todos';
  String searchText = '';

  List<String> years = ['Todos'];
  List<String> months = ['Todos'];

  @override
  void initState() {
    super.initState();
    loadClients();
  }

  Future<void> loadClients() async {
  final user = supabase.auth.currentUser;

  if (user == null) {
    if (mounted) setState(() => loading = false);
    return;
  }

  try {
    setState(() => loading = true);

    final userData = await supabase
        .from('usuarios')
        .select('id, auth_id, rol_usuario')
        .eq('auth_id', user.id)
        .single();

    userAuthId = userData['auth_id']?.toString();
    userRole = userData['rol_usuario']?.toString();

    final userInternalId = userData['id']?.toString();

    if (userAuthId == null || userInternalId == null || userRole == null) {
      if (mounted) {
        setState(() {
          clients = [];
          loading = false;
        });
      }
      return;
    }

    final allowedIds = await getClientesPermitidosPorRol(
      internalId: userInternalId,
      authId: userAuthId!,
      role: userRole!,
    );

    if (allowedIds.isEmpty) {
      if (mounted) {
        setState(() {
          clients = [];
          loading = false;
        });
      }
      return;
    }

    final response = await supabase
        .from('clientes')
        .select('*')
        .inFilter('auth_id', allowedIds)
        .order('created_at', ascending: false);

    clients = List<Map<String, dynamic>>.from(response);

    _buildFilters();

    if (mounted) {
      setState(() => loading = false);
    }
  } catch (e) {
    debugPrint("ERROR LOAD CLIENTS: $e");

    if (mounted) {
      setState(() {
        clients = [];
        loading = false;
      });
    }
  }
}
Future<List<String>> getClientesPermitidosPorRol({
  required String internalId,
  required String authId,
  required String role,
}) async {
  if (role == 'administracion') {
    return [];
  }

  if (role == 'agente') {
    return [authId];
  }

  if (role == 'director_nacional') {
    final usuarios = await supabase
        .from('usuarios')
        .select('auth_id')
        .not('auth_id', 'is', null);

    return usuarios
        .map<String>((e) => e['auth_id']?.toString() ?? '')
        .where((e) => e.isNotEmpty && e != 'null')
        .toList();
  }

  final usuarios = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario');

  final normalized = usuarios.map<Map<String, String?>>((u) {
    return {
      'id': u['id']?.toString(),
      'auth_id': u['auth_id']?.toString(),
      'parent_id': u['parent_id']?.toString(),
      'rol_usuario': u['rol_usuario']?.toString(),
    };
  }).toList();

  final Set<String> resultAuthIds = {};
  resultAuthIds.add(authId);

  void buscarHijos(String parentId) {
    for (final u in normalized) {
      if (u['parent_id'] == parentId) {
        final childId = u['id'];
        final childAuthId = u['auth_id'];

        if (childAuthId != null &&
            childAuthId.isNotEmpty &&
            childAuthId != 'null') {
          resultAuthIds.add(childAuthId);
        }

        if (childId != null && childId.isNotEmpty && childId != parentId) {
          buscarHijos(childId);
        }
      }
    }
  }

  if (role == 'director_zona' ||
      role == 'jefe_ventas' ||
      role == 'jefe_equipo') {
    buscarHijos(internalId);
    return resultAuthIds.toList();
  }

  return [];
}

  void _buildFilters() {
    final Set<String> yearSet = {};
    final Set<int> monthSet = {};

    for (final c in clients) {
      final rawDate = c['created_at'];
      if (rawDate == null) continue;

      final date = DateTime.tryParse(rawDate.toString());
      if (date == null) continue;

      yearSet.add(date.year.toString());
      monthSet.add(date.month);
    }

    final orderedYears = yearSet.toList()
      ..sort((a, b) => b.compareTo(a));

    final orderedMonths = monthSet.toList()..sort();

    years = ['Todos', ...orderedYears];
    months = [
      'Todos',
      ...orderedMonths.map(_monthName),
    ];
  }

  String _monthName(int m) {
    const monthNames = [
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

    return monthNames[m - 1];
  }

  List<Map<String, dynamic>> get filteredClients {
    return clients.where((c) {
      final rawDate = c['created_at'];
      final date = rawDate == null
          ? null
          : DateTime.tryParse(rawDate.toString());

      final matchYear = selectedYear == 'Todos' ||
          (date != null && selectedYear == date.year.toString());

      final matchMonth = selectedMonth == 'Todos' ||
          (date != null && selectedMonth == _monthName(date.month));

      final fullName =
          "${c['nombre'] ?? ''} ${c['apellidos'] ?? ''}".toLowerCase();

      final phone = (c['telefono'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();

      final query = searchText.toLowerCase().trim();

      final matchSearch = query.isEmpty ||
          fullName.contains(query) ||
          phone.contains(query) ||
          email.contains(query);

      return matchYear && matchMonth && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredClients;

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      body: Stack(
        children: [
          const _ClientsPremiumBackground(),
          SafeArea(
            child: loading
    ? const Center(
        child: CircularProgressIndicator(
          color: Colors.cyanAccent,
        ),
      )
    : RefreshIndicator(
        color: Colors.cyanAccent,
        backgroundColor: const Color(0xFF071421),
        onRefresh: loadClients,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 22),
                    _summaryCard(filtered.length),
                    const SizedBox(height: 16),
                    _searchBox(),
                    const SizedBox(height: 14),
                    _filtersRow(),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            if (clients.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  title: "No hay clientes todavía",
                  subtitle: "Cuando registres clientes aparecerán aquí.",
                  icon: Icons.people_alt_outlined,
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  title: "Sin resultados",
                  subtitle: "Prueba con otro nombre, teléfono, año o mes.",
                  icon: Icons.search_off_rounded,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _clientCard(filtered[index], index);
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

  Widget _header() {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Mis Clientes",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                _roleSubtitle(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _premiumIcon(
          Icons.people_alt_rounded,
          Colors.cyanAccent,
          50,
        ),
      ],
    );
  }

  String _roleSubtitle() {
  if (userRole == 'agente') {
    return "Clientes asignados a tu usuario";
  }

  if (userRole == 'jefe_equipo') {
    return "Clientes de tu equipo comercial";
  }

  if (userRole == 'jefe_ventas') {
    return "Clientes de tu estructura comercial";
  }

  if (userRole == 'director_zona') {
    return "Clientes de tu zona comercial";
  }

  if (userRole == 'director_nacional') {
    return "Cartera global de toda la compañía";
  }

  if (userRole == 'administracion') {
    return "Sin acceso a cartera comercial";
  }

  return "Cartera comercial";
}

  Widget _summaryCard(int totalFiltrado) {
    return Container(
      width: double.infinity,
      height: 215,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF062C68),
            Color(0xFF071B3E),
            Color(0xFF050B12),
          ],
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.20),
            blurRadius: 35,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -35,
            child: Icon(
              Icons.groups_rounded,
              size: 150,
              color: Colors.cyanAccent.withOpacity(0.07),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "CARTERA ACTIVA",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "$totalFiltrado",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                totalFiltrado == clients.length
                    ? "clientes registrados"
                    : "clientes según filtros",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.60),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  _summaryChip(
                    Icons.filter_alt_rounded,
                    selectedYear == 'Todos' ? "Todos los años" : selectedYear,
                    Colors.cyanAccent,
                  ),
                  const SizedBox(width: 8),
                  _summaryChip(
                    Icons.calendar_month_rounded,
                    selectedMonth == 'Todos' ? "Todos los meses" : selectedMonth,
                    Colors.purpleAccent,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String text, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: color.withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _searchBox() {
    return TextField(
      onChanged: (v) => setState(() => searchText = v),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      cursorColor: Colors.cyanAccent,
      decoration: InputDecoration(
        hintText: "Buscar por nombre, teléfono o email...",
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.42),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Colors.white.withOpacity(0.70),
        ),
        suffixIcon: searchText.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  setState(() => searchText = '');
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                ),
              ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: Colors.cyanAccent.withOpacity(0.45),
          ),
        ),
      ),
    );
  }

  Widget _filtersRow() {
    return Row(
      children: [
        Expanded(
          child: _filter(
            label: "Año",
            value: selectedYear,
            items: years,
            icon: Icons.date_range_rounded,
            color: Colors.cyanAccent,
            onChanged: (v) {
              if (v == null) return;
              setState(() => selectedYear = v);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _filter(
            label: "Mes",
            value: selectedMonth,
            items: months,
            icon: Icons.calendar_month_rounded,
            color: Colors.purpleAccent,
            onChanged: (v) {
              if (v == null) return;
              setState(() => selectedMonth = v);
            },
          ),
        ),
      ],
    );
  }

  Widget _filter({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required Color color,
    required Function(String?) onChanged,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.065),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: const Color(0xFF071421),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: color,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                items: items
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e,
                        child: Text(
                          e == 'Todos' ? "$label: Todos" : e,
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

  Widget _emptyState({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withOpacity(0.09),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _premiumIcon(icon, Colors.cyanAccent, 72),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 13,
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

  Widget _clientCard(Map<String, dynamic> c, int index) {
    final nombre = (c['nombre'] ?? '').toString().trim();
    final apellidos = (c['apellidos'] ?? '').toString().trim();
    final telefono = (c['telefono'] ?? '').toString().trim();
    final email = (c['email'] ?? '').toString().trim();

    final fullName = "$nombre $apellidos".trim().isEmpty
        ? "Cliente sin nombre"
        : "$nombre $apellidos".trim();

    final rawDate = c['created_at'];
    final date = rawDate == null
        ? null
        : DateTime.tryParse(rawDate.toString());

    final color = _cardColor(index);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.06),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClientDetailScreen(clientId: c['id']),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _avatarClient(fullName, color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (telefono.isNotEmpty)
                      _infoLine(
                        Icons.phone_rounded,
                        telefono,
                        Colors.greenAccent,
                      ),
                    if (email.isNotEmpty)
                      _infoLine(
                        Icons.mail_rounded,
                        email,
                        Colors.cyanAccent,
                      ),
                    if (date != null)
                      _infoLine(
                        Icons.event_rounded,
                        "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}",
                        Colors.purpleAccent,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.35),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarClient(String fullName, Color color) {
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : "?";

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.38),
            color.withOpacity(0.14),
            Colors.white.withOpacity(0.03),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.36),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: color.withOpacity(0.85), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumIcon(IconData icon, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.34),
            color.withOpacity(0.10),
            Colors.white.withOpacity(0.025),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: color,
        size: size * 0.48,
      ),
    );
  }

  Color _cardColor(int index) {
    final colors = [
      Colors.cyanAccent,
      Colors.purpleAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.blueAccent,
    ];

    return colors[index % colors.length];
  }
}

class _ClientsPremiumBackground extends StatelessWidget {
  const _ClientsPremiumBackground();

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
                Color(0xFF050B12),
                Color(0xFF071A2E),
                Color(0xFF050B12),
              ],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -100,
          child: _glow(Colors.cyanAccent, 330, 0.15),
        ),
        Positioned(
          bottom: -170,
          left: -110,
          child: _glow(Colors.blueAccent, 370, 0.14),
        ),
        Positioned(
          top: 310,
          left: -130,
          child: _glow(Colors.purpleAccent, 250, 0.08),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            color: Colors.black.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}