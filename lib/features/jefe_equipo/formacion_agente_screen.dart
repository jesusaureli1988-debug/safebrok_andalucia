import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormacionAgenteScreen extends StatefulWidget {
  final Map<String, dynamic> agente;

  const FormacionAgenteScreen({
    super.key,
    required this.agente,
  });

  @override
  State<FormacionAgenteScreen> createState() =>
      _FormacionAgenteScreenState();
}

class _FormacionAgenteScreenState
    extends State<FormacionAgenteScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;
  bool agenteAutorizado = false;

  String? error;

  bool habilidades = false;
  bool decesos = false;
  bool hogar = false;
  bool vida = false;
  bool accidente = false;
  bool auto = false;
  bool comunidad = false;
  bool salud = false;
  bool comercio = false;

  static const int totalModulos = 9;

  @override
  void initState() {
    super.initState();
    cargarFormacion();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _idTexto(dynamic value) {
    final id = (value ?? '').toString().trim();

    if (id.isEmpty || id.toLowerCase() == 'null') {
      return '';
    }

    return id;
  }

  String _nombreCompleto(
    Map<String, dynamic>? usuario,
  ) {
    if (usuario == null) return 'Sin nombre';

    final nombre =
        usuario['nombre']?.toString().trim() ?? '';

    final apellidos =
        usuario['apellidos']?.toString().trim() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;

    final email =
        usuario['email']?.toString().trim() ?? '';

    return email.isNotEmpty ? email : 'Sin nombre';
  }

  bool _relacionPermitida({
    required String rolPadre,
    required String rolHijo,
  }) {
    final padre = _normalizarRol(rolPadre);
    final hijo = _normalizarRol(rolHijo);

    switch (padre) {
      case 'director_nacional':
        return hijo == 'director_zona' ||
            hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'director_zona':
        return hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_ventas':
        return hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_equipo':
        return hijo == 'agente';

      default:
        return false;
    }
  }

  List<Map<String, dynamic>> _construirEstructura({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolPerfil =
        _normalizarRol(perfil['rol_usuario']);

    if (rolPerfil == 'administracion' ||
        rolPerfil == 'administrador' ||
        rolPerfil == 'admin') {
      return todosUsuarios.where((usuario) {
        return _idTexto(usuario['id']).isNotEmpty &&
            _idTexto(usuario['auth_id']).isNotEmpty;
      }).toList();
    }

    final hijosPorParentId =
        <String, List<Map<String, dynamic>>>{};

    for (final usuario in todosUsuarios) {
      final parentId =
          _idTexto(usuario['parent_id']);

      if (parentId.isEmpty) continue;

      hijosPorParentId
          .putIfAbsent(
            parentId,
            () => <Map<String, dynamic>>[],
          )
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final idActual = _idTexto(actual['id']);

      if (idActual.isEmpty ||
          visitados.contains(idActual)) {
        return;
      }

      visitados.add(idActual);
      resultado.add(actual);

      final rolActual =
          _normalizarRol(actual['rol_usuario']);

      final hijos = hijosPorParentId[idActual] ??
          const <Map<String, dynamic>>[];

      for (final hijo in hijos) {
        final rolHijo =
            _normalizarRol(hijo['rol_usuario']);

        if (!_relacionPermitida(
          rolPadre: rolActual,
          rolHijo: rolHijo,
        )) {
          continue;
        }

        recorrer(hijo);
      }
    }

    recorrer(perfil);

    return resultado;
  }

  Future<bool> _validarAgenteAutorizado() async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) {
      return false;
    }

    final perfilData = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, '
          'nombre, apellidos, email',
        )
        .eq('auth_id', authUser.id)
        .maybeSingle();

    if (perfilData == null) {
      return false;
    }

    final usuariosData = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, '
          'nombre, apellidos, email',
        );

    final estructura = _construirEstructura(
      perfil: Map<String, dynamic>.from(perfilData),
      todosUsuarios:
          List<Map<String, dynamic>>.from(usuariosData),
    );

    final agenteId =
        _idTexto(widget.agente['id']);

    final autorizado = estructura.any((usuario) {
      return _idTexto(usuario['id']) == agenteId &&
          _normalizarRol(usuario['rol_usuario']) ==
              'agente';
    });

    debugPrint(
      'FORMACIÓN DETALLE: agente=$agenteId '
      '| autorizado=$autorizado',
    );

    return autorizado;
  }

  Future<void> cargarFormacion() async {
    try {
      if (mounted) {
        setState(() {
          loading = true;
          error = null;
        });
      }

      final autorizado =
          await _validarAgenteAutorizado();

      if (!autorizado) {
        if (!mounted) return;

        setState(() {
          loading = false;
          agenteAutorizado = false;
          error =
              'Este agente no pertenece a tu estructura.';
        });

        return;
      }

      final data = await supabase
          .from('formacion_agentes')
          .select()
          .eq(
            'agente_id',
            widget.agente['id'],
          )
          .maybeSingle();

      if (data != null) {
        habilidades =
            data['habilidades_comerciales'] == true;

        decesos = data['decesos'] == true;
        hogar = data['hogar'] == true;
        vida = data['vida'] == true;
        accidente = data['accidente'] == true;
        auto = data['auto'] == true;
        comunidad = data['comunidad'] == true;
        salud = data['salud'] == true;
        comercio = data['comercio_pymes'] == true;
      }

      if (!mounted) return;

      setState(() {
        agenteAutorizado = true;
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR CARGAR FORMACIÓN AGENTE: $e',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        loading = false;
        agenteAutorizado = false;
        error = e.toString();
      });
    }
  }

  int get progreso {
    int total = 0;

    if (habilidades) total++;
    if (decesos) total++;
    if (hogar) total++;
    if (vida) total++;
    if (accidente) total++;
    if (auto) total++;
    if (comunidad) total++;
    if (salud) total++;
    if (comercio) total++;

    return total;
  }

  double get porcentaje {
    return progreso / totalModulos;
  }

  Color get colorProgreso {
    if (progreso == totalModulos) {
      return const Color(0xFF16A34A);
    }

    if (progreso >= 5) {
      return const Color(0xFFF59E0B);
    }

    if (progreso > 0) {
      return const Color(0xFF2563EB);
    }

    return const Color(0xFF64748B);
  }

  String get estadoTexto {
    if (progreso == totalModulos) {
      return 'Formación completada';
    }

    if (progreso == 0) {
      return 'Formación pendiente';
    }

    return 'Formación en curso';
  }

  Future<void> guardar() async {
    if (saving || !agenteAutorizado) return;

    try {
      setState(() {
        saving = true;
      });

      /*
       * Se vuelve a validar antes de guardar.
       *
       * Así se evita que alguien conserve abierta una pantalla
       * de un agente que ya no pertenece a su estructura.
       */
      final autorizado =
          await _validarAgenteAutorizado();

      if (!autorizado) {
        throw Exception(
          'El agente ya no pertenece a tu estructura.',
        );
      }

      final datos = <String, dynamic>{
        'agente_id': widget.agente['id'],
        'habilidades_comerciales': habilidades,
        'decesos': decesos,
        'hogar': hogar,
        'vida': vida,
        'accidente': accidente,
        'auto': auto,
        'comunidad': comunidad,
        'salud': salud,
        'comercio_pymes': comercio,
      };

      /*
       * Upsert evita hacer primero una consulta para saber si
       * existe. Para que funcione correctamente, agente_id debe
       * ser único en formacion_agentes.
       */
      await supabase
          .from('formacion_agentes')
          .upsert(
            datos,
            onConflict: 'agente_id',
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Formación guardada correctamente',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor:
              const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint(
        'ERROR GUARDAR FORMACIÓN AGENTE: $e',
      );

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al guardar formación: $e',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void cambiarModulo(
    String key,
    bool value,
  ) {
    setState(() {
      switch (key) {
        case 'habilidades':
          habilidades = value;
          break;

        case 'decesos':
          decesos = value;
          break;

        case 'hogar':
          hogar = value;
          break;

        case 'vida':
          vida = value;
          break;

        case 'accidente':
          accidente = value;
          break;

        case 'auto':
          auto = value;
          break;

        case 'comunidad':
          comunidad = value;
          break;

        case 'salud':
          salud = value;
          break;

        case 'comercio':
          comercio = value;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombre =
        _nombreCompleto(widget.agente);

    final email =
        widget.agente['email']?.toString().trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      bottomNavigationBar:
          loading || !agenteAutorizado
              ? null
              : _saveBar(),
      body: Stack(
        children: [
          const _DetailFormationBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF111827),
                    ),
                  )
                : error != null
                    ? _errorState()
                    : RefreshIndicator(
                        color:
                            const Color(0xFF111827),
                        onRefresh: cargarFormacion,
                        child: ListView(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding:
                              const EdgeInsets.fromLTRB(
                            18,
                            12,
                            18,
                            32,
                          ),
                          children: [
                            _topBar(),
                            const SizedBox(height: 24),
                            _agentHero(
                              nombre,
                              email,
                            ),
                            const SizedBox(height: 18),
                            _progressPanel(),
                            const SizedBox(height: 24),
                            _sectionTitle(),
                            const SizedBox(height: 13),
                            _module(
                              keyModulo: 'habilidades',
                              titulo:
                                  'Habilidades comerciales',
                              descripcion:
                                  'Prospección, argumentario, visita y cierre.',
                              icono:
                                  Icons.record_voice_over_rounded,
                              valor: habilidades,
                              color:
                                  const Color(0xFF7C3AED),
                            ),
                            _module(
                              keyModulo: 'decesos',
                              titulo: 'Decesos',
                              descripcion:
                                  'Producto principal, garantías y comparativa.',
                              icono:
                                  Icons.shield_rounded,
                              valor: decesos,
                              color:
                                  const Color(0xFF2563EB),
                            ),
                            _module(
                              keyModulo: 'hogar',
                              titulo: 'Hogar',
                              descripcion:
                                  'Coberturas, continente, contenido y objeciones.',
                              icono:
                                  Icons.home_rounded,
                              valor: hogar,
                              color:
                                  const Color(0xFFF59E0B),
                            ),
                            _module(
                              keyModulo: 'vida',
                              titulo: 'Vida',
                              descripcion:
                                  'Protección familiar y capital asegurado.',
                              icono:
                                  Icons.favorite_rounded,
                              valor: vida,
                              color:
                                  const Color(0xFFEC4899),
                            ),
                            _module(
                              keyModulo: 'accidente',
                              titulo: 'Accidente',
                              descripcion:
                                  'Indemnizaciones, escenarios y contratación.',
                              icono:
                                  Icons.health_and_safety_rounded,
                              valor: accidente,
                              color:
                                  const Color(0xFFEF4444),
                            ),
                            _module(
                              keyModulo: 'auto',
                              titulo: 'Auto',
                              descripcion:
                                  'Modalidades, comparativa y oportunidades.',
                              icono:
                                  Icons.directions_car_rounded,
                              valor: auto,
                              color:
                                  const Color(0xFF0EA5E9),
                            ),
                            _module(
                              keyModulo: 'comunidad',
                              titulo: 'Comunidad',
                              descripcion:
                                  'Comunidades, administradores y captación.',
                              icono:
                                  Icons.apartment_rounded,
                              valor: comunidad,
                              color:
                                  const Color(0xFF8B5CF6),
                            ),
                            _module(
                              keyModulo: 'salud',
                              titulo: 'Salud',
                              descripcion:
                                  'Cuadro médico, copagos y argumentación.',
                              icono:
                                  Icons.local_hospital_rounded,
                              valor: salud,
                              color:
                                  const Color(0xFF14B8A6),
                            ),
                            _module(
                              keyModulo: 'comercio',
                              titulo: 'Comercio y Pymes',
                              descripcion:
                                  'Negocios, riesgos, RC y multirriesgo.',
                              icono:
                                  Icons.storefront_rounded,
                              valor: comercio,
                              color:
                                  const Color(0xFF16A34A),
                            ),
                            const SizedBox(height: 90),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          elevation: 5,
          shadowColor:
              Colors.black.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () =>
                Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF111827),
                size: 29,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Ficha de formación',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Seguimiento individual',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: cargarFormacion,
          icon: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF111827)
                      .withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _agentHero(
    String nombre,
    String email,
  ) {
    final inicial = nombre.isEmpty
        ? 'A'
        : nombre.substring(0, 1).toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
            Color(0xFFF59E0B),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF111827),
              Color(0xFF1E293B),
              Color(0xFF172554),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -18,
              child: Icon(
                Icons.school_rounded,
                color: Colors.white.withOpacity(0.08),
                size: 125,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color:
                        colorProgreso.withOpacity(0.18),
                    borderRadius:
                        BorderRadius.circular(23),
                    border: Border.all(
                      color:
                          colorProgreso.withOpacity(0.40),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      inicial,
                      style: TextStyle(
                        color: colorProgreso,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AGENTE EN FORMACIÓN',
                        style: TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nombre,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          email,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressPanel() {
    final porcentajeTexto =
        (porcentaje * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: Colors.black.withOpacity(0.045),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 22,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: CircularProgressIndicator(
                      value: porcentaje,
                      strokeWidth: 9,
                      backgroundColor:
                          const Color(0xFFE2E8F0),
                      color: colorProgreso,
                    ),
                  ),
                  Text(
                    '$porcentajeTexto%',
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      estadoTexto,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$progreso de $totalModulos módulos completados',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            colorProgreso.withOpacity(0.10),
                        borderRadius:
                            BorderRadius.circular(99),
                      ),
                      child: Text(
                        progreso == totalModulos
                            ? 'Objetivo completado'
                            : '${totalModulos - progreso} módulos pendientes',
                        style: TextStyle(
                          color: colorProgreso,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: porcentaje,
              minHeight: 10,
              backgroundColor:
                  const Color(0xFFE2E8F0),
              color: colorProgreso,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() {
    return const Row(
      children: [
        Icon(
          Icons.auto_stories_rounded,
          color: Color(0xFF2563EB),
          size: 24,
        ),
        SizedBox(width: 9),
        Text(
          'Módulos formativos',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _module({
    required String keyModulo,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required bool valor,
    required Color color,
  }) {
    final estadoColor = valor
        ? const Color(0xFF16A34A)
        : color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: () =>
              cambiarModulo(keyModulo, !valor),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: valor
                    ? const Color(0xFF16A34A)
                        .withOpacity(0.28)
                    : Colors.black.withOpacity(0.045),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.045),
                  blurRadius: 17,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 51,
                  height: 51,
                  decoration: BoxDecoration(
                    color:
                        estadoColor.withOpacity(0.10),
                    borderRadius:
                        BorderRadius.circular(17),
                  ),
                  child: Icon(
                    valor
                        ? Icons.check_circle_rounded
                        : icono,
                    color: estadoColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration:
                      const Duration(milliseconds: 180),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: valor
                        ? const Color(0xFF16A34A)
                        : Colors.transparent,
                    border: Border.all(
                      color: valor
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                  child: valor
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 21,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(18, 11, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          border: const Border(
            top: BorderSide(
              color: Color(0xFFE2E8F0),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: saving ? null : guardar,
            icon: saving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.save_rounded,
                  ),
            label: Text(
              saving
                  ? 'Guardando...'
                  : 'Guardar formación',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  const Color(0xFF111827),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF94A3B8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _topBar(),
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color:
                  Colors.redAccent.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(
                Icons.lock_person_rounded,
                color: Colors.redAccent,
                size: 58,
              ),
              const SizedBox(height: 14),
              const Text(
                'Acceso no autorizado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error ??
                    'No se pudo abrir la formación.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailFormationBackground
    extends StatelessWidget {
  const _DetailFormationBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFFF4F6FB),
        ),
        Positioned(
          top: -100,
          right: -80,
          child: _DetailGlow(
            color:
                const Color(0xFF2563EB).withOpacity(0.10),
            size: 270,
          ),
        ),
        Positioned(
          top: 360,
          left: -135,
          child: _DetailGlow(
            color:
                const Color(0xFF7C3AED).withOpacity(0.065),
            size: 300,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _DetailGlow(
            color:
                const Color(0xFFF59E0B).withOpacity(0.065),
            size: 290,
          ),
        ),
        BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: 55, sigmaY: 55),
          child: Container(
            color: Colors.white.withOpacity(0.02),
          ),
        ),
      ],
    );
  }
}

class _DetailGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _DetailGlow({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}