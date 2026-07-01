import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class RecibosAgenteScreen extends StatefulWidget {
  const RecibosAgenteScreen({super.key});

  @override
  State<RecibosAgenteScreen> createState() => _RecibosAgenteScreenState();
}

class _RecibosAgenteScreenState extends State<RecibosAgenteScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String filtro = 'Todos';
  String searchText = '';

  List<Map<String, dynamic>> recibos = [];

  @override
  void initState() {
    super.initState();
    cargarRecibos();
  }

  Future<void> cargarRecibos() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final data = await supabase
          .from('recibos')
          .select()
          .eq('agente', user.id)
          .order('fecha', ascending: false);

      if (!mounted) return;

      setState(() {
        recibos = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR RECIBOS: $e');

      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando recibos: $e')),
      );
    }
  }

  List<Map<String, dynamic>> get recibosFiltrados {
    return recibos.where((r) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      final poliza = (r['poliza'] ?? '').toString().toLowerCase();
      final cliente = (r['cliente'] ?? '').toString().toLowerCase();
      final compania = (r['compania'] ?? '').toString().toLowerCase();
      final motivo = (r['motivo'] ?? '').toString().toLowerCase();

      final search = searchText.toLowerCase();

      final matchSearch = search.isEmpty ||
          poliza.contains(search) ||
          cliente.contains(search) ||
          compania.contains(search) ||
          motivo.contains(search);

      final matchFiltro = filtro == 'Todos'
          ? true
          : estado == filtro.toLowerCase();

      return matchSearch && matchFiltro;
    }).toList();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  double get totalPendiente {
    return recibos.where((r) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      return estado == 'pendiente' ||
          estado == 'devuelto' ||
          estado == 'en gestión' ||
          estado == 'en gestion';
    }).fold(0.0, (sum, r) => sum + _money(r['importe']));
  }

  int get totalRecibos => recibos.length;

  int get pendientes {
    return recibos.where((r) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      return estado == 'pendiente' ||
          estado == 'devuelto' ||
          estado == 'en gestión' ||
          estado == 'en gestion';
    }).length;
  }

  int get pagados {
    return recibos.where((r) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      return estado == 'pagado';
    }).length;
  }

  String _formatFecha(dynamic fecha) {
    if (fecha == null) return 'Sin fecha';

    try {
      final dt = DateTime.parse(fecha.toString());
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return fecha.toString();
    }
  }

  Color _estadoColor(String estado) {
    final e = estado.toLowerCase();

    if (e == 'pagado') return Colors.greenAccent;
    if (e == 'pendiente') return Colors.orangeAccent;
    if (e == 'devuelto') return Colors.redAccent;
    if (e == 'en gestión' || e == 'en gestion') return Colors.cyanAccent;
    if (e == 'anulado') return Colors.white38;

    return Colors.white54;
  }
  

  IconData _estadoIcon(String estado) {
    final e = estado.toLowerCase();

    if (e == 'pagado') return Icons.verified_rounded;
    if (e == 'pendiente') return Icons.schedule_rounded;
    if (e == 'devuelto') return Icons.warning_rounded;
    if (e == 'en gestión' || e == 'en gestion') {
      return Icons.support_agent_rounded;
    }
    if (e == 'anulado') return Icons.block_rounded;

    return Icons.receipt_long_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050B12),
        elevation: 0,
        title: const Text(
          'Recibos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: cargarRecibos,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : RefreshIndicator(
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFF102331),
              onRefresh: cargarRecibos,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                children: [
                  _header(),
                  const SizedBox(height: 14),
                  _kpis(),
                  const SizedBox(height: 14),
                  _search(),
                  const SizedBox(height: 12),
                  _filters(),
                  const SizedBox(height: 14),

                  if (recibosFiltrados.isEmpty)
                    _emptyState()
                  else
                    ...recibosFiltrados.map((r) => _reciboCard(r)),
                ],
              ),
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
            Color(0xFF063151),
            Color(0xFF071A2E),
            Color(0xFF050B12),
          ],
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
                  Colors.cyanAccent,
                  Color(0xFF1D7CFF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.25),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.black,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de recibos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Impagos, pagos, pólizas e histórico',
                  style: TextStyle(
                    color: Colors.white60,
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

  Widget _kpis() {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: 'Pendiente',
            value: '${totalPendiente.toStringAsFixed(2)} €',
            icon: Icons.warning_rounded,
            color: Colors.orangeAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: 'Recibos',
            value: totalRecibos.toString(),
            icon: Icons.receipt_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: 'Pagados',
            value: pagados.toString(),
            icon: Icons.verified_rounded,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _search() {
    return TextField(
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      onChanged: (v) => setState(() => searchText = v),
      decoration: InputDecoration(
        hintText: 'Buscar póliza, cliente, compañía o motivo...',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.white.withOpacity(0.055),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.09)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.cyanAccent),
        ),
      ),
    );
  }

  Widget _filters() {
    final filtros = [
      'Todos',
      'Pendiente',
      'Devuelto',
      'En gestión',
      'Pagado',
      'Anulado',
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filtros.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = filtros[index];
          final selected = filtro == item;

          return GestureDetector(
            onTap: () => setState(() => filtro = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.cyanAccent
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected
                      ? Colors.cyanAccent
                      : Colors.white.withOpacity(0.10),
                ),
              ),
              child: Text(
                item,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _reciboCard(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? 'Pendiente').toString();
    final color = _estadoColor(estado);

    final importe = _money(r['importe']);
    final poliza = (r['poliza'] ?? 'Sin póliza').toString();
    final cliente = (r['cliente'] ?? 'Sin cliente').toString();
    final compania = (r['compania'] ?? 'Sin compañía').toString();
    final motivo = (r['motivo'] ?? '').toString();
    final fecha = _formatFecha(r['fecha']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReciboDetalleScreen(recibo: r),
              ),
            );

            cargarRecibos();
          },
          child: Ink(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.035),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: color.withOpacity(0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(_estadoIcon(estado), color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cliente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Póliza $poliza',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${importe.toStringAsFixed(2)} €',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            estado,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _miniInfo(Icons.business_rounded, compania, Colors.cyanAccent),
                    const SizedBox(width: 10),
                    _miniInfo(Icons.calendar_today_rounded, fecha, Colors.orangeAccent),
                  ],
                ),
                if (motivo.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            motivo,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 84,
            color: Colors.white.withOpacity(0.16),
          ),
          const SizedBox(height: 18),
          const Text(
            'Sin recibos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No hay recibos para este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ReciboDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> recibo;

  const ReciboDetalleScreen({
    super.key,
    required this.recibo,
  });

  @override
  State<ReciboDetalleScreen> createState() => _ReciboDetalleScreenState();
}

class _ReciboDetalleScreenState extends State<ReciboDetalleScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> comentarios = [];
  List<Map<String, dynamic>> pagos = [];

  final comentarioController = TextEditingController();
  final pagoController = TextEditingController();

  String metodoPago = 'Tarjeta';

  @override
  void initState() {
    super.initState();
    cargarDetalle();
  }

  @override
  void dispose() {
    comentarioController.dispose();
    pagoController.dispose();
    super.dispose();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatFecha(dynamic fecha) {
    if (fecha == null) return 'Sin fecha';

    try {
      final dt = DateTime.parse(fecha.toString());
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return fecha.toString();
    }
  }

  Color _estadoColor(String estado) {
    final e = estado.toLowerCase();

    if (e == 'pagado') return Colors.greenAccent;
    if (e == 'pendiente') return Colors.orangeAccent;
    if (e == 'devuelto') return Colors.redAccent;
    if (e == 'en gestión' || e == 'en gestion') return Colors.cyanAccent;
    if (e == 'anulado') return Colors.white38;

    return Colors.white54;
  }
  bool get accionesPermitidas {
  final estado = (widget.recibo['estado'] ?? '').toString().toLowerCase();

  return estado == 'devuelto' ||
      estado == 'impagado' ||
      estado == 'pendiente' ||
      estado == 'en gestión' ||
      estado == 'en gestion';
}



Future<void> abrirModalEnviarTpv() async {
  if (!accionesPermitidas) {
    _accionNoPermitida();
    return;
  }

  final emailController = TextEditingController();

  final poliza = widget.recibo['poliza']?.toString() ?? '';
  final cliente = widget.recibo['cliente']?.toString() ?? '';
  final compania = widget.recibo['compania']?.toString() ?? '';
  final importe = _money(widget.recibo['importe']);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF071421),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(28),
      ),
    ),
    builder: (_) {
      return Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Enviar enlace TPV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 16),

            _modalInfo('Cliente', cliente),
            _modalInfo('Póliza', poliza),
            _modalInfo('Compañía', compania),
            _modalInfo('Importe', '${importe.toStringAsFixed(2)} €'),

            const SizedBox(height: 16),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Email destinatario'),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  enviarEmailTpv(emailController.text.trim());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'ENVIAR EMAIL',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> enviarEmailTpv(String emailDestino) async {
  if (emailDestino.isEmpty || !emailDestino.contains('@')) {
    _snack('Introduce un email válido');
    return;
  }

  if (!accionesPermitidas) {
    _accionNoPermitida();
    return;
  }

  const url = 'https://www.fiatc.es/atencion-cliente/pago-recibos';

  final poliza = widget.recibo['poliza']?.toString() ?? '';
  final cliente = widget.recibo['cliente']?.toString() ?? '';
  final importe = _money(widget.recibo['importe']);

  try {
    final response = await supabase.functions.invoke(
      'enviar-tpv-recibo',
      body: {
        'email': emailDestino,
        'cliente': cliente,
        'poliza': poliza,
        'importe': importe,
        'url': url,
      },
    );

    if (response.status != 200) {
      debugPrint('ERROR FUNCTION TPV: ${response.data}');
      _snack('No se pudo enviar el email');
      return;
    }

    await supabase.from('recibos_comentarios').insert({
      'poliza': widget.recibo['poliza'],
      'comentario': 'Email con enlace TPV enviado a $emailDestino',
      'usuario': supabase.auth.currentUser?.email ??
          supabase.auth.currentUser?.id ??
          'Usuario',
    });

    await supabase
        .from('recibos')
        .update({'estado': 'En gestión'})
        .eq('poliza', widget.recibo['poliza']);

    await cargarDetalle();

    _snack('Email enviado correctamente');
  } catch (e) {
    debugPrint('ERROR ENVIANDO EMAIL TPV: $e');
    _snack('Error enviando email: $e');
  }
}

Widget _modalInfo(String title, String value) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.055),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value.isEmpty ? 'Sin dato' : value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

void _accionNoPermitida() {
  _snack('Este recibo ya está pagado/cobrado. No se pueden realizar acciones.');
}

void _snack(String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF102331),
      behavior: SnackBarBehavior.floating,
      content: Text(
        text,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

  Future<void> cargarDetalle() async {
    final poliza = widget.recibo['poliza'];

    try {
      final comentariosData = await supabase
          .from('recibos_comentarios')
          .select()
          .eq('poliza', poliza)
          .order('created_at', ascending: false);

      final pagosData = await supabase
          .from('recibos_pagos')
          .select()
          .eq('poliza', poliza)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        comentarios = List<Map<String, dynamic>>.from(comentariosData);
        pagos = List<Map<String, dynamic>>.from(pagosData);
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR DETALLE RECIBO: $e');

      if (!mounted) return;

      setState(() => loading = false);
    }
  }

  Future<void> anadirComentario() async {
    final text = comentarioController.text.trim();
    if (text.isEmpty) return;

    final user = supabase.auth.currentUser;

    await supabase.from('recibos_comentarios').insert({
      'poliza': widget.recibo['poliza'],
      'comentario': text,
      'usuario': user?.email ?? user?.id ?? 'Usuario',
    });

    comentarioController.clear();
    cargarDetalle();
  }

  Future<void> registrarPago() async {
    final importe = double.tryParse(
      pagoController.text.trim().replaceAll(',', '.'),
    );

    if (importe == null || importe <= 0) return;

    final poliza = widget.recibo['poliza'];

    await supabase.from('recibos_pagos').insert({
      'poliza': poliza,
      'importe': importe,
      'metodo': metodoPago,
      'estado': 'Pagado',
    });

    await supabase
        .from('recibos')
        .update({'estado': 'Pagado'})
        .eq('poliza', poliza);

    pagoController.clear();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pago registrado correctamente')),
    );

    cargarDetalle();
  }

  @override
  Widget build(BuildContext context) {
    final recibo = widget.recibo;

    final estado = (recibo['estado'] ?? 'Pendiente').toString();
    final color = _estadoColor(estado);
    final importe = _money(recibo['importe']);
    final poliza = (recibo['poliza'] ?? '').toString();
    final cliente = (recibo['cliente'] ?? 'Sin cliente').toString();
    final compania = (recibo['compania'] ?? 'Sin compañía').toString();
    final motivo = (recibo['motivo'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050B12),
        elevation: 0,
        title: const Text(
          'Detalle recibo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.20),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(color: color.withOpacity(0.28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Póliza $poliza · $compania',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${importe.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          estado,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (motivo.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Motivo: $motivo',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 18),

               _section(
  title: 'Gestión de cobro',
  child: Column(
    children: [

     _paymentAction(
  icon: Icons.link_rounded,
  color: accionesPermitidas ? Colors.cyanAccent : Colors.grey,
  title: 'Enviar enlace de pago',
  subtitle: accionesPermitidas
      ? 'Preparar email con enlace TPV'
      : 'No disponible para recibos pagados',
  onTap: abrirModalEnviarTpv,
),

      const SizedBox(height: 10),

      _paymentAction(
        icon: Icons.account_balance_rounded,
        color: Colors.orangeAccent,
        title: 'Registrar transferencia',
        subtitle: 'Añadir justificante bancario',
        onTap: () {

        },
      ),

      const SizedBox(height: 10),

     Opacity(
  opacity: 0.45,
  child: _paymentAction(
    icon: Icons.payments_rounded,
    color: Colors.grey,
    title: 'Registrar efectivo',
    subtitle: 'Disponible próximamente',
    onTap: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta función estará disponible en una próxima actualización.',
          ),
        ),
      );
    },
  ),
),

      const SizedBox(height: 10),

      _paymentAction(
        icon: Icons.account_balance_wallet_rounded,
        color: Colors.purpleAccent,
        title: 'Cobrado por banco',
        subtitle: 'Confirmar domiciliación bancaria',
        onTap: () {

        },
      ),

    ],
  ),
),
                const SizedBox(height: 18),

                _section(
                  title: 'Añadir comentario',
                  child: Column(
                    children: [
                      TextField(
                        controller: comentarioController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('Escribe una gestión...'),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: anadirComentario,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'GUARDAR COMENTARIO',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                _section(
                  title: 'Pagos registrados',
                  child: pagos.isEmpty
                      ? const Text(
                          'Sin pagos registrados',
                          style: TextStyle(color: Colors.white54),
                        )
                      : Column(
                          children: pagos.map((p) {
                            return _historyRow(
                              icon: Icons.payments_rounded,
                              color: Colors.greenAccent,
                              title:
                                  '${_money(p['importe']).toStringAsFixed(2)} € · ${p['metodo'] ?? ''}',
                              subtitle:
                                  '${p['estado'] ?? ''} · ${_formatFecha(p['created_at'])}',
                            );
                          }).toList(),
                        ),
                ),

                const SizedBox(height: 18),

                _section(
                  title: 'Histórico de gestiones',
                  child: comentarios.isEmpty
                      ? const Text(
                          'Sin comentarios todavía',
                          style: TextStyle(color: Colors.white54),
                        )
                      : Column(
                          children: comentarios.map((c) {
                            return _historyRow(
                              icon: Icons.chat_bubble_outline_rounded,
                              color: Colors.cyanAccent,
                              title: c['comentario']?.toString() ?? '',
                              subtitle:
                                  '${c['usuario'] ?? ''} · ${_formatFecha(c['created_at'])}',
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withOpacity(0.055),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.09)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.cyanAccent),
      ),
    );
  }

  Widget _section({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _historyRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _paymentAction({
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      splashColor: color.withOpacity(0.12),
      highlightColor: color.withOpacity(0.05),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(
            color: color.withOpacity(0.22),
          ),
        ),
        child: Row(
          children: [

            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: color,
              ),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),

                ],
              ),
            ),

            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white38,
              size: 16,
            ),

          ],
        ),
      ),
    ),
  );
}
}