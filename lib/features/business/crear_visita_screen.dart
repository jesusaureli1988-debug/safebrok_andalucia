import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CrearVisitaScreen extends StatefulWidget {
  const CrearVisitaScreen({super.key});

  @override
  State<CrearVisitaScreen> createState() => _CrearVisitaScreenState();
}

class _CrearVisitaScreenState extends State<CrearVisitaScreen> {
  final supabase = Supabase.instance.client;

  final nombreController = TextEditingController();
  final telefonoController = TextEditingController();
  final direccionController = TextEditingController();
  final numeroController = TextEditingController();
  final cpController = TextEditingController();
  final poblacionController = TextEditingController();
  final provinciaController = TextEditingController();
  final observacionesController = TextEditingController();

  DateTime? fechaVisita;
  TimeOfDay? horaVisita;

  bool loading = false;
  bool showErrors = false;

  @override
  void dispose() {
    nombreController.dispose();
    telefonoController.dispose();
    direccionController.dispose();
    numeroController.dispose();
    cpController.dispose();
    poblacionController.dispose();
    provinciaController.dispose();
    observacionesController.dispose();
    super.dispose();
  }

  bool get formularioValido =>
      nombreController.text.trim().isNotEmpty &&
      telefonoController.text.trim().isNotEmpty &&
      direccionController.text.trim().isNotEmpty &&
      fechaVisita != null &&
      horaVisita != null;

  Future<void> guardarVisita() async {
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() => showErrors = true);

    if (!formularioValido) {
      _snack("Completa los campos obligatorios");
      return;
    }

    try {
      setState(() => loading = true);

      await supabase.from('visitas').insert({
        'auth_id': user.id,
        'nombre_cliente': nombreController.text.trim(),
        'telefono': telefonoController.text.trim(),
        'direccion': direccionController.text.trim(),
        'numero': numeroController.text.trim(),
        'codigo_postal': cpController.text.trim(),
        'poblacion': poblacionController.text.trim(),
        'provincia': provinciaController.text.trim(),
        'fecha_visita': fechaVisita!.toIso8601String(),
        'hora_visita':
            "${horaVisita!.hour.toString().padLeft(2, '0')}:${horaVisita!.minute.toString().padLeft(2, '0')}",
        'observaciones': observacionesController.text.trim(),
        'estado': 'Pendiente',
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack("Error al guardar la visita");
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

  Future<void> seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaVisita ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              surface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => fechaVisita = picked);
    }
  }

  Future<void> seleccionarHora() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: horaVisita ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              surface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => horaVisita = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        title: const Text(
          "Nueva visita",
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
                  title: "Datos del cliente",
                  icon: Icons.person_rounded,
                  children: [
                    _field(
                      controller: nombreController,
                      label: "Nombre cliente *",
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
                  title: "Dirección de la visita",
                  icon: Icons.location_on_rounded,
                  children: [
                    _field(
                      controller: direccionController,
                      label: "Dirección *",
                      icon: Icons.route_rounded,
                      required: true,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            controller: numeroController,
                            label: "Número",
                            icon: Icons.numbers_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            controller: cpController,
                            label: "Código Postal",
                            icon: Icons.local_post_office_rounded,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            controller: poblacionController,
                            label: "Población",
                            icon: Icons.location_city_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            controller: provinciaController,
                            label: "Provincia",
                            icon: Icons.map_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: "Agenda",
                  icon: Icons.calendar_month_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _selectorCard(
                            title: "Fecha *",
                            value: fechaVisita == null
                                ? "Seleccionar"
                                : "${fechaVisita!.day.toString().padLeft(2, '0')}/${fechaVisita!.month.toString().padLeft(2, '0')}/${fechaVisita!.year}",
                            icon: Icons.event_available_rounded,
                            error: showErrors && fechaVisita == null,
                            onTap: seleccionarFecha,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _selectorCard(
                            title: "Hora *",
                            value: horaVisita == null
                                ? "Seleccionar"
                                : horaVisita!.format(context),
                            icon: Icons.schedule_rounded,
                            error: showErrors && horaVisita == null,
                            onTap: seleccionarHora,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: "Observaciones",
                  icon: Icons.notes_rounded,
                  children: [
                    _field(
                      controller: observacionesController,
                      label: "Notas de la visita",
                      icon: Icons.edit_note_rounded,
                      maxLines: 4,
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
        borderRadius: BorderRadius.circular(28),
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
            height: 58,
            width: 58,
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
              Icons.add_location_alt_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Crear nueva visita",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Agenda una visita comercial con control profesional.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.3,
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
          boxShadow: [
            if (!error)
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
        onPressed: loading ? null : guardarVisita,
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
                    "Guardar visita",
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