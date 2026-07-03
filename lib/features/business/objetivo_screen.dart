import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ObjetivoScreen extends StatefulWidget {
  final String role;

  const ObjetivoScreen({
    super.key,
    required this.role,
  });

  @override
  State<ObjetivoScreen> createState() => _ObjetivoScreenState();
}

class _ObjetivoScreenState extends State<ObjetivoScreen> {
  final supabase = Supabase.instance.client;

  double primasTotales = 0;
  double primasEquipo = 0;
  double primasPropias = 0;

  double primaNeta = 0;
  double porcentajeDV = 0;

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

 Future<void> loadData() async {
  try {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final now = DateTime.now();

    final start = now.day >= 25
        ? DateTime(now.year, now.month, 25)
        : DateTime(now.year, now.month - 1, 25);

    final end = now.day >= 25
        ? DateTime(now.year, now.month + 1, 25)
        : DateTime(now.year, now.month, 25);

    final usuariosData = await supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, rol_usuario, email');

    final usuariosTabla = List<Map<String, dynamic>>.from(usuariosData);

    String limpiar(dynamic v) => (v ?? '').toString().trim().toLowerCase();

    final miUsuario = usuariosTabla.firstWhere(
      (u) =>
          limpiar(u['auth_id']) == limpiar(user.id) ||
          limpiar(u['email']) == limpiar(user.email),
      orElse: () => {},
    );

    if (miUsuario.isEmpty) {
      debugPrint('NO SE ENCUENTRA USUARIO LOGUEADO EN TABLA usuarios');

      if (mounted) {
        setState(() {
          loading = false;
          primaNeta = 0;
          primasTotales = 0;
          primasPropias = 0;
          primasEquipo = 0;
          porcentajeDV = 0;
        });
      }
      return;
    }

    final miId = limpiar(miUsuario['id']);
    final miAuthId = limpiar(miUsuario['auth_id']);
    final role = limpiar(widget.role);

    final idsUsuariosEstructura = <String>{miId};
    final authIdsEstructura = <String>{};

    void buscarDescendientes(String parentId) {
      for (final u in usuariosTabla) {
        final idUsuario = limpiar(u['id']);
        final parentUsuario = limpiar(u['parent_id']);

        if (parentUsuario == parentId &&
            idUsuario.isNotEmpty &&
            !idsUsuariosEstructura.contains(idUsuario)) {
          idsUsuariosEstructura.add(idUsuario);
          buscarDescendientes(idUsuario);
        }
      }
    }

    if (role == 'director_nacional') {
      for (final u in usuariosTabla) {
        final authId = limpiar(u['auth_id']);
        if (authId.isNotEmpty) authIdsEstructura.add(authId);
      }
    } else if (role == 'agente') {
      authIdsEstructura.add(miAuthId);
    } else {
      buscarDescendientes(miId);

      for (final u in usuariosTabla) {
        final idUsuario = limpiar(u['id']);
        final authId = limpiar(u['auth_id']);

        if (idsUsuariosEstructura.contains(idUsuario) && authId.isNotEmpty) {
          authIdsEstructura.add(authId);
        }
      }
    }

    double primas = 0;
    double decesosVida = 0;
    double propias = 0;
    double equipo = 0;

    if (authIdsEstructura.isNotEmpty) {
      final ventas = await supabase
          .from('ventas')
          .select('prima_anual_neta, producto, agente_auth_id')
          .inFilter('agente_auth_id', authIdsEstructura.toList())
          .gte('fecha_efecto', start.toIso8601String())
          .lt('fecha_efecto', end.toIso8601String());

      for (final v in ventas) {
        final primaRaw = v['prima_anual_neta'];
        final prima = primaRaw is num
            ? primaRaw.toDouble()
            : double.tryParse(primaRaw?.toString() ?? '0') ?? 0;

        final agenteAuthId = limpiar(v['agente_auth_id']);

        primas += prima;

        if (agenteAuthId == miAuthId) {
          propias += prima;
        } else {
          equipo += prima;
        }

        final producto = limpiar(v['producto']);

        if (producto.contains('decesos') || producto.contains('vida')) {
          decesosVida += prima;
        }
      }
    }

    final porcentaje = primas > 0 ? (decesosVida / primas) * 100 : 0.0;

    if (!mounted) return;

    setState(() {
      primaNeta = primas;
      porcentajeDV = porcentaje;
      primasPropias = propias;
      primasEquipo = equipo;
      primasTotales = primas;
      loading = false;
    });
  } catch (e, s) {
    debugPrint("ERROR OBJETIVOS: $e");
    debugPrint("$s");

    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  double get objetivoPrimas {
  final role = widget.role.toLowerCase().trim();

  if (role == 'jefe_equipo') return 10000;
  if (role == 'jefe_ventas') return 12000;
  if (role == 'director_zona') return 15000;
  if (role == 'director_nacional') return 25000;

  return 12000;
}

 String get roleLabel {
  final role = widget.role.toLowerCase().trim();

  if (role == 'director_nacional') return "Director Nacional";
  if (role == 'director_zona') return "Director de Zona";
  if (role == 'jefe_ventas') return "Jefe de Ventas";
  if (role == 'jefe_equipo') return "Jefe de Equipo";

  return "Agente";
}

  @override
  Widget build(BuildContext context) {
    final bool objetivoPrimasOk = primaNeta >= objetivoPrimas;
    final bool objetivoDVOk = porcentajeDV >= 30;
    final bool objetivoGeneralOk = objetivoPrimasOk && objetivoDVOk;

    final double progresoPrimas = (primaNeta / objetivoPrimas).clamp(0.0, 1.0);
    final double progresoDV = (porcentajeDV / 30).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      body: Stack(
        children: [
          const _ObjetivoBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
                    children: [
                      _header(objetivoGeneralOk),
                      const SizedBox(height: 24),
                      _heroCard(
                        objetivoGeneralOk: objetivoGeneralOk,
                        progresoPrimas: progresoPrimas,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _miniResumeCard(
                              title: "Propias",
                              value: "${primasPropias.toStringAsFixed(0)} €",
                              icon: Icons.person_rounded,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _miniResumeCard(
                              title: "Equipo",
                              value: "${primasEquipo.toStringAsFixed(0)} €",
                              icon: Icons.groups_rounded,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _objectiveCard(
                        title: "Objetivo primas",
                        current:
                            "${primaNeta.toStringAsFixed(2)} €",
                        target:
                            "${objetivoPrimas.toStringAsFixed(0)} €",
                        progress: progresoPrimas,
                        ok: objetivoPrimasOk,
                        icon: Icons.trending_up_rounded,
                        color: Colors.cyanAccent,
                        description:
                            "Tienes que alcanzar el volumen de primas marcado para tu perfil.",
                      ),
                      const SizedBox(height: 14),
                      _objectiveCard(
                        title: "Objetivo Decesos + Vida",
                        current:
                            "${porcentajeDV.toStringAsFixed(2)}%",
                        target: "30%",
                        progress: progresoDV,
                        ok: objetivoDVOk,
                        icon: Icons.shield_rounded,
                        color: Colors.greenAccent,
                        description:
                            "Mínimo requerido de producción en Decesos y Vida.",
                      ),
                      const SizedBox(height: 20),
                      _statusPanel(
                        objetivoPrimasOk: objetivoPrimasOk,
                        objetivoDVOk: objetivoDVOk,
                        objetivoGeneralOk: objetivoGeneralOk,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(bool objetivoGeneralOk) {
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
                "Objetivos",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                "Control de primas y Decesos + Vida",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: objetivoGeneralOk
                ? Colors.greenAccent.withOpacity(0.13)
                : Colors.orangeAccent.withOpacity(0.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: objetivoGeneralOk
                  ? Colors.greenAccent.withOpacity(0.30)
                  : Colors.orangeAccent.withOpacity(0.30),
            ),
          ),
          child: Icon(
            objetivoGeneralOk
                ? Icons.verified_rounded
                : Icons.rocket_launch_rounded,
            color: objetivoGeneralOk ? Colors.greenAccent : Colors.orangeAccent,
            size: 25,
          ),
        ),
      ],
    );
  }

  Widget _heroCard({
    required bool objetivoGeneralOk,
    required double progresoPrimas,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF062C68),
            Color(0xFF10114A),
            Color(0xFF050B12),
          ],
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.24),
            blurRadius: 35,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -20,
            child: Icon(
              objetivoGeneralOk
                  ? Icons.emoji_events_rounded
                  : Icons.track_changes_rounded,
              color: objetivoGeneralOk
                  ? Colors.amberAccent.withOpacity(0.16)
                  : Colors.cyanAccent.withOpacity(0.12),
              size: 145,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roleLabel.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "${primaNeta.toStringAsFixed(0)} €",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 50,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "de ${objetivoPrimas.toStringAsFixed(0)} € en primas",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: LinearProgressIndicator(
                  value: progresoPrimas,
                  minHeight: 9,
                  backgroundColor: Colors.white.withOpacity(0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    objetivoGeneralOk ? Colors.greenAccent : Colors.cyanAccent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _statusChip(
                    objetivoGeneralOk ? "Objetivo OK" : "En progreso",
                    objetivoGeneralOk ? Colors.greenAccent : Colors.orangeAccent,
                    objetivoGeneralOk
                        ? Icons.check_circle_rounded
                        : Icons.auto_graph_rounded,
                  ),
                  const Spacer(),
                  Text(
                    "${(progresoPrimas * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniResumeCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.16),
            Colors.white.withOpacity(0.045),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.24),
        ),
      ),
      child: Row(
        children: [
          _premiumIcon(icon, color, 44),
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
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectiveCard({
    required String title,
    required String current,
    required String target,
    required double progress,
    required bool ok,
    required IconData icon,
    required Color color,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: ok
              ? Colors.greenAccent.withOpacity(0.24)
              : Colors.white.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _premiumIcon(icon, ok ? Colors.greenAccent : color, 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _statusChip(
                ok ? "OK" : "FALTA",
                ok ? Colors.greenAccent : Colors.redAccent,
                ok ? Icons.check_rounded : Icons.close_rounded,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                current,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Text(
                target,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(
                ok ? Colors.greenAccent : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel({
    required bool objetivoPrimasOk,
    required bool objetivoDVOk,
    required bool objetivoGeneralOk,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            objetivoGeneralOk
                ? Colors.greenAccent.withOpacity(0.14)
                : Colors.orangeAccent.withOpacity(0.12),
            Colors.white.withOpacity(0.045),
          ],
        ),
        border: Border.all(
          color: objetivoGeneralOk
              ? Colors.greenAccent.withOpacity(0.28)
              : Colors.orangeAccent.withOpacity(0.24),
        ),
      ),
      child: Row(
        children: [
          _premiumIcon(
            objetivoGeneralOk
                ? Icons.emoji_events_rounded
                : Icons.rocket_launch_rounded,
            objetivoGeneralOk ? Colors.amberAccent : Colors.orangeAccent,
            58,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              objetivoGeneralOk
                  ? "Perfecto. Cumples primas y el mínimo de Decesos + Vida."
                  : _mensajePendiente(objetivoPrimasOk, objetivoDVOk),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _mensajePendiente(bool primasOk, bool dvOk) {
    if (!primasOk && !dvOk) {
      return "Todavía faltan primas y también subir el porcentaje de Decesos + Vida.";
    }

    if (!primasOk) {
      return "El porcentaje de Decesos + Vida está bien. Ahora falta alcanzar primas.";
    }

    return "Las primas están conseguidas. Falta llegar al 30% en Decesos + Vida.";
  }

  Widget _statusChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
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
}

class _ObjetivoBackground extends StatelessWidget {
  const _ObjetivoBackground();

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