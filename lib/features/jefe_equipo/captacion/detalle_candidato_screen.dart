import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:safebrok_andalucia/core/storage/private_storage_reference.dart';

class DetalleCandidatoScreen extends StatefulWidget {
  final Map<String, dynamic> candidato;

  const DetalleCandidatoScreen({super.key, required this.candidato});

  @override
  State<DetalleCandidatoScreen> createState() => _DetalleCandidatoScreenState();
}

class _DetalleCandidatoScreenState extends State<DetalleCandidatoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false;
  bool loadingResponsables = true;
  bool reasignando = false;

  List<Map<String, dynamic>> responsablesDisponibles = [];

  String? responsableAuthId;
  String? responsableUsuarioId;
  String? responsableNombre;
  String? responsableRol;

  late String estado;
  String? motivoDescarte;

  DateTime? fechaEntrevista;
  DateTime? fechaProxima;

  final estadosFlow = const [
    'CV_RECIBIDO',
    'CONTACTADO',
    'ENTREVISTA_CONCERTADA',
    'ENTREVISTA_REALIZADA',
    'SELECCIONADO',
    'INCORPORADO',
  ];

  @override
  void initState() {
    super.initState();

    estado = widget.candidato['estado'] ?? 'CV_RECIBIDO';
    motivoDescarte = widget.candidato['motivo_descarte'];

    responsableAuthId = widget.candidato['asignado_auth_id']?.toString().trim();
    responsableUsuarioId = widget.candidato['asignado_usuario_id']
        ?.toString()
        .trim();
    responsableNombre = widget.candidato['asignado_nombre']?.toString().trim();
    responsableRol = widget.candidato['asignado_rol']?.toString().trim();

    cargarResponsables();

    if (widget.candidato['fecha_entrevista_programada'] != null) {
      fechaEntrevista = DateTime.tryParse(
        widget.candidato['fecha_entrevista_programada'].toString(),
      );
    }

    if (widget.candidato['fecha_proxima_accion'] != null) {
      fechaProxima = DateTime.tryParse(
        widget.candidato['fecha_proxima_accion'].toString(),
      );
    }
  }

  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _rolTexto(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      default:
        return rol.isEmpty ? 'Sin figura' : rol;
    }
  }

  int _nivelRol(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 5;
      case 'director_zona':
        return 4;
      case 'jefe_ventas':
        return 3;
      case 'jefe_equipo':
        return 2;
      case 'agente':
        return 1;
      default:
        return 0;
    }
  }

  Future<void> cargarResponsables() async {
    try {
      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        if (mounted) {
          setState(() {
            responsablesDisponibles = [];
            loadingResponsables = false;
          });
        }
        return;
      }

      final data = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos');

      final usuarios = List<Map<String, dynamic>>.from(data).map((u) {
        return <String, dynamic>{
          'id': u['id']?.toString().trim() ?? '',
          'auth_id': u['auth_id']?.toString().trim() ?? '',
          'parent_id': u['parent_id']?.toString().trim() ?? '',
          'rol': _normalizarRol(u['rol_usuario']),
          'nombre': u['nombre']?.toString().trim() ?? '',
          'apellidos': u['apellidos']?.toString().trim() ?? '',
        };
      }).toList();

      final yo = usuarios.firstWhere(
        (u) => u['auth_id'] == authUser.id,
        orElse: () => <String, dynamic>{},
      );

      if (yo.isEmpty) {
        if (mounted) {
          setState(() {
            responsablesDisponibles = [];
            loadingResponsables = false;
          });
        }
        return;
      }

      final hijosPorParentId = <String, List<Map<String, dynamic>>>{};

      for (final usuario in usuarios) {
        final parentId = usuario['parent_id']?.toString() ?? '';

        if (parentId.isEmpty || parentId.toLowerCase() == 'null') {
          continue;
        }

        hijosPorParentId
            .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
            .add(usuario);
      }

      final permitidos = <Map<String, dynamic>>[];
      final visitados = <String>{};

      void recorrer(Map<String, dynamic> actual) {
        final id = actual['id']?.toString() ?? '';
        final rol = _normalizarRol(actual['rol']);

        if (id.isEmpty || visitados.contains(id)) return;

        visitados.add(id);

        if (rol != 'agente' &&
            rol != 'administracion' &&
            rol != 'administrador' &&
            rol != 'admin') {
          permitidos.add(actual);
        }

        final nivelActual = _nivelRol(rol);
        final hijos = hijosPorParentId[id] ?? <Map<String, dynamic>>[];

        for (final hijo in hijos) {
          final rolHijo = _normalizarRol(hijo['rol']);
          final nivelHijo = _nivelRol(rolHijo);

          if (nivelHijo <= 0 || nivelHijo >= nivelActual) continue;

          recorrer(hijo);
        }
      }

      final rolLogueado = _normalizarRol(yo['rol']);

      if (rolLogueado == 'administracion' ||
          rolLogueado == 'administrador' ||
          rolLogueado == 'admin') {
        permitidos.addAll(
          usuarios.where((u) {
            final rol = _normalizarRol(u['rol']);
            return rol == 'director_nacional' ||
                rol == 'director_zona' ||
                rol == 'jefe_ventas' ||
                rol == 'jefe_equipo';
          }),
        );
      } else {
        recorrer(yo);
      }

      final unicos = <String, Map<String, dynamic>>{};

      for (final usuario in permitidos) {
        final authId = usuario['auth_id']?.toString() ?? '';
        if (authId.isEmpty || authId.toLowerCase() == 'null') continue;
        unicos[authId] = usuario;
      }

      final lista = unicos.values.toList()
        ..sort((a, b) {
          final nivelA = _nivelRol(a['rol']?.toString() ?? '');
          final nivelB = _nivelRol(b['rol']?.toString() ?? '');

          final porNivel = nivelB.compareTo(nivelA);
          if (porNivel != 0) return porNivel;

          final nombreA = '${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}'
              .trim()
              .toLowerCase();
          final nombreB = '${b['nombre'] ?? ''} ${b['apellidos'] ?? ''}'
              .trim()
              .toLowerCase();

          return nombreA.compareTo(nombreB);
        });

      if (!mounted) return;

      setState(() {
        responsablesDisponibles = lista;
        loadingResponsables = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGANDO RESPONSABLES: $e');

      if (!mounted) return;

      setState(() {
        responsablesDisponibles = [];
        loadingResponsables = false;
      });
    }
  }

  Future<void> abrirReasignacion() async {
    if (loadingResponsables) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La estructura todavía se está cargando')),
      );
      return;
    }

    if (responsablesDisponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('No hay responsables disponibles en tu estructura'),
        ),
      );
      return;
    }

    final seleccionado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.48,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Reasignar candidato',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona al nuevo responsable del proceso.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: responsablesDisponibles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (_, index) {
                          final responsable = responsablesDisponibles[index];

                          final authId =
                              responsable['auth_id']?.toString() ?? '';
                          final nombre =
                              '${responsable['nombre'] ?? ''} ${responsable['apellidos'] ?? ''}'
                                  .trim();
                          final rol = _normalizarRol(responsable['rol']);
                          final actual = responsableAuthId == authId;

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () => Navigator.pop(context, responsable),
                              child: Ink(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: actual
                                      ? const Color(
                                          0xFF2563EB,
                                        ).withOpacity(0.10)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: actual
                                        ? const Color(0xFF2563EB)
                                        : Colors.black.withOpacity(0.04),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      height: 48,
                                      width: 48,
                                      decoration: BoxDecoration(
                                        color: actual
                                            ? const Color(0xFF2563EB)
                                            : const Color(
                                                0xFF111827,
                                              ).withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                      child: Icon(
                                        actual
                                            ? Icons.check_rounded
                                            : Icons.person_rounded,
                                        color: actual
                                            ? Colors.white
                                            : const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombre.isEmpty
                                                ? 'Usuario sin nombre'
                                                : nombre,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF111827),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _rolTexto(rol),
                                            style: TextStyle(
                                              color: actual
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.black.withOpacity(
                                                      0.45,
                                                    ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 15,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (seleccionado == null) return;

    await reasignarCandidato(seleccionado);
  }

  Future<void> _notificarCandidatoReasignado({
    required String candidatoId,
    required String candidatoNombre,
    required String remitenteAuthId,
    required String destinatarioAuthId,
  }) async {
    try {
      final usuarioRemitente = await supabase
          .from('usuarios')
          .select('nombre, apellidos')
          .eq('auth_id', remitenteAuthId)
          .maybeSingle();

      final nombreRemitente = [
        usuarioRemitente?['nombre']?.toString().trim() ?? '',
        usuarioRemitente?['apellidos']?.toString().trim() ?? '',
      ].where((parte) => parte.isNotEmpty).join(' ');

      final remitenteVisible = nombreRemitente.isEmpty
          ? 'Un responsable'
          : nombreRemitente;

      final response = await supabase.functions.invoke(
        'enviar-push',
        body: {
          'auth_id_destino': destinatarioAuthId,
          'titulo': 'Candidato reasignado',
          'mensaje':
              '$remitenteVisible te ha asignado a $candidatoNombre '
              'para continuar su proceso de selección. Entra en '
              'Candidatos para revisar su perfil.',
          'data': {
            'tipo': 'candidato_reasignado',
            'pantalla_destino': 'candidatos',
            'candidato_id': candidatoId,
            'remitente_auth_id': remitenteAuthId,
            'destinatario_auth_id': destinatarioAuthId,
          },
        },
      );

      if (response.status < 200 || response.status >= 300) {
        debugPrint(
          'PUSH REASIGNACIÓN NO ENVIADO: '
          'HTTP ${response.status} - ${response.data}',
        );
      }
    } catch (error, stackTrace) {
      // El push es secundario: nunca debe impedir la reasignación.
      debugPrint('ERROR PUSH CANDIDATO REASIGNADO: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> reasignarCandidato(Map<String, dynamic> responsable) async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) return;

    final authId = responsable['auth_id']?.toString() ?? '';
    final usuarioId = responsable['id']?.toString() ?? '';
    final rol = _normalizarRol(responsable['rol']);
    final nombre =
        '${responsable['nombre'] ?? ''} ${responsable['apellidos'] ?? ''}'
            .trim();

    if (authId.isEmpty) return;

    if (authId == responsableAuthId) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta persona ya es responsable del candidato'),
        ),
      );
      return;
    }

    setState(() => reasignando = true);

    try {
      await supabase
          .from('candidatos_captacion')
          .update({
            'asignado_auth_id': authId,
            'asignado_usuario_id': usuarioId,
            'asignado_nombre': nombre.isEmpty ? 'Usuario sin nombre' : nombre,
            'asignado_rol': rol,
            'asignado_por': authUser.id,
            'fecha_asignacion': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.candidato['id']);

      final candidatoId = widget.candidato['id'].toString();
      final candidatoNombre =
          widget.candidato['nombre']?.toString().trim() ?? '';

      unawaited(
        _notificarCandidatoReasignado(
          candidatoId: candidatoId,
          candidatoNombre: candidatoNombre.isEmpty
              ? 'un nuevo candidato'
              : candidatoNombre,
          remitenteAuthId: authUser.id,
          destinatarioAuthId: authId,
        ),
      );

      if (!mounted) return;

      setState(() {
        responsableAuthId = authId;
        responsableUsuarioId = usuarioId;
        responsableNombre = nombre.isEmpty ? 'Usuario sin nombre' : nombre;
        responsableRol = rol;
        reasignando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF22C55E),
          content: Text('Candidato reasignado correctamente'),
        ),
      );
    } catch (e) {
      debugPrint('ERROR REASIGNANDO CANDIDATO: $e');

      if (!mounted) return;

      setState(() => reasignando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('No se pudo reasignar el candidato: $e'),
        ),
      );
    }
  }

  Color estadoColor(String e) {
    switch (e) {
      case 'CV_RECIBIDO':
        return const Color(0xFF2563EB);
      case 'CONTACTADO':
        return const Color(0xFFF97316);
      case 'ENTREVISTA_CONCERTADA':
        return const Color(0xFFEAB308);
      case 'ENTREVISTA_REALIZADA':
        return const Color(0xFF8B5CF6);
      case 'SELECCIONADO':
        return const Color(0xFF22C55E);
      case 'INCORPORADO':
        return const Color(0xFF14B8A6);
      case 'DESCARTADO':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String estadoTexto(String e) {
    switch (e) {
      case 'CV_RECIBIDO':
        return 'CV recibido';
      case 'CONTACTADO':
        return 'Contactado';
      case 'ENTREVISTA_CONCERTADA':
        return 'Entrevista concertada';
      case 'ENTREVISTA_REALIZADA':
        return 'Entrevista realizada';
      case 'SELECCIONADO':
        return 'Seleccionado';
      case 'INCORPORADO':
        return 'Incorporado';
      case 'DESCARTADO':
        return 'Descartado';
      default:
        return 'Sin estado';
    }
  }

  double progresoEstado() {
    final i = estadosFlow.indexOf(estado);
    if (i == -1) return estado == 'DESCARTADO' ? 1 : 0;
    return (i + 1) / estadosFlow.length;
  }

  String fechaTexto(DateTime? date) {
    if (date == null) return 'Sin fecha';
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";
  }

  Future<void> llamar() async {
    final tel = widget.candidato['telefono'];

    if (tel == null || tel.toString().trim().isEmpty) return;

    await launchUrl(Uri.parse("tel:$tel"));
  }

  Future<void> verCV() async {
    final url = widget.candidato['cv_url'];

    if (url == null || url.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este candidato no tiene CV adjunto")),
      );
      return;
    }

    final resolvedUrl = await PrivateStorageReference.resolve(url.toString());
    await launchUrl(
      Uri.parse(resolvedUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> seleccionarEstado() async {
    final estados = [
      {
        "valor": "CV_RECIBIDO",
        "texto": "CV recibido",
        "icono": Icons.description_rounded,
      },
      {
        "valor": "CONTACTADO",
        "texto": "Contactado",
        "icono": Icons.phone_in_talk_rounded,
      },
      {
        "valor": "ENTREVISTA_CONCERTADA",
        "texto": "Entrevista concertada",
        "icono": Icons.event_available_rounded,
      },
      {
        "valor": "ENTREVISTA_REALIZADA",
        "texto": "Entrevista realizada",
        "icono": Icons.person_search_rounded,
      },
      {
        "valor": "SELECCIONADO",
        "texto": "Seleccionado",
        "icono": Icons.star_rounded,
      },
      {
        "valor": "INCORPORADO",
        "texto": "Incorporado",
        "icono": Icons.badge_rounded,
      },
      {
        "valor": "DESCARTADO",
        "texto": "Descartado",
        "icono": Icons.cancel_rounded,
      },
    ];

    final seleccionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: SafeArea(
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      "Cambiar estado del candidato",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "Selecciona en qué punto del proceso se encuentra.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 18),

                    ...estados.map((item) {
                      final valor = item["valor"] as String;
                      final color = estadoColor(valor);
                      final seleccionadoActual = estado == valor;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        decoration: BoxDecoration(
                          color: seleccionadoActual
                              ? color.withOpacity(0.10)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: seleccionadoActual
                                ? color.withOpacity(0.35)
                                : Colors.black.withOpacity(0.04),
                          ),
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            leading: Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.13),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                item["icono"] as IconData,
                                color: color,
                              ),
                            ),
                            title: Text(
                              item["texto"] as String,
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            trailing: seleccionadoActual
                                ? Icon(Icons.check_circle_rounded, color: color)
                                : const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 15,
                                    color: Color(0xFF94A3B8),
                                  ),
                            onTap: () => Navigator.pop(context, valor),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (seleccionado == null) return;

    if (seleccionado == "DESCARTADO") {
      await marcarDescartado();
    } else {
      setState(() {
        estado = seleccionado;
        motivoDescarte = null;
      });
    }
  }

  Future<void> marcarDescartado() async {
    final controller = TextEditingController(text: motivoDescarte ?? '');

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Motivo de descarte",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Ejemplo: no interesado, perfil no encaja...",
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (motivo != null) {
      setState(() {
        estado = 'DESCARTADO';
        motivoDescarte = motivo.trim();
      });
    }
  }

  Future<void> guardar() async {
    setState(() => loading = true);

    try {
      await supabase
          .from('candidatos_captacion')
          .update({
            'estado': estado,
            'motivo_descarte': motivoDescarte,
            'fecha_entrevista_programada': fechaEntrevista?.toIso8601String(),
            'fecha_proxima_accion': fechaProxima?.toIso8601String(),
          })
          .eq('id', widget.candidato['id']);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("❌ ERROR GUARDANDO CANDIDATO: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text("No se pudo guardar el candidato"),
          ),
        );
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> pickFecha({
    required DateTime? actual,
    required Function(DateTime) onPick,
  }) async {
    final d = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF111827)),
          ),
          child: child!,
        );
      },
    );

    if (d != null) onPick(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidato;
    final color = estadoColor(estado);

    final nombre = c['nombre']?.toString() ?? 'Candidato sin nombre';
    final telefono = c['telefono']?.toString() ?? 'Sin teléfono';
    final email = c['email']?.toString() ?? 'Sin email';
    final origen = c['origen']?.toString() ?? 'Sin origen';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      bottomNavigationBar: _bottomSaveBar(),
      body: Stack(
        children: [
          const _TalentDetailBackground(),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
                    child: Column(
                      children: [
                        _heroCard(
                          nombre: nombre,
                          telefono: telefono,
                          email: email,
                          origen: origen,
                          color: color,
                        ),
                        const SizedBox(height: 18),
                        _quickActions(color),
                        const SizedBox(height: 18),
                        _responsableCard(),
                        const SizedBox(height: 18),
                        _pipelineCard(color),
                        const SizedBox(height: 18),
                        _datesCard(),
                        const SizedBox(height: 18),
                        _cvCard(),
                        if (estado == 'DESCARTADO') ...[
                          const SizedBox(height: 18),
                          _discardCard(),
                        ],
                      ],
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          _SmallButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
            dark: false,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Ficha candidato",
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _SmallButton(
            icon: Icons.save_rounded,
            onTap: loading ? null : guardar,
            dark: true,
          ),
        ],
      ),
    );
  }

  Widget _heroCard({
    required String nombre,
    required String telefono,
    required String email,
    required String origen,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF111827), color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            bottom: -46,
            child: Icon(
              Icons.person_search_rounded,
              size: 170,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusBadge(color),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withOpacity(0.20)),
                    ),
                    child: Center(
                      child: Text(
                        nombre.trim().isNotEmpty
                            ? nombre.trim()[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _heroInfo(Icons.phone_rounded, telefono),
              _heroInfo(Icons.mail_rounded, email),
              _heroInfo(Icons.campaign_rounded, origen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(Color color) {
    return GestureDetector(
      onTap: seleccionarEstado,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 7),
              Text(
                estadoTexto(estado).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.78), size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(Color color) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.visibility_rounded,
            label: "Ver CV",
            color: const Color(0xFF2563EB),
            onTap: verCV,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.phone_in_talk_rounded,
            label: "Llamar",
            color: const Color(0xFF22C55E),
            onTap: llamar,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.swap_horiz_rounded,
            label: "Estado",
            color: color,
            onTap: seleccionarEstado,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.close_rounded,
            label: "Descartar",
            color: const Color(0xFFEF4444),
            onTap: marcarDescartado,
          ),
        ),
      ],
    );
  }

  Widget _responsableCard() {
    final tieneResponsable =
        responsableAuthId != null &&
        responsableAuthId!.isNotEmpty &&
        responsableNombre != null &&
        responsableNombre!.isNotEmpty;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon: Icons.assignment_ind_rounded,
            title: 'Responsable del candidato',
            subtitle: 'Persona encargada del proceso de captación',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tieneResponsable
                  ? const Color(0xFF2563EB).withOpacity(0.08)
                  : const Color(0xFFEF4444).withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: tieneResponsable
                    ? const Color(0xFF2563EB).withOpacity(0.16)
                    : const Color(0xFFEF4444).withOpacity(0.16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: tieneResponsable
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    tieneResponsable
                        ? Icons.person_rounded
                        : Icons.person_off_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tieneResponsable
                            ? responsableNombre!
                            : 'Sin responsable asignado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tieneResponsable
                            ? _rolTexto(responsableRol ?? '')
                            : 'Debes asignar este candidato',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ClickChip(
                  text: reasignando
                      ? 'Guardando...'
                      : tieneResponsable
                      ? 'Reasignar'
                      : 'Asignar',
                  color: const Color(0xFF2563EB),
                  onTap: reasignando ? () {} : abrirReasignacion,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipelineCard(Color color) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon: Icons.timeline_rounded,
            title: "Pipeline del candidato",
            subtitle: "Evolución dentro del proceso de selección",
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LinearProgressIndicator(
              value: progresoEstado(),
              minHeight: 11,
              color: color,
              backgroundColor: Colors.black.withOpacity(0.06),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                "${(progresoEstado() * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "completado",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.45),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _ClickChip(
                text: estadoTexto(estado),
                color: color,
                onTap: seleccionarEstado,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datesCard() {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon: Icons.event_note_rounded,
            title: "Agenda de seguimiento",
            subtitle: "Programa entrevistas y próximas acciones",
          ),
          const SizedBox(height: 16),
          _DateRow(
            icon: Icons.calendar_month_rounded,
            title: "Entrevista",
            value: fechaTexto(fechaEntrevista),
            onTap: () {
              pickFecha(
                actual: fechaEntrevista,
                onPick: (d) => setState(() => fechaEntrevista = d),
              );
            },
          ),
          const SizedBox(height: 10),
          _DateRow(
            icon: Icons.alarm_rounded,
            title: "Próxima acción",
            value: fechaTexto(fechaProxima),
            onTap: () {
              pickFecha(
                actual: fechaProxima,
                onPick: (d) => setState(() => fechaProxima = d),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cvCard() {
    final tieneCV =
        widget.candidato['cv_url'] != null &&
        widget.candidato['cv_url'].toString().trim().isNotEmpty;

    return _WhiteCard(
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: tieneCV
                  ? const Color(0xFFEF4444).withOpacity(0.12)
                  : const Color(0xFF64748B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              tieneCV
                  ? Icons.picture_as_pdf_rounded
                  : Icons.description_outlined,
              color: tieneCV
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tieneCV ? "CV disponible" : "CV no adjuntado",
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tieneCV
                      ? "Pulsa para abrir el currículum del candidato."
                      : "Este candidato todavía no tiene currículum asociado.",
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (tieneCV)
            _ClickChip(
              text: "Abrir",
              color: const Color(0xFF2563EB),
              onTap: verCV,
            ),
        ],
      ),
    );
  }

  Widget _discardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Motivo de descarte: ${motivoDescarte?.isNotEmpty == true ? motivoDescarte : 'Sin motivo indicado'}",
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFF111827)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.42),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomSaveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: MouseRegion(
          cursor: loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: SizedBox(
            height: 58,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : guardar,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Guardar cambios",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;

  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool hovering = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = pressing
        ? 0.96
        : hovering
        ? 1.04
        : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) {
        setState(() {
          hovering = false;
          pressing = false;
        });
      },
      child: Listener(
        onPointerDown: (_) => setState(() => pressing = true),
        onPointerUp: (_) => setState(() => pressing = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: hovering
                        ? widget.color.withOpacity(0.22)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: hovering ? 22 : 14,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(widget.icon, color: widget.color, size: 25),
                  const SizedBox(height: 7),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClickChip extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _ClickChip({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
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
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _DateRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF2563EB)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;

  const _SmallButton({
    required this.icon,
    required this.onTap,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: dark ? Colors.white : const Color(0xFF111827),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

class _TalentDetailBackground extends StatelessWidget {
  const _TalentDetailBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: _bubble(const Color(0xFF00C2FF), 250),
        ),
        Positioned(
          top: 250,
          left: -150,
          child: _bubble(const Color(0xFF8B5CF6), 280),
        ),
        Positioned(
          bottom: -150,
          right: -90,
          child: _bubble(const Color(0xFF22C55E), 260),
        ),
      ],
    );
  }

  Widget _bubble(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.13),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}
