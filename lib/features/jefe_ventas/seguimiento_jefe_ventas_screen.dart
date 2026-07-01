import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class SeguimientoJefeVentasScreen extends StatefulWidget {
  const SeguimientoJefeVentasScreen({super.key});

  @override
  State<SeguimientoJefeVentasScreen> createState() =>
      _SeguimientoJefeVentasScreenState();
}

class _SeguimientoJefeVentasScreenState
    extends State<SeguimientoJefeVentasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  String? myUserId;

  List<Map<String, dynamic>> equipos = [];
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> contactosData = [];

  String selectedEquipo = 'Todos';

  Map<String, List<String>> equipoAuthIds = {};

  DateTime? fromDate;
  DateTime? toDate;

  static const Color bg = Color(0xFF07111D);
  static const Color card = Color(0xFF101C2B);
  static const Color card2 = Color(0xFF132437);
  static const Color blue = Color(0xFF4DA3FF);
  static const Color green = Color(0xFF31D0AA);
  static const Color orange = Color(0xFFFFB020);
  static const Color red = Color(0xFFFF5C7A);

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final me = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      myUserId = me['id'].toString();

      final jefesEquipo = await supabase
          .from('usuarios')
          .select('id, auth_id, nombre')
          .eq('parent_id', myUserId!)
          .eq('rol_usuario', 'jefe_equipo');

      List<Map<String, dynamic>> listaEquipos = [];
      Map<String, List<String>> mapaEquipos = {};

      for (final jefe in jefesEquipo) {
        final agentes = await supabase
            .from('usuarios')
            .select('auth_id')
            .eq('parent_id', jefe['id'])
            .eq('rol_usuario', 'agente');

        final ids = agentes
            .map<String>((e) => e['auth_id'].toString())
            .toList();

        listaEquipos.add({
          "nombre": jefe['nombre'] ?? 'Sin nombre',
        });

        mapaEquipos[jefe['nombre'] ?? 'Sin nombre'] = ids;
      }

      equipos = listaEquipos;
      equipoAuthIds = mapaEquipos;

      List<String> ids = [];

      for (final lista in equipoAuthIds.values) {
        ids.addAll(lista);
      }

      ids.add(user.id);

      final contactosRes = await supabase
          .from('contactos_diarios')
          .select('contactos_positivos, auth_id');

      contactosData = List<Map<String, dynamic>>.from(contactosRes)
          .where((c) => ids.contains(c['auth_id']))
          .toList();

      final salesRes = await supabase
          .from('ventas')
          .select('*')
          .inFilter('agente_auth_id', ids)
          .order('fecha_efecto', ascending: false);

      sales = List<Map<String, dynamic>>.from(salesRes);

      setState(() => loading = false);
    } catch (e) {
      debugPrint("ERROR SEGUIMIENTO JEFE VENTAS: $e");
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get filteredSales {
    return sales.where((s) {
      if (s['fecha_efecto'] == null) return false;

      final date = DateTime.parse(s['fecha_efecto']);

      bool equipoOk = true;

      if (selectedEquipo != 'Todos') {
        final idsEquipo = equipoAuthIds[selectedEquipo] ?? [];
        equipoOk = idsEquipo.contains(s['agente_auth_id']);
      }

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

      return equipoOk && fromOk && toOk;
    }).toList();
  }

  List<Map<String, dynamic>> get filteredContactos {
    if (selectedEquipo == 'Todos') return contactosData;

    final idsEquipo = equipoAuthIds[selectedEquipo] ?? [];

    return contactosData
        .where((c) => idsEquipo.contains(c['auth_id']))
        .toList();
  }

  double calcPrima(Map<String, dynamic> s) {
    final price = double.tryParse((s['precio'] ?? 0).toString()) ?? 0;

    final form = (s['forma_pago'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

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
      filteredSales.fold<double>(0, (sum, s) => sum + calcPrima(s));

  double get mediaPrima =>
      filteredSales.isEmpty ? 0 : totalPrima / filteredSales.length;

  double get mediaVentas =>
      filteredSales.isEmpty ? 0 : totalVentas.toDouble();

  int get totalContactosPositivos {
    return filteredContactos.fold<int>(
      0,
      (sum, c) {
        final value = int.tryParse(
              (c['contactos_positivos'] ?? 0).toString(),
            ) ??
            0;
        return sum + value;
      },
    );
  }

  double get eficaciaEquipo {
    if (filteredSales.isEmpty) return 0;
    if (totalContactosPositivos == 0) return 0;

    return totalVentas / totalContactosPositivos;
  }

  Map<String, int> get productos {
    Map<String, int> map = {};

    for (final s in filteredSales) {
      final p = (s['producto'] ?? 'Sin producto').toString();
      map[p] = (map[p] ?? 0) + 1;
    }

    return map;
  }

  List<FlSpot> get monthlySalesSpots {
    final now = DateTime.now();
    Map<int, double> totals = {};

    for (final sale in filteredSales) {
      if (sale['fecha_efecto'] == null) continue;

      final date = DateTime.parse(sale['fecha_efecto']);

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

  String money(double value) {
    return "${value.toStringAsFixed(2).replaceAll('.', ',')} €";
  }

  String shortDate(DateTime? date) {
    if (date == null) return '';
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  Future<void> pickDate(bool isFrom) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: blue,
              surface: card,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null) return;

    setState(() {
      if (isFrom) {
        fromDate = date;
      } else {
        toDate = date;
      }
    });
  }

  void clearFilters() {
    setState(() {
      selectedEquipo = 'Todos';
      fromDate = null;
      toDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        title: const Text(
          "Seguimiento Comercial",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: blue),
            )
          : RefreshIndicator(
              onRefresh: loadData,
              color: blue,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    _filters(),
                    const SizedBox(height: 18),
                    _kpiGrid(),
                    const SizedBox(height: 18),
                    monthlySalesChart(),
                    const SizedBox(height: 18),
                    _productosSection(),
                    const SizedBox(height: 30),
                  ],
                ),
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Panel ejecutivo de ventas",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selectedEquipo == 'Todos'
                ? "Visualizando toda tu estructura comercial"
                : "Visualizando equipo: $selectedEquipo",
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniBadge("Equipos", equipos.length.toString(), blue),
              const SizedBox(width: 10),
              _miniBadge("Ventas", totalVentas.toString(), green),
              const SizedBox(width: 10),
              _miniBadge("Prima", money(totalPrima), orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Filtros de análisis",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: card2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: DropdownButton<String>(
              value: selectedEquipo,
              dropdownColor: card2,
              iconEnabledColor: Colors.white,
              underline: const SizedBox(),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem(
                  value: 'Todos',
                  child: Text('Toda la estructura'),
                ),
                ...equipos.map(
                  (e) => DropdownMenuItem<String>(
                    value: e['nombre'],
                    child: Text(e['nombre']),
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => selectedEquipo = v);
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  title: fromDate == null ? "Desde" : shortDate(fromDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: () => pickDate(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton(
                  title: toDate == null ? "Hasta" : shortDate(toDate),
                  icon: Icons.event_available_rounded,
                  onTap: () => pickDate(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: clearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text("Limpiar filtros"),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: card2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _kpiCard(
          "Ventas",
          totalVentas.toString(),
          Icons.shopping_bag_rounded,
          blue,
        ),
        _kpiCard(
          "Prima total",
          money(totalPrima),
          Icons.euro_rounded,
          green,
        ),
        _kpiCard(
          "Prima media",
          money(mediaPrima),
          Icons.trending_up_rounded,
          orange,
        ),
        _kpiCard(
          "Eficacia",
          "${(eficaciaEquipo * 100).toStringAsFixed(1)}%",
          Icons.speed_rounded,
          red,
        ),
      ],
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget monthlySalesChart() {
    final spots = monthlySalesSpots;

    final double highest = spots.isEmpty
        ? 100
        : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    final double chartMaxY = highest <= 0 ? 100 : highest * 1.25;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Evolución de prima este mes",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Importe diario según fecha de efecto",
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMaxY / 4,
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
                      reservedSize: 44,
                      interval: chartMaxY / 4,
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

                        if (day != 1 && day % 5 != 0) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            day.toString(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Colors.black87,
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.all(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          money(spot.y),
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
                    color: blue,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          blue.withOpacity(0.28),
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

  Widget _productosSection() {
    final entries = productos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Distribución por productos",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              "No hay ventas para los filtros seleccionados.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
              ),
            )
          else
            ...entries.map((e) {
              final percent =
                  totalVentas == 0 ? 0 : (e.value / totalVentas) * 100;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          "${e.value} ventas",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: percent / 100,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        color: blue,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}