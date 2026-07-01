import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detalle_seguimiento_screen.dart';

class SeguimientoClientesScreen extends StatefulWidget {
  const SeguimientoClientesScreen({super.key});

  @override
  State<SeguimientoClientesScreen> createState() =>
      _SeguimientoClientesScreenState();
}

class _SeguimientoClientesScreenState extends State<SeguimientoClientesScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  List<Map<String, dynamic>> llamadas = [];

  int llamadasVencidas = 0;
  int llamadasHoy = 0;

  @override
  void initState() {
    super.initState();
    loadSeguimiento();
  }

  Future<void> loadSeguimiento() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      setState(() => loading = true);

      final data = await supabase
          .from('seguimiento_clientes')
          .select()
          .eq('auth_id', user.id)
          .eq('estado', 'Pendiente');
          await comprobarAlertasSeguimientoJefe();

      final now = DateTime.now();
      final hoy = DateTime(now.year, now.month, now.day);

      int vencidas = 0;
      int hoyCount = 0;

      final filtradas = List<Map<String, dynamic>>.from(data).where((r) {
        final rawFecha = r['proxima_llamada'];

        if (rawFecha == null || rawFecha.toString().trim().isEmpty) {
          return false;
        }

        DateTime fecha;

        try {
          fecha = DateTime.parse(rawFecha.toString());
        } catch (_) {
          return false;
        }

        final fechaLlamada = DateTime(
          fecha.year,
          fecha.month,
          fecha.day,
        );

        final debeSalir = !fechaLlamada.isAfter(hoy);

        if (debeSalir) {
          if (fechaLlamada.isBefore(hoy)) {
            vencidas++;
          } else {
            hoyCount++;
          }
        }

        return debeSalir;
      }).toList();

      filtradas.sort((a, b) {
        final fa = DateTime.parse(a['proxima_llamada'].toString());
        final fb = DateTime.parse(b['proxima_llamada'].toString());
        return fa.compareTo(fb);
      });

      setState(() {
        llamadas = filtradas;
        llamadasVencidas = vencidas;
        llamadasHoy = hoyCount;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al cargar seguimientos: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
  Future<void> comprobarAlertasSeguimientoJefe() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final hoy = DateTime.now();

  final limite = DateTime(
    hoy.year,
    hoy.month,
    hoy.day,
  ).subtract(const Duration(days: 3));

  final limiteString =
      "${limite.year.toString().padLeft(4, '0')}-"
      "${limite.month.toString().padLeft(2, '0')}-"
      "${limite.day.toString().padLeft(2, '0')}";

  final seguimientosAtrasados = await supabase
      .from('seguimiento_clientes')
      .select('id')
      .eq('auth_id', user.id)
      .eq('estado', 'Pendiente')
      .lte('proxima_llamada', limiteString);

  if (seguimientosAtrasados.isEmpty) return;

  final agente = await supabase
      .from('usuarios')
      .select('nombre, auth_id, parent_id')
      .eq('auth_id', user.id)
      .maybeSingle();

  if (agente == null) return;

  final parentId = agente['parent_id'];

  if (parentId == null) return;

  final jefe = await supabase
      .from('usuarios')
      .select('auth_id')
      .eq('id', parentId)
      .maybeSingle();

  if (jefe == null) return;

  final authIdJefe = jefe['auth_id'];

  final alertaExistente = await supabase
      .from('alertas')
      .select('id')
      .eq('auth_id_destino', authIdJefe)
      .eq('auth_id_origen', user.id)
      .eq('tipo', 'seguimiento_atrasado')
      .eq('leida', false)
      .maybeSingle();

  if (alertaExistente != null) return;

  await supabase.from('alertas').insert({
    'auth_id_destino': authIdJefe,
    'auth_id_origen': user.id,
    'tipo': 'seguimiento_atrasado',
    'titulo': 'Seguimiento atrasado',
    'mensaje':
        '${agente['nombre']} tiene ${seguimientosAtrasados.length} seguimiento(s) de clientes atrasado(s) más de 3 días. Revisa con el agente que gestione esas llamadas cuanto antes.',
  });
}

  Future<void> _abrirDetalle(Map<String, dynamic> llamada) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleSeguimientoScreen(
          seguimiento: llamada,
        ),
      ),
    );

    loadSeguimiento();
  }

  String _fechaBonita(dynamic value) {
    if (value == null) return "Sin fecha";

    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/"
          "${fecha.month.toString().padLeft(2, '0')}/"
          "${fecha.year}";
    } catch (_) {
      return "Fecha no válida";
    }
  }

  bool _estaVencida(dynamic value) {
    if (value == null) return false;

    try {
      final fecha = DateTime.parse(value.toString());
      final now = DateTime.now();

      final hoy = DateTime(now.year, now.month, now.day);
      final fechaLlamada = DateTime(fecha.year, fecha.month, fecha.day);

      return fechaLlamada.isBefore(hoy);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: RefreshIndicator(
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFF102331),
              onRefresh: loadSeguimiento,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverToBoxAdapter(child: _headerCard()),
                  if (loading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                      ),
                    )
                  else if (llamadas.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      sliver: SliverList.separated(
                        itemCount: llamadas.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          return _llamadaCard(llamadas[index]);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Seguimientos",
              style: TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.35),
              ),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.cyanAccent,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.16),
            const Color(0xFF081A2A).withOpacity(0.92),
            const Color(0xFF061018).withOpacity(0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.11),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "LLAMADAS DE HOY",
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${llamadas.length}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      height: 0.9,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      "pendientes",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _miniKpi(
                      title: "Para hoy",
                      value: "$llamadasHoy",
                      icon: Icons.today_rounded,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _miniKpi(
                      title: "Atrasadas",
                      value: "$llamadasVencidas",
                      icon: Icons.warning_amber_rounded,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniKpi({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _llamadaCard(Map<String, dynamic> l) {
    final bool vencida = _estaVencida(l['proxima_llamada']);

    final color = vencida ? Colors.orangeAccent : Colors.cyanAccent;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _abrirDetalle(l),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.13),
              Colors.white.withOpacity(0.055),
              Colors.white.withOpacity(0.035),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(
            color: color.withOpacity(0.27),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              height: 66,
              width: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.45)),
              ),
              child: Icon(
                vencida
                    ? Icons.priority_high_rounded
                    : Icons.phone_in_talk_rounded,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 58,
              color: Colors.white.withOpacity(0.10),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${l['nombre'] ?? 'Cliente sin nombre'}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "${l['producto'] ?? 'Producto no indicado'}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        icon: Icons.calendar_month_rounded,
                        text: _fechaBonita(l['proxima_llamada']),
                        color: color,
                      ),
                      _chip(
                        icon: Icons.call_rounded,
                        text: "${l['tipo_llamada'] ?? 'Llamada'}",
                        color: Colors.cyanAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.50),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 108,
            width: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.greenAccent.withOpacity(0.10),
              border: Border.all(
                color: Colors.greenAccent.withOpacity(0.35),
              ),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.greenAccent,
              size: 62,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            "Todo al día",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "No tienes seguimientos pendientes para hoy.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        ],
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
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF02060A),
                Color(0xFF061018),
                Color(0xFF071827),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _blurCircle(220, Colors.cyanAccent.withOpacity(0.18)),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(240, Colors.blueAccent.withOpacity(0.10)),
        ),
        Positioned(
          bottom: -100,
          right: -100,
          child: _blurCircle(260, Colors.cyanAccent.withOpacity(0.10)),
        ),
      ],
    );
  }

  static Widget _blurCircle(double size, Color color) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 80,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}