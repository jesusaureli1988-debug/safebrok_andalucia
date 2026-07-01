import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clients/client_detail_screen.dart';

class AgentClientsScreen extends StatefulWidget {
  final String agentAuthId;
  final String agentName;

  const AgentClientsScreen({
    super.key,
    required this.agentAuthId,
    required this.agentName,
  });

  @override
  State<AgentClientsScreen> createState() => _AgentClientsScreenState();
}

class _AgentClientsScreenState extends State<AgentClientsScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  List<Map<String, dynamic>> clients = [];
  String searchText = '';

  @override
  void initState() {
    super.initState();
    loadClients();
  }

  Future<void> loadClients({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (isRefresh) {
        refreshing = true;
      } else {
        loading = true;
      }
      errorMessage = null;
    });

    try {
      final response = await supabase
          .from('clientes')
          .select('*')
          .eq('auth_id', widget.agentAuthId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        clients = List<Map<String, dynamic>>.from(response);
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("ERROR AGENT CLIENTS: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudieron cargar los clientes";
      });
    }
  }

  List<Map<String, dynamic>> get filteredClients {
    if (searchText.trim().isEmpty) return clients;

    final query = searchText.toLowerCase().trim();

    return clients.where((client) {
      final fullName =
          "${client['nombre'] ?? ''} ${client['apellidos'] ?? ''}"
              .toLowerCase();

      final phone = (client['telefono'] ?? '').toString().toLowerCase();
      final email = (client['email'] ?? '').toString().toLowerCase();

      return fullName.contains(query) ||
          phone.contains(query) ||
          email.contains(query);
    }).toList();
  }

  String _clientName(Map<String, dynamic> client) {
    final nombre = (client['nombre'] ?? '').toString().trim();
    final apellidos = (client['apellidos'] ?? '').toString().trim();

    final fullName = "$nombre $apellidos".trim();

    return fullName.isEmpty ? "Cliente sin nombre" : fullName;
  }

  String _initial(Map<String, dynamic> client) {
    final name = (client['nombre'] ?? '').toString().trim();
    if (name.isEmpty) return "C";
    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        title: Text(
          widget.agentName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Actualizar",
            onPressed: refreshing ? null : () => loadClients(isRefresh: true),
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _ClientsBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => loadClients(isRefresh: true),
                    color: const Color(0xFF38BDF8),
                    backgroundColor: const Color(0xFF0F172A),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AgentHeaderPanel(
                                  agentName: widget.agentName,
                                  totalClients: clients.length,
                                  visibleClients: filteredClients.length,
                                ),
                                if (errorMessage != null) ...[
                                  const SizedBox(height: 16),
                                  _ErrorBox(
                                    message: errorMessage!,
                                    onRetry: () => loadClients(),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                _SearchBox(
                                  onChanged: (value) {
                                    setState(() {
                                      searchText = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        "Cartera de clientes",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                    ),
                                    _CounterBadge(
                                      text: "${filteredClients.length}",
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Pulsa sobre un cliente para abrir su ficha completa.",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.58),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (filteredClients.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              searching: searchText.trim().isNotEmpty,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            sliver: SliverList.separated(
                              itemCount: filteredClients.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final client = filteredClients[index];

                                return _ClientCard(
                                  initials: _initial(client),
                                  name: _clientName(client),
                                  phone:
                                      (client['telefono'] ?? '').toString(),
                                  email: (client['email'] ?? '').toString(),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ClientDetailScreen(
                                          clientId: client['id'],
                                        ),
                                      ),
                                    );
                                  },
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
}

class _ClientsBackground extends StatelessWidget {
  const _ClientsBackground();

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
                Color(0xFF0B1F2E),
                Color(0xFF12384E),
              ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _GlowCircle(
            size: 230,
            color: const Color(0xFF38BDF8).withOpacity(0.24),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: _GlowCircle(
            size: 260,
            color: const Color(0xFF22C55E).withOpacity(0.16),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _AgentHeaderPanel extends StatelessWidget {
  final String agentName;
  final int totalClients;
  final int visibleClients;

  const _AgentHeaderPanel({
    required this.agentName,
    required this.totalClients,
    required this.visibleClients,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF38BDF8),
                  Color(0xFF2563EB),
                ],
              ),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "$totalClients clientes asignados",
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniMetric(
                      icon: Icons.folder_shared_rounded,
                      text: "$visibleClients visibles",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniMetric({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF38BDF8).withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF38BDF8).withOpacity(0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF7DD3FC),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFBAE6FD),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchBox({
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: const Color(0xFF38BDF8),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, teléfono o email...',
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.42),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Colors.white.withOpacity(0.48),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.075),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(
            color: Color(0xFF38BDF8),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

class _CounterBadge extends StatelessWidget {
  final String text;

  const _CounterBadge({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final String initials;
  final String name;
  final String phone;
  final String email;
  final VoidCallback onTap;

  const _ClientCard({
    required this.initials,
    required this.name,
    required this.phone,
    required this.email,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone.trim().isNotEmpty;
    final hasEmail = email.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF22C55E),
                      Color(0xFF38BDF8),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(
                      icon: Icons.phone_rounded,
                      text: hasPhone ? phone : "Sin teléfono",
                      muted: !hasPhone,
                    ),
                    const SizedBox(height: 5),
                    _InfoLine(
                      icon: Icons.email_rounded,
                      text: hasEmail ? email : "Sin email",
                      muted: !hasEmail,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;

  const _InfoLine({
    required this.icon,
    required this.text,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: muted
              ? Colors.white.withOpacity(0.30)
              : const Color(0xFF7DD3FC),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted
                  ? Colors.white.withOpacity(0.36)
                  : Colors.white.withOpacity(0.64),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;

  const _EmptyState({
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.folder_open_rounded,
              size: 58,
              color: Colors.white.withOpacity(0.35),
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? "No hay clientes con esa búsqueda"
                  : "Este agente no tiene clientes",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? "Prueba buscando por nombre, teléfono o email."
                  : "Cuando este agente tenga clientes asignados aparecerán aquí.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text("Reintentar"),
          ),
        ],
      ),
    );
  }
}