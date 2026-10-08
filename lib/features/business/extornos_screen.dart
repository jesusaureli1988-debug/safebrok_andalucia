import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/widgets/progressive_records.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExtornosScreen extends StatefulWidget {
  const ExtornosScreen({super.key});

  @override
  State<ExtornosScreen> createState() => _ExtornosScreenState();
}

class _ExtornosScreenState extends State<ExtornosScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _busqueda = TextEditingController();

  List<Map<String, dynamic>> _extornos = [];
  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;
  String? _error;
  String? _authIdActual;

  DateTime? _desde;
  DateTime? _hasta;
  String _persona = 'Todos';
  String _producto = 'Todos';
  String _compania = 'Todos';

  static const _navy = Color(0xFF071A3A);
  static const _blue = Color(0xFF2454D3);
  static const _red = Color(0xFFE5484D);
  static const _bg = Color(0xFFF4F6FB);

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(_actualizar);
    _cargar();
  }

  @override
  void dispose() {
    _busqueda
      ..removeListener(_actualizar)
      ..dispose();
    super.dispose();
  }

  void _actualizar() {
    if (mounted) setState(() {});
  }

  String _texto(dynamic value) => (value ?? '').toString().trim();

  String _rol(dynamic value) =>
      _texto(value).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  double _numero(dynamic value) {
    if (value is num) return value.toDouble();
    final text = _texto(value).replaceAll(',', '.');
    return double.tryParse(text) ?? 0;
  }

  DateTime? _fecha(dynamic value) {
    final text = _texto(value);
    return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
  }

  String _nombre(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Sin asignar';
    final nombre =
        '${_texto(usuario['nombre'])} ${_texto(usuario['apellidos'])}'.trim();
    return nombre.isNotEmpty ? nombre : _texto(usuario['email']);
  }

  List<Map<String, dynamic>> _estructura({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todos,
  }) {
    final rol = _rol(perfil['rol_usuario']);
    if (<String>{
      'administracion',
      'administrador',
      'admin',
      'director_nacional',
    }.contains(rol)) {
      return todos.where((u) => _texto(u['auth_id']).isNotEmpty).toList();
    }

    final porPadre = <String, List<Map<String, dynamic>>>{};
    for (final usuario in todos) {
      final parentId = _texto(usuario['parent_id']);
      if (parentId.isNotEmpty) {
        porPadre.putIfAbsent(parentId, () => []).add(usuario);
      }
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> usuario) {
      final id = _texto(usuario['id']);
      if (id.isEmpty || !visitados.add(id)) return;
      if (_texto(usuario['auth_id']).isNotEmpty) resultado.add(usuario);
      for (final hijo in porPadre[id] ?? const <Map<String, dynamic>>[]) {
        recorrer(hijo);
      }
    }

    recorrer(perfil);
    return resultado;
  }

  bool _esExtorno(Map<String, dynamic> venta) {
    final estado = _texto(venta['estado_poliza']).toLowerCase();
    return estado.contains('anulad') ||
        estado.contains('extorn') ||
        estado.contains('cancelad') ||
        estado == 'baja' ||
        _texto(venta['fecha_anulacion']).isNotEmpty ||
        _texto(venta['anulacion_id']).isNotEmpty;
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final auth = supabase.auth.currentUser;
      if (auth == null) throw Exception('No hay una sesión activa.');

      final perfilRaw = await supabase
          .from('usuarios')
          .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,email')
          .eq('auth_id', auth.id)
          .single();
      final perfil = Map<String, dynamic>.from(perfilRaw);

      final usuariosRaw = await supabase
          .from('usuarios')
          .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,email');
      final todos = List<Map<String, dynamic>>.from(usuariosRaw);
      final permitidos = _estructura(perfil: perfil, todos: todos);
      final authIds = permitidos
          .map((u) => _texto(u['auth_id']))
          .where((id) => id.isNotEmpty)
          .toList();

      final encontrados = <Map<String, dynamic>>[];
      if (authIds.isNotEmpty) {
        final ventasRaw = await supabase
            .from('ventas')
            .select('''
              id,created_at,agente_auth_id,producto,compania,numero_poliza,
              fecha_efecto,estado_poliza,fecha_anulacion,motivo_anulacion,
              observaciones_anulacion,prima_anual_neta,prima_extornada,
              comision,comision_extornada,anulacion_id,
              clientes(nombre,apellidos,telefono)
            ''')
            .inFilter('agente_auth_id', authIds)
            .order('fecha_anulacion', ascending: false);
        encontrados.addAll(
          List<Map<String, dynamic>>.from(ventasRaw).where(_esExtorno),
        );
      }

      if (!mounted) return;
      setState(() {
        _authIdActual = auth.id;
        _usuarios = permitidos
          ..sort((a, b) => _nombre(a).compareTo(_nombre(b)));
        _extornos = encontrados;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Map<String, dynamic>? _usuarioPorAuth(dynamic authId) {
    final id = _texto(authId);
    for (final usuario in _usuarios) {
      if (_texto(usuario['auth_id']) == id) return usuario;
    }
    return null;
  }

  List<Map<String, dynamic>> get _filtrados {
    final query = _busqueda.text.trim().toLowerCase();
    return _extornos.where((venta) {
      final fecha =
          _fecha(venta['fecha_anulacion']) ??
          _fecha(venta['created_at']) ??
          _fecha(venta['fecha_efecto']);
      if (_desde != null &&
          (fecha == null ||
              fecha.isBefore(
                DateTime(_desde!.year, _desde!.month, _desde!.day),
              ))) {
        return false;
      }
      if (_hasta != null) {
        final fin = DateTime(
          _hasta!.year,
          _hasta!.month,
          _hasta!.day,
          23,
          59,
          59,
          999,
        );
        if (fecha == null || fecha.isAfter(fin)) return false;
      }
      if (_persona != 'Todos' && _texto(venta['agente_auth_id']) != _persona) {
        return false;
      }
      if (_producto != 'Todos' && _texto(venta['producto']) != _producto) {
        return false;
      }
      if (_compania != 'Todos' && _texto(venta['compania']) != _compania) {
        return false;
      }
      if (query.isNotEmpty) {
        final cliente = venta['clientes'] is Map
            ? Map<String, dynamic>.from(venta['clientes'])
            : <String, dynamic>{};
        final contenido = [
          venta['numero_poliza'],
          venta['producto'],
          venta['compania'],
          venta['motivo_anulacion'],
          cliente['nombre'],
          cliente['apellidos'],
          _nombre(_usuarioPorAuth(venta['agente_auth_id'])),
        ].map(_texto).join(' ').toLowerCase();
        if (!contenido.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  List<String> _opciones(String campo) {
    final values =
        _extornos
            .map((e) => _texto(e[campo]))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['Todos', ...values];
  }

  double get _primaTotal =>
      _filtrados.fold(0, (total, e) => total + _numero(e['prima_extornada']));

  double get _comisionTotal => _filtrados.fold(
    0,
    (total, e) => total + _numero(e['comision_extornada']),
  );

  String _euros(double value) =>
      '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

  String _fechaTexto(dynamic value) {
    final fecha = _fecha(value);
    if (fecha == null) return 'Sin fecha';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Future<void> _seleccionarFecha(bool desde) async {
    final actual = desde ? _desde : _hasta;
    final value = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: desde ? 'Fecha inicial' : 'Fecha final',
    );
    if (value == null || !mounted) return;
    setState(() {
      if (desde) {
        _desde = value;
      } else {
        _hasta = value;
      }
    });
  }

  void _limpiarFiltros() {
    _busqueda.clear();
    setState(() {
      _desde = null;
      _hasta = null;
      _persona = 'Todos';
      _producto = 'Todos';
      _compania = 'Todos';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Extornos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : _error != null
          ? _errorView()
          : RefreshIndicator(
              onRefresh: _cargar,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _hero(),
                        const SizedBox(height: 16),
                        _resumen(),
                        const SizedBox(height: 16),
                        _filtros(),
                        const SizedBox(height: 16),
                        _cabeceraResultados(),
                        const SizedBox(height: 10),
                      ]),
                    ),
                  ),
                  if (_filtrados.isEmpty)
                    SliverToBoxAdapter(child: _vacio())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: ProgressiveSliverList.builder(
                        itemCount: _filtrados.length,
                        resetKey: progressiveRecordKey(_filtrados),
                        itemBuilder: (_, index) =>
                            _tarjetaExtorno(_filtrados[index]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8E1B2D), Color(0xFFE5484D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _red.withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(
              Icons.trending_down_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bajas y extornos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Consulta el impacto propio y de toda tu estructura.',
                  style: TextStyle(color: Color(0xFFEFF4FF), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumen() {
    return Row(
      children: [
        Expanded(
          child: _metrica(
            'Pólizas',
            _filtrados.length.toString(),
            Icons.receipt_long_rounded,
            _navy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metrica(
            'Prima',
            _euros(_primaTotal),
            Icons.south_east_rounded,
            _red,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metrica(
            'Comisión',
            _euros(_comisionTotal),
            Icons.account_balance_wallet_outlined,
            const Color(0xFFB56A00),
          ),
        ),
      ],
    );
  }

  Widget _metrica(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: _blue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Filtros',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              TextButton(
                onPressed: _limpiarFiltros,
                child: const Text('Limpiar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _busqueda,
            decoration: _decoracion(
              'Cliente, póliza o motivo',
              Icons.search_rounded,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth > 720
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: width, child: _personaDropdown()),
                  SizedBox(
                    width: width,
                    child: _dropdown(
                      value: _producto,
                      label: 'Producto',
                      icon: Icons.inventory_2_outlined,
                      options: _opciones('producto'),
                      onChanged: (v) => setState(() => _producto = v),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _dropdown(
                      value: _compania,
                      label: 'Compañía',
                      icon: Icons.business_outlined,
                      options: _opciones('compania'),
                      onChanged: (v) => setState(() => _compania = v),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _fechaButton(true)),
              const SizedBox(width: 12),
              Expanded(child: _fechaButton(false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _personaDropdown() {
    final options = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'Todos', child: Text('Toda mi estructura')),
      ..._usuarios.map(
        (usuario) => DropdownMenuItem(
          value: _texto(usuario['auth_id']),
          child: Text(
            _texto(usuario['auth_id']) == _authIdActual
                ? '${_nombre(usuario)} (yo)'
                : _nombre(usuario),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
    return DropdownButtonFormField<String>(
      value: _persona,
      isExpanded: true,
      decoration: _decoracion('Persona', Icons.person_outline_rounded),
      items: options,
      onChanged: (value) => setState(() => _persona = value ?? 'Todos'),
    );
  }

  Widget _dropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: _decoracion(label, icon),
      items: options
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) => onChanged(v ?? 'Todos'),
    );
  }

  InputDecoration _decoracion(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _blue),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE1E7EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE1E7EF)),
      ),
    );
  }

  Widget _fechaButton(bool desde) {
    final value = desde ? _desde : _hasta;
    return OutlinedButton.icon(
      onPressed: () => _seleccionarFecha(desde),
      icon: const Icon(Icons.calendar_month_rounded),
      label: Text(
        value == null
            ? (desde ? 'Desde' : 'Hasta')
            : _fechaTexto(value.toIso8601String()),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _navy,
        padding: const EdgeInsets.symmetric(vertical: 15),
        side: const BorderSide(color: Color(0xFFD5DDE8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _cabeceraResultados() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Pólizas dadas de baja',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        Text(
          '${_filtrados.length} resultados',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _tarjetaExtorno(Map<String, dynamic> venta) {
    final cliente = venta['clientes'] is Map
        ? Map<String, dynamic>.from(venta['clientes'])
        : <String, dynamic>{};
    final nombreCliente =
        '${_texto(cliente['nombre'])} ${_texto(cliente['apellidos'])}'.trim();
    final usuario = _usuarioPorAuth(venta['agente_auth_id']);
    final esPropio = _texto(venta['agente_auth_id']) == _authIdActual;
    final motivo = _texto(venta['motivo_anulacion']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.trending_down_rounded, color: _red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _texto(venta['producto']).isEmpty
                          ? 'Producto sin indicar'
                          : _texto(venta['producto']),
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      nombreCliente.isEmpty
                          ? 'Cliente sin nombre'
                          : nombreCliente,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              _chip(
                esPropio ? 'Propio' : 'Estructura',
                esPropio ? _blue : _red,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _dato(
                Icons.confirmation_number_outlined,
                _texto(venta['numero_poliza']).isEmpty
                    ? 'Sin póliza'
                    : _texto(venta['numero_poliza']),
              ),
              _dato(Icons.business_outlined, _texto(venta['compania'])),
              _dato(
                Icons.event_busy_outlined,
                _fechaTexto(venta['fecha_anulacion']),
              ),
              _dato(Icons.person_outline_rounded, _nombre(usuario)),
            ],
          ),
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              motivo,
              style: const TextStyle(color: Color(0xFF475569), height: 1.4),
            ),
          ],
          const Divider(height: 26, color: Color(0xFFE8EDF3)),
          Row(
            children: [
              Expanded(
                child: _importe(
                  'Prima extornada',
                  _numero(venta['prima_extornada']),
                  _red,
                ),
              ),
              Expanded(
                child: _importe(
                  'Comisión afectada',
                  _numero(venta['comision_extornada']),
                  const Color(0xFFB56A00),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
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
    );
  }

  Widget _dato(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _importe(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _euros(value),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _vacio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: const Column(
        children: [
          Icon(Icons.verified_outlined, color: Color(0xFF94A3B8), size: 48),
          SizedBox(height: 12),
          Text(
            'No hay extornos con estos filtros',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Prueba otro periodo, persona, producto o compañía.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _red, size: 52),
            const SizedBox(height: 14),
            Text(
              _error ?? 'No se pudieron cargar los extornos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
