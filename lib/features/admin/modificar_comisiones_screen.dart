import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModificarComisionesScreen extends StatefulWidget {
  const ModificarComisionesScreen({super.key});

  @override
  State<ModificarComisionesScreen> createState() =>
      _ModificarComisionesScreenState();
}

class _ModificarComisionesScreenState
    extends State<ModificarComisionesScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  List<Map<String, dynamic>> productos = [];

  @override
  void initState() {
    super.initState();
    cargarComisiones();
  }

  double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Future<void> cargarComisiones() async {
    setState(() => loading = true);

    final data = await supabase
        .from('comisiones_productos')
        .select()
        .order('orden');

    setState(() {
      productos = List<Map<String, dynamic>>.from(data);
      loading = false;
    });
  }

  void incrementar(int index) {
    final valor = _num(productos[index]['porcentaje_comision']) + 0.5;

    setState(() {
      productos[index]['porcentaje_comision'] = valor;
    });
  }

  void disminuir(int index) {
    final actual = _num(productos[index]['porcentaje_comision']);
    final valor = actual <= 0 ? 0 : actual - 0.5;

    setState(() {
      productos[index]['porcentaje_comision'] = valor < 0 ? 0 : valor;
    });
  }

  Future<void> guardar() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      for (final producto in productos) {
        await supabase.from('comisiones_productos').update({
          'porcentaje_comision': producto['porcentaje_comision'],
          'actualizado_en': DateTime.now().toIso8601String(),
        }).eq('id', producto['id']);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comisiones actualizadas correctamente'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando comisiones: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  double get mediaComision {
    if (productos.isEmpty) return 0;
    final total = productos.fold<double>(
      0,
      (sum, p) => sum + _num(p['porcentaje_comision']),
    );
    return total / productos.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Modificar comisiones',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: loading ? null : cargarComisiones,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
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
                    onRefresh: cargarComisiones,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                      children: [
                        _header(),
                        const SizedBox(height: 16),
                        _resumenPanel(),
                        const SizedBox(height: 16),
                        ...productos.asMap().entries.map(
                              (entry) =>
                                  _productoCard(entry.value, entry.key),
                            ),
                        const SizedBox(height: 18),
                        _guardarButton(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.greenAccent.withOpacity(0.18),
                Colors.white.withOpacity(0.045),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Container(
                height: 62,
                width: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Colors.greenAccent,
                      Colors.cyanAccent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.percent_rounded,
                  color: Colors.black,
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel de comisiones',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Actualiza el porcentaje que generará cada producto en las nuevas ventas.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
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

  Widget _resumenPanel() {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'Productos',
            productos.length.toString(),
            Icons.inventory_2_rounded,
            Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Media',
            '${mediaComision.toStringAsFixed(2)} %',
            Icons.query_stats_rounded,
            Colors.greenAccent,
          ),
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
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontWeight: FontWeight.w600,
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

  Widget _productoCard(Map<String, dynamic> producto, int index) {
    final nombre = producto['producto']?.toString() ?? 'Producto';
    final descripcion =
        producto['descripcion']?.toString() ?? 'Producto comercial';
    final porcentaje = _num(producto['porcentaje_comision']);
    final actualizado = producto['actualizado_en']?.toString();

    final primaEjemplo = 1000.0;
    final comisionEjemplo = primaEjemplo * (porcentaje / 100);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index * 35)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.10),
              Colors.white.withOpacity(0.035),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.greenAccent.withOpacity(0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.24),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.euro_rounded,
                    color: Colors.cyanAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.52),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _pill(
                  'Actual',
                  Colors.greenAccent,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.20),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                children: [
                  Text(
                    'Comisión actual',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${porcentaje.toStringAsFixed(2)} %',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _stepButton(
                          label: '- 0,50',
                          icon: Icons.remove_rounded,
                          color: Colors.redAccent,
                          onTap: () => disminuir(index),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _stepButton(
                          label: '+ 0,50',
                          icon: Icons.add_rounded,
                          color: Colors.greenAccent,
                          onTap: () => incrementar(index),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _infoLine(
                    'Ejemplo prima neta',
                    '${primaEjemplo.toStringAsFixed(0)} €',
                    Colors.cyanAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _infoLine(
                    'Generaría',
                    '${comisionEjemplo.toStringAsFixed(2)} €',
                    Colors.greenAccent,
                  ),
                ),
              ],
            ),
            if (actualizado != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Última modificación: ${_fechaSimple(actualizado)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.48),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _guardarButton() {
    return SizedBox(
      height: 58,
      child: ElevatedButton.icon(
        onPressed: saving ? null : guardar,
        icon: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.save_rounded),
        label: Text(
          saving ? 'GUARDANDO...' : 'GUARDAR CAMBIOS',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.greenAccent.withOpacity(0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  String _fechaSimple(String value) {
    final fecha = DateTime.tryParse(value);
    if (fecha == null) return value;

    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
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
            color: Colors.greenAccent.withOpacity(0.18),
            size: 270,
          ),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(
            color: Colors.cyanAccent.withOpacity(0.16),
            size: 290,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _blurCircle(
            color: const Color(0xFF2D7DFF).withOpacity(0.14),
            size: 320,
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
            blurRadius: 95,
            spreadRadius: 38,
          ),
        ],
      ),
    );
  }
}