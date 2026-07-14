import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnularPolizaScreen extends StatefulWidget {
  const AnularPolizaScreen({super.key});

  @override
  State<AnularPolizaScreen> createState() => _AnularPolizaScreenState();
}

class _AnularPolizaScreenState extends State<AnularPolizaScreen> {
  final supabase = Supabase.instance.client;

  final buscarCtrl = TextEditingController();
  final motivoCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();

  bool loading = false;
  bool anulandoRecibos = false;
  bool anulandoPoliza = false;

  Map<String, dynamic>? venta;
  Map<String, dynamic>? cliente;
  List<Map<String, dynamic>> recibos = [];

  @override
  void dispose() {
    buscarCtrl.dispose();
    motivoCtrl.dispose();
    observacionesCtrl.dispose();
    super.dispose();
  }

  String normalizarBusqueda(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _text(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool get recibosAnulados {
    if (recibos.isEmpty) return true;

    return recibos.every((r) {
      final estado = _text(
        r['estado_recibo'] ?? r['estado'],
      ).toUpperCase();

      return estado == 'ANULADO' || estado == 'ANULADA';
    });
  }

  Future<void> buscarPoliza() async {
    final texto = buscarCtrl.text.trim();

    if (texto.isEmpty) {
      _snack('Introduce número de póliza o DNI');
      return;
    }

    setState(() {
      loading = true;
      venta = null;
      cliente = null;
      recibos = [];
    });

    try {
      final busqueda = normalizarBusqueda(texto);

      final data = await supabase
          .from('ventas')
          .select('''
            *,
            clientes:cliente_id (
              id,
              dni,
              nombre,
              apellidos,
              telefono,
              email,
              direccion,
              numero,
              poblacion,
              provincia
            )
          ''')
          .limit(1000);

      final ventas = List<Map<String, dynamic>>.from(data);

      Map<String, dynamic>? ventaEncontrada;
      Map<String, dynamic>? clienteEncontrado;

      for (final v in ventas) {
        final numeroPoliza = normalizarBusqueda(
          v['numero_poliza']?.toString() ?? '',
        );

        final c = v['clientes'] as Map<String, dynamic>?;

        final dni = normalizarBusqueda(
          c?['dni']?.toString() ?? '',
        );

        if (numeroPoliza.contains(busqueda) || dni.contains(busqueda)) {
          ventaEncontrada = v;
          clienteEncontrado = c;
          break;
        }
      }

      if (ventaEncontrada == null) {
        _snack('No se encontró ninguna póliza');
        return;
      }

      setState(() {
        venta = ventaEncontrada;
        cliente = clienteEncontrado;
      });

      await cargarRecibos();

      _snack('Póliza encontrada');
    } catch (e) {
      _snack('Error buscando póliza: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> cargarRecibos() async {
    if (venta == null) return;

    final numeroPoliza = venta!['numero_poliza']?.toString();

    if (numeroPoliza == null || numeroPoliza.trim().isEmpty) {
      setState(() => recibos = []);
      return;
    }

    final data = await supabase
    .from('recibos')
    .select()
    .eq('poliza', numeroPoliza);

    setState(() {
      recibos = List<Map<String, dynamic>>.from(data);
    });
  }

  Map<String, dynamic> calcularExtorno() {
    final fechaEfecto = _date(venta?['fecha_efecto']);
    final fechaAnulacion = DateTime.now();

    final prima = _money(
      venta?['prima_anual_neta'] ?? venta?['prima_neta'] ?? venta?['prima'],
    );

    final comision = _money(venta?['comision']);

    int diasConsumidos = 0;
    int diasPendientes = 0;
    double primaExtornada = 0;
    double comisionExtornada = 0;

    if (fechaEfecto != null) {
      diasConsumidos = fechaAnulacion.difference(fechaEfecto).inDays;
      diasPendientes = 365 - diasConsumidos;

      if (diasConsumidos < 365 && diasPendientes > 0) {
        primaExtornada = prima * diasPendientes / 365;
        comisionExtornada = comision * diasPendientes / 365;
      }
    }

    return {
      'dias_consumidos': diasConsumidos < 0 ? 0 : diasConsumidos,
      'dias_pendientes': diasPendientes < 0 ? 0 : diasPendientes,
      'prima_extornada': primaExtornada,
      'comision_extornada': comisionExtornada,
    };
  }

  Future<void> anularRecibos() async {
  if (venta == null) return;

  final numeroPoliza = venta?['numero_poliza']?.toString();

  if (numeroPoliza == null || numeroPoliza.trim().isEmpty) {
    _snack('La póliza no tiene número');
    return;
  }

  setState(() => anulandoRecibos = true);

  try {
    final user = supabase.auth.currentUser;

    await supabase
        .from('recibos')
        .update({
          'estado_recibo': 'ANULADO',
          'fecha_anulacion': DateTime.now().toIso8601String(),
          'motivo_anulacion': motivoCtrl.text.trim(),
          'observaciones_anulacion': observacionesCtrl.text.trim(),
          'anulado_por': user?.id,
        })
        .eq('poliza', numeroPoliza);

    await cargarRecibos();

    _snack('Recibos anulados correctamente');
  } catch (e) {
    _snack('Error anulando recibos: $e');
  } finally {
    if (mounted) setState(() => anulandoRecibos = false);
  }
}

  Future<void> anularUnRecibo(Map<String, dynamic> recibo) async {
  setState(() => anulandoRecibos = true);

  try {
    final user = supabase.auth.currentUser;

    await supabase
        .from('recibos')
        .update({
          'estado_recibo': 'ANULADO',
          'fecha_anulacion': DateTime.now().toIso8601String(),
          'motivo_anulacion': motivoCtrl.text.trim(),
          'observaciones_anulacion': observacionesCtrl.text.trim(),
          'anulado_por': user?.id,
        })
        .eq('id', recibo['id']);

    await cargarRecibos();

    _snack('Recibo anulado correctamente');
  } catch (e) {
    _snack('Error anulando recibo: $e');
  } finally {
    if (mounted) setState(() => anulandoRecibos = false);
  }
}

  Future<void> anularPoliza() async {
    if (venta == null) return;

    if (!recibosAnulados) {
      _snack('Primero debes anular todos los recibos');
      return;
    }

    if (motivoCtrl.text.trim().isEmpty) {
      _snack('Introduce el motivo de anulación');
      return;
    }

    setState(() => anulandoPoliza = true);

    try {
      final user = supabase.auth.currentUser;
      final extorno = calcularExtorno();

      final anulacion = await supabase
          .from('anulaciones_polizas')
          .insert({
            'venta_id': venta?['id'],
            'cliente_id': venta?['cliente_id'],
            'numero_poliza': venta?['numero_poliza'],
            'dni_cliente': cliente?['dni'],
            'nombre_cliente':
                '${_text(cliente?['nombre'])} ${_text(cliente?['apellidos'])}',
            'fecha_efecto': venta?['fecha_efecto'],
            'fecha_anulacion': DateTime.now().toIso8601String(),
            'motivo': motivoCtrl.text.trim(),
            'observaciones': observacionesCtrl.text.trim(),
            'prima_anual_neta': _money(venta?['prima_anual_neta']),
            'comision_original': _money(venta?['comision']),
            'dias_consumidos': extorno['dias_consumidos'],
            'dias_pendientes': extorno['dias_pendientes'],
            'prima_extornada': extorno['prima_extornada'],
            'comision_extornada': extorno['comision_extornada'],
            'recibos_anulados': recibos.length,
            'estado': 'ANULADA',
            'anulada_por': user?.id,
          })
          .select()
          .single();

      await supabase.from('ventas').update({
        'estado_poliza': 'ANULADA',
        'fecha_anulacion': DateTime.now().toIso8601String(),
        'motivo_anulacion': motivoCtrl.text.trim(),
        'observaciones_anulacion': observacionesCtrl.text.trim(),
        'prima_extornada': extorno['prima_extornada'],
        'comision_extornada': extorno['comision_extornada'],
        'anulacion_id': anulacion['id'],
        'anulada_por': user?.id,
      }).eq('id', venta?['id']);

     final numeroPoliza = venta?['numero_poliza']?.toString();

if (numeroPoliza == null || numeroPoliza.trim().isEmpty) {
  _snack('La póliza no tiene número');
  return;
}

await supabase.from('recibos').update({
  'anulacion_id': anulacion['id'],
}).eq('poliza', numeroPoliza);
      _snack('Póliza anulada correctamente');

      await buscarPoliza();
    } catch (e) {
      _snack('Error anulando póliza: $e');
    } finally {
      if (mounted) setState(() => anulandoPoliza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extorno = venta == null ? null : calcularExtorno();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoClaroPremium(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  _topHeader(),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 390,
                          child: _formularioBusqueda(),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _resultado(extorno),
                        ),
                      ],
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

  Widget _topHeader() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Anular póliza',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                'Anulación controlada de pólizas, recibos y cálculo automático de extorno.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formularioBusqueda() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitle(
            Icons.cancel_presentation_rounded,
            'Buscar póliza',
            'Introduce número de póliza o DNI.',
          ),
          const SizedBox(height: 22),
          _input(
            buscarCtrl,
            'Número de póliza o DNI',
            Icons.manage_search_rounded,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: loading ? null : buscarPoliza,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                loading ? 'Buscando...' : 'Buscar póliza',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'La búsqueda ignora guiones, barras, espacios y símbolos. Puedes escribir la póliza seguida o el DNI del cliente.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          _input(
            motivoCtrl,
            'Motivo de anulación',
            Icons.edit_note_rounded,
          ),
          _input(
            observacionesCtrl,
            'Observaciones',
            Icons.notes_rounded,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _resultado(Map<String, dynamic>? extorno) {
    if (venta == null) {
      return _glassPanel(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.policy_rounded,
                size: 92,
                color: const Color(0xFFDC2626).withOpacity(0.25),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sin póliza seleccionada',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca una póliza para iniciar el proceso de anulación.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _moduleTitle(
                Icons.verified_rounded,
                'Datos de la póliza',
                'Información encontrada en ventas y clientes.',
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _dataCard('Póliza', _text(venta?['numero_poliza']),
                      Icons.confirmation_number_rounded),
                  _dataCard('Estado', _text(venta?['estado_poliza']),
                      Icons.info_rounded),
                  _dataCard('Cliente',
                      '${_text(cliente?['nombre'])} ${_text(cliente?['apellidos'])}',
                      Icons.person_rounded),
                  _dataCard('DNI', _text(cliente?['dni']),
                      Icons.badge_rounded),
                  _dataCard('Producto', _text(venta?['producto']),
                      Icons.inventory_2_rounded),
                  _dataCard('Fecha efecto',
                      _text(venta?['fecha_efecto']).split('T').first,
                      Icons.calendar_month_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                'Prima neta anual',
                '${_money(venta?['prima_anual_neta']).toStringAsFixed(2)} €',
                Icons.trending_up_rounded,
                const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _metricCard(
                'Comisión original',
                '${_money(venta?['comision']).toStringAsFixed(2)} €',
                Icons.euro_rounded,
                const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _glassPanel(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _moduleTitle(
        Icons.receipt_long_rounded,
        'Recibos asociados',
        'Revisa y anula los recibos antes de anular la póliza.',
      ),
      const SizedBox(height: 18),

      _resumenRecibos(),

      const SizedBox(height: 18),

      if (recibos.isEmpty)
        const Text(
          'No hay recibos asociados a esta póliza.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        )
      else
        _tablaRecibos(),

      const SizedBox(height: 18),

      SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: anulandoRecibos ? null : anularRecibos,
          icon: anulandoRecibos
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.done_all_rounded),
          label: Text(
            anulandoRecibos
                ? 'Anulando recibos...'
                : 'Anular todos los recibos',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF97316),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    ],
  ),
),
        const SizedBox(height: 18),
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _moduleTitle(
                Icons.calculate_rounded,
                'Cálculo de extorno',
                'Proporcional al tiempo pendiente hasta completar el primer año.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _dataCard(
                    'Días consumidos',
                    '${extorno?['dias_consumidos'] ?? 0}',
                    Icons.timelapse_rounded,
                  ),
                  _dataCard(
                    'Días pendientes',
                    '${extorno?['dias_pendientes'] ?? 0}',
                    Icons.hourglass_bottom_rounded,
                  ),
                  _dataCard(
                    'Prima extornada',
                    '${_money(extorno?['prima_extornada']).toStringAsFixed(2)} €',
                    Icons.payments_rounded,
                  ),
                  _dataCard(
                    'Comisión a descontar',
                    '${_money(extorno?['comision_extornada']).toStringAsFixed(2)} €',
                    Icons.remove_circle_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: recibosAnulados
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  recibosAnulados
                      ? 'Todos los recibos están anulados. Ya puedes anular la póliza.'
                      : 'No puedes anular la póliza hasta anular todos los recibos.',
                  style: TextStyle(
                    color: recibosAnulados
                        ? const Color(0xFF166534)
                        : const Color(0xFF9A3412),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed:
                      recibosAnulados && !anulandoPoliza ? anularPoliza : null,
                  icon: anulandoPoliza
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cancel_rounded),
                  label: Text(
                    anulandoPoliza ? 'Anulando póliza...' : 'Anular póliza',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reciboItem(Map<String, dynamic> r) {
    final estado = _text(r['estado_recibo'] ?? r['estado']);
    final anulado = estado.toUpperCase() == 'ANULADO';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: anulado ? const Color(0xFFDCFCE7) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: anulado ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            anulado ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: anulado ? const Color(0xFF16A34A) : const Color(0xFFF97316),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Recibo ${_text(r['numero_recibo'] ?? r['id'])}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '${_money(r['importe']).toStringAsFixed(2)} €',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            estado,
            style: TextStyle(
              color: anulado ? const Color(0xFF16A34A) : const Color(0xFFF97316),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenRecibos() {
  final total = recibos.length;
  final anulados = recibos.where((r) {
    final estado = _text(r['estado_recibo'] ?? r['estado']).toUpperCase();
    return estado == 'ANULADO' || estado == 'ANULADA';
  }).length;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: recibosAnulados ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(
          recibosAnulados
              ? Icons.check_circle_rounded
              : Icons.warning_amber_rounded,
          color: recibosAnulados
              ? const Color(0xFF16A34A)
              : const Color(0xFFF97316),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Recibos anulados: $anulados / $total',
            style: TextStyle(
              color: recibosAnulados
                  ? const Color(0xFF166534)
                  : const Color(0xFF9A3412),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _tablaRecibos() {
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Recibo')),
            DataColumn(label: Text('Vencimiento')),
            DataColumn(label: Text('Importe')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acción')),
          ],
          rows: recibos.map((r) {
            final estado = _text(r['estado_recibo'] ?? r['estado']);
            final anulado = estado.toUpperCase() == 'ANULADO' ||
                estado.toUpperCase() == 'ANULADA';

            return DataRow(
              cells: [
                DataCell(Text(_text(r['numero_recibo'] ?? r['id']))),
                DataCell(Text(_text(
                  r['fecha_vencimiento'] ??
                      r['vencimiento'] ??
                      r['fecha'] ??
                      '-',
                ).split('T').first)),
                DataCell(Text(
                  '${_money(r['importe'] ?? r['prima'] ?? r['total']).toStringAsFixed(2)} €',
                )),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: anulado
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFFEDD5),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      estado,
                      style: TextStyle(
                        color: anulado
                            ? const Color(0xFF166534)
                            : const Color(0xFF9A3412),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  anulado
                      ? const Icon(
                          Icons.lock_rounded,
                          color: Color(0xFF94A3B8),
                        )
                      : ElevatedButton.icon(
                          onPressed: anulandoRecibos
                              ? null
                              : () => anularUnRecibo(r),
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: const Text('Anular'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    ),
  );
}

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFFDC2626)),
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _moduleTitle(IconData icon, String title, String subtitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFDC2626),
                Color(0xFFFB7185),
              ],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 29),
        ),
        const SizedBox(width: 13),
        Flexible(
          fit: FlexFit.loose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dataCard(String title, String value, IconData icon) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B))),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }
}

class _FondoClaroPremium extends StatelessWidget {
  const _FondoClaroPremium();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFFF4F7FB)),
        Positioned(
          top: -140,
          right: -120,
          child: _orb(330, const Color(0xFFFCA5A5)),
        ),
        Positioned(
          bottom: -150,
          left: -130,
          child: _orb(360, const Color(0xFFC4B5FD)),
        ),
        Positioned(
          top: 260,
          left: 360,
          child: _orb(230, const Color(0xFFBBF7D0)),
        ),
      ],
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.45),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.38),
            blurRadius: 120,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }
}