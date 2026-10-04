import 'package:flutter/material.dart';
import '../../core/production/premium_weighting.dart';
import '../../core/production/production_period_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProduccionEquipoScreen extends StatefulWidget {
  const ProduccionEquipoScreen({super.key});

  @override
  State<ProduccionEquipoScreen> createState() => _ProduccionEquipoScreenState();
}

class _ProduccionEquipoScreenState extends State<ProduccionEquipoScreen> {
  final supabase = Supabase.instance.client;

  double produccionEquipo = 0;
  int ventasHoy = 0;
  int agentesEquipo = 0;
  double mixEquipo = 0;
  ProductionPeriod? periodo;

  List<Map<String, dynamic>> ranking = [];

  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos({bool isRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      refreshing = isRefresh;
      if (!isRefresh) loading = true;
      errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('Usuario no autenticado');

      final currentPeriod = await ProductionPeriodService.instance.current(
        forceRefresh: isRefresh,
      );
      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', currentUser.id)
          .maybeSingle();
      if (jefe == null) throw Exception('No se encontró el jefe de equipo');

      final rawUsers = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, nombre, apellidos, rol_usuario')
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          );
      final users = List<Map<String, dynamic>>.from(rawUsers);
      final byParent = <String, List<Map<String, dynamic>>>{};
      for (final item in users) {
        final parentId = (item['parent_id'] ?? '').toString().trim();
        if (parentId.isNotEmpty && parentId != 'null') {
          byParent.putIfAbsent(parentId, () => []).add(item);
        }
      }

      final descendants = <Map<String, dynamic>>[];
      final visited = <String>{};
      void walk(String parentId) {
        for (final child in byParent[parentId] ?? const []) {
          final childId = (child['id'] ?? '').toString().trim();
          if (childId.isEmpty || !visited.add(childId)) continue;
          descendants.add(child);
          walk(childId);
        }
      }

      walk(jefe['id'].toString());
      final agentes = descendants.where((item) {
        final role = (item['rol_usuario'] ?? '')
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_');
        final authId = (item['auth_id'] ?? '').toString().trim();
        return role == 'agente' && authId.isNotEmpty && authId != 'null';
      }).toList();

      final ventas = <Map<String, dynamic>>[];
      final authIds = agentes
          .map((item) => item['auth_id'].toString())
          .toList();
      final from = _databaseDate(currentPeriod.start);
      final to = _databaseDate(currentPeriod.endExclusive);

      for (var offset = 0; offset < authIds.length; offset += 100) {
        final chunk = authIds.skip(offset).take(100).toList();
        for (var page = 0; ; page += 1000) {
          final rows = await supabase
              .from('ventas')
              .select(
                'id, agente_auth_id, prima_anual_neta, producto, fecha_efecto',
              )
              .inFilter('agente_auth_id', chunk)
              .gte('fecha_efecto', from)
              .lt('fecha_efecto', to)
              .order('id')
              .range(page, page + 999);
          ventas.addAll(List<Map<String, dynamic>>.from(rows));
          if (rows.length < 1000) break;
        }
      }

      final ventasPorAgente = <String, List<Map<String, dynamic>>>{};
      for (final venta in ventas) {
        final authId = (venta['agente_auth_id'] ?? '').toString();
        ventasPorAgente.putIfAbsent(authId, () => []).add(venta);
      }

      var total = 0.0;
      var totalMix = 0.0;
      final detalle = <Map<String, dynamic>>[];
      for (final agente in agentes) {
        final authId = agente['auth_id'].toString();
        final ventasAgente = ventasPorAgente[authId] ?? const [];
        var primas = 0.0;
        var primasMix = 0.0;
        for (final venta in ventasAgente) {
          final prima = PremiumWeighting.net(venta);
          primas += prima;
          if (_esMix(venta['producto'])) primasMix += prima;
        }
        total += primas;
        totalMix += primasMix;
        final nombre = '${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}'
            .trim();
        detalle.add({
          'nombre': nombre.isEmpty ? 'Agente sin nombre' : nombre,
          'produccion': primas,
          'mix_primas': primasMix,
          'mix_porcentaje': primas <= 0 ? 0.0 : primasMix / primas * 100,
          'polizas': ventasAgente.length,
        });
      }
      detalle.sort(
        (a, b) =>
            (b['produccion'] as double).compareTo(a['produccion'] as double),
      );

      if (!mounted) return;
      setState(() {
        produccionEquipo = total;
        mixEquipo = totalMix;
        ventasHoy = ventas.length;
        ranking = detalle;
        agentesEquipo = agentes.length;
        periodo = currentPeriod;
        loading = false;
        refreshing = false;
      });
    } catch (error) {
      debugPrint('ERROR PRODUCCION EQUIPO: $error');
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = 'No se pudo cargar la producción del equipo';
      });
    }
  }

  bool _esMix(dynamic value) {
    final producto = (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    return producto.contains('deces') || producto.contains('vida');
  }

  String _databaseDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  double get mixPorcentaje =>
      produccionEquipo <= 0 ? 0 : mixEquipo / produccionEquipo * 100;

  String get etiquetaPeriodo {
    final value = periodo;
    if (value == null) return 'Cargo actual';
    return 'Cargo ${value.month.toString().padLeft(2, '0')}/${value.year} · '
        '${value.from.day.toString().padLeft(2, '0')}/'
        '${value.from.month.toString().padLeft(2, '0')}–'
        '${value.to.day.toString().padLeft(2, '0')}/'
        '${value.to.month.toString().padLeft(2, '0')}';
  }

  double get mejorProduccion {
    if (ranking.isEmpty) return 0;
    return ranking.first['produccion'] ?? 0;
  }

  double get mediaProduccion {
    if (ranking.isEmpty) return 0;
    return agentesEquipo == 0 ? 0 : produccionEquipo / agentesEquipo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6FB),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF13244D),
        ),
        title: const Text(
          "Producción equipo",
          style: TextStyle(
            color: const Color(0xFF071A3A),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Actualizar",
            color: const Color(0xFF13244D),
            onPressed: refreshing ? null : () => cargarDatos(isRefresh: true),
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
          const _PremiumBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2454D3)),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2454D3),
                    backgroundColor: Colors.white,
                    onRefresh: () => cargarDatos(isRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        _HeaderCard(
                          produccionEquipo: produccionEquipo,
                          ventasHoy: ventasHoy,
                          mixPorcentaje: mixPorcentaje,
                          periodo: etiquetaPeriodo,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBox(
                            message: errorMessage!,
                            onRetry: () => cargarDatos(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _KpiGrid(
                          agentes: agentesEquipo,
                          ventasHoy: ventasHoy,
                          mediaProduccion: mediaProduccion,
                          mejorProduccion: mixEquipo,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          title: "Producción por agente",
                          subtitle:
                              "Detalle individual del equipo en el cargo actual",
                        ),
                        const SizedBox(height: 12),
                        if (ranking.isEmpty)
                          const _EmptyState()
                        else
                          ...ranking.asMap().entries.map(
                            (entry) => _RankingCard(
                              position: entry.key + 1,
                              nombre: entry.value['nombre'],
                              produccion: entry.value['produccion'],
                              maxProduccion: produccionEquipo,
                              mixPrimas: entry.value['mix_primas'],
                              mixPorcentaje: entry.value['mix_porcentaje'],
                              polizas: entry.value['polizas'],
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

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4F6FB), Color(0xFFEAF1FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final double produccionEquipo;
  final int ventasHoy;
  final double mixPorcentaje;
  final String periodo;

  const _HeaderCard({
    required this.produccionEquipo,
    required this.ventasHoy,
    required this.mixPorcentaje,
    required this.periodo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF172B58), Color(0xFF2454D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13244D).withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -32,
            child: Icon(
              Icons.query_stats_rounded,
              size: 145,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.groups_rounded,
                    color: Color(0xFFCBD9FA),
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      periodo,
                      style: const TextStyle(
                        color: Color(0xFFCBD9FA),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              const Text(
                'PRODUCCIÓN TOTAL DEL EQUIPO',
                style: TextStyle(
                  color: Color(0xFFE1E9FC),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                produccionEquipo.toStringAsFixed(0) + ' €',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 39,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(
                    icon: Icons.shield_rounded,
                    text:
                        'Mix Decesos + Vida · ' +
                        mixPorcentaje.toStringAsFixed(1) +
                        '%',
                  ),
                  _MiniChip(
                    icon: Icons.description_rounded,
                    text: ventasHoy.toString() + ' pólizas',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int agentes;
  final int ventasHoy;
  final double mediaProduccion;
  final double mejorProduccion;

  const _KpiGrid({
    required this.agentes,
    required this.ventasHoy,
    required this.mediaProduccion,
    required this.mejorProduccion,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _KpiCard(
              width: width,
              title: 'Agentes activos',
              value: agentes.toString(),
              icon: Icons.people_alt_rounded,
            ),
            _KpiCard(
              width: width,
              title: 'Pólizas del cargo',
              value: ventasHoy.toString(),
              icon: Icons.description_rounded,
            ),
            _KpiCard(
              width: width,
              title: 'Media por agente',
              value: mediaProduccion.toStringAsFixed(0) + ' €',
              icon: Icons.analytics_rounded,
            ),
            _KpiCard(
              width: width,
              title: 'Primas de mix',
              value: mejorProduccion.toStringAsFixed(0) + ' €',
              icon: Icons.shield_rounded,
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE5F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2454D3), size: 23),
          const SizedBox(height: 11),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.account_tree_rounded,
          color: Color(0xFF2454D3),
          size: 23,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: const Color(0xFF071A3A),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: const Color(0xFF53627A),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankingCard extends StatelessWidget {
  final int position;
  final String nombre;
  final double produccion;
  final double maxProduccion;
  final double mixPrimas;
  final double mixPorcentaje;
  final int polizas;

  const _RankingCard({
    required this.position,
    required this.nombre,
    required this.produccion,
    required this.maxProduccion,
    required this.mixPrimas,
    required this.mixPorcentaje,
    required this.polizas,
  });

  @override
  Widget build(BuildContext context) {
    final share = maxProduccion <= 0 ? 0.0 : produccion / maxProduccion;
    final initial = nombre.isEmpty ? '?' : nombre[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE5F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13244D).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFFEAF0FF),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF2454D3),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
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
                        color: Color(0xFF0F172A),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      polizas.toString() +
                          ' pólizas · Mix ' +
                          mixPorcentaje.toStringAsFixed(1) +
                          '%',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                produccion.toStringAsFixed(0) + ' €',
                style: const TextStyle(
                  color: Color(0xFF13244D),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFFE5EBF5),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2454D3)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mix: ' + mixPrimas.toStringAsFixed(0) + ' €',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                (share * 100).toStringAsFixed(1) + '% del equipo',
                style: const TextStyle(
                  color: Color(0xFF2454D3),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE5F2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 48,
            color: const Color(0xFF2454D3),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin agentes o producción",
            style: TextStyle(
              color: const Color(0xFF071A3A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Cuando tu equipo tenga agentes y ventas registradas aparecerán aquí sus primas, pólizas y mix.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF53627A),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: const Color(0xFF071A3A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text("Reintentar")),
        ],
      ),
    );
  }
}
