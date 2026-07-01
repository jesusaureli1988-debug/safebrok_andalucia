import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IntegracionAgenteDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> agente;

  const IntegracionAgenteDetalleScreen({
    super.key,
    required this.agente,
  });

  @override
  State<IntegracionAgenteDetalleScreen> createState() =>
      _IntegracionAgenteDetalleScreenState();
}

class _IntegracionAgenteDetalleScreenState
    extends State<IntegracionAgenteDetalleScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  Map<String, dynamic> data = {};

  final contactosController = TextEditingController();
  final visitasController = TextEditingController();
  final presupuestosController = TextEditingController();
  final polizasController = TextEditingController();

  static const int totalPasos = 5;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    contactosController.dispose();
    visitasController.dispose();
    presupuestosController.dispose();
    polizasController.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    try {
      final res = await supabase
          .from('integracion_agentes')
          .select()
          .eq('agente_id', widget.agente['id'])
          .limit(1);

      final row = res.isNotEmpty ? res.first : null;

      data = row ??
          {
            'agente_id': widget.agente['id'],
            'bienvenida': false,
            'alta_sistema': false,
            'grupo_whatsapp': false,
            'primera_reunion': false,
            'primera_venta': false,
            'contactos': 0,
            'visitas': 0,
            'presupuestos': 0,
            'polizas': 0,
          };

      contactosController.text = "${data['contactos'] ?? 0}";
      visitasController.text = "${data['visitas'] ?? 0}";
      presupuestosController.text = "${data['presupuestos'] ?? 0}";
      polizasController.text = "${data['polizas'] ?? 0}";

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      debugPrint("ERROR CARGA INTEGRACIÓN DETALLE: $e");

      if (!mounted) return;
      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al cargar integración: $e")),
      );
    }
  }

  int progreso() {
    int total = 0;

    if (data['bienvenida'] == true) total++;
    if (data['alta_sistema'] == true) total++;
    if (data['grupo_whatsapp'] == true) total++;
    if (data['primera_reunion'] == true) total++;
    if (data['primera_venta'] == true) total++;

    return total;
  }

  double get porcentaje => progreso() / totalPasos;

  Color get colorEstado {
    if (progreso() == totalPasos) return const Color(0xFF16A34A);
    if (progreso() == 0) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String get textoEstado {
    if (progreso() == totalPasos) return "Integración completada";
    if (progreso() == 0) return "Integración pendiente";
    return "Integración en progreso";
  }

  Future<void> guardar() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      data['contactos'] = int.tryParse(contactosController.text.trim()) ?? 0;
      data['visitas'] = int.tryParse(visitasController.text.trim()) ?? 0;
      data['presupuestos'] =
          int.tryParse(presupuestosController.text.trim()) ?? 0;
      data['polizas'] = int.tryParse(polizasController.text.trim()) ?? 0;

      final payload = Map<String, dynamic>.from(data);
      payload.remove('id');

      await supabase.from('integracion_agentes').upsert(
            payload,
            onConflict: 'agente_id',
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Integración guardada correctamente"),
          backgroundColor: Color(0xFF16A34A),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("❌ ERROR GUARDAR INTEGRACIÓN: $e");

      if (!mounted) return;
      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al guardar integración: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void actualizarCheck(String key, bool value) {
    setState(() {
      data[key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombre =
        "${widget.agente['nombre'] ?? ''} ${widget.agente['apellidos'] ?? ''}"
            .trim();
    final email = widget.agente['email'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF0F172A),
        title: const Text(
          "Detalle de integración",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: saving ? null : guardar,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      saving ? "Guardando..." : "Guardar cambios",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2563EB),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _cabeceraAgente(nombre, email),
                const SizedBox(height: 16),
                _panelProgreso(),
                const SizedBox(height: 20),

                const Text(
                  "Pasos de integración",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),

                _checkCard(
                  keyData: "bienvenida",
                  titulo: "Bienvenida realizada",
                  descripcion: "Presentación inicial del equipo y explicación del método.",
                  icono: Icons.waving_hand_rounded,
                ),
                _checkCard(
                  keyData: "alta_sistema",
                  titulo: "Alta en sistema",
                  descripcion: "Usuario creado y acceso operativo a la plataforma.",
                  icono: Icons.admin_panel_settings_rounded,
                ),
                _checkCard(
                  keyData: "grupo_whatsapp",
                  titulo: "Grupo WhatsApp",
                  descripcion: "Agente añadido al canal de comunicación del equipo.",
                  icono: Icons.groups_rounded,
                ),
                _checkCard(
                  keyData: "primera_reunion",
                  titulo: "Primera reunión",
                  descripcion: "Primera sesión de seguimiento, formación o planificación.",
                  icono: Icons.event_available_rounded,
                ),
                _checkCard(
                  keyData: "primera_venta",
                  titulo: "Primera venta",
                  descripcion: "Primera póliza o venta conseguida por el agente.",
                  icono: Icons.workspace_premium_rounded,
                ),

                const SizedBox(height: 20),

                const Text(
                  "Actividad inicial",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),

                _actividadPanel(),

                const SizedBox(height: 90),
              ],
            ),
    );
  }

  Widget _cabeceraAgente(String nombre, String email) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
            child: Text(
              nombre.isNotEmpty ? nombre.substring(0, 1).toUpperCase() : "A",
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre.isEmpty ? "Agente sin nombre" : nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelProgreso() {
    final p = progreso();
    final porcentajeTexto = (porcentaje * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1E40AF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: CircularProgressIndicator(
                  value: porcentaje,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  color: Colors.white,
                ),
              ),
              Text(
                "$porcentajeTexto%",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textoEstado,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$p de $totalPasos pasos completados",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    "Onboarding comercial",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
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

  Widget _checkCard({
    required String keyData,
    required String titulo,
    required String descripcion,
    required IconData icono,
  }) {
    final activo = data[keyData] == true;
    final color = activo ? const Color(0xFF16A34A) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => actualizarCheck(keyData, !activo),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: activo
                    ? const Color(0xFF16A34A).withOpacity(0.35)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icono, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activo ? const Color(0xFF16A34A) : Colors.white,
                    border: Border.all(
                      color: activo
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                  child: activo
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actividadPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _numberInput(
                  controller: contactosController,
                  label: "Contactos",
                  icono: Icons.call_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberInput(
                  controller: visitasController,
                  label: "Visitas",
                  icono: Icons.handshake_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _numberInput(
                  controller: presupuestosController,
                  label: "Presupuestos",
                  icono: Icons.description_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberInput(
                  controller: polizasController,
                  label: "Pólizas",
                  icono: Icons.verified_user_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberInput({
    required TextEditingController controller,
    required String label,
    required IconData icono,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, color: const Color(0xFF2563EB)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF2563EB),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}