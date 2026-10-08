import 'package:safebrok_andalucia/core/widgets/progressive_records.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VentasSinAgentesScreen extends StatefulWidget {
  const VentasSinAgentesScreen({super.key});
  @override
  State<VentasSinAgentesScreen> createState() => _VentasSinAgentesScreenState();
}

class _VentasSinAgentesScreenState extends State<VentasSinAgentesScreen> {
  final _db = Supabase.instance.client;
  final _busqueda = TextEditingController();
  List<Map<String, dynamic>> _polizas = [];
  final Set<String> _seleccion = {};
  bool _cargando = true;
  bool _asignando = false;
  bool _autorizado = false;
  String? _error;
  String? _agenteExcel;
  DateTimeRange? _fechas;
  String _tipoFecha = 'efecto';
  String? _resultado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  String _texto(dynamic value) => (value ?? '').toString();
  String _normalizar(dynamic value) => _texto(value)
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  Map<String, dynamic> _datos(Map<String, dynamic> p, String campo) =>
      Map<String, dynamic>.from(p[campo] as Map? ?? {});

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión.');
      final perfil = await _db
          .from('usuarios')
          .select('rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();
      final rol = _texto(
        perfil?['rol_usuario'],
      ).trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
      if (rol != 'director_nacional') {
        if (mounted) setState(() => _autorizado = false);
        return;
      }
      final filas = <Map<String, dynamic>>[];
      for (var desde = 0; ; desde += 1000) {
        final pagina = await _db
            .from('polizas_pendientes_asignacion')
            .select()
            .order('created_at', ascending: false)
            .order('id')
            .range(desde, desde + 999);
        filas.addAll(List<Map<String, dynamic>>.from(pagina));
        if (pagina.length < 1000) break;
      }
      if (!mounted) return;
      setState(() {
        _autorizado = true;
        _polizas = filas;
        _seleccion.retainAll(filas.map((p) => _texto(p['id'])));
        if (!filas.any((p) => p['agente_nombre_importado'] == _agenteExcel)) {
          _agenteExcel = null;
        }
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'No se pudo cargar el listado: $error');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    final buscar = _normalizar(_busqueda.text.trim());
    return _polizas.where((p) {
      final venta = _datos(p, 'venta_datos');
      final cliente = _datos(p, 'cliente_datos');
      if (_agenteExcel != null && p['agente_nombre_importado'] != _agenteExcel)
        return false;
      if (_fechas != null) {
        final fecha = DateTime.tryParse(
          _texto(
            _tipoFecha == 'efecto' ? venta['fecha_efecto'] : p['created_at'],
          ),
        )?.toLocal();
        if (fecha == null) return false;
        final dia = DateTime(fecha.year, fecha.month, fecha.day);
        if (dia.isBefore(_fechas!.start) || dia.isAfter(_fechas!.end))
          return false;
      }
      return buscar.isEmpty ||
          _normalizar(
            [
              p['numero_poliza'],
              p['agente_nombre_importado'],
              cliente['nombre'],
              cliente['apellidos'],
              cliente['dni'],
              cliente['email'],
              venta['producto'],
              venta['compania'],
            ].join(' '),
          ).contains(buscar);
    }).toList();
  }

  Future<Map<String, dynamic>?> _elegirMediador() async {
    final usuarios = <Map<String, dynamic>>[];
    for (var desde = 0; ; desde += 1000) {
      final pagina = await _db
          .from('usuarios')
          .select('auth_id,nombre,apellidos,rol_usuario,estado')
          .order('id')
          .range(desde, desde + 999);
      usuarios.addAll(
        List<Map<String, dynamic>>.from(pagina).where(
          (u) =>
              _texto(u['auth_id']).isNotEmpty &&
              !{
                'inactivo',
                'inactiva',
                'baja',
                'bloqueado',
                'bloqueada',
                'desactivado',
                'desactivada',
                'suspendido',
                'suspendida',
              }.contains(_normalizar(u['estado'])),
        ),
      );
      if (pagina.length < 1000) break;
    }
    if (!mounted) return null;
    var buscar = '';
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, actualizar) {
          final visibles = usuarios
              .where(
                (u) => _normalizar(
                  '${u['nombre']} ${u['apellidos']} ${u['rol_usuario']}',
                ).contains(buscar),
              )
              .toList();
          return AlertDialog(
            title: const Text('Asignar a mediador o responsable de estructura'),
            content: SizedBox(
              width: 550,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar nombre o rol',
                    ),
                    onChanged: (v) => actualizar(() => buscar = _normalizar(v)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ProgressiveListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (ctx, i) {
                        final u = visibles[i];
                        return ListTile(
                          title: Text(
                            '${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}'
                                .trim(),
                          ),
                          subtitle: Text(_texto(u['rol_usuario'])),
                          onTap: () => Navigator.pop(ctx, u),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reasignar() async {
    if (_seleccion.isEmpty || _asignando) return;
    setState(() => _asignando = true);
    var guardadas = 0;
    try {
      final agente = await _elegirMediador();
      if (agente == null || !mounted) return;
      final nombre = '${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}'
          .trim();
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar asignación'),
          content: Text(
            'Asignar ${_seleccion.length} pólizas a $nombre. Aparecerán en sus ventas y en su estructura.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      final ids = _seleccion.toList();
      for (var i = 0; i < ids.length; i += 50) {
        final fin = i + 50 < ids.length ? i + 50 : ids.length;
        final lote = ids.sublist(i, fin);
        final cantidad = await _db.rpc(
          'app_asignar_polizas_pendientes',
          params: {'p_ids': lote, 'p_agente_auth_id': agente['auth_id']},
        );
        guardadas += (cantidad as num).toInt();
        if (!mounted) return;
        setState(() {
          _seleccion.removeAll(lote);
          _resultado = '$guardadas pólizas asignadas a $nombre';
        });
      }
      await _cargar();
    } catch (error) {
      if (mounted)
        setState(
          () => _resultado =
              '$guardadas asignadas. No se pudo completar el resto: $error',
        );
      await _cargar();
    } finally {
      if (mounted) setState(() => _asignando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    if (!_autorizado)
      return const Center(
        child: Text('Solo disponible para el director nacional.'),
      );
    final filas = _filtradas;
    final idsVisibles = filas.map((p) => _texto(p['id'])).toSet();
    final seleccionadasVisibles = idsVisibles.where(_seleccion.contains).length;
    final agentes =
        _polizas
            .map((p) => _texto(p['agente_nombre_importado']))
            .toSet()
            .toList()
          ..sort();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ventas sin agentes',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF071A3A),
            ),
          ),
          Text(
            '${_polizas.length} pólizas guardadas pendientes de asignación · ${filas.length} visibles',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _busqueda,
            enabled: !_asignando,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar póliza, tomador, NIF, agente o compañía',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: _agenteExcel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Agente del Excel',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...agentes.map(
                      (a) => DropdownMenuItem(value: a, child: Text(a)),
                    ),
                  ],
                  onChanged: _asignando
                      ? null
                      : (v) => setState(() => _agenteExcel = v),
                ),
              ),
              DropdownButton<String>(
                value: _tipoFecha,
                items: const [
                  DropdownMenuItem(
                    value: 'efecto',
                    child: Text('Fecha de efecto'),
                  ),
                  DropdownMenuItem(
                    value: 'carga',
                    child: Text('Fecha de carga'),
                  ),
                ],
                onChanged: _asignando
                    ? null
                    : (v) => setState(() => _tipoFecha = v!),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  _fechas == null
                      ? 'Filtrar fechas'
                      : '${_fechas!.start.day}/${_fechas!.start.month}/${_fechas!.start.year} — ${_fechas!.end.day}/${_fechas!.end.month}/${_fechas!.end.year}',
                ),
                onPressed: _asignando
                    ? null
                    : () async {
                        final rango = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                          initialDateRange: _fechas,
                        );
                        if (mounted && rango != null)
                          setState(() => _fechas = rango);
                      },
              ),
              TextButton(
                onPressed: _asignando
                    ? null
                    : () => setState(() {
                        _fechas = null;
                        _agenteExcel = null;
                        _busqueda.clear();
                      }),
                child: const Text('Limpiar filtros'),
              ),
              IconButton(
                onPressed: _asignando ? null : _cargar,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            tristate: true,
            value: seleccionadasVisibles == 0
                ? false
                : seleccionadasVisibles == idsVisibles.length
                ? true
                : null,
            title: Text('Seleccionar todo (${filas.length})'),
            subtitle: const Text(
              'Selecciona todas las pólizas que cumplen los filtros actuales.',
            ),
            onChanged: _asignando || idsVisibles.isEmpty
                ? null
                : (_) => setState(() {
                    if (seleccionadasVisibles == idsVisibles.length) {
                      _seleccion.removeAll(idsVisibles);
                    } else {
                      _seleccion.addAll(idsVisibles);
                    }
                  }),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _asignando ? null : () => setState(_seleccion.clear),
                child: const Text('Quitar selección'),
              ),
              FilledButton.icon(
                onPressed: _asignando || _seleccion.isEmpty ? null : _reasignar,
                icon: const Icon(Icons.person_add_alt),
                label: Text(
                  _asignando
                      ? 'Asignando…'
                      : 'Reasignar ${_seleccion.length} seleccionadas',
                ),
              ),
            ],
          ),
          if (_resultado != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(_resultado!),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: filas.isEmpty
                ? const Center(
                    child: Text('No hay pólizas pendientes con estos filtros.'),
                  )
                : ProgressiveListView.builder(
                    itemCount: filas.length,
                    resetKey: progressiveRecordKey(filas),
                    itemBuilder: (ctx, i) {
                      final p = filas[i];
                      final v = _datos(p, 'venta_datos');
                      final c = _datos(p, 'cliente_datos');
                      final id = _texto(p['id']);
                      return Card(
                        child: CheckboxListTile(
                          value: _seleccion.contains(id),
                          onChanged: _asignando
                              ? null
                              : (valor) => setState(() {
                                  if (valor == true) {
                                    _seleccion.add(id);
                                  } else {
                                    _seleccion.remove(id);
                                  }
                                }),
                          title: Text(
                            '${p['numero_poliza']} · ${c['nombre'] ?? ''} ${c['apellidos'] ?? ''}',
                          ),
                          subtitle: Text(
                            'Agente Excel: ${p['agente_nombre_importado']}\n'
                            '${v['compania'] ?? ''} · ${v['producto'] ?? ''} · Efecto: ${v['fecha_efecto'] ?? ''}\n'
                            'Prima neta: ${v['prima_anual_neta'] ?? 0} € · NIF: ${c['dni'] ?? ''}',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
