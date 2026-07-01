import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddContactosDiariosScreen extends StatefulWidget {
  const AddContactosDiariosScreen({super.key});

  @override
  State<AddContactosDiariosScreen> createState() =>
      _AddContactosDiariosScreenState();
}

class _AddContactosDiariosScreenState
    extends State<AddContactosDiariosScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool loading = false;
  bool showErrors = false;

  int frios = 0;
  int telefonicos = 0;
  int positivos = 0;
  int negativos = 0;

  final friosController = TextEditingController();
  final telefonicosController = TextEditingController();
  final positivosController = TextEditingController();
  final negativosController = TextEditingController();

  List<TextEditingController> nombres = [];
  List<TextEditingController> telefonos = [];

  int get totalContactos => frios + telefonicos;
  double get progreso => (positivos / 6).clamp(0.0, 1.0);
  bool get objetivoCumplido => positivos >= 6;

  @override
  void dispose() {
    friosController.dispose();
    telefonicosController.dispose();
    positivosController.dispose();
    negativosController.dispose();

    for (final c in nombres) {
      c.dispose();
    }

    for (final c in telefonos) {
      c.dispose();
    }

    super.dispose();
  }

  void generarCamposPositivos(int value) {
    for (final c in nombres) {
      c.dispose();
    }

    for (final c in telefonos) {
      c.dispose();
    }

    setState(() {
      positivos = value < 0 ? 0 : value;
      nombres = List.generate(positivos, (_) => TextEditingController());
      telefonos = List.generate(positivos, (_) => TextEditingController());
    });
  }

  bool validarPositivos() {
    for (int i = 0; i < positivos; i++) {
      if (nombres[i].text.trim().isEmpty ||
          telefonos[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  Future<void> guardar() async {
    FocusScope.of(context).unfocus();

    setState(() => showErrors = true);

    final formOk = _formKey.currentState!.validate();
    final positivosOk = validarPositivos();

    if (!formOk || !positivosOk) {
      _snack('Rellena todos los campos obligatorios', Colors.orangeAccent);
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      _snack('No hay usuario conectado', Colors.redAccent);
      return;
    }

    setState(() => loading = true);

    try {
      final fecha = DateTime.now();

      final insert = await supabase.from('contactos_diarios').insert({
        'auth_id': user.id,
        'fecha': fecha.toIso8601String(),
        'contactos_frios': frios,
        'contactos_telefonicos': telefonicos,
        'contactos_positivos': positivos,
        'contactos_negativos': negativos,
      }).select();

      final contactoId = insert[0]['id'];

      for (int i = 0; i < positivos; i++) {
        await supabase.from('contactos_positivos_detalle').insert({
          'contacto_id': contactoId,
          'nombre': nombres[i].text.trim(),
          'telefono': telefonos[i].text.trim(),
        });
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        _snack('Error al guardar los contactos', Colors.redAccent);
      }
    }
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF102331),
        behavior: SnackBarBehavior.floating,
        content: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  int _parse(String value) {
    return int.tryParse(value.trim()) ?? 0;
  }

  void _syncNumbers() {
    frios = _parse(friosController.text);
    telefonicos = _parse(telefonicosController.text);
    negativos = _parse(negativosController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Nuevo registro',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      body: Stack(
        children: [
          const _PremiumBackground(),

          SafeArea(
            child: Form(
              key: _formKey,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 118),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(),
                        const SizedBox(height: 14),
                        _summaryPanel(),
                        const SizedBox(height: 16),

                        _sectionTitle(
                          'Actividad del día',
                          'Introduce la producción real realizada hoy.',
                        ),

                        const SizedBox(height: 12),

                        _numberInput(
                          controller: friosController,
                          label: 'Contactos fríos',
                          icon: Icons.ac_unit_rounded,
                          color: Colors.lightBlueAccent,
                          onChanged: (_) {
                            setState(() {
                              _syncNumbers();
                            });
                          },
                        ),

                        _numberInput(
                          controller: telefonicosController,
                          label: 'Contactos telefónicos',
                          icon: Icons.phone_in_talk_rounded,
                          color: Colors.orangeAccent,
                          onChanged: (_) {
                            setState(() {
                              _syncNumbers();
                            });
                          },
                        ),

                        _numberInput(
                          controller: positivosController,
                          label: 'Contactos positivos',
                          icon: Icons.thumb_up_alt_rounded,
                          color: Colors.greenAccent,
                          onChanged: (v) {
                            _syncNumbers();
                            generarCamposPositivos(_parse(v));
                          },
                        ),

                        _numberInput(
                          controller: negativosController,
                          label: 'Contactos negativos',
                          icon: Icons.thumb_down_alt_rounded,
                          color: Colors.redAccent,
                          onChanged: (_) {
                            setState(() {
                              _syncNumbers();
                            });
                          },
                        ),

                        const SizedBox(height: 18),

                        if (positivos > 0) ...[
                          _sectionTitle(
                            'Detalle de positivos',
                            'Añade nombre y teléfono de cada positivo.',
                          ),
                          const SizedBox(height: 12),
                        ],

                        for (int i = 0; i < positivos; i++)
                          _positivoCard(i),
                      ],
                    ),
                  ),

                  _bottomButton(),
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
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.13),
                Colors.white.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                      Colors.cyanAccent,
                      Color(0xFF2D7DFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.25),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.black,
                  size: 32,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Registro diario',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Objetivo recomendado: 6 contactos positivos diarios',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.60),
                        fontWeight: FontWeight.w600,
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

  Widget _summaryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _miniKpi(
                  'Base',
                  totalContactos.toString(),
                  Icons.groups_rounded,
                  Colors.cyanAccent,
                ),
              ),
              Expanded(
                child: _miniKpi(
                  'Positivos',
                  positivos.toString(),
                  Icons.verified_rounded,
                  Colors.greenAccent,
                ),
              ),
              Expanded(
                child: _miniKpi(
                  'Negativos',
                  negativos.toString(),
                  Icons.close_rounded,
                  Colors.redAccent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: progreso,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    color: objetivoCumplido
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$positivos/6',
                style: TextStyle(
                  color: objetivoCumplido
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniKpi(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.50),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.50),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _numberInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Obligatorio';
          }

          final n = int.tryParse(value.trim());
          if (n == null || n < 0) {
            return 'Introduce un número válido';
          }

          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.62)),
          prefixIcon: Icon(icon, color: color),
          filled: true,
          fillColor: Colors.white.withOpacity(0.055),
          errorStyle: const TextStyle(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.w700,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.09)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: color.withOpacity(0.75), width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.orangeAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.orangeAccent),
          ),
        ),
      ),
    );
  }

  Widget _positivoCard(int index) {
    final hasError = showErrors &&
        (nombres[index].text.trim().isEmpty ||
            telefonos[index].text.trim().isEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.035),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasError
              ? Colors.orangeAccent.withOpacity(0.65)
              : Colors.greenAccent.withOpacity(0.18),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Colors.greenAccent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Positivo ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _detailInput(
            controller: nombres[index],
            label: 'Nombre completo',
            icon: Icons.person_rounded,
            keyboardType: TextInputType.name,
          ),

          const SizedBox(height: 10),

          _detailInput(
            controller: telefonos[index],
            label: 'Teléfono',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget _detailInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Obligatorio';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.58)),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.black.withOpacity(0.18),
        errorStyle: const TextStyle(
          color: Colors.orangeAccent,
          fontWeight: FontWeight.w700,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.cyanAccent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.orangeAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.orangeAccent),
        ),
      ),
    );
  }

  Widget _bottomButton() {
    return Positioned(
      bottom: 18,
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF061018).withOpacity(0.76),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: loading ? null : guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  disabledBackgroundColor: Colors.white.withOpacity(0.10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'GUARDAR CONTACTOS',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
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
        Container(color: const Color(0xFF061018)),

        Positioned(
          top: -120,
          right: -90,
          child: _blurCircle(
            color: Colors.cyanAccent.withOpacity(0.22),
            size: 260,
          ),
        ),

        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(
            color: const Color(0xFF2D7DFF).withOpacity(0.18),
            size: 280,
          ),
        ),

        Positioned(
          bottom: -120,
          right: -100,
          child: _blurCircle(
            color: Colors.greenAccent.withOpacity(0.12),
            size: 300,
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
            blurRadius: 90,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }
}