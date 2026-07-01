import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetalleVisitaScreen extends StatefulWidget {
  final Map<String, dynamic> visita;

  const DetalleVisitaScreen({
    super.key,
    required this.visita,
  });

  @override
  State<DetalleVisitaScreen> createState() => _DetalleVisitaScreenState();
}

class _DetalleVisitaScreenState extends State<DetalleVisitaScreen> {
  final supabase = Supabase.instance.client;

  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.visita;

    final nombre = _nombreCompleto(v);
    final estado = v['estado'] ?? 'Pendiente';
    final realizada = estado == 'Realizada';

    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        title: const Text(
          "Detalle visita",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              _header(nombre, estado, realizada),
              const SizedBox(height: 20),

              _section(
                title: "Información del cliente",
                icon: Icons.person_rounded,
                children: [
                  _infoTile(
                    icon: Icons.badge_rounded,
                    label: "Cliente",
                    value: nombre.isEmpty ? "Sin nombre" : nombre,
                  ),
                  _infoTile(
                    icon: Icons.phone_rounded,
                    label: "Teléfono",
                    value: v['telefono'] ?? "Sin teléfono",
                  ),
                ],
              ),

              const SizedBox(height: 18),

              _section(
                title: "Dirección",
                icon: Icons.location_on_rounded,
                children: [
                  _infoTile(
                    icon: Icons.route_rounded,
                    label: "Dirección completa",
                    value: _direccionCompleta(v),
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
                        child: _miniCard(
                          icon: Icons.event_available_rounded,
                          label: "Fecha",
                          value: _formatFecha(v['fecha_visita']),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _miniCard(
                          icon: Icons.schedule_rounded,
                          label: "Hora",
                          value: v['hora_visita'] ?? "Sin hora",
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if ((v['observaciones'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 18),
                _section(
                  title: "Observaciones",
                  icon: Icons.notes_rounded,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1724),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        v['observaciones'],
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if ((v['resultado'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 18),
                _section(
                  title: "Resultado",
                  icon: Icons.fact_check_rounded,
                  children: [
                    _infoTile(
                      icon: Icons.verified_rounded,
                      label: "Resultado visita",
                      value: v['resultado'],
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 28),

              _mainButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(String nombre, String estado, bool realizada) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  Icons.assignment_ind_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  nombre.isEmpty ? "Visita comercial" : nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _estadoChip(estado, realizada),
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

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1724),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF22D3EE), size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

  Widget _miniCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1724),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF22D3EE)),
          const SizedBox(height: 12),
          Text(
            label,
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
        ],
      ),
    );
  }

  Widget _estadoChip(String estado, bool realizada) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: realizada
            ? Colors.greenAccent.withOpacity(0.14)
            : Colors.orangeAccent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: realizada
              ? Colors.greenAccent.withOpacity(0.35)
              : Colors.orangeAccent.withOpacity(0.35),
        ),
      ),
      child: Text(
        estado.isEmpty ? "Pendiente" : estado,
        style: TextStyle(
          color: realizada ? Colors.greenAccent : Colors.orangeAccent,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _mainButton() {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: saving ? null : gestionarVisita,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22D3EE),
          disabledBackgroundColor: Colors.white12,
          foregroundColor: const Color(0xFF07111B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: saving
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
                  Icon(Icons.manage_accounts_rounded),
                  SizedBox(width: 10),
                  Text(
                    "Gestionar visita",
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

  void gestionarVisita() {
    String resultado = "Realizada con venta";
    DateTime? nuevaFecha;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF102331).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
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
                              Icons.fact_check_rounded,
                              color: Color(0xFF22D3EE),
                            ),
                            SizedBox(width: 10),
                            Text(
                              "Gestionar visita",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        DropdownButtonFormField<String>(
                          value: resultado,
                          dropdownColor: const Color(0xFF0B1724),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: InputDecoration(
                            labelText: "Resultado",
                            labelStyle: const TextStyle(color: Colors.white54),
                            prefixIcon: const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF22D3EE),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0B1724),
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
                              ),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Realizada con venta",
                              child: Text("Realizada con venta"),
                            ),
                            DropdownMenuItem(
                              value: "Realizada sin venta",
                              child: Text("Realizada sin venta"),
                            ),
                            DropdownMenuItem(
                              value: "Pospuesta",
                              child: Text("Pospuesta"),
                            ),
                          ],
                          onChanged: (v) {
                            setModal(() {
                              resultado = v!;
                            });
                          },
                        ),

                        if (resultado == "Pospuesta") ...[
                          const SizedBox(height: 16),
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2035),
                                initialDate: DateTime.now(),
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
                                setModal(() {
                                  nuevaFecha = picked;
                                });
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B1724),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_repeat_rounded,
                                    color: Color(0xFF22D3EE),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      nuevaFecha == null
                                          ? "Seleccionar nueva fecha"
                                          : "${nuevaFecha!.day.toString().padLeft(2, '0')}/${nuevaFecha!.month.toString().padLeft(2, '0')}/${nuevaFecha!.year}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (resultado == "Pospuesta" &&
                                  nuevaFecha == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      "Selecciona la nueva fecha",
                                    ),
                                    backgroundColor: const Color(0xFFE11D48),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                );
                                return;
                              }

                              await _guardarGestion(
                                resultado: resultado,
                                nuevaFecha: nuevaFecha,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22D3EE),
                              foregroundColor: const Color(0xFF07111B),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text(
                              "Guardar gestión",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _guardarGestion({
    required String resultado,
    required DateTime? nuevaFecha,
  }) async {
    try {
      setState(() => saving = true);

      if (resultado == "Pospuesta") {
        await supabase.from('visitas').update({
          'estado': 'Pendiente',
          'fecha_visita': nuevaFecha!.toIso8601String(),
        }).eq('id', widget.visita['id']);
      } else {
        await supabase.from('visitas').update({
          'estado': 'Realizada',
          'resultado': resultado,
        }).eq('id', widget.visita['id']);
      }

      if (!mounted) return;

      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Error al guardar la gestión"),
          backgroundColor: const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  String _nombreCompleto(Map<String, dynamic> v) {
    final nombreCliente = (v['nombre_cliente'] ?? '').toString().trim();

    if (nombreCliente.isNotEmpty) return nombreCliente;

    final nombre = (v['nombre'] ?? '').toString().trim();
    final apellidos = (v['apellidos'] ?? '').toString().trim();

    return "$nombre $apellidos".trim();
  }

  String _direccionCompleta(Map<String, dynamic> v) {
    final partes = [
      v['direccion'],
      v['numero'],
      v['codigo_postal'] ?? v['cp'],
      v['poblacion'],
      v['provincia'],
    ]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .toList();

    if (partes.isEmpty) return "Sin dirección";

    return partes.join(", ");
  }

  String _formatFecha(dynamic value) {
    if (value == null) return "Sin fecha";

    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
    } catch (_) {
      return value.toString();
    }
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