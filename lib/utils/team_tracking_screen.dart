import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class TeamTrackingScreen extends StatefulWidget {
  const TeamTrackingScreen({super.key});

  @override
  State<TeamTrackingScreen> createState() => _TeamTrackingScreenState();
}

class _TeamTrackingScreenState extends State<TeamTrackingScreen> {
  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  String? myUserId;

  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> sales = [];

  String selectedAgent = 'Todos';

  DateTime? fromDate;
  DateTime? toDate;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (isRefresh) {
        refreshing = true;
      } else {
        loading = true;
      }
      errorMessage = null;
    });

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "Usuario no autenticado";
      });
      return;
    }

    try {
      final me = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      myUserId = me['id'];

      final agentsRes = await supabase
          .from('usuarios')
          .select('auth_id, nombre, apellidos')
          .eq('parent_id', myUserId!)
          .order('nombre', ascending: true);

      agents = List<Map<String, dynamic>>.from(agentsRes);

      final ids = agents.map((e) => e['auth_id'].toString()).toList();

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          sales = [];
          loading = false;
          refreshing = false;
        });
        return;
      }

      final salesRes = await supabase
          .from('ventas')
          .select('*')
          .inFilter('agente_auth_id', ids)
          .order('fecha_efecto', ascending: false);

      if (!mounted) return;

      setState(() {
        sales = List<Map<String, dynamic>>.from(salesRes);
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("ERROR TEAM TRACKING: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudo cargar el seguimiento del equipo";
      });
    }
  }

  List<Map<String, dynamic>> get filteredSales {
    return sales.where((s) {
      if (s['fecha_efecto'] == null) return false;

      final date = DateTime.tryParse(s['fecha_efecto'].toString());
      if (date == null) return false;

      final agentOk =
          selectedAgent == 'Todos' || s['agente_auth_id'] == selectedAgent;

      final saleDate = DateTime(date.year, date.month, date.day);

      bool fromOk = true;
      bool toOk = true;

      if (fromDate != null) {
        final from = DateTime(
          fromDate!.year,
          fromDate!.month,
          fromDate!.day,
        );

        fromOk = !saleDate.isBefore(from);
      }

      if (toDate != null) {
        final to = DateTime(
          toDate!.year,
          toDate!.month,
          toDate!.day,
        );

        toOk = !saleDate.isAfter(to);
      }

      return agentOk && fromOk && toOk;
    }).toList();
  }

  double calcPrima(Map<String, dynamic> s) {
    final price = double.tryParse(s['precio'].toString()) ?? 0;

    final form = (s['forma_pago'] ?? '').toString().trim().toLowerCase();

    switch (form) {
      case 'mensual':
        return price * 12;
      case 'trimestral':
        return price * 4;
      case 'semestral':
        return price * 2;
      case 'anual':
        return price;
      default:
        return price;
    }
  }

  int get totalVentas => filteredSales.length;

  double get totalPrima =>
      filteredSales.fold(0, (sum, s) => sum + calcPrima(s));

  double get mediaPrima =>
      filteredSales.isEmpty ? 0 : totalPrima / filteredSales.length;

  double get mediaVentas => filteredSales.isEmpty ? 0 : totalVentas.toDouble();

  Map<String, int> get productos {
    final Map<String, int> map = {};

    for (final s in filteredSales) {
      final p = (s['producto'] ?? 'Sin producto').toString();
      map[p] = (map[p] ?? 0) + 1;
    }

    return map;
  }

  List<FlSpot> get monthlySalesSpots {
    final now = DateTime.now();
    final Map<int, double> totals = {};

    for (final sale in filteredSales) {
      if (sale['fecha_efecto'] == null) continue;

      final date = DateTime.tryParse(sale['fecha_efecto'].toString());
      if (date == null) continue;

      if (date.month != now.month || date.year != now.year) continue;

      final prima = calcPrima(sale);

      totals.update(
        date.day,
        (value) => value + prima,
        ifAbsent: () => prima,
      );
    }

    final lastDay = DateTime(now.year, now.month + 1, 0).day;

    return List.generate(
      lastDay,
      (index) {
        final day = index + 1;
        return FlSpot(day.toDouble(), totals[day] ?? 0);
      },
    );
  }

  double get chartMaxY {
    if (monthlySalesSpots.isEmpty) return 100;

    final maxValue =
        monthlySalesSpots.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    if (maxValue <= 0) return 100;

    return maxValue * 1.25;
  }

  String get selectedAgentName {
    if (selectedAgent == 'Todos') return 'Todo el equipo';

    final agent = agents.firstWhere(
      (a) => a['auth_id'] == selectedAgent,
      orElse: () => {},
    );

    if (agent.isEmpty) return 'Agente';

    return "${agent['nombre'] ?? ''} ${agent['apellidos'] ?? ''}".trim();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "Sin fecha";
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return "$d/$m/${date.year}";
  }

  void _clearFilters() {
    setState(() {
      selectedAgent = 'Todos';
      fromDate = null;
      toDate = null;
    });
  }

  Future<void> _pickFromDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: _datePickerTheme,
    );

    if (date != null) {
      setState(() => fromDate = date);
    }
  }

  Future<void> _pickToDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: _datePickerTheme,
    );

    if (date != null) {
      setState(() => toDate = date);
    }
  }

  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF0F172A),
          onSurface: Colors.white,
        ),
      ),
      child: child!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        title: const Text(
          "Seguimiento Equipo",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Actualizar",
            onPressed: refreshing ? null : () => loadData(isRefresh: true),
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
          const _TrackingBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF38BDF8),
                    backgroundColor: const Color(0xFF0F172A),
                    onRefresh: () => loadData(isRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        _HeaderPanel(
                          agents: agents.length,
                          sales: totalVentas,
                          totalPrima: totalPrima,
                          selectedAgentName: selectedAgentName,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBox(
                            message: errorMessage!,
                            onRetry: () => loadData(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _FiltersPanel(
                          agents: agents,
                          selectedAgent: selectedAgent,
                          fromDate: fromDate,
                          toDate: toDate,
                          formatDate: _formatDate,
                          onAgentChanged: (value) {
                            if (value == null) return;
                            setState(() => selectedAgent = value);
                          },
                          onFromTap: _pickFromDate,
                          onToTap: _pickToDate,
                          onClear: _clearFilters,
                        ),
                        const SizedBox(height: 20),
                        _MonthlySalesChart(
                          spots: monthlySalesSpots,
                          maxY: chartMaxY,
                        ),
                        const SizedBox(height: 20),
                        _KpiGrid(
                          totalVentas: totalVentas,
                          mediaVentas: mediaVentas,
                          totalPrima: totalPrima,
                          mediaPrima: mediaPrima,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          title: "Productos",
                          subtitle: "Distribución de ventas por producto",
                        ),
                        const SizedBox(height: 12),
                        if (productos.isEmpty)
                          const _EmptyProductsState()
                        else
                          ...productos.entries.map(
                            (e) => _ProductRow(
                              product: e.key,
                              count: e.value,
                              total: totalVentas,
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

class _TrackingBackground extends StatelessWidget {
  const _TrackingBackground();

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

class _HeaderPanel extends StatelessWidget {
  final int agents;
  final int sales;
  final double totalPrima;
  final String selectedAgentName;

  const _HeaderPanel({
    required this.agents,
    required this.sales,
    required this.totalPrima,
    required this.selectedAgentName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
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
      child: Column(
        children: [
          Row(
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
                  Icons.analytics_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Panel comercial",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedAgentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeaderMetric(
                  label: "Agentes",
                  value: agents.toString(),
                  icon: Icons.groups_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMetric(
                  label: "Ventas",
                  value: sales.toString(),
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMetric(
                  label: "Prima",
                  value: "${totalPrima.toStringAsFixed(0)}€",
                  icon: Icons.euro_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF7DD3FC),
            size: 21,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.50),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  final List<Map<String, dynamic>> agents;
  final String selectedAgent;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String Function(DateTime?) formatDate;
  final ValueChanged<String?> onAgentChanged;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback onClear;

  const _FiltersPanel({
    required this.agents,
    required this.selectedAgent,
    required this.fromDate,
    required this.toDate,
    required this.formatDate,
    required this.onAgentChanged,
    required this.onFromTap,
    required this.onToTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        selectedAgent != 'Todos' || fromDate != null || toDate != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Filtros de seguimiento",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text("Limpiar"),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedAgent,
                isExpanded: true,
                dropdownColor: const Color(0xFF102331),
                iconEnabledColor: Colors.white70,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'Todos',
                    child: Text('Todo el equipo'),
                  ),
                  ...agents.map(
                    (a) => DropdownMenuItem(
                      value: a['auth_id'],
                      child: Text(
                        "${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}".trim(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: onAgentChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateFilterButton(
                  label: "Desde",
                  value: fromDate == null ? "Seleccionar" : formatDate(fromDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: onFromTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateFilterButton(
                  label: "Hasta",
                  value: toDate == null ? "Seleccionar" : formatDate(toDate),
                  icon: Icons.event_available_rounded,
                  onTap: onToTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateFilterButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value != "Seleccionar";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF38BDF8).withOpacity(0.35)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? const Color(0xFF7DD3FC)
                    : Colors.white.withOpacity(0.42),
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.46),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlySalesChart extends StatelessWidget {
  final List<FlSpot> spots;
  final double maxY;

  const _MonthlySalesChart({
    required this.spots,
    required this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: "Ventas este mes",
            subtitle: "Prima anualizada acumulada por día",
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withOpacity(0.05),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final day = value.toInt();

                        if (day % 5 != 0 && day != 1) {
                          return const SizedBox.shrink();
                        }

                        return Text(
                          day.toString(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.black87,
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.all(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          "${spot.y.toStringAsFixed(0)} €",
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    barWidth: 3.5,
                    color: const Color(0xFF4DA3FF),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4DA3FF).withOpacity(0.25),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
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
}

class _KpiGrid extends StatelessWidget {
  final int totalVentas;
  final double mediaVentas;
  final double totalPrima;
  final double mediaPrima;

  const _KpiGrid({
    required this.totalVentas,
    required this.mediaVentas,
    required this.totalPrima,
    required this.mediaPrima,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: "Ventas",
                value: totalVentas.toString(),
                icon: Icons.shopping_cart_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: "Ventas media",
                value: mediaVentas.toStringAsFixed(0),
                icon: Icons.trending_up_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: "Prima total",
                value: "${totalPrima.toStringAsFixed(2)}€",
                icon: Icons.euro_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: "Prima media",
                value: "${mediaPrima.toStringAsFixed(2)}€",
                icon: Icons.analytics_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF7DD3FC),
              size: 22,
            ),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  final String product;
  final int count;
  final int total;

  const _ProductRow({
    required this.product,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : count / total;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: Color(0xFF86EFAC),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  product,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "$count",
                style: const TextStyle(
                  color: Color(0xFFBAE6FD),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: percent,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF38BDF8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  const _EmptyProductsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin productos en este filtro",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Cuando existan ventas para el filtro seleccionado, aparecerán agrupadas aquí.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
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