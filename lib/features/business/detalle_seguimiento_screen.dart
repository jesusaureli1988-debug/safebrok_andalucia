import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/business/referencia_diaria_screen.dart';

class DetalleSeguimientoScreen extends StatefulWidget {
  final Map<String, dynamic> seguimiento;

  const DetalleSeguimientoScreen({
    super.key,
    required this.seguimiento,
  });

  @override
  State<DetalleSeguimientoScreen> createState() =>
      _DetalleSeguimientoScreenState();
}

class _DetalleSeguimientoScreenState extends State<DetalleSeguimientoScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> historico = [];
  bool loadingHistorico = true;

  @override
  void initState() {
    super.initState();
    cargarHistorico();
  }

  Future<void> cargarHistorico() async {
    try {
      setState(() => loadingHistorico = true);

      final data = await supabase
          .from('seguimiento_clientes')
          .select()
          .eq('cliente_id', widget.seguimiento['cliente_id'])
          .eq('estado', 'Realizada')
          .order('proxima_llamada', ascending: false);

      if (!mounted) return;

      setState(() {
        historico = List<Map<String, dynamic>>.from(data);
        loadingHistorico = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loadingHistorico = false);
      _snack("Error al cargar el histórico");
    }
  }

  void _snack(String text, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  String _txt(dynamic value, {String fallback = '-'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _fechaBonita(dynamic value) {
    if (value == null) return '-';

    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/"
          "${fecha.month.toString().padLeft(2, '0')}/"
          "${fecha.year}";
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _txt(
      widget.seguimiento['nombre'],
      fallback: 'Cliente sin nombre',
    );

    final producto = _txt(
      widget.seguimiento['producto'],
      fallback: 'Producto no indicado',
    );

    final telefono = _txt(widget.seguimiento['telefono']);
    final fechaEfecto = _fechaBonita(widget.seguimiento['fecha_efecto']);

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      body: Stack(
        children: [
          const _PremiumBackground(),

          SafeArea(
            child: RefreshIndicator(
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF102331),
              onRefresh: cargarHistorico,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  _heroCard(
                    nombre: nombre,
                    producto: producto,
                    telefono: telefono,
                    fechaEfecto: fechaEfecto,
                  ),
                  const SizedBox(height: 18),
                  _stats(),
                  const SizedBox(height: 22),
                  _sectionTitle(),

                  if (loadingHistorico)
                    const Padding(
                      padding: EdgeInsets.only(top: 34),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF22D3EE),
                        ),
                      ),
                    )
                  else if (historico.isEmpty)
                    _emptyHistorico()
                  else
                    ...historico.asMap().entries.map(
                          (entry) => _historicoCard(
                            entry.value,
                            entry.key,
                            historico.length,
                          ),
                        ),
                ],
              ),
            ),
          ),

          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: SafeArea(
              child: _bottomAction(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        _glassButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            "Contacto diario",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
        ),
        _glassButton(
          icon: Icons.phone_in_talk_rounded,
          accent: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: accent
              ? const Color(0xFF22D3EE).withOpacity(0.12)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent
                ? const Color(0xFF22D3EE).withOpacity(0.35)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Icon(
          icon,
          color: accent ? const Color(0xFF22D3EE) : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _heroCard({
    required String nombre,
    required String producto,
    required String telefono,
    required String fechaEfecto,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF22D3EE).withOpacity(0.75),
            const Color(0xFF2563EB).withOpacity(0.30),
            Colors.white.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.22),
            blurRadius: 38,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF101E2D),
              Color(0xFF07111B),
              Color(0xFF050B12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusPill(
              text: "CONTACTO EN SEGUIMIENTO",
              icon: Icons.radar_rounded,
              color: const Color(0xFF22D3EE),
            ),
            const SizedBox(height: 20),

            Text(
              nombre,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                height: 1.05,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFF22D3EE),
                  size: 19,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    producto,
                    style: const TextStyle(
                      color: Color(0xFF22D3EE),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            Row(
              children: [
                Expanded(
                  child: _infoBox(
                    icon: Icons.phone_rounded,
                    title: "Teléfono",
                    value: telefono,
                    color: const Color(0xFF22D3EE),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _infoBox(
                    icon: Icons.event_available_rounded,
                    title: "Fecha efecto",
                    value: fechaEfecto,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            title: "Llamadas realizadas",
            value: historico.length.toString(),
            icon: Icons.history_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            title: "Estado",
            value: _txt(widget.seguimiento['estado'], fallback: 'Pendiente'),
            icon: Icons.flag_rounded,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF22D3EE), size: 26),
              const SizedBox(width: 12),
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
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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
    Widget _sectionTitle() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            "Histórico de llamadas",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Text(
            "${historico.length}",
            style: const TextStyle(
              color: Color(0xFF22D3EE),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _historicoCard(
    Map<String, dynamic> h,
    int index,
    int total,
  ) {
    final resultado = _txt(h['resultado']);
    final observaciones = _txt(
      h['observaciones'],
      fallback: 'Sin observaciones',
    );
    final fecha = _fechaBonita(h['proxima_llamada']);

    Color resultColor = Colors.greenAccent;
    IconData resultIcon = Icons.check_circle_rounded;

    if (resultado.toLowerCase().contains('regular')) {
      resultColor = Colors.orangeAccent;
      resultIcon = Icons.remove_circle_rounded;
    }

    if (resultado.toLowerCase().contains('negativa')) {
      resultColor = Colors.redAccent;
      resultIcon = Icons.cancel_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: resultColor.withOpacity(0.13),
                  border: Border.all(color: resultColor.withOpacity(0.45)),
                  boxShadow: [
                    BoxShadow(
                      color: resultColor.withOpacity(0.15),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Icon(resultIcon, color: resultColor, size: 28),
              ),
              if (index != total - 1)
                Container(
                  width: 2,
                  height: 64,
                  margin: const EdgeInsets.only(top: 8),
                  color: Colors.white.withOpacity(0.10),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    resultColor.withOpacity(0.11),
                    Colors.white.withOpacity(0.060),
                    Colors.white.withOpacity(0.035),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: resultColor.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resultado,
                    style: TextStyle(
                      color: resultColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.white54,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        fecha,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    observaciones,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHistorico() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            color: Colors.white.withOpacity(0.35),
            size: 58,
          ),
          const SizedBox(height: 15),
          const Text(
            "Sin llamadas realizadas",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Cuando gestiones este contacto, aparecerá aquí el histórico de llamadas.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.25),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: gestionarLlamada,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text("Gestionar llamada"),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22D3EE),
          foregroundColor: const Color(0xFF061018),
          elevation: 0,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void gestionarLlamada() {
    String resultado = "Satisfactoria";
    String observaciones = "";
    bool aportaReferencia = false;
    String estadoFinal = "Realizada";
    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07111B).withOpacity(0.98),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: const Color(0xFF22D3EE).withOpacity(0.28),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),

                          const SizedBox(height: 20),

                          const Row(
                            children: [
                              Icon(
                                Icons.phone_callback_rounded,
                                color: Color(0xFF22D3EE),
                                size: 30,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Gestionar llamada",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          _premiumDropdown(
                            value: resultado,
                            label: "Resultado de la llamada",
                            icon: Icons.fact_check_rounded,
                            items: const [
                              "Satisfactoria",
                              "Regular",
                              "Negativa",
                            ],
                            onChanged: (v) {
                              setModal(() => resultado = v);
                            },
                          ),

                          const SizedBox(height: 14),

                          _premiumDropdown(
                            value: estadoFinal,
                            label: "Estado final",
                            icon: Icons.flag_rounded,
                            items: const [
                              "Realizada",
                              "En curso",
                            ],
                            onChanged: (v) {
                              setModal(() => estadoFinal = v);
                            },
                          ),

                          const SizedBox(height: 14),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: aportaReferencia
                                  ? Colors.greenAccent.withOpacity(0.10)
                                  : Colors.white.withOpacity(0.055),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: aportaReferencia
                                    ? Colors.greenAccent.withOpacity(0.42)
                                    : Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: SwitchListTile(
                              value: aportaReferencia,
                              activeColor: Colors.greenAccent,
                              title: const Text(
                                "¿Aporta referencia?",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: const Text(
                                "Si aporta referencia, se abrirá la pantalla para crearla.",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              onChanged: (v) {
                                setModal(() => aportaReferencia = v);
                              },
                            ),
                          ),

                          const SizedBox(height: 14),

                          TextField(
                            maxLines: 4,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            onChanged: (v) => observaciones = v,
                            decoration: InputDecoration(
                              labelText: "Observaciones",
                              labelStyle: const TextStyle(color: Colors.white60),
                              filled: true,
                              fillColor: const Color(0xFF0B1724),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: Color(0xFF22D3EE),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: guardando
                                  ? null
                                  : () async {
                                      setModal(() => guardando = true);

                                      try {
                                        await supabase
                                            .from('seguimiento_clientes')
                                            .update({
                                          'estado': estadoFinal,
                                          'resultado': resultado,
                                          'observaciones': observaciones,
                                          'referencia': aportaReferencia,
                                        }).eq(
                                          'id',
                                          widget.seguimiento['id'],
                                        );

                                        if (!mounted) return;

                                        Navigator.pop(context);

                                        await cargarHistorico();

                                        if (aportaReferencia) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ReferenciaDiariaScreen(),
                                            ),
                                          );
                                        } else {
                                          _snack(
                                            "Seguimiento guardado correctamente",
                                            ok: true,
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        _snack("Error al guardar seguimiento");
                                      } finally {
                                        if (mounted) {
                                          setModal(() => guardando = false);
                                        }
                                      }
                                    },
                              icon: guardando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF061018),
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                guardando
                                    ? "Guardando..."
                                    : "Guardar seguimiento",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22D3EE),
                                disabledBackgroundColor: Colors.white12,
                                foregroundColor: const Color(0xFF061018),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
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

  Widget _premiumDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFF102331),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: const Color(0xFF22D3EE)),
        filled: true,
        fillColor: const Color(0xFF0B1724),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(
            color: Color(0xFF22D3EE),
            width: 1.4,
          ),
        ),
      ),
      iconEnabledColor: const Color(0xFF22D3EE),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e,
              child: Text(e),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        onChanged(v);
      },
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
              colors: [
                Color(0xFF02060A),
                Color(0xFF061018),
                Color(0xFF071827),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _blurCircle(
            240,
            const Color(0xFF22D3EE).withOpacity(0.18),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -110,
          child: _blurCircle(
            280,
            Colors.blueAccent.withOpacity(0.12),
          ),
        ),
      ],
    );
  }

  static Widget _blurCircle(double size, Color color) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 90,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}
  