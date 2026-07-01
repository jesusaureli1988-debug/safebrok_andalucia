import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DirectorNacionalKpisScreen extends StatefulWidget {
  const DirectorNacionalKpisScreen({super.key});

  @override
  State<DirectorNacionalKpisScreen> createState() =>
      _DirectorNacionalKpisScreenState();
}

class _DirectorNacionalKpisScreenState
    extends State<DirectorNacionalKpisScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> ventas = [];
  List<Map<String, dynamic>> clientes = [];

  String selectedYear = 'Todos';
  String selectedMonth = 'Todos';

  List<String> years = ['Todos'];
  List<String> months = [
    'Todos',
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

  final monthNames = const [
    '',
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

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    try {
      setState(() => loading = true);

      final usuariosData = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos');

      final ventasData = await supabase
          .from('ventas')
          .select()
          .order('created_at', ascending: false);

      final clientesData = await supabase
          .from('clientes')
          .select()
          .order('created_at', ascending: false);

      usuarios = List<Map<String, dynamic>>.from(usuariosData);
      ventas = List<Map<String, dynamic>>.from(ventasData);
      clientes = List<Map<String, dynamic>>.from(clientesData);

      _buildYears();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      debugPrint('ERROR KPIS DIRECTOR NACIONAL: $e');

      if (!mounted) return;
      setState(() {
        usuarios = [];
        ventas = [];
        clientes = [];
        loading = false;
      });
    }
  }

  void _buildYears() {
    final set = <String>{};

    for (final v in ventas) {
      final fecha = _parseDate(v);
      if (fecha != null) set.add(fecha.year.toString());
    }

    years = ['Todos', ...set.toList()..sort((a, b) => b.compareTo(a))];
  }

  DateTime? _parseDate(Map<String, dynamic> row) {
    final posibles = [
      row['fecha'],
      row['created_at'],
      row['fecha_efecto'],
      row['fecha_registro'],
    ];

    for (final value in posibles) {
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }

    return null;
  }

  List<Map<String, dynamic>> get ventasFiltradas {
    return ventas.where((v) {
      final fecha = _parseDate(v);

      final okYear = selectedYear == 'Todos' ||
          (fecha != null && fecha.year.toString() == selectedYear);

      final okMonth = selectedMonth == 'Todos' ||
          (fecha != null && monthNames[fecha.month] == selectedMonth);

      return okYear && okMonth;
    }).toList();
  }

  List<Map<String, dynamic>> get clientesFiltrados {
    return clientes.where((c) {
      final fecha = _parseDate(c);

      final okYear = selectedYear == 'Todos' ||
          (fecha != null && fecha.year.toString() == selectedYear);

      final okMonth = selectedMonth == 'Todos' ||
          (fecha != null && monthNames[fecha.month] == selectedMonth);

      return okYear && okMonth;
    }).toList();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }

  int _intValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  double get primaMensualTotal {
    return ventasFiltradas.fold(
      0,
      (sum, v) => sum + _money(v['precio']),
    );
  }

  double get primaAnualEstimada {
    return primaMensualTotal * 12;
  }

  int get aseguradosTotal {
    return ventasFiltradas.fold(
      0,
      (sum, v) => sum + _intValue(v['numero_asegurados']),
    );
  }

  int get agentesActivos {
    final authIdsConVenta = ventasFiltradas
        .map((v) => v['agente_auth_id']?.toString())
        .where((e) => e != null && e.isNotEmpty && e != 'null')
        .toSet();

    return authIdsConVenta.length;
  }

  Map<String, int> get ventasPorRol {
    final mapAuthRol = <String, String>{};

    for (final u in usuarios) {
      final authId = u['auth_id']?.toString();
      final role = u['rol_usuario']?.toString();

      if (authId != null && role != null) {
        mapAuthRol[authId] = role;
      }
    }

    final result = <String, int>{};

    for (final v in ventasFiltradas) {
      final authId = v['agente_auth_id']?.toString();
      final role = mapAuthRol[authId] ?? 'sin_rol';

      result[role] = (result[role] ?? 0) + 1;
    }

    return result;
  }

  List<MapEntry<String, int>> get rankingAgentes {
    final result = <String, int>{};
    final nombres = <String, String>{};

    for (final u in usuarios) {
      final authId = u['auth_id']?.toString();
      if (authId == null || authId.isEmpty || authId == 'null') continue;

      final nombre =
          "${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}".trim();

      nombres[authId] = nombre.isEmpty ? 'Usuario sin nombre' : nombre;
      result[authId] = 0;
    }

    for (final v in ventasFiltradas) {
      final authId = v['agente_auth_id']?.toString();
      if (authId == null || authId.isEmpty || authId == 'null') continue;

      result[authId] = (result[authId] ?? 0) + 1;
    }

    final entries = result.entries
        .where((e) => e.value > 0)
        .map((e) => MapEntry(nombres[e.key] ?? e.key, e.value))
        .toList();

    entries.sort((a, b) => b.value.compareTo(a.value));

    return entries.take(10).toList();
  }

  List<int> get ventasPorMes {
    final data = List<int>.filled(12, 0);

    for (final v in ventas) {
      final fecha = _parseDate(v);
      if (fecha == null) continue;

      if (selectedYear != 'Todos' && fecha.year.toString() != selectedYear) {
        continue;
      }

      data[fecha.month - 1]++;
    }

    return data;
  }

  double get cumplimientoObjetivo {
    const objetivoMensual = 50;

    if (selectedMonth == 'Todos') {
      return ventasFiltradas.length / (objetivoMensual * 12);
    }

    return ventasFiltradas.length / objetivoMensual;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _DirectorBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF071A3A),
                    onRefresh: cargarDatos,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _topBar()),
                        SliverToBoxAdapter(child: _hero()),
                        SliverToBoxAdapter(child: _filters()),
                        SliverToBoxAdapter(child: _kpiGrid()),
                        SliverToBoxAdapter(child: _chartCard()),
                        SliverToBoxAdapter(child: _rolesCard()),
                        SliverToBoxAdapter(child: _rankingCard()),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
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
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'KPIs Globales',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                  Color(0xFF7C3AED),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    final progreso = cumplimientoObjetivo.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF22D3EE).withOpacity(0.22),
                  const Color(0xFF071A3A).withOpacity(0.94),
                  const Color(0xFF020617).withOpacity(0.96),
                ],
              ),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visión nacional de la red',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Control total de producción, cartera, agentes activos y rendimiento comercial.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progreso,
                          minHeight: 11,
                          backgroundColor: Colors.white.withOpacity(0.10),
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(progreso * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  selectedMonth == 'Todos'
                      ? 'Cumplimiento sobre objetivo anual estimado'
                      : 'Cumplimiento sobre objetivo mensual de 50 pólizas',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Row(
        children: [
          Expanded(
            child: _filter(
              value: selectedYear,
              items: years,
              icon: Icons.date_range_rounded,
              onChanged: (v) {
                if (v == null) return;
                setState(() => selectedYear = v);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _filter(
              value: selectedMonth,
              items: months,
              icon: Icons.calendar_month_rounded,
              onChanged: (v) {
                if (v == null) return;
                setState(() => selectedMonth = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filter({
    required String value,
    required List<String> items,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : 'Todos',
                isExpanded: true,
                dropdownColor: const Color(0xFF071A3A),
                iconEnabledColor: Colors.cyanAccent,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
                items: items
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e,
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

  Widget _kpiGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        children: [
          _kpiCard(
            'Ventas',
            ventasFiltradas.length.toString(),
            Icons.receipt_long_rounded,
            Colors.cyanAccent,
          ),
          _kpiCard(
            'Asegurados',
            aseguradosTotal.toString(),
            Icons.groups_rounded,
            Colors.greenAccent,
          ),
          _kpiCard(
            'Prima mensual',
            '${primaMensualTotal.toStringAsFixed(0)} €',
            Icons.euro_rounded,
            Colors.amberAccent,
          ),
          _kpiCard(
            'Agentes activos',
            agentesActivos.toString(),
            Icons.verified_user_rounded,
            Colors.purpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bubble(icon, color),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final data = ventasPorMes;
    final maxValue = data.isEmpty
        ? 1
        : data.reduce((a, b) => a > b ? a : b).clamp(1, 999999);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(const Color(0xFF22D3EE)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evolución mensual de ventas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(12, (index) {
                  final value = data[index];
                  final height = maxValue == 0 ? 0.0 : value / maxValue;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            value.toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            height: 120 * height.clamp(0.05, 1.0),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF22D3EE),
                                  Color(0xFF2563EB),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            monthNames[index + 1].substring(0, 3),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rolesCard() {
    final roles = ventasPorRol.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(const Color(0xFFA855F7)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Producción por rol',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (roles.isEmpty)
              Text(
                'Sin datos en el periodo seleccionado.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...roles.map((e) {
                final total = ventasFiltradas.isEmpty
                    ? 0.0
                    : e.value / ventasFiltradas.length;

                return _roleLine(
                  _roleName(e.key),
                  e.value,
                  total.clamp(0.0, 1.0),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _roleLine(String title, int value, double progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$value ventas',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.10),
              color: Colors.purpleAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankingCard() {
    final ranking = rankingAgentes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(const Color(0xFFFFB020)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top 10 red comercial',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (ranking.isEmpty)
              Text(
                'No hay ventas para mostrar ranking.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...List.generate(ranking.length, (index) {
                final item = ranking[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? Colors.amberAccent.withOpacity(0.22)
                              : Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                              color: index == 0
                                  ? Colors.amberAccent
                                  : Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${item.value}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _roleName(String role) {
    switch (role) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director zona';
      case 'jefe_ventas':
        return 'Jefes de ventas';
      case 'jefe_equipo':
        return 'Jefes de equipo';
      case 'agente':
        return 'Agentes';
      default:
        return 'Sin rol';
    }
  }

  Widget _bubble(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Icon(icon, color: color),
    );
  }

  BoxDecoration _cardDecoration(Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withOpacity(0.20),
          const Color(0xFF071A3A).withOpacity(0.92),
          const Color(0xFF020617).withOpacity(0.96),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
        color: color.withOpacity(0.30),
      ),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.10),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}

class _DirectorBackground extends StatelessWidget {
  const _DirectorBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF020617)),
        Positioned(
          top: -120,
          right: -90,
          child: _glow(const Color(0xFF22D3EE), 300),
        ),
        Positioned(
          top: 300,
          left: -140,
          child: _glow(const Color(0xFF7C3AED), 320),
        ),
        Positioned(
          bottom: -140,
          right: -110,
          child: _glow(const Color(0xFFFFB020), 300),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
    );
  }
}