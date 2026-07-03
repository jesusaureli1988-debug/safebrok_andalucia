import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ReferenciasScreen extends StatefulWidget {
  const ReferenciasScreen({super.key});

  @override
  State<ReferenciasScreen> createState() => _ReferenciasScreenState();
}

class _ReferenciasScreenState extends State<ReferenciasScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> referencias = [];
  List<String> authIdsPermitidos = [];

  bool cargando = true;

  String filtro = "Todas";
  String busqueda = "";

  String? userRole;
  String? userAuthId;
 String? userInternalId;

  @override
  void initState() {
    super.initState();
    loadReferencias();
  }

 Future<void> loadReferencias() async {
  final user = supabase.auth.currentUser;

  print('================ REFERENCIAS DEBUG ================');
  print('USER AUTH ACTUAL: ${user?.id}');

  if (user == null) {
    print('NO HAY USUARIO LOGUEADO');
    setState(() => cargando = false);
    return;
  }

  setState(() => cargando = true);

  try {
    final perfil = await supabase
        .from('usuarios')
        .select('id, auth_id, rol_usuario, parent_id')
        .eq('auth_id', user.id)
        .maybeSingle();

    print('PERFIL USUARIO: $perfil');

    userRole = perfil?['rol_usuario']?.toString();
    userAuthId = perfil?['auth_id']?.toString();
    userInternalId = perfil?['id']?.toString();

    print('ROLE: $userRole');
    print('USER AUTH ID PERFIL: $userAuthId');
    print('USER INTERNAL ID: $userInternalId');

    authIdsPermitidos = await _getAuthIdsEstructura(
      internalId: userInternalId,
      authId: userAuthId ?? user.id,
      role: userRole ?? 'agente',
    );

    print('AUTH IDS PERMITIDOS: $authIdsPermitidos');
    print('VE TODO: ${_veTodo(userRole)}');

    dynamic query = supabase.from('referencias_viables').select();

    if (!_veTodo(userRole)) {
      print('APLICANDO FILTRO POR ESTRUCTURA');
      query = query.inFilter('auth_id', authIdsPermitidos);
    } else {
      print('NO APLICA FILTRO, VE TODO');
    }

    final data = await query;

    final usuariosData = await supabase
    .from('usuarios')
    .select('auth_id, nombre');

final usuariosPorAuthId = {
  for (final u in List<Map<String, dynamic>>.from(usuariosData))
    if (u['auth_id'] != null)
      u['auth_id'].toString(): u['nombre']?.toString() ?? 'Sin agente',
};

    print('DATA RAW TIPO: ${data.runtimeType}');
    print('DATA RAW TOTAL: ${data.length}');
    print('DATA RAW PRIMEROS 3: ${List<Map<String, dynamic>>.from(data).take(3).toList()}');

    final listaRaw = List<Map<String, dynamic>>.from(data).map((r) {
  final authIdRef = r['auth_id']?.toString();

  return {
    ...r,
    'nombre_agente_ref': usuariosPorAuthId[authIdRef] ?? 'Sin agente',
  };
}).toList();

    final filtradas = listaRaw.where((r) {
      final estado = r['estado']?.toString().toLowerCase().trim() ?? '';

      final activa = estado != 'resuelto' &&
          estado != 'cerrado' &&
          estado != 'contratado' &&
          estado != 'desechado';

      print(
        'REF ${r['id']} | auth_id=${r['auth_id']} | estado=$estado | activa=$activa | nombre=${r['nombre']}',
      );

      return activa;
    }).toList();

    print('TOTAL DESPUES FILTRO ACTIVAS: ${filtradas.length}');

    filtradas.sort((a, b) {
      final scoreA = _scoreReferencia(a);
      final scoreB = _scoreReferencia(b);
      return scoreB.compareTo(scoreA);
    });

    if (!mounted) return;

    setState(() {
      referencias = filtradas;
      cargando = false;
    });

    print('TOTAL FINAL EN STATE: ${referencias.length}');
    print('================ FIN REFERENCIAS DEBUG ================');
  } catch (e) {
    print('ERROR LOAD REFERENCIAS: $e');
    print('================ FIN REFERENCIAS DEBUG CON ERROR ================');

    if (!mounted) return;
    setState(() => cargando = false);
    _snack('Error cargando referencias: $e');
  }
}

  bool _veTodo(String? role) {
    return role == 'director_nacional' || role == 'administracion';
  }

 Future<List<String>> _getAuthIdsEstructura({
  required String? internalId,
  required String authId,
  required String role,
}) async {
  if (role == 'administracion' || role == 'director_nacional') {
    return [];
  }

  if (role == 'agente') {
    return [authId];
  }

  if (internalId == null || internalId.isEmpty) {
    return [authId];
  }

  final usuarios = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario');

  final lista = List<Map<String, dynamic>>.from(usuarios);

  final Set<String> idsPermitidos = {internalId};
  final Set<String> authPermitidos = {};

  bool added = true;

  while (added) {
    added = false;

    for (final u in lista) {
      final id = u['id']?.toString();
      final parentId = u['parent_id']?.toString();

      if (id != null &&
          id.isNotEmpty &&
          parentId != null &&
          parentId.isNotEmpty &&
          idsPermitidos.contains(parentId) &&
          !idsPermitidos.contains(id)) {
        idsPermitidos.add(id);
        added = true;
      }
    }
  }

  for (final u in lista) {
    final id = u['id']?.toString();
    final auth = u['auth_id']?.toString();

    if (id != null &&
        idsPermitidos.contains(id) &&
        auth != null &&
        auth.isNotEmpty &&
        auth != 'null') {
      authPermitidos.add(auth);
    }
  }

  authPermitidos.add(authId);

  print('IDS INTERNOS PERMITIDOS: $idsPermitidos');
  print('AUTH IDS FINALES PERMITIDOS: $authPermitidos');

  return authPermitidos.toList();
}

  List<Map<String, dynamic>> get referenciasFiltradas {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return referencias.where((r) {
      final prioridad = r['prioridad']?.toString() ?? 'Media';
      final nombre = r['nombre']?.toString().toLowerCase() ?? '';
      final telefono = r['telefono']?.toString().toLowerCase() ?? '';
      final compania = r['compania_actual']?.toString().toLowerCase() ?? '';
      final texto = busqueda.toLowerCase().trim();

      final score = _scoreReferencia(r);
      final requiereVisita = r['requiere_visita'] == true;

      final fechaVencimiento = _parseDate(r['fecha_vencimiento']);
      final fechaRellamada = _parseDate(r['fecha_rellamada']);

      final venceHoy = fechaVencimiento != null && _sameDay(fechaVencimiento, today);
      final llamadaHoy = fechaRellamada != null && _sameDay(fechaRellamada, today);

      final vence7Dias = fechaVencimiento != null &&
          !fechaVencimiento.isBefore(today) &&
          fechaVencimiento.difference(today).inDays <= 7;

      final proximaLlamada = fechaRellamada != null &&
          !fechaRellamada.isBefore(today);

      final cumpleFiltro =
          filtro == "Todas" ||
          filtro == "Hoy" && (venceHoy || llamadaHoy) ||
          filtro == "Próximas" && proximaLlamada ||
          filtro == "Calientes" && score >= 75 ||
          filtro == "Visitas" && requiereVisita ||
          filtro == "Vencimientos" && vence7Dias ||
          filtro == prioridad;

      final cumpleBusqueda = texto.isEmpty ||
          nombre.contains(texto) ||
          telefono.contains(texto) ||
          compania.contains(texto);

      return cumpleFiltro && cumpleBusqueda;
    }).toList();
  }

  int get totalHoy {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return referencias.where((r) {
      final v = _parseDate(r['fecha_vencimiento']);
      final rr = _parseDate(r['fecha_rellamada']);
      return (v != null && _sameDay(v, today)) ||
          (rr != null && _sameDay(rr, today));
    }).length;
  }

  int get totalAlta =>
      referencias.where((r) => r['prioridad'] == 'Alta').length;

  int get totalVisita =>
      referencias.where((r) => r['requiere_visita'] == true).length;

  int get totalUrgentes =>
      referencias.where((r) => _scoreReferencia(r) >= 75).length;

  int get totalVencen7 {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return referencias.where((r) {
      final fecha = _parseDate(r['fecha_vencimiento']);
      return fecha != null &&
          !fecha.isBefore(today) &&
          fecha.difference(today).inDays <= 7;
    }).length;
  }

  int get totalCerradasMes {
    final now = DateTime.now();

    return referencias.where((r) {
      final estado = r['estado']?.toString();
      final fecha = _parseDate(r['updated_at']) ?? _parseDate(r['created_at']);
      return estado == 'Resuelto' &&
          fecha != null &&
          fecha.month == now.month &&
          fecha.year == now.year;
    }).length;
  }

  double get conversionMes {
    if (referencias.isEmpty) return 0;
    return (totalCerradasMes / referencias.length) * 100;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  bool _sameDay(DateTime value, DateTime today) {
    return value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
  }

  int _scoreReferencia(Map<String, dynamic> r) {
    int score = 20;

    final prioridad = r['prioridad']?.toString() ?? 'Media';

    if (prioridad == 'Alta') score += 35;
    if (prioridad == 'Media') score += 20;
    if (prioridad == 'Baja') score += 8;

    if (r['requiere_visita'] == true) score += 15;

    final productos = _productos(r['productos_actuales']);
    if (productos.length >= 2) score += 12;
    if (productos.length >= 3) score += 8;

    final fecha = _parseDate(r['fecha_vencimiento']);

    if (fecha != null) {
      final dias = fecha.difference(DateTime.now()).inDays;

      if (dias <= 7 && dias >= 0) score += 25;
      if (dias <= 15 && dias > 7) score += 15;
      if (dias < 0) score += 18;
    }

    final rellamada = _parseDate(r['fecha_rellamada']);

    if (rellamada != null) {
      final diasRellamada = rellamada.difference(DateTime.now()).inDays;
      if (diasRellamada <= 0) score += 12;
      if (diasRellamada > 0 && diasRellamada <= 3) score += 8;
    }

    return score.clamp(0, 100);
  }

  List<String> _productos(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    final text = value.toString();

    if (text.contains('/')) {
      return text.split('/').where((e) => e.trim().isNotEmpty).toList();
    }

    if (text.contains(',')) {
      return text.split(',').where((e) => e.trim().isNotEmpty).toList();
    }

    if (text.trim().isEmpty) return [];

    return [text];
  }

  String _fechaTexto(dynamic value) {
    if (value == null || value.toString().isEmpty) return "Sin vencimiento";

    final fecha = DateTime.tryParse(value.toString());
    if (fecha == null) return "Sin vencimiento";

    final hoy = DateTime.now();
    final today = DateTime(hoy.year, hoy.month, hoy.day);
    final cleanFecha = DateTime(fecha.year, fecha.month, fecha.day);

    final dias = cleanFecha.difference(today).inDays;

    if (dias < 0) return "Vencida hace ${dias.abs()} días";
    if (dias == 0) return "Vence hoy";
    if (dias == 1) return "Vence mañana";

    return "Vence en $dias días";
  }

  String _fechaBonita(dynamic value) {
    if (value == null || value.toString().isEmpty) return "Sin fecha";

    final fecha = DateTime.tryParse(value.toString());
    if (fecha == null) return "Sin fecha";

    return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
  }

  Color _prioridadColor(String prioridad) {
    switch (prioridad) {
      case 'Alta':
        return Colors.redAccent;
      case 'Media':
        return Colors.orangeAccent;
      case 'Baja':
        return Colors.greenAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  Color _scoreColor(int score) {
    if (score >= 75) return Colors.redAccent;
    if (score >= 50) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _scoreTexto(int score) {
    if (score >= 75) return "Muy caliente";
    if (score >= 50) return "Interesante";
    return "Seguimiento";
  }

  void _snack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  Future<void> crearReferencia() async {
    final nombreController = TextEditingController();
    final telefonoController = TextEditingController();
    final notasController = TextEditingController();

    String prioridad = "Media";
    String compania = "Mapfre";
    DateTime? fechaVencimiento;
    bool visita = false;
    List<String> productos = [];

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061018).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.35),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.person_add_alt_1_rounded,
                                color: Colors.cyanAccent,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Nueva referencia",
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

                          _campoDialogo(
                            controller: nombreController,
                            label: "Nombre",
                            icon: Icons.person_rounded,
                          ),

                          const SizedBox(height: 12),

                          _campoDialogo(
                            controller: telefonoController,
                            label: "Teléfono",
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                          ),

                          const SizedBox(height: 12),

                          _dropdownDialogo(
                            value: compania,
                            label: "Compañía",
                            icon: Icons.apartment_rounded,
                            items: const [
                              "Mapfre",
                              "Allianz",
                              "AXA",
                              "Generali",
                              "DKV",
                              "Sanitas",
                              "Asisa",
                              "Otra",
                            ],
                            onChanged: (v) {
                              setDialogState(() => compania = v!);
                            },
                          ),

                          const SizedBox(height: 18),

                          const Text(
                            "Productos actuales",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              "Decesos",
                              "Hogar",
                              "Auto",
                              "Vida",
                              "Salud",
                            ].map((p) {
                              final selected = productos.contains(p);

                              return FilterChip(
                                label: Text(
                                  p,
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xFF061018)
                                        : Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: Colors.cyanAccent,
                                backgroundColor: const Color(0xFF162033),
                                checkmarkColor: const Color(0xFF061018),
                                side: BorderSide(
                                  color: selected
                                      ? Colors.cyanAccent
                                      : Colors.white.withOpacity(0.15),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                showCheckmark: false,
                                onSelected: (v) {
                                  setDialogState(() {
                                    if (v) {
                                      productos.add(p);
                                    } else {
                                      productos.remove(p);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 14),

                          _dropdownDialogo(
                            value: prioridad,
                            label: "Prioridad",
                            icon: Icons.flag_rounded,
                            items: const ["Alta", "Media", "Baja"],
                            onChanged: (v) {
                              setDialogState(() => prioridad = v!);
                            },
                          ),

                          const SizedBox(height: 12),

                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.cyanAccent,
                                        surface: Color(0xFF061018),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );

                              if (date != null) {
                                setDialogState(() => fechaVencimiento = date);
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.cyanAccent.withOpacity(0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_rounded,
                                    color: Colors.cyanAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      fechaVencimiento == null
                                          ? "Seleccionar fecha de vencimiento"
                                          : "Vence: ${fechaVencimiento!.day}/${fechaVencimiento!.month}/${fechaVencimiento!.year}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SwitchListTile(
                              value: visita,
                              activeColor: Colors.cyanAccent,
                              title: const Text(
                                "Requiere visita",
                                style: TextStyle(color: Colors.white),
                              ),
                              onChanged: (v) {
                                setDialogState(() => visita = v);
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          _campoDialogo(
                            controller: notasController,
                            label: "Notas",
                            icon: Icons.notes_rounded,
                            maxLines: 3,
                          ),

                          const SizedBox(height: 22),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.25),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text("Cancelar"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final user = supabase.auth.currentUser;
                                    if (user == null) return;

                                    if (nombreController.text.trim().isEmpty) {
                                      _snack('Introduce el nombre');
                                      return;
                                    }

                                    await supabase
                                        .from('referencias_viables')
                                        .insert({
                                      'auth_id': user.id,
                                      'nombre': nombreController.text.trim(),
                                      'telefono':
                                          telefonoController.text.trim(),
                                      'compania_actual': compania,
                                      'productos_actuales': productos,
                                      'prioridad': prioridad,
                                      'fecha_vencimiento':
                                          fechaVencimiento?.toIso8601String(),
                                      'requiere_visita': visita,
                                      'notas': notasController.text.trim(),
                                      'estado': 'Pendiente',
                                      'created_at':
                                          DateTime.now().toIso8601String(),
                                    });

                                    if (!mounted) return;

                                    Navigator.pop(context);
                                    loadReferencias();
                                  },
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text("Guardar"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: const Color(0xFF031018),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

    nombreController.dispose();
    telefonoController.dispose();
    notasController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = referenciasFiltradas;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: crearReferencia,
        backgroundColor: Colors.cyanAccent,
        foregroundColor: const Color(0xFF031018),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          "Nueva",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          const _FondoReferencias(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: loadReferencias,
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFF0F172A),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 95),
                children: [
                  _header(),
                  const SizedBox(height: 20),
                  if (cargando)
                    const Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                      ),
                    )
                  else ...[
                    _kpis(),
                    const SizedBox(height: 16),
                    _embudoCard(),
                    const SizedBox(height: 16),
                    _buscadorFiltros(),
                    const SizedBox(height: 16),
                    if (lista.isEmpty)
                      _sinReferencias()
                    else
                      ...lista.map(_tarjetaReferencia),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final subtitle = _veTodo(userRole)
        ? "CRM completo de toda la red"
        : "CRM de tu estructura comercial";

    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.18),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Referencias CRM",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.cyanAccent.withOpacity(0.12),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.38),
            ),
          ),
          child: const Icon(
            Icons.hub_rounded,
            color: Colors.cyanAccent,
          ),
        ),
      ],
    );
  }

  Widget _kpis() {
    return _glassCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _kpiBox(
                  title: "Hoy",
                  value: totalHoy.toString(),
                  icon: Icons.today_rounded,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpiBox(
                  title: "Calientes",
                  value: totalUrgentes.toString(),
                  icon: Icons.local_fire_department_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _kpiBox(
                  title: "Visitas",
                  value: totalVisita.toString(),
                  icon: Icons.home_work_rounded,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpiBox(
                  title: "Vencen 7d",
                  value: totalVencen7.toString(),
                  icon: Icons.warning_rounded,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _embudoCard() {
    final total = referencias.length;
    final calientes = totalUrgentes;
    final visitas = totalVisita;
    final cerradas = totalCerradasMes;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Embudo comercial",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          _funnelLine("Referencias activas", total, total, Colors.cyanAccent),
          _funnelLine("Muy calientes", calientes, total, Colors.redAccent),
          _funnelLine("Con visita", visitas, total, Colors.orangeAccent),
          _funnelLine("Cerradas mes", cerradas, total, Colors.greenAccent),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.20)),
            ),
            child: Text(
              "Conversión estimada del mes: ${conversionMes.toStringAsFixed(1)}%",
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _funnelLine(String title, int value, int total, Color color) {
    final percent = total == 0 ? 0.0 : value / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          SizedBox(
            width: 115,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: percent.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.10),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buscadorFiltros() {
    final filtros = [
      "Hoy",
      "Próximas",
      "Calientes",
      "Visitas",
      "Vencimientos",
      "Todas",
      "Alta",
      "Media",
      "Baja",
    ];

    return _glassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => busqueda = v),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Buscar por nombre, teléfono o compañía...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.cyanAccent,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filtros.map((f) {
                final selected = filtro == f;
                final color = f == "Alta"
                    ? Colors.redAccent
                    : f == "Media"
                        ? Colors.orangeAccent
                        : f == "Baja"
                            ? Colors.greenAccent
                            : f == "Calientes"
                                ? Colors.redAccent
                                : f == "Visitas"
                                    ? Colors.orangeAccent
                                    : f == "Vencimientos"
                                        ? Colors.purpleAccent
                                        : Colors.cyanAccent;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      f,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF061018)
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    selected: selected,
                    selectedColor: color,
                    backgroundColor: const Color(0xFF162033),
                    side: BorderSide(
                      color: selected ? color : Colors.white.withOpacity(0.12),
                    ),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    onSelected: (_) {
                      setState(() => filtro = f);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaReferencia(Map<String, dynamic> r) {
    final prioridad = r['prioridad']?.toString() ?? "Media";
    final color = _prioridadColor(prioridad);
    final productos = _productos(r['productos_actuales']);
    final score = _scoreReferencia(r);
    final scoreColor = _scoreColor(score);
    final nombre = r['nombre']?.toString() ?? "Sin nombre";
    final telefono = r['telefono']?.toString() ?? "";
    final rellamada = r['fecha_rellamada'];

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () async {
        final actualizado = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReferenciaDetailScreen(referencia: r),
          ),
        );

        if (actualizado == true) {
          loadReferencias();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.075),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: color.withOpacity(0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(nombre),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _scoreTexto(score),
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                _pill(
                  prioridad,
                  color,
                  Icons.flag_rounded,
                ),
              ],
            ),

            const SizedBox(height: 16),

            _infoMini(
              Icons.phone_rounded,
              telefono.isEmpty ? "Sin teléfono" : telefono,
              Colors.white70,
            ),

            const SizedBox(height: 7),

            _infoMini(
              Icons.apartment_rounded,
              r['compania_actual']?.toString() ?? "Sin compañía",
              Colors.cyanAccent,
            ),

            const SizedBox(height: 7),

_infoMini(
  Icons.person_rounded,
  r['nombre_agente_ref']?.toString() ?? "Sin agente",
  Colors.amberAccent,
),

            const SizedBox(height: 7),

            _infoMini(
              Icons.event_rounded,
              _fechaTexto(r['fecha_vencimiento']),
              scoreColor,
            ),

            if (rellamada != null && rellamada.toString().isNotEmpty) ...[
              const SizedBox(height: 7),
              _infoMini(
                Icons.phone_callback_rounded,
                "Rellamada: ${_fechaBonita(rellamada)}",
                Colors.greenAccent,
              ),
            ],

            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(scoreColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "$score%",
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),

            if (productos.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: productos.map<Widget>((p) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142235),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.45),
                        width: 1.1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sell_rounded,
                          color: Colors.cyanAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            if ((r['notas']?.toString() ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                r['notas'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  height: 1.35,
                ),
              ),
            ],

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    "Gestionar",
                    Icons.settings_suggest_rounded,
                    Colors.cyanAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    "Programar",
                    Icons.phone_callback_rounded,
                    Colors.orangeAccent,
                  ),
                ),
              ],
            ),

            if (r['requiere_visita'] == true) ...[
              const SizedBox(height: 14),
              _pill(
                "Requiere visita",
                Colors.redAccent,
                Icons.home_work_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoMini(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.13),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54),
                ),
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

  Widget _avatar(String name) {
    final letter = name.trim().isEmpty ? "?" : name.trim()[0].toUpperCase();

    return Container(
      height: 50,
      width: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.35),
            Colors.purpleAccent.withOpacity(0.25),
          ],
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.38),
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinReferencias() {
    return _glassCard(
      child: const Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            color: Colors.white38,
            size: 58,
          ),
          SizedBox(height: 12),
          Text(
            "Sin referencias",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "No hay referencias para este filtro.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _campoDialogo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.white.withOpacity(0.065),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.cyanAccent.withOpacity(0.65),
          ),
        ),
      ),
    );
  }

  Widget _dropdownDialogo({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFF0F172A),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        filled: true,
        fillColor: Colors.white.withOpacity(0.065),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.cyanAccent.withOpacity(0.65),
          ),
        ),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _FondoReferencias extends StatelessWidget {
  const _FondoReferencias();

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
                Color(0xFF020617),
                Color(0xFF061A2D),
                Color(0xFF0B1026),
              ],
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _glow(260, Colors.cyanAccent),
        ),
        Positioned(
          bottom: 160,
          left: -120,
          child: _glow(280, Colors.purpleAccent),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: _glow(240, Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}
class ReferenciaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> referencia;

  const ReferenciaDetailScreen({
    super.key,
    required this.referencia,
  });

  @override
  State<ReferenciaDetailScreen> createState() => _ReferenciaDetailScreenState();
}

class _ReferenciaDetailScreenState extends State<ReferenciaDetailScreen> {
  final supabase = Supabase.instance.client;

  DateTime? fechaRellamada;

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _fechaBonita(dynamic value) {
    final fecha = _parseDate(value);
    if (fecha == null) return "Sin fecha";

    return "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
  }

  List<String> _productos(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    final text = value.toString();

    if (text.contains('/')) {
      return text.split('/').where((e) => e.trim().isNotEmpty).toList();
    }

    if (text.contains(',')) {
      return text.split(',').where((e) => e.trim().isNotEmpty).toList();
    }

    if (text.trim().isEmpty) return [];

    return [text];
  }

  int _scoreReferencia(Map<String, dynamic> r) {
    int score = 20;

    final prioridad = r['prioridad']?.toString() ?? 'Media';

    if (prioridad == 'Alta') score += 35;
    if (prioridad == 'Media') score += 20;
    if (prioridad == 'Baja') score += 8;

    if (r['requiere_visita'] == true) score += 15;

    final productos = _productos(r['productos_actuales']);
    if (productos.length >= 2) score += 12;
    if (productos.length >= 3) score += 8;

    final fecha = _parseDate(r['fecha_vencimiento']);

    if (fecha != null) {
      final dias = fecha.difference(DateTime.now()).inDays;

      if (dias <= 7 && dias >= 0) score += 25;
      if (dias <= 15 && dias > 7) score += 15;
      if (dias < 0) score += 18;
    }

    final rellamada = _parseDate(r['fecha_rellamada']);

    if (rellamada != null) {
      final diasRellamada = rellamada.difference(DateTime.now()).inDays;
      if (diasRellamada <= 0) score += 12;
      if (diasRellamada > 0 && diasRellamada <= 3) score += 8;
    }

    return score.clamp(0, 100);
  }

  Color _scoreColor(int score) {
    if (score >= 75) return Colors.redAccent;
    if (score >= 50) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _scoreTexto(int score) {
    if (score >= 75) return "Muy caliente";
    if (score >= 50) return "Interesante";
    return "Seguimiento";
  }

  Color _prioridadColor(String prioridad) {
    switch (prioridad) {
      case 'Alta':
        return Colors.redAccent;
      case 'Media':
        return Colors.orangeAccent;
      case 'Baja':
        return Colors.greenAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  String _fechaTexto(dynamic value) {
    final fecha = _parseDate(value);
    if (fecha == null) return "Sin vencimiento";

    final hoy = DateTime.now();
    final today = DateTime(hoy.year, hoy.month, hoy.day);
    final cleanFecha = DateTime(fecha.year, fecha.month, fecha.day);

    final dias = cleanFecha.difference(today).inDays;

    if (dias < 0) return "Vencida hace ${dias.abs()} días";
    if (dias == 0) return "Vence hoy";
    if (dias == 1) return "Vence mañana";

    return "Vence en $dias días";
  }

  IconData _iconoProducto(String producto) {
    switch (producto) {
      case 'Decesos':
        return Icons.shield_rounded;
      case 'Hogar':
        return Icons.home_rounded;
      case 'Auto':
        return Icons.directions_car_rounded;
      case 'Vida':
        return Icons.favorite_rounded;
      case 'Salud':
        return Icons.medical_services_rounded;
      default:
        return Icons.sell_rounded;
    }
  }

  Color _colorProducto(String producto) {
    switch (producto) {
      case 'Decesos':
        return Colors.purpleAccent;
      case 'Hogar':
        return Colors.greenAccent;
      case 'Auto':
        return Colors.orangeAccent;
      case 'Vida':
        return Colors.pinkAccent;
      case 'Salud':
        return Colors.blueAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(' ').where((e) => e.isNotEmpty).toList();

    if (partes.isEmpty) return "?";
    if (partes.length == 1) return partes.first[0].toUpperCase();

    return "${partes[0][0]}${partes[1][0]}".toUpperCase();
  }

  Future<DateTime?> _pickDate(DateTime? initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.cyanAccent,
              surface: Color(0xFF061018),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF061018),
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> gestionarReferencia() async {
    final notaController = TextEditingController();

    String estado = widget.referencia['estado']?.toString() ?? "En curso";
    if (estado == "Pendiente") estado = "En curso";

    String resultado = widget.referencia['resultado']?.toString() ?? "Contratado";

    fechaRellamada = _parseDate(widget.referencia['fecha_rellamada']);

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061018).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.35),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.settings_suggest_rounded,
                                color: Colors.cyanAccent,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Gestionar referencia",
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

                          TextField(
                            controller: notaController,
                            maxLines: 3,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: "Nota de seguimiento",
                              labelStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(
                                Icons.notes_rounded,
                                color: Colors.cyanAccent,
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.065),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.cyanAccent.withOpacity(0.65),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          DropdownButtonFormField<String>(
                            value: estado,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: "Estado",
                              labelStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(
                                Icons.track_changes_rounded,
                                color: Colors.cyanAccent,
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.065),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.cyanAccent.withOpacity(0.65),
                                ),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: "En curso",
                                child: Text("En curso"),
                              ),
                              DropdownMenuItem(
                                value: "Resuelto",
                                child: Text("Resuelto"),
                              ),
                            ],
                            onChanged: (v) {
                              setDialogState(() {
                                estado = v!;
                              });
                            },
                          ),

                          const SizedBox(height: 14),

                          if (estado == "En curso")
                            InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () async {
                                final date = await _pickDate(fechaRellamada);
                                if (date != null) {
                                  setDialogState(() {
                                    fechaRellamada = date;
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.cyanAccent.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.phone_callback_rounded,
                                      color: Colors.cyanAccent,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        fechaRellamada == null
                                            ? "Programar próxima llamada"
                                            : "Rellamada: ${_fechaBonita(fechaRellamada!.toIso8601String())}",
                                        style: const TextStyle(
                                          color: Colors.cyanAccent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (estado == "Resuelto")
                            DropdownButtonFormField<String>(
                              value: resultado,
                              dropdownColor: const Color(0xFF0F172A),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "Resultado",
                                labelStyle: const TextStyle(color: Colors.white60),
                                prefixIcon: const Icon(
                                  Icons.verified_rounded,
                                  color: Colors.cyanAccent,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.065),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: Colors.cyanAccent.withOpacity(0.65),
                                  ),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "Contratado",
                                  child: Text("Contratado"),
                                ),
                                DropdownMenuItem(
                                  value: "Desechado",
                                  child: Text("Desechado"),
                                ),
                              ],
                              onChanged: (v) {
                                setDialogState(() {
                                  resultado = v!;
                                });
                              },
                            ),

                          const SizedBox(height: 24),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.25),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text("Cancelar"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await supabase
                                        .from('referencias_viables')
                                        .update({
                                      'estado': estado,
                                      'resultado': estado == "Resuelto"
                                          ? resultado
                                          : null,
                                      'nota_seguimiento':
                                          notaController.text.trim(),
                                      'fecha_rellamada': estado == "En curso"
                                          ? fechaRellamada?.toIso8601String()
                                          : null,
                                      'updated_at':
                                          DateTime.now().toIso8601String(),
                                    }).eq('id', widget.referencia['id']);

                                    if (!mounted) return;

                                    Navigator.pop(context);
                                    Navigator.pop(context, true);
                                  },
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text("Guardar"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: const Color(0xFF031018),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

    notaController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.referencia;

    final nombre = r['nombre']?.toString() ?? "Sin nombre";
    final telefono = r['telefono']?.toString() ?? "";
    final compania = r['compania_actual']?.toString() ?? "Sin compañía";
    final prioridad = r['prioridad']?.toString() ?? "Media";
    final estado = r['estado']?.toString() ?? "Pendiente";
    final notas = r['notas']?.toString() ?? "";
    final notaSeguimiento = r['nota_seguimiento']?.toString() ?? "";
    final resultado = r['resultado']?.toString() ?? "";

    final productos = _productos(r['productos_actuales']);
    final score = _scoreReferencia(r);
    final scoreColor = _scoreColor(score);
    final prioridadColor = _prioridadColor(prioridad);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _FondoReferencias(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
              children: [
                _header(),
                const SizedBox(height: 22),
                _heroCliente(
                  nombre: nombre,
                  compania: compania,
                  prioridad: prioridad,
                  prioridadColor: prioridadColor,
                  score: score,
                  scoreColor: scoreColor,
                ),
                const SizedBox(height: 16),
                _alertaVencimiento(r['fecha_vencimiento'], scoreColor),
                const SizedBox(height: 16),
                _datosCard(
                  telefono: telefono,
                  compania: compania,
                  prioridad: prioridad,
                  prioridadColor: prioridadColor,
                  estado: estado,
                  resultado: resultado,
                ),
                const SizedBox(height: 16),
                if (productos.isNotEmpty) _productosCard(productos),
                if (productos.isNotEmpty) const SizedBox(height: 16),
                _notasCard(
                  titulo: "Notas de la referencia",
                  texto: notas.trim().isEmpty ? "Sin notas registradas." : notas,
                  icon: Icons.notes_rounded,
                  color: Colors.cyanAccent,
                ),
                if (notaSeguimiento.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _notasCard(
                    titulo: "Último seguimiento",
                    texto: notaSeguimiento,
                    icon: Icons.history_rounded,
                    color: Colors.orangeAccent,
                  ),
                ],
                const SizedBox(height: 16),
                _timelineCard(r),
                const SizedBox(height: 24),
                if (estado != "Resuelto")
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: gestionarReferencia,
                      icon: const Icon(Icons.settings_suggest_rounded),
                      label: const Text(
                        "Gestionar referencia",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: const Color(0xFF031018),
                        padding: const EdgeInsets.symmetric(vertical: 17),
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
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.45),
              ),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Detalle CRM",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 3),
              Text(
                "Ficha completa de oportunidad",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroCliente({
    required String nombre,
    required String compania,
    required String prioridad,
    required Color prioridadColor,
    required int score,
    required Color scoreColor,
  }) {
    return _glassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.35),
                  Colors.purpleAccent.withOpacity(0.25),
                ],
              ),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.45),
                width: 1.4,
              ),
            ),
            child: Center(
              child: Text(
                _iniciales(nombre),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            nombre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            compania,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                prioridad,
                prioridadColor,
                Icons.flag_rounded,
              ),
              _pill(
                _scoreTexto(score),
                scoreColor,
                Icons.local_fire_department_rounded,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    minHeight: 12,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "$score%",
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Score de oportunidad",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertaVencimiento(dynamic value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.24),
            Colors.cyanAccent.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _fechaTexto(value),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            _fechaBonita(value),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _datosCard({
    required String telefono,
    required String compania,
    required String prioridad,
    required Color prioridadColor,
    required String estado,
    required String resultado,
  }) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Datos principales",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _infoLine(
            Icons.phone_rounded,
            "Teléfono",
            telefono.isEmpty ? "Sin teléfono" : telefono,
            Colors.white70,
          ),
          _infoLine(
            Icons.apartment_rounded,
            "Compañía",
            compania,
            Colors.cyanAccent,
          ),
          _infoLine(
            Icons.flag_rounded,
            "Prioridad",
            prioridad,
            prioridadColor,
          ),
          _infoLine(
            Icons.track_changes_rounded,
            "Estado",
            estado,
            estado == "Resuelto" ? Colors.greenAccent : Colors.orangeAccent,
          ),
          if (resultado.trim().isNotEmpty)
            _infoLine(
              Icons.verified_rounded,
              "Resultado",
              resultado,
              resultado == "Contratado"
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
          if (widget.referencia['requiere_visita'] == true)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.redAccent.withOpacity(0.32),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.home_work_rounded,
                    color: Colors.redAccent,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Requiere visita",
                    style: TextStyle(
                      color: Colors.redAccent,
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

  Widget _productosCard(List<String> productos) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Productos actuales",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: productos.map<Widget>((p) {
              final color = _colorProducto(p);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF142235),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: color.withOpacity(0.45),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconoProducto(p),
                      color: color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _notasCard({
    required String titulo,
    required String texto,
    required IconData icon,
    required Color color,
  }) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineCard(Map<String, dynamic> r) {
    final estado = r['estado']?.toString() ?? "Pendiente";
    final createdAt = r['created_at'];
    final rellamada = r['fecha_rellamada'];

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Timeline CRM",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _timelineItem(
            icon: Icons.add_circle_rounded,
            color: Colors.cyanAccent,
            title: "Referencia creada",
            subtitle: _fechaBonita(createdAt),
          ),
          _timelineItem(
            icon: estado == "Resuelto"
                ? Icons.check_circle_rounded
                : Icons.pending_actions_rounded,
            color: estado == "Resuelto"
                ? Colors.greenAccent
                : Colors.orangeAccent,
            title: "Estado actual",
            subtitle: estado,
          ),
          if (rellamada != null && rellamada.toString().isNotEmpty)
            _timelineItem(
              icon: Icons.phone_callback_rounded,
              color: Colors.greenAccent,
              title: "Próxima llamada",
              subtitle: _fechaBonita(rellamada),
            ),
          if ((r['nota_seguimiento']?.toString() ?? '').trim().isNotEmpty)
            _timelineItem(
              icon: Icons.notes_rounded,
              color: Colors.purpleAccent,
              title: "Seguimiento registrado",
              subtitle: r['nota_seguimiento'].toString(),
              last: true,
            )
          else
            _timelineItem(
              icon: Icons.touch_app_rounded,
              color: Colors.white38,
              title: "Pendiente de gestión",
              subtitle: "Pulsa en gestionar referencia",
              last: true,
            ),
        ],
      ),
    );
  }

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool last = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.16),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            if (!last)
              Container(
                width: 2,
                height: 34,
                color: Colors.white.withOpacity(0.13),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoLine(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 21),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}