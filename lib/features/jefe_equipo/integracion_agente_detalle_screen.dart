import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IntegracionAgenteDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> agente;

  const IntegracionAgenteDetalleScreen({
    super.key,
    required this.agente,
  });

  @override
  State<IntegracionAgenteDetalleScreen> createState() =>
      _IntegracionAgenteDetalleScreenState();
}

class _IntegracionAgenteDetalleScreenState
    extends State<IntegracionAgenteDetalleScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;
  bool agenteAutorizado = false;

  String? error;

  Map<String, dynamic> data = {};

  final contactosController = TextEditingController();
  final visitasController = TextEditingController();
  final presupuestosController = TextEditingController();
  final polizasController = TextEditingController();

  static const int totalPasos = 5;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    contactosController.dispose();
    visitasController.dispose();
    presupuestosController.dispose();
    polizasController.dispose();
    super.dispose();
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
      'INTEGRACIÓN DETALLE: agente=$agenteId '
      '| autorizado=$autorizado',
    );

    return autorizado;
  }

  Future<void> cargar() async {
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

      final row = await supabase
          .from('integracion_agentes')
          .select()
          .eq('agente_id', widget.agente['id'])
          .maybeSingle();

      data = row ??
          <String, dynamic>{
            'agente_id': widget.agente['id'],
            'bienvenida': false,
            'alta_sistema': false,
            'grupo_whatsapp': false,
            'primera_reunion': false,
            'primera_venta': false,
            'contactos': 0,
            'visitas': 0,
            'presupuestos': 0,
            'polizas': 0,
          };

      contactosController.text =
          '${data['contactos'] ?? 0}';

      visitasController.text =
          '${data['visitas'] ?? 0}';

      presupuestosController.text =
          '${data['presupuestos'] ?? 0}';

      polizasController.text =
          '${data['polizas'] ?? 0}';

      if (!mounted) return;

      setState(() {
        loading = false;
        agenteAutorizado = true;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR CARGA INTEGRACIÓN DETALLE: $e',
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

  int progreso() {
    int total = 0;

    if (data['bienvenida'] == true) total++;
    if (data['alta_sistema'] == true) total++;
    if (data['grupo_whatsapp'] == true) total++;
    if (data['primera_reunion'] == true) total++;
    if (data['primera_venta'] == true) total++;

    return total;
  }

  double get porcentaje => progreso() / totalPasos;

  Color get colorEstado {
    if (progreso() == totalPasos) return const Color(0xFF16A34A);
    if (progreso() == 0) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String get textoEstado {
    if (progreso() == totalPasos) return "Integración completada";
    if (progreso() == 0) return "Integración pendiente";
    return "Integración en progreso";
  }

  Future<void> guardar() async {
    if (saving || !agenteAutorizado) return;

    setState(() {
      saving = true;
    });

    try {
      /*
       * Se vuelve a comprobar la estructura antes de guardar.
       * Así no se puede modificar un agente que haya sido
       * reasignado mientras esta pantalla seguía abierta.
       */
      final autorizado =
          await _validarAgenteAutorizado();

      if (!autorizado) {
        throw Exception(
          'El agente ya no pertenece a tu estructura.',
        );
      }

      data['agente_id'] = widget.agente['id'];

      data['contactos'] =
          int.tryParse(
            contactosController.text.trim(),
          ) ??
          0;

      data['visitas'] =
          int.tryParse(
            visitasController.text.trim(),
          ) ??
          0;

      data['presupuestos'] =
          int.tryParse(
            presupuestosController.text.trim(),
          ) ??
          0;

      data['polizas'] =
          int.tryParse(
            polizasController.text.trim(),
          ) ??
          0;

      final payload =
          Map<String, dynamic>.from(data);

      payload.remove('id');

      await supabase
          .from('integracion_agentes')
          .upsert(
            payload,
            onConflict: 'agente_id',
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Integración guardada correctamente',
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
        'ERROR GUARDAR INTEGRACIÓN: $e',
      );

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al guardar integración: $e',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void actualizarCheck(String key, bool value) {
    setState(() {
      data[key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombre =
        "${widget.agente['nombre'] ?? ''} ${widget.agente['apellidos'] ?? ''}"
            .trim();
    final email = widget.agente['email'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF0F172A),
        title: const Text(
          "Detalle de integración",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar:
          loading || !agenteAutorizado
              ? null
              : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: saving ? null : guardar,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      saving ? "Guardando..." : "Guardar cambios",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2563EB),
              ),
            )
          : error != null
              ? _estadoError()
              : RefreshIndicator(
                  color: const Color(0xFF2563EB),
                  onRefresh: cargar,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _cabeceraAgente(nombre, email),
                const SizedBox(height: 16),
                _panelProgreso(),
                const SizedBox(height: 20),

                const Text(
                  "Pasos de integración",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),

                _checkCard(
                  keyData: "bienvenida",
                  titulo: "Bienvenida realizada",
                  descripcion: "Presentación inicial del equipo y explicación del método.",
                  icono: Icons.waving_hand_rounded,
                ),
                _checkCard(
                  keyData: "alta_sistema",
                  titulo: "Alta en sistema",
                  descripcion: "Usuario creado y acceso operativo a la plataforma.",
                  icono: Icons.admin_panel_settings_rounded,
                ),
                _checkCard(
                  keyData: "grupo_whatsapp",
                  titulo: "Grupo WhatsApp",
                  descripcion: "Agente añadido al canal de comunicación del equipo.",
                  icono: Icons.groups_rounded,
                ),
                _checkCard(
                  keyData: "primera_reunion",
                  titulo: "Primera reunión",
                  descripcion: "Primera sesión de seguimiento, formación o planificación.",
                  icono: Icons.event_available_rounded,
                ),
                _checkCard(
                  keyData: "primera_venta",
                  titulo: "Primera venta",
                  descripcion: "Primera póliza o venta conseguida por el agente.",
                  icono: Icons.workspace_premium_rounded,
                ),

                const SizedBox(height: 20),

                const Text(
                  "Actividad inicial",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),

                _actividadPanel(),

                const SizedBox(height: 90),
              ],
            ),
          ),
    );
  }

  Widget _estadoError() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        40,
        20,
        28,
      ),
      children: [
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
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error ??
                    'No se pudo abrir la integración.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                ),
                label: const Text(
                  'Volver',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cabeceraAgente(String nombre, String email) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
            child: Text(
              nombre.isNotEmpty ? nombre.substring(0, 1).toUpperCase() : "A",
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre.isEmpty ? "Agente sin nombre" : nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
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

  Widget _panelProgreso() {
    final p = progreso();
    final porcentajeTexto = (porcentaje * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1E40AF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: CircularProgressIndicator(
                  value: porcentaje,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  color: Colors.white,
                ),
              ),
              Text(
                "$porcentajeTexto%",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textoEstado,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$p de $totalPasos pasos completados",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    "Onboarding comercial",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
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

  Widget _checkCard({
    required String keyData,
    required String titulo,
    required String descripcion,
    required IconData icono,
  }) {
    final activo = data[keyData] == true;
    final color = activo ? const Color(0xFF16A34A) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => actualizarCheck(keyData, !activo),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: activo
                    ? const Color(0xFF16A34A).withOpacity(0.35)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icono, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
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
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activo ? const Color(0xFF16A34A) : Colors.white,
                    border: Border.all(
                      color: activo
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                  child: activo
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
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

  Widget _actividadPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _numberInput(
                  controller: contactosController,
                  label: "Contactos",
                  icono: Icons.call_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberInput(
                  controller: visitasController,
                  label: "Visitas",
                  icono: Icons.handshake_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _numberInput(
                  controller: presupuestosController,
                  label: "Presupuestos",
                  icono: Icons.description_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberInput(
                  controller: polizasController,
                  label: "Pólizas",
                  icono: Icons.verified_user_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberInput({
    required TextEditingController controller,
    required String label,
    required IconData icono,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, color: const Color(0xFF2563EB)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF2563EB),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}