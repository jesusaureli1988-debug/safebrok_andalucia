import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleTareaJefeScreen extends StatefulWidget {
  final Map<String, dynamic> tarea;

  const DetalleTareaJefeScreen({
    super.key,
    required this.tarea,
  });

  @override
  State<DetalleTareaJefeScreen> createState() =>
      _DetalleTareaJefeScreenState();
}

class _DetalleTareaJefeScreenState extends State<DetalleTareaJefeScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false;
  bool loadingUsuario = true;
  bool realizada = false;

  int equipo = 0;
  int propios = 0;
  int total = 0;

  Map<String, dynamic>? usuario;

  final TextEditingController equipoController = TextEditingController();
  final TextEditingController propiosController = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargarDatos();
    cargarUsuario();
  }

  @override
  void dispose() {
    equipoController.dispose();
    propiosController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _valorUsuario(List<String> keys, String fallback) {
    if (usuario == null) return fallback;

    for (final key in keys) {
      final value = usuario![key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  String _fechaBonita(dynamic value) {
    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/"
          "${fecha.month.toString().padLeft(2, '0')}/"
          "${fecha.year}";
    } catch (_) {
      return "Sin fecha";
    }
  }

  void cargarDatos() {
    final tarea = widget.tarea;

    equipo = _toInt(tarea['contactos_equipo']);
    propios = _toInt(tarea['contactos_propios']);
    total = _toInt(tarea['total_contactos']);

    if (total == 0) {
      total = equipo + propios;
    }

    realizada = tarea['realizada'] == true;

    equipoController.text = equipo.toString();
    propiosController.text = propios.toString();

    setState(() {});
  }

  Future<void> cargarUsuario() async {
    try {
      final authId = widget.tarea['auth_id'];

      if (authId == null) {
        setState(() => loadingUsuario = false);
        return;
      }

      final data = await supabase
          .from('usuarios')
          .select()
          .eq('auth_id', authId)
          .maybeSingle();

      setState(() {
        usuario = data;
        loadingUsuario = false;
      });
    } catch (e) {
      debugPrint("❌ ERROR CARGANDO USUARIO JEFE: $e");
      setState(() => loadingUsuario = false);
    }
  }

  Future<void> completarTarea() async {
    if (equipo == 0 && propios == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text("Debes introducir contactos antes de completar"),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.from('contactos_diarios_jefe_equipo').update({
        'contactos_equipo': equipo,
        'contactos_propios': propios,
        'total_contactos': equipo + propios,
        'realizada': true,
      }).eq('id', widget.tarea['id']);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("❌ ERROR GUARDANDO TAREA: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text("No se pudo guardar la tarea"),
          ),
        );
      }
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = realizada;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Stack(
        children: [
          const _GlowBackground(),
          SafeArea(
            child: Column(
              children: [
                _topBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                    child: Column(
                      children: [
                        _heroCard(),
                        const SizedBox(height: 18),
                        _usuarioCard(),
                        const SizedBox(height: 18),
                        _contadorCard(bloqueado),
                        const SizedBox(height: 18),
                        _totalCard(),
                        const SizedBox(height: 24),
                        _botonCompletar(bloqueado),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Detalle diario",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    final color = realizada ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.24),
            Colors.white.withOpacity(0.06),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.18),
              border: Border.all(color: color.withOpacity(0.45)),
            ),
            child: Icon(
              realizada
                  ? Icons.verified_rounded
                  : Icons.hourglass_top_rounded,
              color: color,
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  realizada ? "Tarea completada" : "Tarea pendiente",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Fecha: ${_fechaBonita(widget.tarea['fecha'])}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usuarioCard() {
    final nombre = _valorUsuario(
      [
        'nombre',
        'nombre_completo',
        'nombre_apellidos',
        'nombre_y_apellidos',
        'NOMBRE Y APELLIDOS',
      ],
      'Jefe de equipo',
    );

    final telefono = _valorUsuario(
      [
        'telefono',
        'teléfono',
        'TELEFONO',
        'TELÉFONO',
      ],
      'Sin teléfono',
    );

    final email = _valorUsuario(
      [
        'email',
        'EMAIL',
        'correo',
      ],
      'Sin email',
    );

    final ciudad = _valorUsuario(
      [
        'ciudad',
        'poblacion',
        'población',
        'direccion',
        'dirección',
        'DIRECCIÓN',
      ],
      'Sin ciudad',
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: loadingUsuario
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 54,
                          width: 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF38BDF8),
                                Color(0xFF6366F1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 30,
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
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Responsable del registro diario",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.50),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _infoLine(Icons.phone_rounded, telefono),
                    _infoLine(Icons.email_rounded, email),
                    _infoLine(Icons.location_on_rounded, ciudad),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7DD3FC), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contadorCard(bool bloqueado) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          _numberInput(
            title: "Contactos del equipo",
            subtitle: "Actividad generada por tus comerciales",
            icon: Icons.groups_rounded,
            controller: equipoController,
            enabled: !bloqueado,
            onChanged: (v) {
              equipo = int.tryParse(v) ?? 0;
              setState(() => total = equipo + propios);
            },
          ),
          const SizedBox(height: 16),
          _numberInput(
            title: "Contactos propios",
            subtitle: "Actividad realizada directamente por ti",
            icon: Icons.person_pin_circle_rounded,
            controller: propiosController,
            enabled: !bloqueado,
            onChanged: (v) {
              propios = int.tryParse(v) ?? 0;
              setState(() => total = equipo + propios);
            },
          ),
        ],
      ),
    );
  }

  Widget _numberInput({
    required String title,
    required String subtitle,
    required IconData icon,
    required TextEditingController controller,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF7DD3FC),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 74,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: enabled
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0EA5E9),
            Color(0xFF2563EB),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.30),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calculate_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "Total contactos",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            total.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonCompletar(bool bloqueado) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor:
              bloqueado ? Colors.white.withOpacity(0.12) : const Color(0xFF22C55E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        onPressed: (loading || bloqueado) ? null : completarTarea,
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                bloqueado ? "YA COMPLETADA" : "MARCAR COMO COMPLETADA",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}

class _GlowBackground extends StatelessWidget {
  const _GlowBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: -80,
          child: _glow(const Color(0xFF38BDF8), 250),
        ),
        Positioned(
          top: 220,
          right: -120,
          child: _glow(const Color(0xFF6366F1), 260),
        ),
        Positioned(
          bottom: -120,
          left: 20,
          child: _glow(const Color(0xFF22C55E), 240),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.22),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: const SizedBox(),
      ),
    );
  }
}
