import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_contactos_diarios_screen.dart';

class ContactosDiariosScreen extends StatefulWidget {
  const ContactosDiariosScreen({super.key});

  @override
  State<ContactosDiariosScreen> createState() =>
      _ContactosDiariosScreenState();
}

class _ContactosDiariosScreenState extends State<ContactosDiariosScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> registros = [];
  bool loading = true;

  String filtro = 'Todos';

  @override
  void initState() {
    super.initState();
    cargarHistorial();
  }

  Future<void> cargarHistorial() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final data = await supabase
          .from('contactos_diarios')
          .select()
          .eq('auth_id', user.id)
          .order('fecha', ascending: false);

      setState(() {
        registros = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get registrosFiltrados {
    if (filtro == 'Objetivo cumplido') {
      return registros.where((r) => _int(r['contactos_positivos']) >= 6).toList();
    }

    if (filtro == 'Pendientes') {
      return registros.where((r) => _int(r['contactos_positivos']) < 6).toList();
    }

    return registros;
  }

  int get totalFrios =>
      registros.fold(0, (sum, r) => sum + _int(r['contactos_frios']));

  int get totalTelefonicos =>
      registros.fold(0, (sum, r) => sum + _int(r['contactos_telefonicos']));

  int get totalPositivos =>
      registros.fold(0, (sum, r) => sum + _int(r['contactos_positivos']));

  int get totalNegativos =>
      registros.fold(0, (sum, r) => sum + _int(r['contactos_negativos']));

  double get ratioPositivo {
    final totalContactos = totalFrios + totalTelefonicos;
    if (totalContactos == 0) return 0;
    return (totalPositivos / totalContactos) * 100;
  }

  int _int(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  String _formatFecha(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return "${dt.day.toString().padLeft(2, '0')}/"
          "${dt.month.toString().padLeft(2, '0')}/"
          "${dt.year}";
    } catch (_) {
      return fecha;
    }
  }

  String _diaSemana(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      const dias = [
        'Lunes',
        'Martes',
        'Miércoles',
        'Jueves',
        'Viernes',
        'Sábado',
        'Domingo',
      ];
      return dias[dt.weekday - 1];
    } catch (_) {
      return '';
    }
  }

  Future<void> _abrirNuevoRegistro() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddContactosDiariosScreen(),
      ),
    );

    cargarHistorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Contactos diarios',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: cargarHistorial,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
        elevation: 12,
        onPressed: _abrirNuevoRegistro,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nuevo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      body: Stack(
        children: [
          const _PremiumBackground(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF102331),
                    onRefresh: cargarHistorial,
                    child: registros.isEmpty
                        ? _emptyState()
                        : CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(child: _header()),
                              SliverToBoxAdapter(child: _kpiPanel()),
                              SliverToBoxAdapter(child: _filters()),

                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  100,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: registrosFiltrados.length,
                                  itemBuilder: (context, index) {
                                    final r = registrosFiltrados[index];
                                    return _registroCard(r, index);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.13),
                  Colors.white.withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                        Colors.cyanAccent,
                        Color(0xFF2D7DFF),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.25),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.groups_2_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Control de actividad',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${registros.length} registros guardados · objetivo diario 6 positivos',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  title: 'Positivos',
                  value: totalPositivos.toString(),
                  icon: Icons.trending_up_rounded,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  title: 'Ratio',
                  value: '${ratioPositivo.toStringAsFixed(1)}%',
                  icon: Icons.percent_rounded,
                  color: Colors.cyanAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  title: 'Fríos',
                  value: totalFrios.toString(),
                  icon: Icons.ac_unit_rounded,
                  color: Colors.lightBlueAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  title: 'Teléfono',
                  value: totalTelefonicos.toString(),
                  icon: Icons.phone_in_talk_rounded,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
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

  Widget _filters() {
    final filtros = ['Todos', 'Objetivo cumplido', 'Pendientes'];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filtros.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final item = filtros[index];
          final selected = filtro == item;

          return GestureDetector(
            onTap: () => setState(() => filtro = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.cyanAccent
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected
                      ? Colors.cyanAccent
                      : Colors.white.withOpacity(0.10),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                item,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _registroCard(Map<String, dynamic> r, int index) {
    final frios = _int(r['contactos_frios']);
    final telefonicos = _int(r['contactos_telefonicos']);
    final positivos = _int(r['contactos_positivos']);
    final negativos = _int(r['contactos_negativos']);

    final cumplido = positivos >= 6;
    final total = frios + telefonicos;
    final progress = (positivos / 6).clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + (index * 45)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () {},
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.035),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: cumplido
                      ? Colors.greenAccent.withOpacity(0.25)
                      : Colors.orangeAccent.withOpacity(0.20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 46,
                        width: 46,
                        decoration: BoxDecoration(
                          color: cumplido
                              ? Colors.greenAccent.withOpacity(0.16)
                              : Colors.orangeAccent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          cumplido
                              ? Icons.verified_rounded
                              : Icons.timelapse_rounded,
                          color: cumplido
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatFecha(r['fecha'].toString()),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _diaSemana(r['fecha'].toString()),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.52),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: cumplido
                              ? Colors.greenAccent.withOpacity(0.13)
                              : Colors.orangeAccent.withOpacity(0.13),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          cumplido ? 'Cumplido' : 'Pendiente',
                          style: TextStyle(
                            color: cumplido
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: _miniMetric(
                          'Fríos',
                          frios,
                          Icons.ac_unit_rounded,
                          Colors.lightBlueAccent,
                        ),
                      ),
                      Expanded(
                        child: _miniMetric(
                          'Tel',
                          telefonicos,
                          Icons.phone_rounded,
                          Colors.orangeAccent,
                        ),
                      ),
                      Expanded(
                        child: _miniMetric(
                          'Pos',
                          positivos,
                          Icons.thumb_up_alt_rounded,
                          Colors.greenAccent,
                        ),
                      ),
                      Expanded(
                        child: _miniMetric(
                          'Neg',
                          negativos,
                          Icons.thumb_down_alt_rounded,
                          Colors.redAccent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: LinearProgressIndicator(
                            minHeight: 9,
                            value: progress,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            color: cumplido
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$positivos/6',
                        style: TextStyle(
                          color: cumplido
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    total == 0
                        ? 'Sin contactos fríos o telefónicos registrados.'
                        : 'Total contactos base: $total · Objetivo diario: 6 positivos',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(
    String label,
    int value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.50),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(
          Icons.assignment_outlined,
          size: 80,
          color: Colors.white.withOpacity(0.18),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'Sin registros todavía',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Pulsa en Nuevo para registrar tus contactos diarios.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF061018)),

        Positioned(
          top: -120,
          right: -90,
          child: _blurCircle(
            color: Colors.cyanAccent.withOpacity(0.22),
            size: 260,
          ),
        ),

        Positioned(
          top: 220,
          left: -120,
          child: _blurCircle(
            color: const Color(0xFF2D7DFF).withOpacity(0.18),
            size: 280,
          ),
        ),

        Positioned(
          bottom: -120,
          right: -100,
          child: _blurCircle(
            color: Colors.greenAccent.withOpacity(0.12),
            size: 300,
          ),
        ),
      ],
    );
  }

  Widget _blurCircle({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 90,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }
}