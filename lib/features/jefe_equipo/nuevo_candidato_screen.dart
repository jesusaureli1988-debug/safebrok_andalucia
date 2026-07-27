import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class NuevoCandidatoScreen extends StatefulWidget {
  const NuevoCandidatoScreen({super.key});

  @override
  State<NuevoCandidatoScreen> createState() => _NuevoCandidatoScreenState();
}

class _NuevoCandidatoScreenState extends State<NuevoCandidatoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false;
  bool uploadingCV = false;
  bool showErrors = false;

  String? cvUrl;
  String? cvFileName;
  String? origenSeleccionado;

  bool loadingResponsables = true;
  String? responsableAuthId;
  String? responsableUsuarioId;
  String? responsableNombre;
  String? responsableRol;

  List<Map<String, dynamic>> responsablesDisponibles = [];

  final nombreController = TextEditingController();
  final telefonoController = TextEditingController();
  final emailController = TextEditingController();
  final ciudadController = TextEditingController();
  final observacionesController = TextEditingController();

  final List<String> origenes = [
    "Jobtoday",
    "Infojobs",
    "Infoempleo",
    "Trabajos.com",
    "Linkedin",
    "Otros portales",
    "Captacion directa",
    "Recomendacion de un comercial",
    "Cliente asegurado",
  ];

  bool get nombreError => nombreController.text.trim().isEmpty;
  bool get telefonoError => telefonoController.text.trim().isEmpty;
  bool get emailError => emailController.text.trim().isEmpty;
  bool get ciudadError => ciudadController.text.trim().isEmpty;
  bool get origenError => origenSeleccionado == null;
  bool get responsableError => responsableAuthId == null;

  bool get formularioValido =>
      !nombreError &&
      !telefonoError &&
      !emailError &&
      !ciudadError &&
      !origenError &&
      !responsableError;

  @override
  void initState() {
    super.initState();
    cargarResponsables();
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
        return rol;
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
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos',
          );

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

          if (nivelHijo <= 0 || nivelHijo >= nivelActual) {
            continue;
          }

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

      final unicosPorAuthId = <String, Map<String, dynamic>>{};

      for (final usuario in permitidos) {
        final authId = usuario['auth_id']?.toString() ?? '';
        if (authId.isEmpty || authId.toLowerCase() == 'null') continue;
        unicosPorAuthId[authId] = usuario;
      }

      final lista = unicosPorAuthId.values.toList()
        ..sort((a, b) {
          final nivelA = _nivelRol(a['rol']?.toString() ?? '');
          final nivelB = _nivelRol(b['rol']?.toString() ?? '');

          final porNivel = nivelB.compareTo(nivelA);
          if (porNivel != 0) return porNivel;

          final nombreA =
              '${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}'.trim().toLowerCase();
          final nombreB =
              '${b['nombre'] ?? ''} ${b['apellidos'] ?? ''}'.trim().toLowerCase();

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

  @override
  void dispose() {
    nombreController.dispose();
    telefonoController.dispose();
    emailController.dispose();
    ciudadController.dispose();
    observacionesController.dispose();
    super.dispose();
  }

  Future<void> subirCV() async {
    try {
      final picker = ImagePicker();

      final option = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _CvPickerSheet(),
      );

      if (option == null) return;

      setState(() => uploadingCV = true);

      Uint8List? bytes;
      String extension = "pdf";
      String originalName = "cv";

      if (option == "camera") {
        final img = await picker.pickImage(source: ImageSource.camera);
        if (img == null) {
          setState(() => uploadingCV = false);
          return;
        }

        bytes = await img.readAsBytes();
        extension = "jpg";
        originalName = img.name;
      }

      if (option == "gallery") {
        final img = await picker.pickImage(source: ImageSource.gallery);
        if (img == null) {
          setState(() => uploadingCV = false);
          return;
        }

        bytes = await img.readAsBytes();
        extension = "jpg";
        originalName = img.name;
      }

      if (option == "file") {
        final result = await FilePicker.platform.pickFiles(
          withData: true,
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        );

        if (result == null) {
          setState(() => uploadingCV = false);
          return;
        }

        bytes = result.files.first.bytes;
        originalName = result.files.first.name;

        final split = originalName.split('.');
        if (split.length > 1) {
          extension = split.last.toLowerCase();
        }
      }

      if (bytes == null) {
        setState(() => uploadingCV = false);
        return;
      }

      final user = supabase.auth.currentUser;
      final userId = user?.id ?? 'sin_usuario';
      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${userId}_cv.$extension";

      final path = fileName;

      await supabase.storage
          .from('cv_candidatos')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage.from('cv_candidatos').getPublicUrl(path);

      setState(() {
        cvUrl = url;
        cvFileName = originalName;
        uploadingCV = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("CV subido correctamente")),
        );
      }
    } catch (e) {
      debugPrint("ERROR CV: $e");

      if (mounted) {
        setState(() => uploadingCV = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo subir el CV: $e")),
        );
      }
    }
  }

  Future<void> _notificarCandidatoAsignado({
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

      final remitenteVisible =
          nombreRemitente.isEmpty ? 'Un responsable' : nombreRemitente;

      final response = await supabase.functions.invoke(
        'enviar-push',
        body: {
          'auth_id_destino': destinatarioAuthId,
          'titulo': 'Nuevo candidato asignado',
          'mensaje':
              '$remitenteVisible te ha asignado a $candidatoNombre '
              'para el proceso de selección. Entra en Candidatos '
              'para revisar su perfil.',
          'data': {
            'tipo': 'candidato_asignado',
            'pantalla_destino': 'candidatos',
            'candidato_id': candidatoId,
            'remitente_auth_id': remitenteAuthId,
            'destinatario_auth_id': destinatarioAuthId,
          },
        },
      );

      if (response.status < 200 || response.status >= 300) {
        debugPrint(
          'PUSH CANDIDATO NO ENVIADO: '
          'HTTP ${response.status} - ${response.data}',
        );
      }
    } catch (error, stackTrace) {
      // El push es secundario: nunca debe impedir guardar el candidato.
      debugPrint('ERROR PUSH CANDIDATO ASIGNADO: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> guardarCandidato() async {
    setState(() => showErrors = true);

    if (!formularioValido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text("Completa todos los campos obligatorios"),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception("No hay usuario autenticado");
      }

      final candidatoNombre = nombreController.text.trim();
      final destinatarioAuthId = responsableAuthId!;

      final candidatoCreado = await supabase
          .from('candidatos_captacion')
          .insert({
            'auth_id': user.id,
            'nombre': candidatoNombre,
            'telefono': telefonoController.text.trim(),
            'email': emailController.text.trim(),
            'ciudad': ciudadController.text.trim(),
            'origen': origenSeleccionado,
            'observaciones': observacionesController.text.trim(),
            'cv_url': cvUrl,
            'estado': 'CV_RECIBIDO',
            'asignado_por': user.id,
            'asignado_auth_id': destinatarioAuthId,
            'asignado_usuario_id': responsableUsuarioId,
            'asignado_nombre': responsableNombre,
            'asignado_rol': responsableRol,
            'fecha_asignacion': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      unawaited(
        _notificarCandidatoAsignado(
          candidatoId: candidatoCreado['id'].toString(),
          candidatoNombre: candidatoNombre,
          remitenteAuthId: user.id,
          destinatarioAuthId: destinatarioAuthId,
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("ERROR GUARDAR: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }

    if (mounted) setState(() => loading = false);
  }

  InputDecoration deco({
    required String label,
    required IconData icon,
    required bool error,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: error ? const Color(0xFFEF4444) : const Color(0xFF64748B),
      ),
      labelStyle: TextStyle(
        color: error ? const Color(0xFFEF4444) : Colors.black.withOpacity(0.48),
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(
        color: Colors.black.withOpacity(0.30),
        fontSize: 13,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: error ? const Color(0xFFEF4444) : Colors.black.withOpacity(0.05),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: error ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completado = [
      !nombreError,
      !telefonoError,
      !emailError,
      !ciudadError,
      !origenError,
      !responsableError,
      cvUrl != null,
    ].where((v) => v).length;

    final progreso = completado / 7;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      bottomNavigationBar: _bottomSaveBar(),
      body: Stack(
        children: [
          const _TalentNewBackground(),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 115),
                    child: Column(
                      children: [
                        _heroCard(progreso),
                        const SizedBox(height: 18),
                        _sectionCard(
                          title: "Datos del candidato",
                          subtitle: "Información principal para iniciar el proceso",
                          icon: Icons.person_add_alt_1_rounded,
                          child: Column(
                            children: [
                              _input(
                                controller: nombreController,
                                label: "Nombre completo *",
                                hint: "Ej. Antonio García",
                                icon: Icons.person_rounded,
                                error: showErrors && nombreError,
                              ),
                              const SizedBox(height: 13),
                              _input(
                                controller: telefonoController,
                                label: "Teléfono *",
                                hint: "Ej. 600 000 000",
                                icon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                                error: showErrors && telefonoError,
                              ),
                              const SizedBox(height: 13),
                              _input(
                                controller: emailController,
                                label: "Email *",
                                hint: "Ej. candidato@email.com",
                                icon: Icons.mail_rounded,
                                keyboardType: TextInputType.emailAddress,
                                error: showErrors && emailError,
                              ),
                              const SizedBox(height: 13),
                              _input(
                                controller: ciudadController,
                                label: "Ciudad *",
                                hint: "Ej. Sevilla",
                                icon: Icons.location_on_rounded,
                                error: showErrors && ciudadError,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _sectionCard(
                          title: "Origen de captación",
                          subtitle: "Indica desde dónde llega este perfil",
                          icon: Icons.campaign_rounded,
                          child: _origenSelector(),
                        ),
                        const SizedBox(height: 18),
                        _sectionCard(
                          title: "Asignar candidato",
                          subtitle: "Selecciona quién será responsable del proceso",
                          icon: Icons.assignment_ind_rounded,
                          child: _responsableSelector(),
                        ),
                        const SizedBox(height: 18),
                        _sectionCard(
                          title: "Observaciones",
                          subtitle: "Notas internas sobre el candidato",
                          icon: Icons.notes_rounded,
                          child: _input(
                            controller: observacionesController,
                            label: "Observaciones",
                            hint: "Ej. Buena actitud, experiencia comercial...",
                            icon: Icons.edit_note_rounded,
                            maxLines: 4,
                            error: false,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _cvUploader(),
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
              "Nuevo candidato",
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _SmallButton(
            icon: Icons.check_rounded,
            onTap: loading ? null : guardarCandidato,
            dark: true,
          ),
        ],
      ),
    );
  }

  Widget _heroCard(double progreso) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF111827),
            Color(0xFF2563EB),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "ALTA EN PIPELINE",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Crea una ficha profesional de candidato.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Añade datos, origen, observaciones y CV para iniciar el proceso de selección.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 10,
                  backgroundColor: Colors.white.withOpacity(0.14),
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "${(progreso * 100).toStringAsFixed(0)}% de ficha completada",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
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
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool error,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: keyboardType == TextInputType.phone
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))]
          : null,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontWeight: FontWeight.w700,
      ),
      decoration: deco(
        label: label,
        icon: icon,
        hint: hint,
        error: error,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _origenSelector() {
    return Column(
      children: [
        if (showErrors && origenError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              "Selecciona un origen de captación",
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: origenes.map((origen) {
            final selected = origenSeleccionado == origen;
            final color = _origenColor(origen);

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => origenSeleccionado = origen),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? color : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected
                          ? color
                          : Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: Text(
                    origen,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF111827),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _responsableSelector() {
    if (loadingResponsables) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2563EB),
          ),
        ),
      );
    }

    if (responsablesDisponibles.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFEF4444).withOpacity(0.18),
          ),
        ),
        child: const Text(
          "No se han encontrado responsables disponibles en tu estructura.",
          style: TextStyle(
            color: Color(0xFFEF4444),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showErrors && responsableError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              "Debes asignar el candidato a una persona",
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ...responsablesDisponibles.map((responsable) {
          final authId = responsable['auth_id']?.toString() ?? '';
          final usuarioId = responsable['id']?.toString() ?? '';
          final rol = _normalizarRol(responsable['rol']);
          final nombre =
              "${responsable['nombre'] ?? ''} ${responsable['apellidos'] ?? ''}"
                  .trim();

          final seleccionado = responsableAuthId == authId;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    setState(() {
                      responsableAuthId = authId;
                      responsableUsuarioId = usuarioId;
                      responsableNombre =
                          nombre.isEmpty ? 'Usuario sin nombre' : nombre;
                      responsableRol = rol;
                    });
                  },
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: seleccionado
                          ? const Color(0xFF2563EB).withOpacity(0.10)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: seleccionado
                            ? const Color(0xFF2563EB)
                            : Colors.black.withOpacity(0.05),
                        width: seleccionado ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: seleccionado
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF111827).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            seleccionado
                                ? Icons.check_rounded
                                : Icons.person_rounded,
                            color: seleccionado
                                ? Colors.white
                                : const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                  color: seleccionado
                                      ? const Color(0xFF2563EB)
                                      : Colors.black.withOpacity(0.45),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Radio<String>(
                          value: authId,
                          groupValue: responsableAuthId,
                          activeColor: const Color(0xFF2563EB),
                          onChanged: (_) {
                            setState(() {
                              responsableAuthId = authId;
                              responsableUsuarioId = usuarioId;
                              responsableNombre =
                                  nombre.isEmpty ? 'Usuario sin nombre' : nombre;
                              responsableRol = rol;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _origenColor(String origen) {
    if (origen.toLowerCase().contains('jobtoday')) {
      return const Color(0xFF2563EB);
    }
    if (origen.toLowerCase().contains('infojobs')) {
      return const Color(0xFF0EA5E9);
    }
    if (origen.toLowerCase().contains('linkedin')) {
      return const Color(0xFF1D4ED8);
    }
    if (origen.toLowerCase().contains('recomendacion')) {
      return const Color(0xFF22C55E);
    }
    if (origen.toLowerCase().contains('cliente')) {
      return const Color(0xFF14B8A6);
    }
    if (origen.toLowerCase().contains('directa')) {
      return const Color(0xFFF97316);
    }
    return const Color(0xFF64748B);
  }

  Widget _cvUploader() {
    final tieneCV = cvUrl != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tieneCV ? const Color(0xFF22C55E).withOpacity(0.10) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: tieneCV
              ? const Color(0xFF22C55E).withOpacity(0.22)
              : Colors.black.withOpacity(0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: tieneCV
                  ? const Color(0xFF22C55E).withOpacity(0.14)
                  : const Color(0xFF2563EB).withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: uploadingCV
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF2563EB),
                    ),
                  )
                : Icon(
                    tieneCV ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                    color: tieneCV ? const Color(0xFF22C55E) : const Color(0xFF2563EB),
                    size: 31,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tieneCV ? "CV cargado correctamente" : "Añadir CV",
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tieneCV
                      ? (cvFileName ?? "Documento adjuntado")
                      : "Foto, galería o archivo PDF/DOC.",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ClickChip(
            text: tieneCV ? "Cambiar" : "Subir",
            color: tieneCV ? const Color(0xFF22C55E) : const Color(0xFF2563EB),
            onTap: uploadingCV ? null : subirCV,
          ),
        ],
      ),
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
              onPressed: loading ? null : guardarCandidato,
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
                      "Guardar candidato",
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

class _CvPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              "Añadir currículum",
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Selecciona cómo quieres adjuntar el CV.",
              style: TextStyle(
                color: Colors.black.withOpacity(0.45),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            _SheetOption(
              icon: Icons.camera_alt_rounded,
              title: "Hacer foto del CV",
              subtitle: "Usar la cámara del dispositivo",
              color: const Color(0xFF22C55E),
              value: "camera",
            ),
            const SizedBox(height: 10),
            _SheetOption(
              icon: Icons.photo_library_rounded,
              title: "Elegir desde galería",
              subtitle: "Seleccionar una imagen guardada",
              color: const Color(0xFF8B5CF6),
              value: "gallery",
            ),
            const SizedBox(height: 10),
            _SheetOption(
              icon: Icons.picture_as_pdf_rounded,
              title: "PDF / archivo",
              subtitle: "PDF, Word o imagen",
              color: const Color(0xFFEF4444),
              value: "file",
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String value;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.pop(context, value),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color),
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
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: Color(0xFF94A3B8),
                ),
              ],
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
  final VoidCallback? onTap;

  const _ClickChip({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
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

class _TalentNewBackground extends StatelessWidget {
  const _TalentNewBackground();

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
