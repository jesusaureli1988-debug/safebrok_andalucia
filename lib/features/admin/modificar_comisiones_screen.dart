import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TipoEdicionComision { comisiones, impuestos }

class ModificarComisionesScreen extends StatefulWidget {
  const ModificarComisionesScreen({super.key});

  @override
  State<ModificarComisionesScreen> createState() =>
      _ModificarComisionesScreenState();
}

class _ModificarComisionesScreenState extends State<ModificarComisionesScreen> {
  final supabase = Supabase.instance.client;

  static const _primary = Color(0xFF0284C7);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _surface = Color(0xFFFFFFFF);
  static const _background = Color(0xFFF6F9FC);

  bool loading = true;
  bool saving = false;

  TipoEdicionComision tipoEdicion = TipoEdicionComision.comisiones;

  List<Map<String, dynamic>> productos = [];
  final Map<String, double> comisionesPorCompania = {};

  static const List<String> companias = [
    'Ocaso',
    'Santalucía',
    'DKV',
    'Adeslas',
    'Mapfre',
    'Generali',
    'Helvetia',
    'Axa',
    'Allianz',
    'Zurich',
    'Active',
    'Aura',
    'Occident',
    'Fiact',
    'Asisa',
    'Pelayo',
    'Reale Seguros',
    'Sanitas',
  ];

  String companiaSeleccionada = companias.first;

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

    try {
      final resultados = await Future.wait([
        supabase.from('comisiones_productos').select().order('orden'),
        supabase
            .from('comisiones_producto_compania')
            .select('producto, compania, porcentaje_comision'),
      ]);

      final productosCargados = List<Map<String, dynamic>>.from(
        resultados[0] as List,
      );
      final comisionesCargadas = List<Map<String, dynamic>>.from(
        resultados[1] as List,
      );

      comisionesPorCompania.clear();
      for (final fila in comisionesCargadas) {
        final producto = fila['producto']?.toString().trim() ?? '';
        final compania = fila['compania']?.toString().trim() ?? '';
        if (producto.isEmpty || compania.isEmpty) continue;

        comisionesPorCompania[_claveComision(producto, compania)] = _num(
          fila['porcentaje_comision'],
        );
      }

      if (!mounted) return;
      setState(() {
        productos = productosCargados;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando comisiones: $e')));
    }
  }

  String _claveComision(String producto, String compania) {
    return '${producto.trim()}|||${compania.trim()}';
  }

  double _comisionProducto(Map<String, dynamic> producto) {
    final nombre = producto['producto']?.toString().trim() ?? '';
    return comisionesPorCompania[_claveComision(
          nombre,
          companiaSeleccionada,
        )] ??
        _num(producto['porcentaje_comision']);
  }

  void _cambiarComision(int index, double variacion) {
    final nombre = productos[index]['producto']?.toString().trim() ?? '';
    if (nombre.isEmpty) return;

    final clave = _claveComision(nombre, companiaSeleccionada);
    final nuevoValor = _limitarPorcentaje(
      _comisionProducto(productos[index]) + variacion,
    );

    setState(() {
      // Evita residuos binarios y conserva exactamente dos decimales.
      comisionesPorCompania[clave] = double.parse(
        nuevoValor.toStringAsFixed(2),
      );
    });
  }

  double _limitarPorcentaje(double value) {
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
  }

  void incrementarComision(int index) {
    _cambiarComision(index, 0.05);
  }

  void disminuirComision(int index) {
    _cambiarComision(index, -0.05);
  }

  void incrementarImpuestos(int index) {
    final actual = _num(productos[index]['porcentaje_impuestos']);

    setState(() {
      productos[index]['porcentaje_impuestos'] = _limitarPorcentaje(
        actual + 0.5,
      );
    });
  }

  void disminuirImpuestos(int index) {
    final actual = _num(productos[index]['porcentaje_impuestos']);

    setState(() {
      productos[index]['porcentaje_impuestos'] = _limitarPorcentaje(
        actual - 0.5,
      );
    });
  }

  Future<void> guardar() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      final actualizadoEn = DateTime.now().toIso8601String();

      if (tipoEdicion == TipoEdicionComision.comisiones) {
        final filas = productos
            .map((producto) {
              final nombre = producto['producto']?.toString().trim() ?? '';
              return {
                'producto': nombre,
                'compania': companiaSeleccionada,
                'porcentaje_comision': _comisionProducto(producto),
                'actualizado_en': actualizadoEn,
              };
            })
            .where((fila) {
              return (fila['producto'] as String).isNotEmpty;
            })
            .toList();

        await supabase
            .from('comisiones_producto_compania')
            .upsert(filas, onConflict: 'producto,compania');
      } else {
        for (final producto in productos) {
          await supabase
              .from('comisiones_productos')
              .update({
                'porcentaje_impuestos': _num(producto['porcentaje_impuestos']),
                'actualizado_en': actualizadoEn,
              })
              .eq('id', producto['id']);
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tipoEdicion == TipoEdicionComision.comisiones
                ? 'Comisiones de $companiaSeleccionada actualizadas'
                : 'Impuestos actualizados correctamente',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando comisiones: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  double get mediaComision {
    if (productos.isEmpty) return 0;
    final total = productos.fold<double>(
      0,
      (sum, p) => sum + _comisionProducto(p),
    );
    return total / productos.length;
  }

  double get mediaImpuestos {
    if (productos.isEmpty) return 0;
    final total = productos.fold<double>(
      0,
      (sum, p) => sum + _num(p['porcentaje_impuestos']),
    );
    return total / productos.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: const Color(0xFFF1F5F9),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _ink,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Comisiones e impuestos',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: loading ? null : cargarComisiones,
            tooltip: 'Actualizar datos',
            icon: const Icon(Icons.refresh_rounded, color: _primary),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary),
                  )
                : RefreshIndicator(
                    color: _primary,
                    backgroundColor: Colors.white,
                    onRefresh: cargarComisiones,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                      children: [
                        _header(),
                        const SizedBox(height: 16),
                        _selectorEdicion(),
                        if (tipoEdicion == TipoEdicionComision.comisiones) ...[
                          const SizedBox(height: 16),
                          _selectorCompania(),
                        ],
                        const SizedBox(height: 16),
                        _resumenPanel(),
                        const SizedBox(height: 16),
                        ...productos.asMap().entries.map(
                          (entry) => _productoCard(entry.value, entry.key),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFD97706),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tipoEdicion == TipoEdicionComision.comisiones
                                      ? 'IMPORTANTE\n\n'
                                            'Los cambios realizados en las comisiones se aplicarán únicamente a las ventas que se registren a partir de este momento.\n\n'
                                            'Las ventas ya existentes conservarán la comisión con la que fueron creadas.'
                                      : 'IMPORTANTE\n\n'
                                            'Los cambios realizados en los impuestos se aplicarán únicamente a las ventas que se registren a partir de este momento.\n\n'
                                            'La prima anual neta se calculará descontando de la prima anual bruta el porcentaje de impuestos configurado para cada producto.',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 13,
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  Widget _selectorEdicion() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _selectorButton(
              title: 'Comisiones',
              icon: Icons.percent_rounded,
              selected: tipoEdicion == TipoEdicionComision.comisiones,
              color: _primary,
              onTap: () {
                setState(() {
                  tipoEdicion = TipoEdicionComision.comisiones;
                });
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _selectorButton(
              title: 'Impuestos',
              icon: Icons.receipt_long_rounded,
              selected: tipoEdicion == TipoEdicionComision.impuestos,
              color: const Color(0xFF0F766E),
              onTap: () {
                setState(() {
                  tipoEdicion = TipoEdicionComision.impuestos;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorCompania() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.business_rounded, color: _primary, size: 22),
              SizedBox(width: 9),
              Text(
                'Elige una compañía',
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Las comisiones mostradas pertenecen únicamente a esta compañía.',
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: companiaSeleccionada,
            dropdownColor: Colors.white,
            iconEnabledColor: _primary,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              prefixIcon: const Icon(Icons.apartment_rounded, color: _primary),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
            ),
            items: companias.map((compania) {
              return DropdownMenuItem<String>(
                value: compania,
                child: Text(compania),
              );
            }).toList(),
            onChanged: saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => companiaSeleccionada = value);
                  },
          ),
        ],
      ),
    );
  }

  Widget _selectorButton({
    required String title,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color.withOpacity(0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: saving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? color : const Color(0xFF78909C),
                size: 20,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0F2FE), Color(0xFFF0FDFA)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        children: [
          Container(
            height: 62,
            width: 62,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330284C7),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              tipoEdicion == TipoEdicionComision.comisiones
                  ? Icons.percent_rounded
                  : Icons.receipt_long_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipoEdicion == TipoEdicionComision.comisiones
                      ? 'Configuración de comisiones'
                      : 'Configuración de impuestos',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tipoEdicion == TipoEdicionComision.comisiones
                      ? 'Ajusta las condiciones de $companiaSeleccionada por producto.'
                      : 'Define el porcentaje aplicado al cálculo de la prima neta.',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            _primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            tipoEdicion == TipoEdicionComision.comisiones
                ? 'Media · $companiaSeleccionada'
                : 'Media impuestos',
            tipoEdicion == TipoEdicionComision.comisiones
                ? '${mediaComision.toStringAsFixed(2)} %'
                : '${mediaImpuestos.toStringAsFixed(2)} %',
            tipoEdicion == TipoEdicionComision.comisiones
                ? Icons.query_stats_rounded
                : Icons.receipt_long_rounded,
            tipoEdicion == TipoEdicionComision.comisiones
                ? _primary
                : const Color(0xFF0F766E),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
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
                    color: const Color(0xFF071A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: _muted,
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
    final editandoComisiones = tipoEdicion == TipoEdicionComision.comisiones;

    final nombre = producto['producto']?.toString() ?? 'Producto';
    final descripcion =
        producto['descripcion']?.toString() ?? 'Producto comercial';

    final porcentajeComision = editandoComisiones
        ? _comisionProducto(producto)
        : _num(producto['porcentaje_comision']);
    final porcentajeImpuestos = _num(producto['porcentaje_impuestos']);

    final actualizado = producto['actualizado_en']?.toString();

    const primaBrutaEjemplo = 1000.0;
    final primaNetaEjemplo =
        primaBrutaEjemplo * (1 - (porcentajeImpuestos / 100));
    final comisionEjemplo = primaNetaEjemplo * (porcentajeComision / 100);

    final porcentajeMostrado = editandoComisiones
        ? porcentajeComision
        : porcentajeImpuestos;

    final colorPrincipal = editandoComisiones
        ? _primary
        : const Color(0xFF0F766E);

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
          color: _surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0D0F172A),
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
                    color: colorPrincipal.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    editandoComisiones
                        ? Icons.euro_rounded
                        : Icons.receipt_long_rounded,
                    color: colorPrincipal,
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
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _pill(
                  editandoComisiones ? 'Comisión' : 'Impuestos',
                  colorPrincipal,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  Text(
                    editandoComisiones
                        ? 'Comisión actual'
                        : 'Impuestos actuales',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${porcentajeMostrado.toStringAsFixed(2)} %',
                    style: TextStyle(
                      color: colorPrincipal,
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
                          label: editandoComisiones ? '- 0,05' : '- 0,50',
                          icon: Icons.remove_rounded,
                          color: Colors.redAccent,
                          onTap: () {
                            if (editandoComisiones) {
                              disminuirComision(index);
                            } else {
                              disminuirImpuestos(index);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _stepButton(
                          label: editandoComisiones ? '+ 0,05' : '+ 0,50',
                          icon: Icons.add_rounded,
                          color: colorPrincipal,
                          onTap: () {
                            if (editandoComisiones) {
                              incrementarComision(index);
                            } else {
                              incrementarImpuestos(index);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (editandoComisiones)
              Row(
                children: [
                  Expanded(
                    child: _infoLine(
                      'Prima neta ejemplo',
                      '${primaNetaEjemplo.toStringAsFixed(2)} €',
                      _primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _infoLine(
                      'Comisión generada',
                      '${comisionEjemplo.toStringAsFixed(2)} €',
                      const Color(0xFF16A34A),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _infoLine(
                      'Prima anual bruta',
                      '${primaBrutaEjemplo.toStringAsFixed(2)} €',
                      const Color(0xFF53627A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _infoLine(
                      'Prima anual neta',
                      '${primaNetaEjemplo.toStringAsFixed(2)} €',
                      _primary,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comisión: ${porcentajeComision.toStringAsFixed(2)} %',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(width: 1, height: 20, color: Colors.white12),
                  Expanded(
                    child: Text(
                      'Impuestos: ${porcentajeImpuestos.toStringAsFixed(2)} %',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (actualizado != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Última modificación: ${_fechaSimple(actualizado)}',
                  style: TextStyle(
                    color: _muted,
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
        onTap: saving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
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
              color: _muted,
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
          saving
              ? 'GUARDANDO...'
              : tipoEdicion == TipoEdicionComision.comisiones
              ? 'GUARDAR COMISIONES'
              : 'GUARDAR IMPUESTOS',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: tipoEdicion == TipoEdicionComision.comisiones
              ? _primary
              : const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              (tipoEdicion == TipoEdicionComision.comisiones
                      ? _primary
                      : const Color(0xFF0F766E))
                  .withOpacity(0.45),
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
        Container(color: const Color(0xFFF6F9FC)),
        Positioned(
          top: -120,
          right: -90,
          child: _blurCircle(
            color: const Color(0xFFBAE6FD).withOpacity(0.52),
            size: 270,
          ),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(
            color: const Color(0xFFCCFBF1).withOpacity(0.48),
            size: 290,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _blurCircle(
            color: const Color(0xFFDBEAFE).withOpacity(0.48),
            size: 320,
          ),
        ),
      ],
    );
  }

  Widget _blurCircle({required Color color, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 95, spreadRadius: 38)],
      ),
    );
  }
}
