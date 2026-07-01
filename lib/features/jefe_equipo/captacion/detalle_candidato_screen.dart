import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DetalleCandidatoScreen extends StatefulWidget {
  final Map<String, dynamic> candidato;

  const DetalleCandidatoScreen({
    super.key,
    required this.candidato,
  });

  @override
  State<DetalleCandidatoScreen> createState() => _DetalleCandidatoScreenState();
}

class _DetalleCandidatoScreenState extends State<DetalleCandidatoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false;

  late String estado;
  String? motivoDescarte;

  DateTime? fechaEntrevista;
  DateTime? fechaProxima;

  final estadosFlow = const [
    'CV_RECIBIDO',
    'CONTACTADO',
    'ENTREVISTA_CONCERTADA',
    'ENTREVISTA_REALIZADA',
    'SELECCIONADO',
    'INCORPORADO',
  ];

  @override
  void initState() {
    super.initState();

    estado = widget.candidato['estado'] ?? 'CV_RECIBIDO';
    motivoDescarte = widget.candidato['motivo_descarte'];

    if (widget.candidato['fecha_entrevista_programada'] != null) {
      fechaEntrevista = DateTime.tryParse(
        widget.candidato['fecha_entrevista_programada'].toString(),
      );
    }

    if (widget.candidato['fecha_proxima_accion'] != null) {
      fechaProxima = DateTime.tryParse(
        widget.candidato['fecha_proxima_accion'].toString(),
      );
    }
  }

  Color estadoColor(String e) {
    switch (e) {
      case 'CV_RECIBIDO':
        return const Color(0xFF2563EB);
      case 'CONTACTADO':
        return const Color(0xFFF97316);
      case 'ENTREVISTA_CONCERTADA':
        return const Color(0xFFEAB308);
      case 'ENTREVISTA_REALIZADA':
        return const Color(0xFF8B5CF6);
      case 'SELECCIONADO':
        return const Color(0xFF22C55E);
      case 'INCORPORADO':
        return const Color(0xFF14B8A6);
      case 'DESCARTADO':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String estadoTexto(String e) {
    switch (e) {
      case 'CV_RECIBIDO':
        return 'CV recibido';
      case 'CONTACTADO':
        return 'Contactado';
      case 'ENTREVISTA_CONCERTADA':
        return 'Entrevista concertada';
      case 'ENTREVISTA_REALIZADA':
        return 'Entrevista realizada';
      case 'SELECCIONADO':
        return 'Seleccionado';
      case 'INCORPORADO':
        return 'Incorporado';
      case 'DESCARTADO':
        return 'Descartado';
      default:
        return 'Sin estado';
    }
  }

  double progresoEstado() {
    final i = estadosFlow.indexOf(estado);
    if (i == -1) return estado == 'DESCARTADO' ? 1 : 0;
    return (i + 1) / estadosFlow.length;
  }

  String fechaTexto(DateTime? date) {
    if (date == null) return 'Sin fecha';
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  Future<void> llamar() async {
    final tel = widget.candidato['telefono'];

    if (tel == null || tel.toString().trim().isEmpty) return;

    await launchUrl(Uri.parse("tel:$tel"));
  }

  Future<void> verCV() async {
    final url = widget.candidato['cv_url'];

    if (url == null || url.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este candidato no tiene CV adjunto"),
        ),
      );
      return;
    }

    await launchUrl(
      Uri.parse(url.toString()),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> seleccionarEstado() async {
  final estados = [
    {
      "valor": "CV_RECIBIDO",
      "texto": "CV recibido",
      "icono": Icons.description_rounded,
    },
    {
      "valor": "CONTACTADO",
      "texto": "Contactado",
      "icono": Icons.phone_in_talk_rounded,
    },
    {
      "valor": "ENTREVISTA_CONCERTADA",
      "texto": "Entrevista concertada",
      "icono": Icons.event_available_rounded,
    },
    {
      "valor": "ENTREVISTA_REALIZADA",
      "texto": "Entrevista realizada",
      "icono": Icons.person_search_rounded,
    },
    {
      "valor": "SELECCIONADO",
      "texto": "Seleccionado",
      "icono": Icons.star_rounded,
    },
    {
      "valor": "INCORPORADO",
      "texto": "Incorporado",
      "icono": Icons.badge_rounded,
    },
    {
      "valor": "DESCARTADO",
      "texto": "Descartado",
      "icono": Icons.cancel_rounded,
    },
  ];

  final seleccionado = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: SafeArea(
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    "Cambiar estado del candidato",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "Selecciona en qué punto del proceso se encuentra.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 18),

                  ...estados.map((item) {
                    final valor = item["valor"] as String;
                    final color = estadoColor(valor);
                    final seleccionadoActual = estado == valor;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: seleccionadoActual
                            ? color.withOpacity(0.10)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: seleccionadoActual
                              ? color.withOpacity(0.35)
                              : Colors.black.withOpacity(0.04),
                        ),
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          leading: Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              item["icono"] as IconData,
                              color: color,
                            ),
                          ),
                          title: Text(
                            item["texto"] as String,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          trailing: seleccionadoActual
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: color,
                                )
                              : const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 15,
                                  color: Color(0xFF94A3B8),
                                ),
                          onTap: () => Navigator.pop(context, valor),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (seleccionado == null) return;

  if (seleccionado == "DESCARTADO") {
    await marcarDescartado();
  } else {
    setState(() {
      estado = seleccionado;
      motivoDescarte = null;
    });
  }
}

  Future<void> marcarDescartado() async {
    final controller = TextEditingController(text: motivoDescarte ?? '');

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Motivo de descarte",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Ejemplo: no interesado, perfil no encaja...",
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (motivo != null) {
      setState(() {
        estado = 'DESCARTADO';
        motivoDescarte = motivo.trim();
      });
    }
  }

  Future<void> guardar() async {
    setState(() => loading = true);

    try {
      await supabase.from('candidatos_captacion').update({
        'estado': estado,
        'motivo_descarte': motivoDescarte,
        'fecha_entrevista_programada': fechaEntrevista?.toIso8601String(),
        'fecha_proxima_accion': fechaProxima?.toIso8601String(),
      }).eq('id', widget.candidato['id']);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("❌ ERROR GUARDANDO CANDIDATO: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text("No se pudo guardar el candidato"),
          ),
        );
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> pickFecha({
    required DateTime? actual,
    required Function(DateTime) onPick,
  }) async {
    final d = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF111827),
            ),
          ),
          child: child!,
        );
      },
    );

    if (d != null) onPick(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidato;
    final color = estadoColor(estado);

    final nombre = c['nombre']?.toString() ?? 'Candidato sin nombre';
    final telefono = c['telefono']?.toString() ?? 'Sin teléfono';
    final email = c['email']?.toString() ?? 'Sin email';
    final origen = c['origen']?.toString() ?? 'Sin origen';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      bottomNavigationBar: _bottomSaveBar(),
      body: Stack(
        children: [
          const _TalentDetailBackground(),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
                    child: Column(
                      children: [
                        _heroCard(
                          nombre: nombre,
                          telefono: telefono,
                          email: email,
                          origen: origen,
                          color: color,
                        ),
                        const SizedBox(height: 18),
                        _quickActions(color),
                        const SizedBox(height: 18),
                        _pipelineCard(color),
                        const SizedBox(height: 18),
                        _datesCard(),
                        const SizedBox(height: 18),
                        _cvCard(),
                        if (estado == 'DESCARTADO') ...[
                          const SizedBox(height: 18),
                          _discardCard(),
                        ],
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          _SmallButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
            dark: false,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Ficha candidato",
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _SmallButton(
            icon: Icons.save_rounded,
            onTap: loading ? null : guardar,
            dark: true,
          ),
        ],
      ),
    );
  }

  Widget _heroCard({
    required String nombre,
    required String telefono,
    required String email,
    required String origen,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF111827),
            color,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            bottom: -46,
            child: Icon(
              Icons.person_search_rounded,
              size: 170,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusBadge(color),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.20),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        nombre.trim().isNotEmpty
                            ? nombre.trim()[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _heroInfo(Icons.phone_rounded, telefono),
              _heroInfo(Icons.mail_rounded, email),
              _heroInfo(Icons.campaign_rounded, origen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(Color color) {
    return GestureDetector(
      onTap: seleccionarEstado,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                estadoTexto(estado).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.78), size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(Color color) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.visibility_rounded,
            label: "Ver CV",
            color: const Color(0xFF2563EB),
            onTap: verCV,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.phone_in_talk_rounded,
            label: "Llamar",
            color: const Color(0xFF22C55E),
            onTap: llamar,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.swap_horiz_rounded,
            label: "Estado",
            color: color,
            onTap: seleccionarEstado,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.close_rounded,
            label: "Descartar",
            color: const Color(0xFFEF4444),
            onTap: marcarDescartado,
          ),
        ),
      ],
    );
  }

  Widget _pipelineCard(Color color) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon: Icons.timeline_rounded,
            title: "Pipeline del candidato",
            subtitle: "Evolución dentro del proceso de selección",
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LinearProgressIndicator(
              value: progresoEstado(),
              minHeight: 11,
              color: color,
              backgroundColor: Colors.black.withOpacity(0.06),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                "${(progresoEstado() * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "completado",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.45),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _ClickChip(
                text: estadoTexto(estado),
                color: color,
                onTap: seleccionarEstado,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datesCard() {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon: Icons.event_note_rounded,
            title: "Agenda de seguimiento",
            subtitle: "Programa entrevistas y próximas acciones",
          ),
          const SizedBox(height: 16),
          _DateRow(
            icon: Icons.calendar_month_rounded,
            title: "Entrevista",
            value: fechaTexto(fechaEntrevista),
            onTap: () {
              pickFecha(
                actual: fechaEntrevista,
                onPick: (d) => setState(() => fechaEntrevista = d),
              );
            },
          ),
          const SizedBox(height: 10),
          _DateRow(
            icon: Icons.alarm_rounded,
            title: "Próxima acción",
            value: fechaTexto(fechaProxima),
            onTap: () {
              pickFecha(
                actual: fechaProxima,
                onPick: (d) => setState(() => fechaProxima = d),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cvCard() {
    final tieneCV = widget.candidato['cv_url'] != null &&
        widget.candidato['cv_url'].toString().trim().isNotEmpty;

    return _WhiteCard(
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: tieneCV
                  ? const Color(0xFFEF4444).withOpacity(0.12)
                  : const Color(0xFF64748B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              tieneCV
                  ? Icons.picture_as_pdf_rounded
                  : Icons.description_outlined,
              color:
                  tieneCV ? const Color(0xFFEF4444) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tieneCV ? "CV disponible" : "CV no adjuntado",
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tieneCV
                      ? "Pulsa para abrir el currículum del candidato."
                      : "Este candidato todavía no tiene currículum asociado.",
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (tieneCV)
            _ClickChip(
              text: "Abrir",
              color: const Color(0xFF2563EB),
              onTap: verCV,
            ),
        ],
      ),
    );
  }

  Widget _discardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_rounded,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Motivo de descarte: ${motivoDescarte?.isNotEmpty == true ? motivoDescarte : 'Sin motivo indicado'}",
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF111827),
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
                  color: Color(0xFF111827),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.42),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomSaveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: MouseRegion(
          cursor: loading
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: SizedBox(
            height: 58,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : guardar,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Guardar cambios",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;

  const _WhiteCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool hovering = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = pressing
        ? 0.96
        : hovering
            ? 1.04
            : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) {
        setState(() {
          hovering = false;
          pressing = false;
        });
      },
      child: Listener(
        onPointerDown: (_) => setState(() => pressing = true),
        onPointerUp: (_) => setState(() => pressing = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: hovering
                        ? widget.color.withOpacity(0.22)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: hovering ? 22 : 14,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    widget.icon,
                    color: widget.color,
                    size: 25,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClickChip extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _ClickChip({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _DateRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: const Color(0xFF2563EB),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;

  const _SmallButton({
    required this.icon,
    required this.onTap,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: dark ? Colors.white : const Color(0xFF111827),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

class _TalentDetailBackground extends StatelessWidget {
  const _TalentDetailBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: _bubble(const Color(0xFF00C2FF), 250),
        ),
        Positioned(
          top: 250,
          left: -150,
          child: _bubble(const Color(0xFF8B5CF6), 280),
        ),
        Positioned(
          bottom: -150,
          right: -90,
          child: _bubble(const Color(0xFF22C55E), 260),
        ),
      ],
    );
  }

  Widget _bubble(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.13),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}