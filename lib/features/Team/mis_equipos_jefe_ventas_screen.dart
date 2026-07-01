import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MisEquiposJefeVentasScreen extends StatefulWidget {
  const MisEquiposJefeVentasScreen({super.key});

  @override
  State<MisEquiposJefeVentasScreen> createState() =>
      _MisEquiposJefeVentasScreenState();
}

class _MisEquiposJefeVentasScreenState
    extends State<MisEquiposJefeVentasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  Map<String, dynamic>? jefeVentas;
  List<Map<String, dynamic>> equipos = [];

  @override
  void initState() {
    super.initState();
    cargarEquipos();
  }

  Future<void> cargarEquipos() async {
    try {
      setState(() {
        loading = true;
        error = null;
      });

      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          loading = false;
          error = 'No hay usuario iniciado.';
        });
        return;
      }

      final jefeVentasRes = await supabase
          .from('usuarios')
          .select()
          .eq('auth_id', user.id)
          .single();

      final jefesEquipo = await supabase
          .from('usuarios')
          .select()
          .eq('parent_id', jefeVentasRes['id'])
          .eq('rol_usuario', 'jefe_equipo');

      final List<Map<String, dynamic>> resultado = [];

      for (final jefe in jefesEquipo) {
        final agentes = await supabase
            .from('usuarios')
            .select()
            .eq('parent_id', jefe['id'])
            .eq('rol_usuario', 'agente');

        int clientesEquipo = 0;
        int ventasEquipo = 0;

        final List<Map<String, dynamic>> agentesProcesados = [];

        for (final agente in agentes) {
          final clientes = await supabase
              .from('clientes')
              .select('id')
              .eq('auth_id', agente['auth_id']);

          final ventas = await supabase
              .from('ventas')
              .select('id')
              .eq('agente_auth_id', agente['auth_id']);

          clientesEquipo += clientes.length;
          ventasEquipo += ventas.length;

          agentesProcesados.add({
            ...Map<String, dynamic>.from(agente),
            'clientes': clientes.length,
            'ventas': ventas.length,
          });
        }

        agentesProcesados.sort((a, b) {
          final ventasA = a['ventas'] ?? 0;
          final ventasB = b['ventas'] ?? 0;
          return ventasB.compareTo(ventasA);
        });

        resultado.add({
          'jefe': Map<String, dynamic>.from(jefe),
          'agentes': agentesProcesados,
          'clientesEquipo': clientesEquipo,
          'ventasEquipo': ventasEquipo,
        });
      }

      resultado.sort((a, b) {
        final ventasA = a['ventasEquipo'] ?? 0;
        final ventasB = b['ventasEquipo'] ?? 0;
        return ventasB.compareTo(ventasA);
      });

      setState(() {
        jefeVentas = Map<String, dynamic>.from(jefeVentasRes);
        equipos = resultado;
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR EQUIPOS: $e");

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  int get totalJefesEquipo => equipos.length;

  int get totalAgentes {
    return equipos.fold<int>(
      0,
      (total, e) => total + ((e['agentes'] as List?)?.length ?? 0),
    );
  }

  int get totalClientes {
    return equipos.fold<int>(
      0,
      (total, e) => total + ((e['clientesEquipo'] ?? 0) as int),
    );
  }

  int get totalVentas {
    return equipos.fold<int>(
      0,
      (total, e) => total + ((e['ventasEquipo'] ?? 0) as int),
    );
  }

  String _nombreCompleto(Map<String, dynamic>? u) {
    if (u == null) return 'Sin nombre';

    final nombre = u['nombre']?.toString() ?? '';
    final apellidos = u['apellidos']?.toString() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isEmpty) return u['email']?.toString() ?? 'Sin nombre';

    return completo;
  }

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(' ').where((e) => e.isNotEmpty).toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();

    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  double _rendimientoEquipo(Map<String, dynamic> equipo) {
    final ventas = (equipo['ventasEquipo'] ?? 0) as int;
    final agentes = (equipo['agentes'] as List?)?.length ?? 0;

    if (agentes == 0) return 0;

    return (ventas / (agentes * 10)).clamp(0.0, 1.0);
  }

  Color _rendimientoColor(double value) {
    if (value >= 0.75) return Colors.greenAccent;
    if (value >= 0.45) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _rendimientoTexto(double value) {
    if (value >= 0.75) return 'Equipo fuerte';
    if (value >= 0.45) return 'En crecimiento';
    return 'Necesita impulso';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _EquiposBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF0F172A),
                    onRefresh: cargarEquipos,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                      children: [
                        _header(),
                        const SizedBox(height: 20),

                        if (error != null)
                          _errorCard()
                        else ...[
                          _directorCard(),
                          const SizedBox(height: 16),
                          _kpiResumen(),
                          const SizedBox(height: 20),
                          _sectionTitle(),
                          const SizedBox(height: 14),

                          if (equipos.isEmpty)
                            _emptyCard()
                          else
                            ...equipos.map(_equipoTreeCard),
                        ],
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
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.16),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mi estructura',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Organigrama comercial del jefe de ventas',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.cyanAccent.withOpacity(0.12),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.38),
            ),
          ),
          child: const Icon(
            Icons.account_tree_rounded,
            color: Colors.cyanAccent,
          ),
        ),
      ],
    );
  }

  Widget _directorCard() {
    final nombre = _nombreCompleto(jefeVentas);

    return _glassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.38),
                  Colors.purpleAccent.withOpacity(0.25),
                ],
              ),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.50),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.22),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _iniciales(nombre),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            nombre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.34),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.cyanAccent,
                  size: 17,
                ),
                SizedBox(width: 7),
                Text(
                  'Jefe de ventas',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 42,
            width: 2,
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estructura comercial',
            style: TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiResumen() {
    return Row(
      children: [
        Expanded(
          child: _kpiBox(
            title: 'Jefes',
            value: totalJefesEquipo.toString(),
            icon: Icons.supervisor_account_rounded,
            color: Colors.purpleAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: 'Agentes',
            value: totalAgentes.toString(),
            icon: Icons.groups_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: 'Ventas',
            value: totalVentas.toString(),
            icon: Icons.trending_up_rounded,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        const Icon(
          Icons.account_tree_rounded,
          color: Colors.cyanAccent,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Árbol de equipos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '$totalClientes clientes',
          style: const TextStyle(
            color: Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _equipoTreeCard(Map<String, dynamic> equipo) {
    final jefe = equipo['jefe'] as Map<String, dynamic>;
    final agentes = List<Map<String, dynamic>>.from(equipo['agentes']);
    final nombreJefe = _nombreCompleto(jefe);

    final rendimiento = _rendimientoEquipo(equipo);
    final rendimientoColor = _rendimientoColor(rendimiento);

    return _glassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: Colors.cyanAccent,
          collapsedIconColor: Colors.white70,
          initiallyExpanded: true,
          title: Row(
            children: [
              _avatar(
                nombreJefe,
                Colors.purpleAccent,
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreJefe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${agentes.length} agentes • ${equipo['clientesEquipo']} clientes • ${equipo['ventasEquipo']} ventas',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: rendimiento,
                      minHeight: 9,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(rendimientoColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _rendimientoTexto(rendimiento),
                  style: TextStyle(
                    color: rendimientoColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          children: [
            _treeConnector(),

            if (agentes.isEmpty)
              _emptyAgents()
            else
              ...agentes.map((a) => _agenteNode(a)),
          ],
        ),
      ),
    );
  }

  Widget _treeConnector() {
    return Row(
      children: [
        const SizedBox(width: 27),
        Container(
          width: 2,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.28),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const Expanded(
          child: SizedBox(),
        ),
      ],
    );
  }

  Widget _agenteNode(Map<String, dynamic> agente) {
    final nombre = _nombreCompleto(agente);
    final ventas = agente['ventas'] ?? 0;
    final clientes = agente['clientes'] ?? 0;

    final Color estadoColor = ventas >= 10
        ? Colors.greenAccent
        : ventas >= 4
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 2,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1C2E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: estadoColor.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  _avatar(nombre, Colors.cyanAccent, size: 46),
                  const SizedBox(width: 12),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _miniPill(
                              Icons.people_alt_rounded,
                              '$clientes clientes',
                              Colors.cyanAccent,
                            ),
                            _miniPill(
                              Icons.trending_up_rounded,
                              '$ventas ventas',
                              estadoColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    ventas >= 10
                        ? Icons.emoji_events_rounded
                        : ventas >= 4
                            ? Icons.bolt_rounded
                            : Icons.priority_high_rounded,
                    color: estadoColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String nombre, Color color, {double size = 50}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.34),
            Colors.blueAccent.withOpacity(0.16),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _iniciales(nombre),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _miniPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.27),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyAgents() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.white54),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este jefe de equipo todavía no tiene agentes asignados.',
              style: TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return _glassCard(
      child: const Column(
        children: [
          Icon(
            Icons.account_tree_outlined,
            color: Colors.white38,
            size: 64,
          ),
          SizedBox(height: 12),
          Text(
            'Sin estructura asignada',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Cuando tengas jefes de equipo y agentes asignados aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _glassCard(
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.orangeAccent,
            size: 52,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar la estructura',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    EdgeInsets? margin,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.075),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EquiposBackground extends StatelessWidget {
  const _EquiposBackground();

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
                Color(0xFF020617),
                Color(0xFF061A2D),
                Color(0xFF0B1026),
              ],
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _glow(260, Colors.cyanAccent),
        ),
        Positioned(
          bottom: 160,
          left: -120,
          child: _glow(280, Colors.purpleAccent),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: _glow(240, Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}