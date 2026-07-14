import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/payroll/generate_nominas.dart';

class CreateSaleWizard extends StatefulWidget {
  final String? clientId;

  const CreateSaleWizard({
    super.key,
    this.clientId,
  });

  @override
  State<CreateSaleWizard> createState() => _CreateSaleWizardState();
}

class _CreateSaleWizardState extends State<CreateSaleWizard> {
  final supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();

  int step = 0;
  bool saving = false;
  double comisionPreview = 0;

  String? selectedProduct;
  String? selectedCompany;
  String? selectedPayment;
  DateTime? fechaEfecto;

  // CLIENTE
  final nombre = TextEditingController();
  final apellidos = TextEditingController();
  final dni = TextEditingController();
  final telefono = TextEditingController();
  final email = TextEditingController();
  final cp = TextEditingController();
  final provincia = TextEditingController();
  final poblacion = TextEditingController();
  final direccion = TextEditingController();
  final numero = TextEditingController();

  // CONTRATACIÓN
  final numeroPoliza = TextEditingController();
  final precio = TextEditingController();
  final asegurados = TextEditingController();

  static const Color bg = Color(0xFF07111D);
  static const Color card = Color(0xFF101C2B);
  static const Color card2 = Color(0xFF132437);
  static const Color blue = Color(0xFF2563EB);
  static const Color cyan = Colors.cyanAccent;

  final products = [
    'Decesos',
    'Hogar',
    'Vida',
    'Auto',
    'Comercio',
    'Comunidad',
    'Salud',
    'Baja laboral',
    'Accidentes',
    'Ahorro',
    'Embarcaciones',
    'Legal familiar',
    'Moto',
    'Vehiculos agricolas',
  ];

  final companies = [
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

  final payments = [
    'Mensual',
    'Trimestral',
    'Semestral',
    'Anual',
  ];

  @override
  void dispose() {
    nombre.dispose();
    apellidos.dispose();
    dni.dispose();
    telefono.dispose();
    email.dispose();
    cp.dispose();
    provincia.dispose();
    poblacion.dispose();
    direccion.dispose();
    numero.dispose();
    numeroPoliza.dispose();
    precio.dispose();
    asegurados.dispose();
    super.dispose();
  }

  bool _validateStep() {
    switch (step) {
      case 0:
        return nombre.text.trim().isNotEmpty &&
            apellidos.text.trim().isNotEmpty &&
            dni.text.trim().isNotEmpty &&
            telefono.text.trim().isNotEmpty &&
            email.text.trim().isNotEmpty &&
            cp.text.trim().isNotEmpty &&
            provincia.text.trim().isNotEmpty &&
            poblacion.text.trim().isNotEmpty &&
            direccion.text.trim().isNotEmpty &&
            numero.text.trim().isNotEmpty;

      case 1:
        return numeroPoliza.text.trim().isNotEmpty &&
            selectedProduct != null &&
            selectedCompany != null &&
            selectedPayment != null &&
            fechaEfecto != null &&
            precio.text.trim().isNotEmpty &&
            (selectedProduct != 'Decesos' || asegurados.text.trim().isNotEmpty);

      default:
        return true;
    }
  }

  void next() {
    if (!formKey.currentState!.validate()) return;

    if (step < 2) {
      setState(() => step++);
    }
  }

  void back() {
    if (step > 0) {
      setState(() => step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        title: const Text(
          "Nueva venta",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: Column(
            children: [
              _topProgress(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildStep(),
                ),
              ),
              _bottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topProgress() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _stepCircle(0, "Cliente", Icons.person_rounded),
              _stepLine(0),
              _stepCircle(1, "Venta", Icons.assignment_rounded),
              _stepLine(1),
              _stepCircle(2, "Revisión", Icons.verified_rounded),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: (step + 1) / 3,
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.08),
            color: cyan,
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (step) {
      case 0:
        return ListView(
          key: const ValueKey(0),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            _hero(
              icon: Icons.person_add_alt_1_rounded,
              title: "Datos del cliente",
              subtitle: "Completa la ficha del cliente antes de crear la venta.",
            ),
            const SizedBox(height: 18),
            _sectionTitle("Identificación"),
            _input(nombre, "Nombre", icon: Icons.person_rounded),
            _input(apellidos, "Apellidos", icon: Icons.badge_rounded),
            _input(
              dni,
              "DNI / NIE",
              icon: Icons.credit_card_rounded,
              textCapitalization: TextCapitalization.characters,
            ),
            _sectionTitle("Contacto"),
            _input(
              telefono,
              "Teléfono",
              icon: Icons.phone_rounded,
              keyboard: TextInputType.phone,
            ),
            _input(
              email,
              "Email",
              icon: Icons.email_rounded,
              keyboard: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
            _sectionTitle("Dirección"),
            _input(
              cp,
              "Código postal",
              icon: Icons.local_post_office_rounded,
              keyboard: TextInputType.number,
            ),
            _input(provincia, "Provincia", icon: Icons.map_rounded),
            _input(poblacion, "Población", icon: Icons.location_city_rounded),
            _input(direccion, "Dirección", icon: Icons.home_rounded),
            _input(numero, "Número / Piso / Portal", icon: Icons.pin_drop_rounded),
          ],
        );

      case 1:
        return ListView(
          key: const ValueKey(1),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            _hero(
              icon: Icons.workspace_premium_rounded,
              title: "Datos de contratación",
              subtitle: "Registra los datos de la póliza y cálculo comercial.",
            ),
            const SizedBox(height: 18),
            _sectionTitle("Póliza"),
            _input(
              numeroPoliza,
              "Número de póliza",
              icon: Icons.confirmation_number_rounded,
              textCapitalization: TextCapitalization.characters,
            ),
            _dropdown(
              label: "Producto",
              icon: Icons.inventory_2_rounded,
              value: selectedProduct,
              items: products,
              onChanged: (v) async {
  setState(() {
    selectedProduct = v;
    if (selectedProduct != 'Decesos') {
      asegurados.clear();
    }
  });

  await actualizarComisionPreview();
},
            ),
            if (selectedProduct == 'Decesos')
              _input(
                asegurados,
                "Nº asegurados",
                icon: Icons.groups_rounded,
                keyboard: TextInputType.number,
              ),
            _dropdown(
              label: "Compañía",
              icon: Icons.business_rounded,
              value: selectedCompany,
              items: companies,
              onChanged: (v) => setState(() => selectedCompany = v),
            ),
            _dropdown(
              label: "Forma de pago",
              icon: Icons.payments_rounded,
              value: selectedPayment,
              items: payments,
              onChanged: (v) => setState(() => selectedPayment = v),
            ),
            _input(
  precio,
  "Precio",
  icon: Icons.euro_rounded,
  keyboard: const TextInputType.numberWithOptions(decimal: true),
  onChangedExtra: actualizarComisionPreview,
),
            _datePicker(),
            const SizedBox(height: 10),
            _calculationPreview(),
          ],
        );

      case 2:
        return ListView(
          key: const ValueKey(2),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            _hero(
              icon: Icons.fact_check_rounded,
              title: "Revisión final",
              subtitle: "Comprueba los datos antes de guardar la venta.",
            ),
            const SizedBox(height: 18),
            _sectionTitle("Cliente"),
            _reviewCard("Nombre", nombre.text),
            _reviewCard("Apellidos", apellidos.text),
            _reviewCard("DNI / NIE", dni.text),
            _reviewCard("Teléfono", telefono.text),
            _reviewCard("Email", email.text),
            _reviewCard("Dirección", "${direccion.text}, ${numero.text}"),
            _reviewCard("Población", "${poblacion.text} - ${provincia.text}"),
            _sectionTitle("Venta"),
            _reviewCard("Número de póliza", numeroPoliza.text),
            _reviewCard("Producto", selectedProduct ?? ""),
            _reviewCard("Compañía", selectedCompany ?? ""),
            _reviewCard("Forma de pago", selectedPayment ?? ""),
            _reviewCard("Precio", "${precio.text} €"),
            _reviewCard("Fecha efecto", _formatDate(fechaEfecto)),
            if (selectedProduct == 'Decesos')
              _reviewCard("Nº asegurados", asegurados.text),
            _sectionTitle("Cálculo"),
            _reviewCard("Prima anual estimada", "${_primaAnual().toStringAsFixed(2)} €"),
            _reviewCard("Prima neta estimada", "${(_primaAnual() * 0.87).toStringAsFixed(2)} €"),
            _reviewCard("Comisión estimada", "${comisionPreview.toStringAsFixed(2)} €"),
          ],
        );

      default:
        return const SizedBox();
    }
  }

  Widget _bottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          if (step > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: saving ? null : back,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text("Atrás"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.18)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          if (step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : _validateStep()
                      ? (step == 2 ? _review : next)
                      : null,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded),
              label: Text(step == 2 ? "Guardar venta" : "Siguiente"),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withOpacity(0.08),
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF102A43),
            Color(0xFF0B1624),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white.withOpacity(0.12),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

 Widget _input(
  TextEditingController controller,
  String hint, {
  IconData? icon,
  TextInputType keyboard = TextInputType.text,
  TextCapitalization textCapitalization = TextCapitalization.none,
  String? Function(String?)? validator,
  Future<void> Function()? onChangedExtra,
}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        textCapitalization: textCapitalization,
        onChanged: (_) async {
  setState(() {});
  if (onChangedExtra != null) {
    await onChangedExtra();
  }
},
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        validator: validator ??
            (value) {
              if (value == null || value.trim().isEmpty) {
                return "Campo obligatorio";
              }
              return null;
            },
        decoration: _decoration(hint, icon),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: card2,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        iconEnabledColor: cyan,
        decoration: _decoration(label, icon),
        items: items
            .map(
              (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "Campo obligatorio";
          }
          return null;
        },
      ),
    );
  }

  Widget _datePicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: fechaEfecto ?? DateTime.now(),
            firstDate: DateTime(2024),
            lastDate: DateTime(2035),
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

          if (picked != null) {
            setState(() => fechaEfecto = picked);
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fechaEfecto == null
                      ? "Fecha de efecto"
                      : _formatDate(fechaEfecto),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData? icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, color: cyan, size: 21),
      hintStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: cyan, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }

  Widget _calculationPreview() {
    final prima = _primaAnual();
    final neta = prima * 0.87;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Vista previa económica",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _miniLine("Prima anual", "${prima.toStringAsFixed(2)} €"),
          _miniLine("Prima neta estimada", "${neta.toStringAsFixed(2)} €"),
          _miniLine("Comisión estimada", "${comisionPreview.toStringAsFixed(2)} €"),
        ],
      ),
    );
  }

  Widget _miniLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: Colors.white.withOpacity(0.58)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value.trim().isEmpty ? "-" : value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCircle(int current, String title, IconData icon) {
    final active = step >= current;

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: active ? blue : Colors.white.withOpacity(0.12),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine(int lineIndex) {
    final active = step > lineIndex;

    return Container(
      width: 24,
      height: 3,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: active ? cyan : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Campo obligatorio";
    }

    if (!value.contains('@') || !value.contains('.')) {
      return "Email no válido";
    }

    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "-";

    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  double _precioValue() {
    return double.tryParse(precio.text.trim().replaceAll(',', '.')) ?? 0;
  }

  double _primaAnual() {
    final value = _precioValue();

    switch (selectedPayment) {
      case 'Mensual':
        return value * 12;
      case 'Trimestral':
        return value * 4;
      case 'Semestral':
        return value * 2;
      case 'Anual':
        return value;
      default:
        return 0;
    }
  }

  Future<void> actualizarComisionPreview() async {
  if (selectedProduct == null) {
    setState(() => comisionPreview = 0);
    return;
  }

  final primaNeta = _primaAnual() * 0.87;

  final producto = await supabase
      .from('comisiones_productos')
      .select('porcentaje_comision')
      .eq('producto', selectedProduct!)
      .maybeSingle();

  final porcentaje =
      (producto?['porcentaje_comision'] as num?)?.toDouble() ?? 0;

  setState(() {
    comisionPreview = primaNeta * (porcentaje / 100);
  });
}

  Future<double> _comision() async {

  final primaNeta = _primaAnual() * 0.87;

  final producto = await supabase
      .from('comisiones_productos')
      .select('porcentaje_comision')
      .eq('producto', selectedProduct!)
      .maybeSingle();

  if (producto == null) {
    return 0;
  }

  final porcentaje =
      (producto['porcentaje_comision'] as num?)?.toDouble() ?? 0;

  return primaNeta * (porcentaje / 100);
}

  void _review() {
    if (!formKey.currentState!.validate()) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: blue,
                  child: Icon(Icons.verified_rounded, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  "¿Guardar venta?",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Se creará el cliente, la venta, los seguimientos y la nómina correspondiente.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.62)),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _save();
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text("Guardar venta"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (saving) return;

    final user = supabase.auth.currentUser;

    if (user == null) return;
    if (fechaEfecto == null) return;

    setState(() => saving = true);

    try {
      late String finalClientId;

      if (widget.clientId != null) {
        finalClientId = widget.clientId!;

        await supabase.from('clientes').update({
          'dni': dni.text.trim(),
          'nombre': nombre.text.trim(),
          'apellidos': apellidos.text.trim(),
          'telefono': telefono.text.trim(),
          'email': email.text.trim(),
          'codigo_postal': cp.text.trim(),
          'provincia': provincia.text.trim(),
          'poblacion': poblacion.text.trim(),
          'direccion': direccion.text.trim(),
          'numero': numero.text.trim(),
        }).eq('id', finalClientId);
      } else {
        final clienteResponse = await supabase
            .from('clientes')
            .insert({
              'auth_id': user.id,
              'nombre': nombre.text.trim(),
              'apellidos': apellidos.text.trim(),
              'dni': dni.text.trim(),
              'telefono': telefono.text.trim(),
              'email': email.text.trim(),
              'codigo_postal': cp.text.trim(),
              'provincia': provincia.text.trim(),
              'poblacion': poblacion.text.trim(),
              'direccion': direccion.text.trim(),
              'numero': numero.text.trim(),
            })
            .select()
            .single();

        finalClientId = clienteResponse['id'];
      }

      if (selectedProduct == null ||
          selectedCompany == null ||
          selectedPayment == null) {
        throw Exception("Faltan datos obligatorios");
      }

      final precioVenta = _precioValue();

      if (precioVenta <= 0) {
        throw Exception("Precio inválido");
      }

      final primaAnual = _primaAnual();
      final primaBrutaAnual = primaAnual;
      final primaNetaAnual = primaBrutaAnual * 0.87;
      final comision = await _comision();

      await supabase.from('ventas').insert({
        'cliente_id': finalClientId,
        'agente_auth_id': user.id,

        'numero_poliza': numeroPoliza.text.trim(),

        'producto': selectedProduct,
        'compania': selectedCompany,
        'forma_pago': selectedPayment,

        'precio': precioVenta,

        'prima_anual': primaAnual,
        'prima_anual_bruta': primaBrutaAnual,
        'prima_anual_neta': primaNetaAnual,

        'comision': comision,

        'categoria_producto': selectedProduct,

        'numero_asegurados': selectedProduct == 'Decesos'
            ? int.tryParse(asegurados.text.trim()) ?? 0
            : null,

        'fecha_efecto': fechaEfecto!.toIso8601String(),
      });

      final seguimientos = [
        {
          "tipo": "10_dias",
          "fecha": fechaEfecto!.add(const Duration(days: 10)),
        },
        {
          "tipo": "1_mes",
          "fecha": DateTime(
            fechaEfecto!.year,
            fechaEfecto!.month + 1,
            fechaEfecto!.day,
          ),
        },
        {
          "tipo": "2_meses",
          "fecha": DateTime(
            fechaEfecto!.year,
            fechaEfecto!.month + 2,
            fechaEfecto!.day,
          ),
        },
        {
          "tipo": "4_meses",
          "fecha": DateTime(
            fechaEfecto!.year,
            fechaEfecto!.month + 4,
            fechaEfecto!.day,
          ),
        },
        {
          "tipo": "6_meses",
          "fecha": DateTime(
            fechaEfecto!.year,
            fechaEfecto!.month + 6,
            fechaEfecto!.day,
          ),
        },
        {
          "tipo": "11_meses",
          "fecha": DateTime(
            fechaEfecto!.year,
            fechaEfecto!.month + 11,
            fechaEfecto!.day,
          ),
        },
      ];

      for (final s in seguimientos) {
        await supabase.from('seguimiento_clientes').insert({
          'cliente_id': finalClientId,
          'auth_id': user.id,
          'nombre': nombre.text.trim(),
          'telefono': telefono.text.trim(),
          'producto': selectedProduct,
          'fecha_efecto': fechaEfecto!.toIso8601String(),
          'tipo_llamada': s['tipo'],
          'proxima_llamada': (s['fecha'] as DateTime).toIso8601String(),
          'estado': 'Pendiente',
        });
      }

      final now = DateTime.now();
      final desde = DateTime(now.year, now.month, 24);

      final payroll = PayrollService();

      await payroll.generateNomina(
        authId: user.id,
        mes: desde.month,
        anio: desde.year,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Venta guardada correctamente")),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint("ERROR SAVE: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }
}