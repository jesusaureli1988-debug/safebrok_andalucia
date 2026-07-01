import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MySalesScreen extends StatefulWidget {
  const MySalesScreen({super.key});

  @override
  State<MySalesScreen> createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> ventas = [];
  bool loading = true;

  String? userRole;
  String? userAuthId;
  String? userInternalId;

  String selectedYear = 'Todos';
  String selectedMonth = 'Todos';
  String selectedProduct = 'Todos';
  String selectedCompany = 'Todos';

  List<String> years = ['Todos'];
  List<String> months = ['Todos'];
  List<String> products = ['Todos'];
  List<String> companies = ['Todos'];

  final List<String> monthNames = const [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    loadSales();
  }

  Future<void> loadSales() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final usuarioDb = await supabase
          .from('usuarios')
          .select('id, auth_id, rol_usuario')
          .eq('auth_id', user.id)
          .single();

      userRole = usuarioDb['rol_usuario']?.toString();
      userAuthId = usuarioDb['auth_id']?.toString();
      userInternalId = usuarioDb['id']?.toString();

      final agentesIds = await getAgentesBajoUsuario(
        userInternalId!,
        userAuthId!,
        userRole!,
      );

      debugPrint('ROL: $userRole');
      debugPrint('AUTH ID: $userAuthId');
      debugPrint('INTERNAL ID: $userInternalId');
      debugPrint('IDS PARA BUSCAR VENTAS: $agentesIds');

      if (agentesIds.isEmpty) {
        setState(() {
          ventas = [];
          loading = false;
        });
        return;
      }

      final response = await supabase
          .from('ventas')
          .select('''
            id,
            created_at,
            agente_auth_id,
            producto,
            compania,
           precio,
numero_asegurados,
forma_pago,
fecha_efecto,
numero_poliza,
clientes (
              nombre,
              apellidos,
              telefono
            )
          ''')
          .inFilter('agente_auth_id', agentesIds)
          .order('created_at', ascending: false);

      ventas = List<Map<String, dynamic>>.from(response);

      debugPrint('VENTAS ENCONTRADAS: ${ventas.length}');

      _buildFilters();

      if (mounted) {
        setState(() => loading = false);
      }
    } catch (e) {
      debugPrint('ERROR LOAD SALES: $e');

      if (mounted) {
        setState(() {
          ventas = [];
          loading = false;
        });
      }
    }
  }

  Future<List<String>> getAgentesBajoUsuario(
  String internalId,
  String authId,
  String role,
) async {
  if (role == 'administracion') {
    return [];
  }

  if (role == 'agente') {
    return [authId];
  }

  if (role == 'director_nacional') {
    final usuarios = await supabase
        .from('usuarios')
        .select('auth_id')
        .not('auth_id', 'is', null);

    return usuarios
        .map<String>((e) => e['auth_id']?.toString() ?? '')
        .where((e) => e.isNotEmpty && e != 'null')
        .toList();
  }

  final usuarios = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario');

  final List<Map<String, String?>> normalized = usuarios.map((u) {
    return {
      'id': u['id']?.toString(),
      'auth_id': u['auth_id']?.toString(),
      'parent_id': u['parent_id']?.toString(),
      'rol_usuario': u['rol_usuario']?.toString(),
    };
  }).toList();

  final Set<String> resultAuthIds = {};
  resultAuthIds.add(authId);

  void buscarHijos(String parentId) {
    for (final u in normalized) {
      if (u['parent_id'] == parentId) {
        final childId = u['id'];
        final childAuthId = u['auth_id'];

        if (childAuthId != null &&
            childAuthId.isNotEmpty &&
            childAuthId != 'null') {
          resultAuthIds.add(childAuthId);
        }

        if (childId != null && childId.isNotEmpty && childId != parentId) {
          buscarHijos(childId);
        }
      }
    }
  }

  if (role == 'director_zona' ||
      role == 'jefe_ventas' ||
      role == 'jefe_equipo') {
    buscarHijos(internalId);
    return resultAuthIds.toList();
  }

  return [];
}

  void _buildFilters() {
    final yearSet = <String>{};
    final monthSet = <String>{};
    final productSet = <String>{};
    final companySet = <String>{};

    for (final v in ventas) {
      final date = DateTime.tryParse(v['created_at']?.toString() ?? '');

      if (date != null) {
        yearSet.add(date.year.toString());
        monthSet.add(monthNames[date.month - 1]);
      }

      final producto = v['producto']?.toString().trim();
      final compania = v['compania']?.toString().trim();

      if (producto != null && producto.isNotEmpty) productSet.add(producto);
      if (compania != null && compania.isNotEmpty) companySet.add(compania);
    }

    years = ['Todos', ...yearSet.toList()..sort((a, b) => b.compareTo(a))];
    months = ['Todos', ...monthNames.where((m) => monthSet.contains(m))];
    products = ['Todos', ...productSet.toList()..sort()];
    companies = ['Todos', ...companySet.toList()..sort()];
  }

  List<Map<String, dynamic>> get filteredVentas {
    return ventas.where((v) {
      final date = DateTime.tryParse(v['created_at']?.toString() ?? '');

      final okYear = selectedYear == 'Todos' ||
          (date != null && selectedYear == date.year.toString());

      final okMonth = selectedMonth == 'Todos' ||
          (date != null && selectedMonth == monthNames[date.month - 1]);

      final okProduct =
          selectedProduct == 'Todos' || selectedProduct == v['producto'];

      final okCompany =
          selectedCompany == 'Todos' || selectedCompany == v['compania'];

      return okYear && okMonth && okProduct && okCompany;
    }).toList();
  }

  int get totalAsegurados {
    return filteredVentas.fold<int>(
      0,
      (sum, v) => sum + ((v['numero_asegurados'] as num?)?.toInt() ?? 0),
    );
  }

  double get totalPrima {
    return filteredVentas.fold<double>(
      0,
      (sum, v) => sum + ((v['precio'] as num?)?.toDouble() ?? 0),
    );
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF07111B),

    appBar: AppBar(
      backgroundColor: const Color(0xFF07111B).withOpacity(0.95),
      elevation: 0,
      scrolledUnderElevation: 0,

      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.35),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),

      leading: IconButton(
        splashRadius: 24,
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 22,
        ),
        onPressed: () => Navigator.pop(context),
      ),

      title: const Text(
        'Mis Ventas',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),

      centerTitle: false,
    ),

    body: Stack(
      children: [
        const _PremiumBackground(),

        if (loading)
          const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          )
        else if (ventas.isEmpty)
          _emptyState()
        else
          RefreshIndicator(
            color: Colors.cyanAccent,
            backgroundColor: const Color(0xFF102331),
            onRefresh: loadSales,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _filters()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: filteredVentas.length,
                    itemBuilder: (context, index) {
                      return _saleCard(filteredVentas[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard(
              'Ventas',
              filteredVentas.length.toString(),
              Icons.receipt_long_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Asegurados',
              totalAsegurados.toString(),
              Icons.groups_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Prima mensual',
              '${totalPrima.toStringAsFixed(2)} €',
              Icons.euro_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 22),
              const SizedBox(height: 12),
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
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Row(
        children: [
          _filter('Año', selectedYear, years, (v) {
            setState(() => selectedYear = v!);
          }),
          const SizedBox(width: 10),
          _filter('Mes', selectedMonth, months, (v) {
            setState(() => selectedMonth = v!);
          }),
          const SizedBox(width: 10),
          _filter('Producto', selectedProduct, products, (v) {
            setState(() => selectedProduct = v!);
          }),
          const SizedBox(width: 10),
          _filter('Compañía', selectedCompany, companies, (v) {
            setState(() => selectedCompany = v!);
          }),
        ],
      ),
    );
  }

  Widget _filter(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : 'Todos',
          dropdownColor: const Color(0xFF102331),
          iconEnabledColor: Colors.cyanAccent,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          items: items.map((e) {
            return DropdownMenuItem(
              value: e,
              child: Text('$label: $e'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _saleCard(Map<String, dynamic> venta) {
  final cliente = venta['clientes'];
  final nombre = cliente != null
      ? '${cliente['nombre'] ?? ''} ${cliente['apellidos'] ?? ''}'.trim()
      : 'Cliente sin vincular';

  final fecha = DateTime.tryParse(venta['created_at']?.toString() ?? '');
  final fechaTexto = fecha == null
      ? 'Sin fecha'
      : '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 24,
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
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.cyanAccent.withOpacity(0.95),
                          Colors.blueAccent.withOpacity(0.80),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF07111B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nombre.isEmpty ? 'Cliente' : nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar venta',
                    onPressed: () => _openEditSaleSheet(venta),
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fechaTexto,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag(Icons.shield_rounded, venta['producto'] ?? 'Producto'),
                  _tag(Icons.business_rounded, venta['compania'] ?? 'Compañía'),
                  _tag(Icons.credit_card_rounded, venta['forma_pago'] ?? 'Forma pago'),
                  _tag(Icons.euro_rounded, '${venta['precio'] ?? 0} €'),
                  _tag(
                    Icons.groups_rounded,
                    '${venta['numero_asegurados'] ?? 0} asegurados',
                  ),
                  if (venta['fecha_efecto'] != null)
                    _tag(
                      Icons.event_available_rounded,
                      venta['fecha_efecto'].toString(),
                    ),
                  if (venta['numero_poliza'] != null)
                    _tag(
                      Icons.confirmation_number_rounded,
                      venta['numero_poliza'].toString(),
                    ),
                  if (cliente != null && cliente['telefono'] != null)
                    _tag(Icons.phone_rounded, cliente['telefono'].toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

 void _openEditSaleSheet(Map<String, dynamic> venta) {
  final productoController =
      TextEditingController(text: venta['producto']?.toString() ?? '');
  final companiaController =
      TextEditingController(text: venta['compania']?.toString() ?? '');
  final formaPagoController =
      TextEditingController(text: venta['forma_pago']?.toString() ?? '');
  final precioController =
      TextEditingController(text: venta['precio']?.toString() ?? '');
  final aseguradosController =
      TextEditingController(text: venta['numero_asegurados']?.toString() ?? '');
  final fechaEfectoController =
      TextEditingController(text: venta['fecha_efecto']?.toString() ?? '');
  final numeroPolizaController =
      TextEditingController(text: venta['numero_poliza']?.toString() ?? '');

  bool saving = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> guardarCambios() async {
            if (saving) return;

            final precio = double.tryParse(
              precioController.text.trim().replaceAll(',', '.'),
            );

            final asegurados = int.tryParse(
              aseguradosController.text.trim(),
            );

            if (productoController.text.trim().isEmpty ||
                companiaController.text.trim().isEmpty ||
                formaPagoController.text.trim().isEmpty ||
                precio == null ||
                asegurados == null ||
                fechaEfectoController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Revisa producto, compañía, forma de pago, precio, asegurados y fecha de efecto',
                  ),
                ),
              );
              return;
            }

            try {
              setModalState(() => saving = true);

              await supabase.from('ventas').update({
                'producto': productoController.text.trim(),
                'compania': companiaController.text.trim(),
                'forma_pago': formaPagoController.text.trim(),
                'precio': precio,
                'numero_asegurados': asegurados,
                'fecha_efecto': fechaEfectoController.text.trim(),
                'numero_poliza': numeroPolizaController.text.trim().isEmpty
                    ? null
                    : numeroPolizaController.text.trim(),
              }).eq('id', venta['id']);

              if (!mounted) return;

              Navigator.pop(context);

              setState(() => loading = true);
              await loadSales();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Venta actualizada correctamente'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              setModalState(() => saving = false);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error al actualizar venta: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          Future<void> seleccionarFechaEfecto() async {
            final actual = DateTime.tryParse(fechaEfectoController.text.trim()) ??
                DateTime.now();

            final picked = await showDatePicker(
              context: context,
              initialDate: actual,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Colors.cyanAccent,
                      onPrimary: Color(0xFF07111B),
                      surface: Color(0xFF102331),
                      onSurface: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (picked != null) {
              fechaEfectoController.text =
                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102331).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Editar venta',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _editField(
                          controller: productoController,
                          label: 'Producto',
                          icon: Icons.shield_rounded,
                        ),
                        _editField(
                          controller: companiaController,
                          label: 'Compañía',
                          icon: Icons.business_rounded,
                        ),
                        _editField(
                          controller: formaPagoController,
                          label: 'Forma de pago',
                          icon: Icons.credit_card_rounded,
                        ),
                        _editField(
                          controller: precioController,
                          label: 'Precio mensual',
                          icon: Icons.euro_rounded,
                          keyboardType: TextInputType.number,
                        ),
                        _editField(
                          controller: aseguradosController,
                          label: 'Número de asegurados',
                          icon: Icons.groups_rounded,
                          keyboardType: TextInputType.number,
                        ),
                        GestureDetector(
                          onTap: seleccionarFechaEfecto,
                          child: AbsorbPointer(
                            child: _editField(
                              controller: fechaEfectoController,
                              label: 'Fecha de efecto',
                              icon: Icons.event_available_rounded,
                            ),
                          ),
                        ),
                        _editField(
                          controller: numeroPolizaController,
                          label: 'Número de póliza',
                          icon: Icons.confirmation_number_rounded,
                        ),

                        const SizedBox(height: 18),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: saving ? null : guardarCambios,
                            icon: saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              saving ? 'Guardando...' : 'Guardar cambios',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: const Color(0xFF07111B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.65)),
          prefixIcon: Icon(icon, color: Colors.cyanAccent),
          filled: true,
          fillColor: Colors.white.withOpacity(0.07),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.cyanAccent),
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              color: Colors.white.withOpacity(0.35),
              size: 64,
            ),
            const SizedBox(height: 18),
            const Text(
              'No hay ventas aún',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando se registren ventas en tu estructura aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF07111B),
                Color(0xFF102331),
                Color(0xFF16384D),
              ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: _GlowBall(color: Colors.cyanAccent.withOpacity(0.22)),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: _GlowBall(color: Colors.blueAccent.withOpacity(0.18)),
        ),
      ],
    );
  }
}

class _GlowBall extends StatelessWidget {
  final Color color;

  const _GlowBall({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      width: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}