import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class TramitarFacturasScreen extends StatefulWidget {
  const TramitarFacturasScreen({super.key});

  @override
  State<TramitarFacturasScreen> createState() => _TramitarFacturasScreenState();
}

class _TramitarFacturasScreenState extends State<TramitarFacturasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardandoAjusteManual = false;
  String role = '';
  List<Map<String, dynamic>> lineasFactura = [];
  String estadoFiltro = 'pendiente_tramitar';
  String busqueda = '';
  int? mesFiltro;
  Map<String, dynamic>? facturaSeleccionada;

  Future<void> cargarLineasFactura(Map<String, dynamic> factura) async {
  try {
    final data = await supabase
        .from('nominas_facturas_lineas')
        .select()
        .eq('factura_id', factura['id'])
        .order('created_at', ascending: true);

    setState(() {
      facturaSeleccionada = factura;
      lineasFactura = (data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  } catch (e) {
    debugPrint('ERROR CARGAR LINEAS FACTURA: $e');

    setState(() {
      facturaSeleccionada = factura;
      lineasFactura = [];
    });
  }
}

  List<Map<String, dynamic>> facturas = [];

  @override
  void initState() {
    super.initState();
    cargarFacturas();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;

    final normalizado = raw.contains(',') && raw.contains('.')
        ? raw.replaceAll('.', '').replaceAll(',', '.')
        : raw.replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  double _primerImporte(
    Map<String, dynamic> fila,
    List<String> columnas,
  ) {
    for (final columna in columnas) {
      if (!fila.containsKey(columna)) continue;
      final valor = _money(fila[columna]);
      if (valor.abs() > 0.001) return valor;
    }
    return 0;
  }

  double _comisionFirmadaLinea(Map<String, dynamic> linea) {
    final tipo = (linea['tipo_movimiento'] ??
            linea['tipo'] ??
            linea['movimiento'] ??
            'VENTA')
        .toString()
        .trim()
        .toUpperCase();

    final importe = _primerImporte(linea, const [
      'comision',
      'importe_comision',
      'comision_total',
      'comision_neta',
      'importe',
      'cantidad',
    ]);

    // Si el importe ya viene negativo, se respeta tal cual.
    if (importe < 0) return importe;

    // Los extornos históricos a veces se guardaron como positivos.
    if (tipo.contains('EXTORNO') &&
        !tipo.contains('REVERSO') &&
        !tipo.contains('ELIMINAR')) {
      return -importe.abs();
    }

    if (tipo.contains('NEGATIVO')) return -importe.abs();
    return importe;
  }

  Map<String, dynamic> _compatibilizarFacturaAntigua(
    Map<String, dynamic> factura,
    List<Map<String, dynamic>> lineas,
  ) {
    final salida = Map<String, dynamic>.from(factura);

    double comisiones = _primerImporte(factura, const [
      'comisiones',
      'comision',
      'total_comisiones',
      'comisiones_totales',
      'importe_comisiones',
      'comision_total',
    ]);

    double rappel = _primerImporte(factura, const [
      'rappel',
      'rapel',
      'importe_rappel',
      'importe_rapel',
      'total_rappel',
      'total_rapel',
    ]);

    final fijo = _primerImporte(factura, const [
      'fijo',
      'importe_fijo',
      'fijo_mensual',
      'salario_fijo',
    ]);

    double base = _primerImporte(factura, const [
      'base_imponible',
      'base',
      'importe_bruto',
      'total_bruto',
      'total_devengado',
      'importe_total',
      'total_nomina',
    ]);

    // Reconstrucción histórica desde las líneas cuando la cabecera antigua
    // no contiene comisiones o fue guardada a cero.
    if (comisiones.abs() < 0.001 && lineas.isNotEmpty) {
      double suma = 0;
      for (final linea in lineas) {
        final tipo = (linea['tipo_movimiento'] ??
                linea['tipo'] ??
                linea['movimiento'] ??
                'VENTA')
            .toString()
            .toUpperCase();

        // Los ajustes de rappel no forman parte de las comisiones.
        if (tipo.contains('RAPPEL') || tipo.contains('RAPEL')) {
          rappel += _comisionFirmadaLinea(linea);
          continue;
        }

        suma += _comisionFirmadaLinea(linea);
      }
      comisiones = suma;
    }

    // Una base histórica válida siempre tiene prioridad. Si no existe,
    // se construye con los conceptos disponibles.
    if (base.abs() < 0.001) {
      base = comisiones + rappel + fijo;
    }

    // Si solo existe la base histórica, recuperamos la comisión restante.
    if (comisiones.abs() < 0.001 && base.abs() > 0.001) {
      comisiones = base - rappel - fijo;
    }

    final irpf = _primerImporte(factura, const [
      'irpf_porcentaje',
      'porcentaje_irpf',
      'irpf',
    ]);
    final porcentajeIrpf = irpf.abs() < 0.001 ? 15.0 : irpf;

    double importeIrpf = _primerImporte(factura, const [
      'importe_irpf',
      'retencion_irpf',
      'irpf_importe',
    ]);
    if (importeIrpf.abs() < 0.001 && base.abs() > 0.001) {
      importeIrpf = base * porcentajeIrpf / 100;
    }

    double total = _primerImporte(factura, const [
      'total_factura',
      'total',
      'liquido',
      'liquido_a_percibir',
      'neto_a_pagar',
      'importe_neto',
    ]);
    if (total.abs() < 0.001 && base.abs() > 0.001) {
      total = base - importeIrpf;
    }

    salida['comisiones'] = comisiones;
    salida['rappel'] = rappel;
    salida['fijo'] = fijo;
    salida['base_imponible'] = base;
    salida['irpf_porcentaje'] = porcentajeIrpf;
    salida['importe_irpf'] = importeIrpf;
    salida['total_factura'] = total;

    return salida;
  }

  bool get esAdmin =>
      role == 'administracion' || role == 'director_nacional';

  bool _esFacturaEditable(Map<String, dynamic> factura) {
    return esAdmin &&
        (factura['estado']?.toString() ?? '') == 'pendiente_tramitar';
  }

  Map<String, double> _calculosFactura(Map<String, dynamic> factura) {
    /*
      IMPORTANTE:
      Las facturas ya creadas desde NominasScreen pueden traer una
      base_imponible correcta aunque alguno de los campos desglosados
      (comisiones, rappel o fijo) venga vacío, nulo o a cero.

      Nunca reconstruimos una base válida como 0. Primero respetamos la
      base guardada y completamos el desglose sin destruir información.
    */
    double comisiones = _primerImporte(factura, const [
      'comisiones', 'comision', 'total_comisiones', 'importe_comisiones'
    ]);
    final rappel = _primerImporte(factura, const [
      'rappel', 'rapel', 'importe_rappel', 'importe_rapel'
    ]);
    final fijo = _primerImporte(factura, const [
      'fijo', 'importe_fijo', 'fijo_mensual'
    ]);

    final baseGuardada = _primerImporte(factura, const [
      'base_imponible', 'base', 'importe_bruto', 'total_bruto',
      'total_devengado', 'importe_total', 'total_nomina'
    ]);
    final sumaDesglose = comisiones + rappel + fijo;

    // Si existe una base válida y las comisiones no han llegado informadas,
    // recuperamos las comisiones como la parte restante de la base.
    if (baseGuardada.abs() > 0.001 &&
        comisiones.abs() < 0.001 &&
        (baseGuardada - rappel - fijo).abs() > 0.001) {
      comisiones = baseGuardada - rappel - fijo;
    }

    // Para facturas existentes, la base guardada es la fuente principal.
    // Para una factura nueva o editada sin base previa, usamos el desglose.
    final base = baseGuardada.abs() > 0.001
        ? baseGuardada
        : (comisiones + rappel + fijo);

    final irpf = _money(factura['irpf_porcentaje']) == 0
        ? 15.0
        : _money(factura['irpf_porcentaje']);

    final importeIrpfGuardado = _money(factura['importe_irpf']);
    final totalGuardado = _money(factura['total_factura']);

    final importeIrpfCalculado = base * irpf / 100;
    final totalCalculado = base - importeIrpfCalculado;

    // Si la factura ya tiene importes finales válidos, se respetan al cargar.
    // Tras una edición manual se guardarán de nuevo ya recalculados.
    final importeIrpf = importeIrpfGuardado.abs() > 0.001
        ? importeIrpfGuardado
        : importeIrpfCalculado;
    final total = totalGuardado.abs() > 0.001
        ? totalGuardado
        : totalCalculado;

    return {
      'comisiones': comisiones,
      'rappel': rappel,
      'fijo': fijo,
      'base': base,
      'base_desglose': sumaDesglose,
      'irpf': irpf,
      'importe_irpf': importeIrpf,
      'total': total,
    };
  }

  Future<void> _guardarTotalesFactura({
    required Map<String, dynamic> factura,
    required double comisiones,
    required double rappel,
    required double fijo,
    double? irpf,
  }) async {
    final porcentajeIrpf = irpf ??
        (_money(factura['irpf_porcentaje']) == 0
            ? 15.0
            : _money(factura['irpf_porcentaje']));

    final baseAnterior = _money(factura['base_imponible']);
    final baseCalculada = comisiones + rappel + fijo;

    // Protección contra sobrescribir accidentalmente una factura válida con 0
    // cuando el desglose no haya llegado todavía desde NominasScreen.
    final base = baseCalculada.abs() < 0.001 && baseAnterior.abs() > 0.001
        ? baseAnterior
        : baseCalculada;

    final importeIrpf = base * porcentajeIrpf / 100;
    final total = base - importeIrpf;

    await supabase.from('nominas_facturas').update({
      'comisiones': comisiones,
      'rappel': rappel,
      'fijo': fijo,
      'base_imponible': base,
      'irpf_porcentaje': porcentajeIrpf,
      'importe_irpf': importeIrpf,
      'total_factura': total,
    }).eq('id', factura['id']);
  }

  Future<void> _recargarFactura(dynamic facturaId) async {
    await cargarFacturas();

    Map<String, dynamic>? encontrada;
    for (final factura in facturas) {
      if (factura['id'].toString() == facturaId.toString()) {
        encontrada = factura;
        break;
      }
    }

    if (encontrada != null) {
      await cargarLineasFactura(encontrada);
    }
  }

  void _mensaje(String texto, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  String nombreMes(dynamic mes) {
    final m = mes is int ? mes : int.tryParse(mes.toString()) ?? 0;
    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    if (m < 1 || m > 12) return '';
    return meses[m];
  }

  Future<void> cargarFacturas() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      setState(() => loading = true);

      final perfil = await supabase
          .from('usuarios')
          .select('rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();

      role = perfil?['rol_usuario']?.toString() ?? '';

      final data = await supabase
          .from('nominas_facturas')
          .select()
          .order('created_at', ascending: false);

      final listaOriginal = (data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Compatibilidad total: cargamos también las líneas para recuperar
      // facturas antiguas cuya cabecera no guardaba los campos actuales.
      final lineasData = await supabase
          .from('nominas_facturas_lineas')
          .select()
          .order('created_at', ascending: true);

      final todasLasLineas = (lineasData as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final lineasPorFactura = <String, List<Map<String, dynamic>>>{};
      for (final linea in todasLasLineas) {
        final facturaId = linea['factura_id']?.toString() ?? '';
        if (facturaId.isEmpty) continue;
        lineasPorFactura.putIfAbsent(facturaId, () => []).add(linea);
      }

      final lista = listaOriginal.map((factura) {
        final facturaId = factura['id']?.toString() ?? '';
        return _compatibilizarFacturaAntigua(
          factura,
          lineasPorFactura[facturaId] ?? const <Map<String, dynamic>>[],
        );
      }).toList();

      setState(() {
        facturas = lista;
        facturaSeleccionada = lista.isNotEmpty ? lista.first : null;
        lineasFactura = lista.isNotEmpty
            ? (lineasPorFactura[lista.first['id']?.toString() ?? ''] ??
                <Map<String, dynamic>>[])
            : <Map<String, dynamic>>[];
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGAR FACTURAS: $e');
      setState(() {
        facturas = [];
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filtradas {
    return facturas.where((f) {
      final estado = f['estado']?.toString() ?? '';
      final texto = busqueda.toLowerCase().trim();

      final nombre = f['usuario_nombre']?.toString().toLowerCase() ?? '';
      final email = f['usuario_email']?.toString().toLowerCase() ?? '';
      final rolUsuario = f['usuario_rol']?.toString().toLowerCase() ?? '';

      if (estadoFiltro != 'todas' && estado != estadoFiltro) return false;
      if (mesFiltro != null && f['mes'] != mesFiltro) return false;

      if (texto.isNotEmpty &&
          !nombre.contains(texto) &&
          !email.contains(texto) &&
          !rolUsuario.contains(texto)) {
        return false;
      }

      return true;
    }).toList();
  }

  int get pendientes =>
      facturas.where((f) => f['estado'] == 'pendiente_tramitar').length;

  int get tramitadas =>
      facturas.where((f) => f['estado'] == 'tramitada').length;

  int get enviadas =>
      facturas.where((f) => f['estado'] == 'enviada_email').length;

      double get totalPagado {
  return facturas
      .where((f) =>
          f['estado'] == 'tramitada' || f['estado'] == 'enviada_email')
      .fold(0.0, (s, f) => s + _money(f['total_factura']));
}

  double get importePendiente {
    return facturas
        .where((f) => f['estado'] == 'pendiente_tramitar')
        .fold(0.0, (s, f) => s + _money(f['base_imponible']));
  }


  Future<void> _abrirEditorFacturaManual(
    Map<String, dynamic> factura,
  ) async {
    if (!_esFacturaEditable(factura)) return;

    String concepto = 'comisiones';
    String operacion = 'sumar';
    final cantidadController = TextEditingController();
    final motivoController = TextEditingController();

    final aceptar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final esExtorno = concepto == 'extorno';

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Modificar factura manualmente')),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Elige el concepto, indica si quieres añadir o quitar '
                        'importe y escribe la cantidad. Los totales, el IRPF y '
                        'el PDF se recalcularán automáticamente.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        value: concepto,
                        decoration: _selectDecoration('Concepto'),
                        items: const [
                          DropdownMenuItem(
                            value: 'comisiones',
                            child: Text('Comisiones'),
                          ),
                          DropdownMenuItem(
                            value: 'rappel',
                            child: Text('Rappel'),
                          ),
                          DropdownMenuItem(
                            value: 'extorno',
                            child: Text('Extorno'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => concepto = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: operacion,
                        decoration: _selectDecoration('Operación'),
                        items: [
                          DropdownMenuItem(
                            value: 'sumar',
                            child: Text(
                              esExtorno
                                  ? 'Añadir extorno'
                                  : 'Añadir cantidad',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'restar',
                            child: Text(
                              esExtorno
                                  ? 'Quitar cantidad de extorno'
                                  : 'Quitar cantidad',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => operacion = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: cantidadController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          'Cantidad en euros',
                          Icons.euro_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: motivoController,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Motivo del ajuste',
                          Icons.notes_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                          ),
                        ),
                        child: const Text(
                          'El ajuste se añadirá al detalle de líneas para que '
                          'quede identificado en la pantalla y en el PDF.',
                          style: TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final cantidad = _money(cantidadController.text);
                    if (cantidad <= 0) {
                      _mensaje(
                        'Introduce una cantidad superior a cero.',
                        error: true,
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (aceptar != true) return;

    await _aplicarAjusteManual(
      factura: factura,
      concepto: concepto,
      operacion: operacion,
      cantidad: _money(cantidadController.text),
      motivo: motivoController.text.trim().isEmpty
          ? 'Ajuste manual'
          : motivoController.text.trim(),
    );
  }

  Future<void> _aplicarAjusteManual({
    required Map<String, dynamic> factura,
    required String concepto,
    required String operacion,
    required double cantidad,
    required String motivo,
  }) async {
    if (!_esFacturaEditable(factura) || guardandoAjusteManual) return;

    setState(() => guardandoAjusteManual = true);

    try {
      final calculos = _calculosFactura(factura);
      double comisiones = calculos['comisiones']!;
      double rappel = calculos['rappel']!;
      final fijo = calculos['fijo']!;

      String tipoMovimiento;
      double importeLinea;

      if (concepto == 'comisiones') {
        importeLinea = operacion == 'sumar' ? cantidad : -cantidad;
        comisiones += importeLinea;
        tipoMovimiento = operacion == 'sumar'
            ? 'AJUSTE_COMISION_POSITIVO'
            : 'AJUSTE_COMISION_NEGATIVO';
      } else if (concepto == 'rappel') {
        importeLinea = operacion == 'sumar' ? cantidad : -cantidad;
        rappel += importeLinea;
        tipoMovimiento = operacion == 'sumar'
            ? 'AJUSTE_RAPPEL_POSITIVO'
            : 'AJUSTE_RAPPEL_NEGATIVO';
      } else {
        // Añadir un extorno reduce las comisiones.
        // Quitar una cantidad de extorno devuelve ese importe.
        importeLinea = operacion == 'sumar' ? -cantidad : cantidad;
        comisiones += importeLinea;
        tipoMovimiento = operacion == 'sumar'
            ? 'EXTORNO_MANUAL'
            : 'REVERSO_EXTORNO_MANUAL';
      }

      await _guardarTotalesFactura(
        factura: factura,
        comisiones: comisiones,
        rappel: rappel,
        fijo: fijo,
      );

      await supabase.from('nominas_facturas_lineas').insert({
        'factura_id': factura['id'],
        'tipo_movimiento': tipoMovimiento,
        'numero_poliza': 'AJUSTE MANUAL',
        'cliente_nombre': motivo,
        'prima_neta': 0,
        'comision': importeLinea,
      });

      await _recargarFactura(factura['id']);
      _mensaje('Ajuste aplicado correctamente.');
    } catch (e) {
      debugPrint('ERROR AJUSTE MANUAL FACTURA: $e');
      _mensaje('No se pudo aplicar el ajuste: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => guardandoAjusteManual = false);
      }
    }
  }

  bool _esLineaManual(Map<String, dynamic> linea) {
    final tipo = linea['tipo_movimiento']?.toString() ?? '';
    return tipo == 'AJUSTE_COMISION_POSITIVO' ||
        tipo == 'AJUSTE_COMISION_NEGATIVO' ||
        tipo == 'AJUSTE_RAPPEL_POSITIVO' ||
        tipo == 'AJUSTE_RAPPEL_NEGATIVO' ||
        tipo == 'EXTORNO_MANUAL' ||
        tipo == 'REVERSO_EXTORNO_MANUAL';
  }

  Future<void> _eliminarAjusteManual(
    Map<String, dynamic> linea,
  ) async {
    final factura = facturaSeleccionada;
    if (factura == null ||
        !_esFacturaEditable(factura) ||
        !_esLineaManual(linea)) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar ajuste manual'),
        content: const Text(
          'El importe se devolverá automáticamente a la factura y '
          'la línea desaparecerá del detalle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final calculos = _calculosFactura(factura);
      double comisiones = calculos['comisiones']!;
      double rappel = calculos['rappel']!;
      final fijo = calculos['fijo']!;
      final importe = _money(linea['comision']);
      final tipo = linea['tipo_movimiento']?.toString() ?? '';

      if (tipo.startsWith('AJUSTE_RAPPEL')) {
        rappel -= importe;
      } else {
        comisiones -= importe;
      }

      await _guardarTotalesFactura(
        factura: factura,
        comisiones: comisiones,
        rappel: rappel,
        fijo: fijo,
      );

      await supabase
          .from('nominas_facturas_lineas')
          .delete()
          .eq('id', linea['id']);

      await _recargarFactura(factura['id']);
      _mensaje('Ajuste eliminado correctamente.');
    } catch (e) {
      debugPrint('ERROR ELIMINAR AJUSTE: $e');
      _mensaje('No se pudo eliminar el ajuste: $e', error: true);
    }
  }

  Map<String, dynamic> _verificarFactura(
    Map<String, dynamic> factura,
  ) {
    int ventas = 0;
    int extornos = 0;
    int ajustes = 0;
    double comisionesLineas = 0;
    double ajustesRappel = 0;

    for (final linea in lineasFactura) {
      final tipo =
          linea['tipo_movimiento']?.toString().toUpperCase() ?? 'VENTA';
      final importe = _money(
        linea['comision'] ??
            linea['importe_comision'] ??
            linea['comision_total'],
      );

      if (tipo == 'VENTA') {
        ventas++;
        comisionesLineas += importe;
      } else if (tipo == 'EXTORNO') {
        extornos++;
        comisionesLineas += importe;
      } else if (tipo.startsWith('AJUSTE_RAPPEL')) {
        ajustes++;
        ajustesRappel += importe;
      } else if (_esLineaManual(linea)) {
        ajustes++;
        comisionesLineas += importe;
      }
    }

    final calculos = _calculosFactura(factura);
    final baseGuardada = _money(factura['base_imponible']);
    final diferenciaBase = baseGuardada - calculos['base']!;

    // La comparación de comisiones solo es concluyente cuando existen líneas.
    final diferenciaComisiones =
        _money(factura['comisiones']) - comisionesLineas;

    final sinLineas = lineasFactura.isEmpty;
    final baseCorrecta = diferenciaBase.abs() < 0.02;
    final comisionesCorrectas =
        sinLineas || diferenciaComisiones.abs() < 0.02;

    return {
      'ventas': ventas,
      'extornos': extornos,
      'ajustes': ajustes,
      'ajustes_rappel': ajustesRappel,
      'diferencia_base': diferenciaBase,
      'diferencia_comisiones': diferenciaComisiones,
      'sin_lineas': sinLineas,
      'correcta': !sinLineas && baseCorrecta && comisionesCorrectas,
    };
  }

  Future<void> _recalcularFactura(
    Map<String, dynamic> factura,
  ) async {
    if (!_esFacturaEditable(factura)) return;

    try {
      final calculos = _calculosFactura(factura);

      await _guardarTotalesFactura(
        factura: factura,
        comisiones: calculos['comisiones']!,
        rappel: calculos['rappel']!,
        fijo: calculos['fijo']!,
      );

      await _recargarFactura(factura['id']);
      _mensaje('Factura recalculada correctamente.');
    } catch (e) {
      _mensaje('No se pudo recalcular la factura: $e', error: true);
    }
  }

  Future<void> tramitarFactura(Map<String, dynamic> f) async {
  if (!esAdmin) return;

  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final calculos = _calculosFactura(f);
    final comisiones = calculos['comisiones']!;
    final rappel = calculos['rappel']!;
    final fijo = calculos['fijo']!;
    final base = calculos['base']!;
    final irpf = calculos['irpf']!;
    final importeIrpf = calculos['importe_irpf']!;
    final total = calculos['total']!;

    await _guardarTotalesFactura(
      factura: f,
      comisiones: comisiones,
      rappel: rappel,
      fijo: fijo,
      irpf: irpf,
    );

    final numeroFactura =
        'FAC-${f['anio']}-${f['mes'].toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch}';

    final lineas = await supabase
        .from('nominas_facturas_lineas')
        .select()
        .eq('factura_id', f['id']);

    final pdfBytes = await _generarPdfFactura(
      factura: f,
      lineas: (lineas as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      numeroFactura: numeroFactura,
      comisiones: comisiones,
      rappel: rappel,
      fijo: fijo,
      base: base,
      irpf: irpf,
      importeIrpf: importeIrpf,
     
      total: total,
    );

    final fileName = '$numeroFactura.pdf';
    final path = 'facturas/${f['anio']}/${f['mes']}/$fileName';

    await supabase.storage.from('facturas').uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    final signedUrl = await supabase.storage
        .from('facturas')
        .createSignedUrl(path, 60 * 60 * 24 * 365);

    await supabase.from('nominas_facturas').update({
      'estado': 'tramitada',
      'numero_factura': numeroFactura,
      'comisiones': comisiones,
      'rappel': rappel,
      'fijo': fijo,
      'base_imponible': base,
      'irpf_porcentaje': irpf,
      'importe_irpf': importeIrpf,
      'total_factura': total,
      'factura_url': signedUrl,
      'tramitada_por': user.id,
      'fecha_tramitacion': DateTime.now().toIso8601String(),
    }).eq('id', f['id']);

    await supabase.functions.invoke(
      'enviar-factura-nomina',
      body: {
        'factura_id': f['id'],
        'email': f['usuario_email'],
        'nombre': f['usuario_nombre'],
        'mes': nombreMes(f['mes']),
        'anio': f['anio'],
        'numero_factura': numeroFactura,
        'pdf_url': signedUrl,
      },
    );

    await supabase.from('nominas_facturas').update({
      'estado': 'enviada_email',
      'fecha_envio_email': DateTime.now().toIso8601String(),
    }).eq('id', f['id']);

    await cargarFacturas();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Factura generada y enviada por email correctamente'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    debugPrint('ERROR TRAMITAR FACTURA: $e');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error generando/enviando factura: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<Uint8List> _generarPdfFactura({
  required Map<String, dynamic> factura,
  required List<Map<String, dynamic>> lineas,
  required String numeroFactura,
  required double comisiones,
  required double rappel,
  required double fijo,
  required double base,
  required double irpf,
  required double importeIrpf,
  required double total,
}) async {
  final pdf = pw.Document();

  String euros(double value) => '${value.toStringAsFixed(2)} EUR';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      build: (context) {
        return [
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SAFEBROK',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Documento de facturación',
                      style: const pw.TextStyle(
                        color: PdfColors.blueGrey100,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'FACTURA',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      numeroFactura,
                      style: const pw.TextStyle(
                        color: PdfColors.blueGrey100,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 22),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _pdfInfoBox(
                  title: 'Colaborador',
                  lines: [
                    'Nombre: ${factura['usuario_nombre'] ?? ''}',
                    'Email: ${factura['usuario_email'] ?? ''}',
                    'Rol: ${factura['usuario_rol'] ?? ''}',
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _pdfInfoBox(
                  title: 'Datos factura',
                  lines: [
                    'Fecha: ${DateTime.now().toString().split(' ').first}',
                    'Periodo: ${nombreMes(factura['mes'])} ${factura['anio']}',
                    'IRPF aplicado: ${irpf.toStringAsFixed(0)}%',
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 24),

          pw.Text(
           'Pólizas, extornos y ajustes aplicados',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),

          pw.SizedBox(height: 10),

          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColors.blueGrey100,
              width: 0.6,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(3.2),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue700,
                ),
                children: [
                  _pdfHeaderCell('Póliza'),
                  _pdfHeaderCell('Cliente'),
                  _pdfHeaderCell('Prima neta'),
                  _pdfHeaderCell('Comisión'),
                ],
              ),
              if (lineas.isEmpty)
  pw.TableRow(
    children: [
      _pdfCell('Sin detalle'),
      _pdfCell('-'),
      _pdfCell('-'),
      _pdfCell('-'),
    ],
  )
else
  ...lineas.map((l) {
    final numeroPoliza =
        (l['numero_poliza'] ?? l['poliza'] ?? l['numero'] ?? 'Sin póliza')
            .toString();

    final cliente =
        (l['cliente_nombre'] ?? l['cliente'] ?? l['nombre_cliente'] ?? 'Sin cliente')
            .toString();

    final prima = _money(
      l['prima_neta'] ??
          l['prima_anual_neta'] ??
          l['prima'] ??
          l['importe_prima'],
    );

    final comision = _money(
      l['comision'] ??
          l['importe_comision'] ??
          l['comision_total'] ??
          0,
    );

final tipo = l['tipo_movimiento']?.toString() ?? 'VENTA';
final esNegativo =
    tipo.contains('EXTORNO') || tipo.contains('NEGATIVO');
final esPagoComercial =
    tipo == 'AJUSTE_COMISION_POSITIVO' ||
    tipo == 'AJUSTE_COMISION_NEGATIVO' ||
    tipo == 'AJUSTE_RAPPEL_POSITIVO' ||
    tipo == 'AJUSTE_RAPPEL_NEGATIVO' ||
    tipo == 'EXTORNO_MANUAL' ||
    tipo == 'REVERSO_EXTORNO_MANUAL';

final detalleMovimiento = esPagoComercial
    ? 'Pago comercial - ${comision < 0 ? 'negativo' : 'positivo'}'
    : '$tipo · $numeroPoliza';

return pw.TableRow(
  decoration: esNegativo
      ? const pw.BoxDecoration(color: PdfColors.red50)
      : null,
  children: [
    _pdfCell(detalleMovimiento),
    _pdfCell(cliente),
    _pdfCell(euros(prima), alignRight: true),
    _pdfCell(euros(comision), alignRight: true),
  ],
);
  }),
            ],
          ),

          pw.SizedBox(height: 26),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'Factura generada automáticamente desde el sistema interno de gestión. '
                    'El detalle anterior recoge las pólizas incluidas en el periodo facturado.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.blueGrey600,
                      lineSpacing: 2,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Container(
                width: 260,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blueGrey200),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  children: [
                    _pdfTotalLine('Comisiones', comisiones),
                    _pdfTotalLine('Rappel', rappel),
                    _pdfTotalLine('Fijo', fijo),
                    pw.Divider(color: PdfColors.blueGrey200),
                    _pdfTotalLine('Base imponible', base),
                    _pdfTotalLine(
                      'IRPF ${irpf.toStringAsFixed(0)}%',
                      -importeIrpf,
                    ),
                    pw.Divider(color: PdfColors.blueGrey400),
                    _pdfTotalLine(
                      'TOTAL A PERCIBIR',
                      total,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];
      },
    ),
  );

  return pdf.save();
}

pw.Widget _pdfInfoBox({
  required String title,
  required List<String> lines,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(13),
    decoration: pw.BoxDecoration(
      color: PdfColors.blue50,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.blue100),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.SizedBox(height: 8),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              line,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.blueGrey700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pdfHeaderCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
    ),
  );
}

pw.Widget _pdfCell(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      maxLines: 2,
      style: const pw.TextStyle(
        fontSize: 8.5,
        color: PdfColors.blueGrey800,
      ),
    ),
  );
}

pw.Widget _pdfTotalLine(String title, double value, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: bold ? PdfColors.blueGrey900 : PdfColors.blueGrey700,
            ),
          ),
        ),
        pw.Text(
          '${value.toStringAsFixed(2)} EUR',
          style: pw.TextStyle(
            fontSize: bold ? 12 : 9.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: bold ? PdfColors.blue700 : PdfColors.blueGrey900,
          ),
        ),
      ],
    ),
  );
}


 Future<void> cambiarIrpf(Map<String, dynamic> f, double irpf) async {
  if (!_esFacturaEditable(f)) return;

  try {
    final calculos = _calculosFactura(f);

    await _guardarTotalesFactura(
      factura: f,
      comisiones: calculos['comisiones']!,
      rappel: calculos['rappel']!,
      fijo: calculos['fijo']!,
      irpf: irpf,
    );

    await _recargarFactura(f['id']);
    _mensaje('IRPF actualizado correctamente.');
  } catch (e) {
    _mensaje('No se pudo actualizar el IRPF: $e', error: true);
  }
}

  @override
  Widget build(BuildContext context) {
    final lista = filtradas;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              )
            : Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topBar(),
        const SizedBox(height: 22),
        _kpiRow(),
        const SizedBox(height: 18),
        _filters(),
        const SizedBox(height: 18),
       Expanded(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 280,
        child: _colaTrabajoPanel(),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: _tablaFacturas(lista),
      ),
      const SizedBox(width: 16),
      SizedBox(
        width: 320,
        child: _detalleFactura(),
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

 

 
  

  Widget _topBar() {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          child: const Row(
            children: [
              Icon(Icons.chevron_left_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 4),
              Text(
                'CUADRO DE MANDOS',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _topChip(Icons.calendar_month_rounded, 'Mes actual'),
        const SizedBox(width: 14),
        _topChip(Icons.person_rounded, role.isEmpty ? 'Usuario' : role),
      ],
    );
  }

  Widget _topChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tramitar facturas',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Centro de expedición y control de facturación',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            _kpiCard('Pendientes', pendientes.toString(), 'Por tramitar',
                Icons.pending_actions_rounded, const Color(0xFF2563EB)),
            _kpiCard('Tramitadas', tramitadas.toString(), 'Este mes',
                Icons.verified_rounded, const Color(0xFF16A34A)),
            _kpiCard(
                'Importe pendiente',
                '${importePendiente.toStringAsFixed(0)} EUR',
                'Base imponible',
                Icons.euro_rounded,
                const Color(0xFF7C3AED)),
           _kpiCard(
  'Total pagado',
  '${totalPagado.toStringAsFixed(0)} EUR',
  'Facturas tramitadas',
  Icons.account_balance_wallet_rounded,
  const Color(0xFF0284C7),
),
            _kpiCard('IRPF más usado', '15%', 'Este mes',
                Icons.percent_rounded, const Color(0xFFEF4444)),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.blueGrey.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  onChanged: (v) => setState(() => busqueda = v),
                  decoration: _inputDecoration(
                    'Buscar por nombre, email o factura...',
                    Icons.search_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: estadoFiltro,
                  decoration: _selectDecoration('Estado'),
                  items: const [
                    DropdownMenuItem(
                      value: 'pendiente_tramitar',
                      child: Text('Pendientes'),
                    ),
                    DropdownMenuItem(
                      value: 'tramitada',
                      child: Text('Tramitadas'),
                    ),
                    DropdownMenuItem(
                      value: 'enviada_email',
                      child: Text('Enviadas'),
                    ),
                    DropdownMenuItem(
                      value: 'todas',
                      child: Text('Todas'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => estadoFiltro = v ?? 'pendiente_tramitar'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  value: mesFiltro,
                  decoration: _selectDecoration('Mes'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(nombreMes(i + 1)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => mesFiltro = v),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    estadoFiltro = 'pendiente_tramitar';
                    mesFiltro = null;
                    busqueda = '';
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Limpiar filtros'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  InputDecoration _selectDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  

Widget _colaTrabajoPanel() {
  final pendientesLista = facturas
      .where((f) => f['estado'] == 'pendiente_tramitar')
      .toList();

  final tramitadasLista = facturas
      .where((f) => f['estado'] == 'tramitada')
      .toList();

  return SingleChildScrollView(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COLA DE TRABAJO',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              _workQueueStat(
                title: 'Pendientes',
                value: pendientesLista.length.toString(),
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 8),
              _workQueueStat(
                title: 'Tramitadas',
                value: tramitadasLista.length.toString(),
                icon: Icons.verified_rounded,
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 8),
              _workQueueStat(
                title: 'Total pagado',
                value: '${totalPagado.toStringAsFixed(0)} €',
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PENDIENTES DE TRAMITAR',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              if (pendientesLista.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 35),
                  child: Center(
                    child: Text(
                      'No hay facturas pendientes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                ...pendientesLista
                    .take(8)
                    .toList()
                    .asMap()
                    .entries
                    .map(
                      (entry) => _workQueueFacturaCard(
                        entry.value,
                        urgente: entry.key <= 1,
                      ),
                    ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _workQueueStat({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.16)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _workQueueFacturaCard(
  Map<String, dynamic> f, {
  required bool urgente,
}) {
  final selected = facturaSeleccionada?['id'] == f['id'];
  final base = _money(f['base_imponible']);
  final rappel = _money(f['rappel']);

  return InkWell(
    onTap: () => cargarLineasFactura(f),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? const Color(0xFF2563EB)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: urgente
                    ? const Color(0xFFFFEDD5)
                    : const Color(0xFFEFF6FF),
                child: Icon(
                  urgente
                      ? Icons.priority_high_rounded
                      : Icons.receipt_long_rounded,
                  color: urgente
                      ? const Color(0xFFF97316)
                      : const Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f['usuario_nombre']?.toString() ?? 'Usuario',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${nombreMes(f['mes'])} ${f['anio']}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${base.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (urgente)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'URGENTE',
                    style: TextStyle(
                      color: Color(0xFFF97316),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _treeLine(String text, int count, int level) {
    return Padding(
      padding: EdgeInsets.only(left: level * 16, bottom: 14),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 7, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tablaFacturas(List<Map<String, dynamic>> lista) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('USUARIO')),
                Expanded(child: _HeaderCell('MES / AÑO')),
                Expanded(child: _HeaderCell('RAPPEL')),
Expanded(child: _HeaderCell('BASE')),
                Expanded(child: _HeaderCell('IRPF')),
                Expanded(child: _HeaderCell('TOTAL')),
                Expanded(child: _HeaderCell('ESTADO')),
                SizedBox(width: 50, child: _HeaderCell('')),
              ],
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? const Center(
                    child: Text(
                      'No hay facturas con estos filtros',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _facturaRow(lista[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _facturaRow(Map<String, dynamic> f) {
    final selected = facturaSeleccionada?['id'] == f['id'];
    final estado = f['estado']?.toString() ?? '';
    final color = _estadoColor(estado);

    return InkWell(
      onTap: () => cargarLineasFactura(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withOpacity(0.14),
                    child: Text(
                      _iniciales(f['usuario_nombre']),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['usuario_nombre']?.toString() ?? 'Usuario',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          f['usuario_rol']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                '${nombreMes(f['mes'])}\n${f['anio']}',
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: _bodyText('${_money(f['rappel']).toStringAsFixed(2)} €')),
Expanded(child: _bodyText('${_money(f['base_imponible']).toStringAsFixed(2)} €')),
Expanded(child: _bodyText('${_money(f['irpf_porcentaje']).toStringAsFixed(0)}%')),
            Expanded(child: _bodyText('${_money(f['total_factura']).toStringAsFixed(2)} €')),
            Expanded(child: _estadoBadge(estado)),
            SizedBox(
              width: 50,
              child: IconButton(
                onPressed: () => cargarLineasFactura(f),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detalleFactura() {
    final f = facturaSeleccionada;

    if (f == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: const Center(
          child: Text(
            'Selecciona una factura',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final calculos = _calculosFactura(f);
    final comisiones = calculos['comisiones']!;
    final rappel = calculos['rappel']!;
    final fijo = calculos['fijo']!;
    final base = calculos['base']!;
    final irpf = calculos['irpf']!;
    final importeIrpf = calculos['importe_irpf']!;
    final total = calculos['total']!;

    final estado = f['estado']?.toString() ?? '';
    final color = _estadoColor(estado);
    final verificacion = _verificarFactura(f);

    return Container(
  padding: const EdgeInsets.all(20),
  decoration: _cardDecoration(),
  child: SingleChildScrollView(
    child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DETALLE DE FACTURA',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (_esFacturaEditable(f))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ElevatedButton.icon(
                    onPressed: guardandoAjusteManual ? null : () => _abrirEditorFacturaManual(f),
                    icon: const Icon(Icons.edit_rounded, size: 17),
                    label: const Text('Editar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              IconButton(
                onPressed: () => setState(() => facturaSeleccionada = null),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 14),
          CircleAvatar(
            radius: 31,
            backgroundColor: color.withOpacity(0.13),
            child: Text(
              _iniciales(f['usuario_nombre']),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            f['usuario_nombre']?.toString() ?? 'Usuario',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            f['usuario_rol']?.toString() ?? '',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            f['usuario_email']?.toString() ?? '',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          _estadoBadge(estado),
          const SizedBox(height: 14),
          _tarjetaVerificacion(verificacion),
          const SizedBox(height: 22),
          Text(
            '${nombreMes(f['mes']).toUpperCase()} ${f['anio']}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const Text(
            'Factura pendiente de tramitar',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
  'CONCEPTOS FACTURADOS',
  style: TextStyle(
    color: Color(0xFF0F172A),
    fontWeight: FontWeight.w900,
    fontSize: 12,
  ),
),

const SizedBox(height: 14),

_detailLine(
  'Comisiones',
  comisiones,
  const Color(0xFF2563EB),
),

_detailLine(
  'Rappel',
  rappel,
  const Color(0xFF7C3AED),
),

_detailLine(
  'Fijo',
  fijo,
  const Color(0xFF16A34A),
),

const Divider(height: 28),

_detailLine(
  'BASE IMPONIBLE',
  base,
  const Color(0xFF0F172A),
),

_detailLine(
  'IRPF (${irpf.toStringAsFixed(0)}%)',
  -importeIrpf,
  Colors.red,
),

const Divider(height: 28),

_detailLine(
  'TOTAL FACTURA',
  total,
  const Color(0xFF2563EB),
  big: true,
),
          const SizedBox(height: 20),

const Text(
  'DETALLE DE PÓLIZAS Y EXTORNOS',
  style: TextStyle(
    color: Color(0xFF0F172A),
    fontWeight: FontWeight.w900,
    fontSize: 12,
  ),
),

const SizedBox(height: 10),

if (lineasFactura.isEmpty)
  const Text(
    'No hay líneas cargadas para esta factura.',
    style: TextStyle(
      color: Color(0xFF64748B),
      fontWeight: FontWeight.w600,
    ),
  )
else
  ...lineasFactura.map((l) {
    final tipo = l['tipo_movimiento']?.toString() ?? 'VENTA';
    final esExtorno = tipo.contains('EXTORNO') || tipo.contains('NEGATIVO');
    final esManual = _esLineaManual(l);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esExtorno
            ? const Color(0xFFFFF1F2)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esExtorno
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$tipo · ${l['numero_poliza'] ?? 'Sin póliza'}',
                  style: TextStyle(
                    color: esExtorno
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${_money(l['comision']).toStringAsFixed(2)} €',
                style: TextStyle(
                  color: esExtorno ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              if (esManual && _esFacturaEditable(f)) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Eliminar ajuste manual',
                  onPressed: () => _eliminarAjusteManual(l),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l['cliente_nombre']?.toString() ?? 'Sin cliente',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prima: ${_money(l['prima_neta']).toStringAsFixed(2)} €',
            style: TextStyle(
              color: esExtorno
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }),
          const SizedBox(height: 22),
          const Text(
            'CONFIGURACIÓN FISCAL',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _irpfButton(f, 7, irpf == 7)),
              const SizedBox(width: 10),
              Expanded(child: _irpfButton(f, 15, irpf == 15)),
            ],
          ),
          if (_esFacturaEditable(f)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _recalcularFactura(f),
                icon: const Icon(Icons.calculate_rounded),
                label: const Text('Recalcular totales'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            maxLines: 3,
            decoration: _inputDecoration('Añade una observación...', Icons.edit_note),
          ),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: estado == 'pendiente_tramitar' && esAdmin
                  ? () => tramitarFactura(f)
                  : null,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Tramitar factura'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: f == null
    ? null
    : () async {
    final calculosPreview = _calculosFactura(f);
    final base = calculosPreview['base']!;
    final rappel = calculosPreview['rappel']!;
    final irpf = calculosPreview['irpf']!;
    final importeIrpf = calculosPreview['importe_irpf']!;
    final total = calculosPreview['total']!;
    final comisiones = calculosPreview['comisiones']!;
    final fijo = calculosPreview['fijo']!;

final lineasPreview = await supabase
    .from('nominas_facturas_lineas')
    .select()
    .eq('factura_id', f['id'])
    .order('created_at', ascending: true);

final lineasPdf = (lineasPreview as List)
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

final bytes = await _generarPdfFactura(
  factura: f,
  lineas: lineasPdf,
  numeroFactura: f['numero_factura']?.toString() ?? 'BORRADOR',
  comisiones: comisiones,
  rappel: rappel,
  fijo: fijo,
  base: base,
  irpf: irpf,
  importeIrpf: importeIrpf,
  total: total,
);

        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
        );
      },
              icon: const Icon(Icons.remove_red_eye_rounded),
              label: const Text('Vista previa PDF'),
            ),
          ),
        ],
        ),
      ),
    );
  }


  Widget _tarjetaVerificacion(Map<String, dynamic> verificacion) {
    final sinLineas = verificacion['sin_lineas'] == true;
    final correcta = verificacion['correcta'] == true;

    final color = sinLineas
        ? const Color(0xFFF59E0B)
        : correcta
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);

    final titulo = sinLineas
        ? 'Sin líneas recibidas desde Nóminas'
        : correcta
            ? 'Datos recibidos correctamente'
            : 'Hay diferencias que revisar';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correcta
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${verificacion['ventas']} ventas · '
            '${verificacion['extornos']} extornos · '
            '${verificacion['ajustes']} ajustes manuales',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          if (!sinLineas && !correcta) ...[
            const SizedBox(height: 5),
            Text(
              'Diferencia comisiones: '
              '${_money(verificacion['diferencia_comisiones']).toStringAsFixed(2)} € · '
              'Diferencia base: '
              '${_money(verificacion['diferencia_base']).toStringAsFixed(2)} €',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _irpfButton(Map<String, dynamic> f, double value, bool selected) {
    return OutlinedButton(
      onPressed: _esFacturaEditable(f) ? () => cambiarIrpf(f, value) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF2563EB) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text('${value.toStringAsFixed(0)}%'),
    );
  }

  Widget _detailLine(String title, double value, Color color, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontWeight: big ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} €',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: big ? 19 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }

  Widget _estadoBadge(String estado) {
    final color = _estadoColor(estado);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }

  Color _estadoColor(String estado) {
    if (estado == 'tramitada') return const Color(0xFF16A34A);
    if (estado == 'enviada_email') return const Color(0xFF2563EB);
    if (estado == 'error_email') return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String _iniciales(dynamic nombre) {
    final text = nombre?.toString().trim() ?? '';
    if (text.isEmpty) return 'US';

    final partes = text.split(' ');
    if (partes.length == 1) {
      return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.blueGrey.withOpacity(0.06),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontWeight: FontWeight.w900,
        fontSize: 11,
      ),
    );
  }
}
