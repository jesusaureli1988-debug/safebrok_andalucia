import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferenciaDiariaScreen extends StatefulWidget {
  const ReferenciaDiariaScreen({super.key});

  @override
  State<ReferenciaDiariaScreen> createState() => _ReferenciaDiariaScreenState();
}

class _ReferenciaDiariaScreenState extends State<ReferenciaDiariaScreen> {
  final supabase = Supabase.instance.client;

  final nombreController = TextEditingController();
  final telefonoController = TextEditingController();
  final companiaController = TextEditingController();
  final productosController = TextEditingController();
  final primaController = TextEditingController();
  final notasController = TextEditingController();

  String producto = "Decesos";
  String prioridad = "Media";

  DateTime? fechaVencimiento;
  DateTime? fechaLlamada;

  bool loading = false;
  bool showErrors = false;

  final List<String> productos = const [
    "Decesos",
    "Hogar",
    "Vida",
    "Salud",
    "Auto",
    "Comercio",
    "Comunidad",
    "RC",
    "Accidente",
    "Ahorro",
  ];

  final List<String> prioridades = const [
    "Alta",
    "Media",
    "Baja",
  ];

  @override
  void dispose() {
    nombreController.dispose();
    telefonoController.dispose();
    companiaController.dispose();
    productosController.dispose();
    primaController.dispose();
    notasController.dispose();
    super.dispose();
  }

  bool get formularioValido =>
      nombreController.text.trim().isNotEmpty &&
      telefonoController.text.trim().isNotEmpty &&
      companiaController.text.trim().isNotEmpty &&
      productosController.text.trim().isNotEmpty &&
      primaController.text.trim().isNotEmpty &&
      notasController.text.trim().isNotEmpty &&
      fechaVencimiento != null &&
      fechaLlamada != null;

  Future<void> guardarReferencia() async {
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() => showErrors = true);

    if (!formularioValido) {
      _snack("Debes completar todos los campos");
      return;
    }

    try {
      setState(() => loading = true);

      await supabase.from('referencias_viables').insert({
        'auth_id': user.id,
        'nombre': nombreController.text.trim(),
        'telefono': telefonoController.text.trim(),
        'producto': producto,
        'prioridad': prioridad,
        'estado': 'Pendiente',
        'compania_actual': companiaController.text.trim(),
        'productos_actuales': productosController.text.trim(),
        'prima_potencial':
            double.tryParse(primaController.text.replaceAll(',', '.')) ?? 0,
        'notas': notasController.text.trim(),
        'fecha_vencimiento': fechaVencimiento?.toIso8601String(),
        'fecha_llamada': fechaLlamada?.toIso8601String(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack("Error al guardar la referencia");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFFE11D48),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Future<void> seleccionarFechaVencimiento() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: fechaVencimiento ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
      builder: _dateTheme,
    );

    if (fecha != null) {
      setState(() => fechaVencimiento = fecha);
    }
  }

  Future<void> seleccionarFechaLlamada() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: fechaLlamada ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: _dateTheme,
    );

    if (fecha != null) {
      setState(() => fechaLlamada = fecha);
    }
  }

  Widget _dateTheme(BuildContext context, Widget? child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          surface: Color(0xFF0F172A),
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
          "Nueva referencia",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                _header(),
                const SizedBox(height: 22),

                _section(
                  title: "Datos del contacto",
                  icon: Icons.person_add_alt_1_rounded,
                  children: [
                    _field(
                      controller: nombreController,
                      label: "Nombre *",
                      icon: Icons.badge_rounded,
                      required: true,
                    ),
                    _field(
                      controller: telefonoController,
                      label: "Teléfono *",
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      required: true,
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: "Producto y oportunidad",
                  icon: Icons.workspace_premium_rounded,
                  children: [
                    _chipSelector(
                      title: "Producto principal",
                      values: productos,
                      selected: producto,
                      onSelected: (value) {
                        setState(() => producto = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    _field(
                      controller: companiaController,
                      label: "Compañía actual *",
                      icon: Icons.business_rounded,
                      required: true,
                    ),
                    _field(
                      controller: productosController,
                      label: "Productos actuales *",
                      icon: Icons.inventory_2_rounded,
                      required: true,
                    ),
                    _field(
                      controller: primaController,
                      label: "Prima potencial *",
                      icon: Icons.euro_rounded,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      required: true,
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: "Prioridad y seguimiento",
                  icon: Icons.flag_rounded,
                  children: [
                    _chipSelector(
                      title: "Prioridad",
                      values: prioridades,
                      selected: prioridad,
                      onSelected: (value) {
                        setState(() => prioridad = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _selectorCard(
                            title: "Vencimiento *",
                            value: fechaVencimiento == null
                                ? "Seleccionar"
                                : _formatFecha(fechaVencimiento!),
                            icon: Icons.event_available_rounded,
                            error: showErrors && fechaVencimiento == null,
                            onTap: seleccionarFechaVencimiento,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _selectorCard(
                            title: "Llamada *",
                            value: fechaLlamada == null
                                ? "Seleccionar"
                                : _formatFecha(fechaLlamada!),
                            icon: Icons.phone_in_talk_rounded,
                            error: showErrors && fechaLlamada == null,
                            onTap: seleccionarFechaLlamada,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: "Notas comerciales",
                  icon: Icons.notes_rounded,
                  children: [
                    _field(
                      controller: notasController,
                      label: "Notas *",
                      icon: Icons.edit_note_rounded,
                      maxLines: 4,
                      required: true,
                    ),
                  ],
                ),

                const SizedBox(height: 26),
                _saveButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF123044),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
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
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.35),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Referencia viable",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Registra oportunidades con vencimiento, llamada y prioridad comercial.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
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

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
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
                  Icon(icon, color: const Color(0xFF22D3EE), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final error = showErrors && required && controller.text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        onChanged: (_) {
          if (showErrors) setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          errorText: error ? "Campo obligatorio" : null,
          prefixIcon: Icon(icon, color: const Color(0xFF22D3EE)),
          labelStyle: const TextStyle(color: Colors.white54),
          errorStyle: const TextStyle(color: Color(0xFFFF6B81)),
          filled: true,
          fillColor: const Color(0xFF0B1724),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xFF22D3EE),
              width: 1.4,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xFFE11D48),
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xFFE11D48),
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipSelector({
    required String title,
    required List<String> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: values.map((value) {
            final active = selected == value;

            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF22D3EE)
                      : const Color(0xFF0B1724),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF22D3EE)
                        : Colors.white.withOpacity(0.10),
                  ),
                  boxShadow: [
                    if (active)
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.25),
                        blurRadius: 18,
                      ),
                  ],
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    color: active ? const Color(0xFF07111B) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _selectorCard({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    bool error = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1724),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: error
                ? const Color(0xFFE11D48)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF22D3EE)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (error) ...[
              const SizedBox(height: 6),
              const Text(
                "Obligatorio",
                style: TextStyle(
                  color: Color(0xFFFF6B81),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: loading ? null : guardarReferencia,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22D3EE),
          disabledBackgroundColor: Colors.white12,
          foregroundColor: const Color(0xFF07111B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_rounded),
                  SizedBox(width: 10),
                  Text(
                    "Guardar referencia",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _formatFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -90,
          right: -70,
          child: _glow(
            color: const Color(0xFF22D3EE),
            size: 230,
          ),
        ),
        Positioned(
          bottom: -110,
          left: -80,
          child: _glow(
            color: const Color(0xFF2563EB),
            size: 260,
          ),
        ),
      ],
    );
  }

  Widget _glow({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: const SizedBox(),
      ),
    );
  }
}