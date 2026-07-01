import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sales/create_sale_wizard.dart';

class ClientDetailScreen extends StatefulWidget {
  final String clientId;

  const ClientDetailScreen({
    super.key,
    required this.clientId,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  Map<String, dynamic>? client;
  List<Map<String, dynamic>> ventas = [];

  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (isRefresh) {
        refreshing = true;
      } else {
        loading = true;
      }
      errorMessage = null;
    });

    final supabase = Supabase.instance.client;

    try {
      final clientRes = await supabase
          .from('clientes')
          .select('*')
          .eq('id', widget.clientId)
          .single();

      final ventasRes = await supabase
          .from('ventas')
          .select('*')
          .eq('cliente_id', widget.clientId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        client = Map<String, dynamic>.from(clientRes);
        ventas = List<Map<String, dynamic>>.from(ventasRes);
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("ERROR CLIENT DETAIL: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudo cargar la ficha del cliente";
      });
    }
  }

  double get totalEuros {
    return ventas.fold<double>(
      0,
      (sum, v) {
        final value = v['precio'];
        if (value is num) return sum + value.toDouble();
        return sum + (double.tryParse(value?.toString() ?? '0') ?? 0);
      },
    );
  }

  int get totalProductos {
    final productos = ventas
        .map((v) => (v['producto'] ?? '').toString().trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    return productos.length;
  }

  String get clientName {
    if (client == null) return "Cliente";

    final nombre = (client!['nombre'] ?? '').toString().trim();
    final apellidos = (client!['apellidos'] ?? '').toString().trim();
    final fullName = "$nombre $apellidos".trim();

    return fullName.isEmpty ? "Cliente sin nombre" : fullName;
  }

  String get initial {
    final nombre = (client?['nombre'] ?? '').toString().trim();
    if (nombre.isEmpty) return "C";
    return nombre.substring(0, 1).toUpperCase();
  }

  String _text(dynamic value, {String fallback = "No informado"}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      floatingActionButton: client == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 12,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                "Nueva póliza",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateSaleWizard(
                      clientId: widget.clientId,
                    ),
                  ),
                );

                loadData(isRefresh: true);
              },
            ),
      appBar: AppBar(
        title: Text(
          clientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Actualizar",
            onPressed: refreshing ? null : () => loadData(isRefresh: true),
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : client == null
                    ? _NotFoundState(
                        message: errorMessage ?? "Cliente no encontrado",
                        onRetry: () => loadData(),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF38BDF8),
                        backgroundColor: const Color(0xFF0F172A),
                        onRefresh: () => loadData(isRefresh: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                          children: [
                            _ClientHeaderCard(
                              initial: initial,
                              name: clientName,
                              phone: _text(client!['telefono']),
                              email: _text(client!['email']),
                            ),
                            if (errorMessage != null) ...[
                              const SizedBox(height: 16),
                              _ErrorBox(
                                message: errorMessage!,
                                onRetry: () => loadData(),
                              ),
                            ],
                            const SizedBox(height: 18),
                            _KpiGrid(
                              ventas: ventas.length,
                              totalEuros: totalEuros,
                              productos: totalProductos,
                            ),
                            const SizedBox(height: 24),
                            _SectionTitle(
                              title: "Información del cliente",
                              subtitle: "Datos principales de contacto",
                            ),
                            const SizedBox(height: 12),
                            _InfoPanel(
                              rows: [
                                _InfoRowData(
                                  icon: Icons.phone_rounded,
                                  label: "Teléfono",
                                  value: _text(client!['telefono']),
                                ),
                                _InfoRowData(
                                  icon: Icons.email_rounded,
                                  label: "Email",
                                  value: _text(client!['email']),
                                ),
                                _InfoRowData(
                                  icon: Icons.badge_rounded,
                                  label: "DNI",
                                  value: _text(client!['dni']),
                                ),
                                _InfoRowData(
                                  icon: Icons.location_on_rounded,
                                  label: "Dirección",
                                  value: _text(client!['direccion']),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _SectionTitle(
                              title: "Pólizas",
                              subtitle:
                                  "${ventas.length} pólizas registradas en la ficha",
                            ),
                            const SizedBox(height: 12),
                            if (ventas.isEmpty)
                              const _EmptySalesState()
                            else
                              ...ventas.map((v) => _SaleCard(v: v)),
                          ],
                        ),
                      ),
          ),
        ],
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
                Color(0xFF0B1F2E),
                Color(0xFF12384E),
              ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _GlowCircle(
            size: 230,
            color: const Color(0xFF38BDF8).withOpacity(0.24),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: _GlowCircle(
            size: 260,
            color: const Color(0xFF22C55E).withOpacity(0.16),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _ClientHeaderCard extends StatelessWidget {
  final String initial;
  final String name;
  final String phone;
  final String email;

  const _ClientHeaderCard({
    required this.initial,
    required this.name,
    required this.phone,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != "No informado";
    final hasEmail = email != "No informado";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF2563EB),
                  Color(0xFF38BDF8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StatusChip(),
                const SizedBox(height: 9),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _MiniLine(
                  icon: Icons.phone_rounded,
                  text: hasPhone ? phone : "Sin teléfono",
                  muted: !hasPhone,
                ),
                const SizedBox(height: 5),
                _MiniLine(
                  icon: Icons.email_rounded,
                  text: hasEmail ? email : "Sin email",
                  muted: !hasEmail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF22C55E).withOpacity(0.28),
        ),
      ),
      child: const Text(
        "CLIENTE ACTIVO",
        style: TextStyle(
          color: Color(0xFFBBF7D0),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;

  const _MiniLine({
    required this.icon,
    required this.text,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: muted
              ? Colors.white.withOpacity(0.28)
              : const Color(0xFF7DD3FC),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted
                  ? Colors.white.withOpacity(0.36)
                  : Colors.white.withOpacity(0.66),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int ventas;
  final double totalEuros;
  final int productos;

  const _KpiGrid({
    required this.ventas,
    required this.totalEuros,
    required this.productos,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: "Pólizas",
            value: ventas.toString(),
            icon: Icons.description_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            title: "Total €",
            value: "${totalEuros.toStringAsFixed(0)}€",
            icon: Icons.euro_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            title: "Productos",
            value: productos.toString(),
            icon: Icons.inventory_2_rounded,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF7DD3FC),
            size: 24,
          ),
          const SizedBox(height: 9),
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
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InfoRowData {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _InfoPanel extends StatelessWidget {
  final List<_InfoRowData> rows;

  const _InfoPanel({
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _InfoRow(row: rows[i]),
            if (i != rows.length - 1)
              Divider(
                height: 1,
                color: Colors.white.withOpacity(0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final _InfoRowData row;

  const _InfoRow({
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final muted = row.value == "No informado";

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 14,
      ),
      child: Row(
        children: [
          Icon(
            row.icon,
            color: muted
                ? Colors.white.withOpacity(0.30)
                : const Color(0xFF7DD3FC),
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted
                    ? Colors.white.withOpacity(0.35)
                    : Colors.white.withOpacity(0.86),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Map<String, dynamic> v;

  const _SaleCard({
    required this.v,
  });

  String _text(dynamic value, {String fallback = "No informado"}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _price(dynamic value) {
    if (value == null) return "0€";
    if (value is num) return "${value.toStringAsFixed(0)}€";
    final parsed = double.tryParse(value.toString());
    if (parsed == null) return "${value.toString()}€";
    return "${parsed.toStringAsFixed(0)}€";
  }

  @override
  Widget build(BuildContext context) {
    final producto = _text(v['producto'], fallback: "Producto sin nombre");
    final compania = _text(v['compania'], fallback: "Compañía no informada");
    final precio = _price(v['precio']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22C55E),
                  Color(0xFF38BDF8),
                ],
              ),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  compania,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF38BDF8).withOpacity(0.25),
              ),
            ),
            child: Text(
              precio,
              style: const TextStyle(
                color: Color(0xFFBAE6FD),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySalesState extends StatelessWidget {
  const _EmptySalesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin pólizas registradas",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Pulsa en “Nueva póliza” para crear la primera venta de este cliente.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _NotFoundState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_rounded,
              size: 60,
              color: Colors.white.withOpacity(0.35),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Reintentar"),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text("Reintentar"),
          ),
        ],
      ),
    );
  }
}