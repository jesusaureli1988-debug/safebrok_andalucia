import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MisVisitasScreen extends StatefulWidget {
  const MisVisitasScreen({super.key});

  @override
  State<MisVisitasScreen> createState() => _MisVisitasScreenState();
}

class _MisVisitasScreenState extends State<MisVisitasScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> visitas = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadVisitas();
  }

  Future<void> loadVisitas() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final data = await supabase
          .from('visitas')
          .select()
          .eq('auth_id', user.id)
          .order('fecha_visita', ascending: false);

      if (!mounted) return;

      setState(() {
        visitas = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Error al cargar las visitas"),
          backgroundColor: const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  int get pendientes =>
      visitas.where((v) => v['estado'] != 'Realizada').length;

  int get realizadas =>
      visitas.where((v) => v['estado'] == 'Realizada').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        title: const Text(
          "Mis visitas",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          if (loading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF22D3EE),
              ),
            )
          else
            RefreshIndicator(
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF102331),
              onRefresh: loadVisitas,
              child: visitas.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SizedBox(height: 120),
                        _emptyState(),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                      children: [
                        _header(),
                        const SizedBox(height: 20),
                        _stats(),
                        const SizedBox(height: 22),
                        ...visitas.map((visita) => _visitaCard(visita)),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF123044),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.35),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Agenda comercial",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Controla tus visitas pendientes y realizadas.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            title: "Total",
            value: visitas.length.toString(),
            icon: Icons.list_alt_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            title: "Pendientes",
            value: pendientes.toString(),
            icon: Icons.schedule_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            title: "Realizadas",
            value: realizadas.toString(),
            icon: Icons.check_circle_rounded,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: const Color(0xFF22D3EE),
                size: 24,
              ),
              const SizedBox(height: 8),
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
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visitaCard(Map<String, dynamic> visita) {
    final estado = visita['estado'] ?? '';
    final realizada = estado == 'Realizada';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.060),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: realizada
                            ? Colors.greenAccent.withOpacity(0.16)
                            : Colors.orangeAccent.withOpacity(0.16),
                        border: Border.all(
                          color: realizada
                              ? Colors.greenAccent.withOpacity(0.45)
                              : Colors.orangeAccent.withOpacity(0.45),
                        ),
                      ),
                      child: Icon(
                        realizada
                            ? Icons.check_rounded
                            : Icons.schedule_rounded,
                        color: realizada
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        visita['nombre_cliente'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _estadoChip(estado, realizada),
                  ],
                ),

                const SizedBox(height: 16),

                _infoRow(
                  icon: Icons.calendar_month_rounded,
                  text: _formatFecha(visita['fecha_visita']),
                ),

                const SizedBox(height: 8),

                _infoRow(
                  icon: Icons.access_time_rounded,
                  text: visita['hora_visita'] ?? 'Sin hora',
                ),

                if ((visita['telefono'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoRow(
                    icon: Icons.phone_rounded,
                    text: visita['telefono'],
                  ),
                ],

                if ((visita['direccion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoRow(
                    icon: Icons.location_on_rounded,
                    text: _direccionCompleta(visita),
                  ),
                ],

                if ((visita['observaciones'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1724),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Text(
                      visita['observaciones'],
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _estadoChip(String estado, bool realizada) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: realizada
            ? Colors.greenAccent.withOpacity(0.14)
            : Colors.orangeAccent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: realizada
              ? Colors.greenAccent.withOpacity(0.35)
              : Colors.orangeAccent.withOpacity(0.35),
        ),
      ),
      child: Text(
        estado.isEmpty ? 'Pendiente' : estado,
        style: TextStyle(
          color: realizada ? Colors.greenAccent : Colors.orangeAccent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFF22D3EE),
          size: 18,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  String _direccionCompleta(Map<String, dynamic> visita) {
    final partes = [
      visita['direccion'],
      visita['numero'],
      visita['codigo_postal'],
      visita['poblacion'],
      visita['provincia'],
    ]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .toList();

    return partes.join(', ');
  }

  String _formatFecha(dynamic value) {
    if (value == null) return 'Sin fecha';

    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
    } catch (_) {
      return value.toString();
    }
  }

  Widget _emptyState() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.event_busy_rounded,
                color: Color(0xFF22D3EE),
                size: 58,
              ),
              SizedBox(height: 16),
              Text(
                "No tienes visitas todavía",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Cuando crees una visita, aparecerá aquí con su fecha, hora, estado y dirección.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  height: 1.4,
                ),
              ),
            ],
          ),
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
        Positioned(
          top: -90,
          right: -70,
          child: _glow(
            color: const Color(0xFF22D3EE),
            size: 230,
          ),
        ),
        Positioned(
          bottom: -110,
          left: -80,
          child: _glow(
            color: const Color(0xFF2563EB),
            size: 260,
          ),
        ),
      ],
    );
  }

  Widget _glow({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: const SizedBox(),
      ),
    );
  }
}