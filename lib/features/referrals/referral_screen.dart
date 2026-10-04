import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/storage/private_storage_reference.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Campaña de captación entre agentes.
///
/// La recompensa se registra como condición comercial; su liquidación se
/// incorporará en una fase posterior y no modifica nóminas ni facturas.
class ReferralScreen extends StatefulWidget {
  final String role;

  const ReferralScreen({super.key, required this.role});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _supabase = Supabase.instance.client;
  final _nombre = TextEditingController();
  final _apellidos = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _ciudad = TextEditingController();
  final _observaciones = TextEditingController();

  List<Map<String, dynamic>> _referidos = [];
  bool _loading = true;
  bool _saving = false;
  bool _uploadingCv = false;
  String? _cvUrl;
  String? _cvFileName;

  bool get _esAgente =>
      widget.role.trim().toLowerCase().replaceAll(' ', '_') == 'agente';

  @override
  void initState() {
    super.initState();
    _cargarReferidos();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellidos.dispose();
    _email.dispose();
    _telefono.dispose();
    _ciudad.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  Future<void> _cargarReferidos() async {
    final user = _supabase.auth.currentUser;
    if (user == null || !_esAgente) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final response = await _supabase
          .from('referidos_campana_amigo')
          .select()
          .eq('referente_auth_id', user.id)
          .order('creado_en', ascending: false);
      if (!mounted) return;
      setState(() {
        _referidos = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron cargar tus recomendaciones: $error'),
        ),
      );
    }
  }

  Future<void> _subirCv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      );
      if (result == null) return;
      final PlatformFile file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null)
        throw Exception('No se ha podido leer el archivo seleccionado.');

      setState(() => _uploadingCv = true);
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Tu sesión ha caducado.');

      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '$userId/referidos/' +
          DateTime.now().millisecondsSinceEpoch.toString() +
          '_' +
          safeName;

      await _supabase.storage
          .from('cv_candidatos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );

      if (!mounted) return;
      setState(() {
        _cvUrl = PrivateStorageReference.encode('cv_candidatos', path);
        _cvFileName = file.name;
        _uploadingCv = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingCv = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se ha podido adjuntar el CV: $error')),
      );
    }
  }

  Future<void> _abrirFormulario() async {
    _nombre.clear();
    _apellidos.clear();
    _email.clear();
    _telefono.clear();
    _ciudad.clear();
    _observaciones.clear();
    _cvUrl = null;
    _cvFileName = null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            top: 28,
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF4F7FC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Recomendar candidato',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Comparte sus datos para iniciar la valoración.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    ),
                    const SizedBox(height: 22),
                    _field(_nombre, 'Nombre', Icons.person_outline_rounded),
                    const SizedBox(height: 12),
                    _field(_apellidos, 'Apellidos', Icons.badge_outlined),
                    const SizedBox(height: 12),
                    _field(
                      _email,
                      'Email',
                      Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _telefono,
                      'Teléfono',
                      Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      required: false,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _ciudad,
                      'Ciudad',
                      Icons.location_on_outlined,
                      required: false,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _observaciones,
                      'Observaciones',
                      Icons.notes_rounded,
                      required: false,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: _uploadingCv
                            ? null
                            : () async {
                                await _subirCv();
                                if (mounted) setSheetState(() {});
                              },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFDCE5F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F3FF),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: _uploadingCv
                                    ? const Padding(
                                        padding: EdgeInsets.all(11),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.upload_file_rounded,
                                        color: Color(0xFF1677FF),
                                      ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _cvFileName ?? 'Adjuntar CV',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF172033),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _cvFileName == null
                                          ? 'PDF, Word o imagen · recomendado'
                                          : 'CV preparado para enviar',
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _rewardNotice(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1677FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        onPressed: _saving
                            ? null
                            : () => _guardarReferido(sheetContext),
                        icon: _saving
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _saving ? 'Enviando…' : 'Enviar recomendación',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    bool required = true,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none
          : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon, color: const Color(0xFF526581)),
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Color(0xFF526581)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCE5F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCE5F0)),
        ),
      ),
    );
  }

  Future<void> _guardarReferido(BuildContext sheetContext) async {
    final nombre = _nombre.text.trim();
    final apellidos = _apellidos.text.trim();
    final email = _email.text.trim().toLowerCase();
    if (nombre.length < 2 || apellidos.length < 2 || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indica nombre, apellidos y un email válido.'),
        ),
      );
      return;
    }
    if (!_esAgente) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo los agentes pueden registrar candidatos en esta campaña.',
          ),
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('referidos_campana_amigo').insert({
        'referente_auth_id': user.id,
        'nombre': nombre,
        'apellidos': apellidos,
        'email': email,
        'telefono': _telefono.text.trim().isEmpty
            ? null
            : _telefono.text.trim(),
        'ciudad': _ciudad.text.trim().isEmpty ? null : _ciudad.text.trim(),
        'observaciones': _observaciones.text.trim().isEmpty
            ? null
            : _observaciones.text.trim(),
        'cv_url': _cvUrl,
      });
      if (!mounted) return;
      Navigator.of(sheetContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Candidato recomendado. Lo revisaremos muy pronto.'),
        ),
      );
      await _cargarReferidos();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == '23505'
          ? 'Ya tienes una recomendación registrada con este email.'
          : 'No se ha podido guardar la recomendación.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se ha podido guardar: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1677FF),
        foregroundColor: Colors.white,
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Recomendar',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF1677FF),
          onRefresh: _cargarReferidos,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              _topBar(),
              const SizedBox(height: 20),
              _hero(),
              const SizedBox(height: 18),
              _rewardCard(),
              const SizedBox(height: 24),
              const Text(
                'Tus recomendaciones',
                style: TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _esAgente
                    ? 'Consulta cómo avanza cada candidato recomendado.'
                    : 'Puedes conocer la campaña; el registro de candidatos está reservado a agentes.',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              if (!_esAgente)
                _notEligibleCard()
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_referidos.isEmpty)
                _emptyCard()
              else
                ..._referidos.map(_referralCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: () => Navigator.maybePop(context),
          borderRadius: BorderRadius.circular(17),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE1E8F1)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF172033),
            ),
          ),
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Text(
          'Trae a un amigo',
          style: TextStyle(
            color: Color(0xFF172033),
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
      ),
    ],
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF111C45), Color(0xFF2563EB)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1D4ED8).withValues(alpha: .22),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CAMPAÑA DE TALENTO',
                style: TextStyle(
                  color: Color(0xFFBFD7FF),
                  letterSpacing: 1,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 11),
              Text(
                'Tu próxima gran incorporación puede estar cerca.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'Recomienda un candidato y acompaña su evolución.',
                style: TextStyle(
                  color: Color(0xFFD8E4FF),
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12),
        Icon(Icons.diversity_3_rounded, size: 64, color: Color(0xFFBFD7FF)),
      ],
    ),
  );

  Widget _rewardCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: const Color(0xFFDCE5F0)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: .05),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFE7F1FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: Color(0xFF1677FF),
            size: 31,
          ),
        ),
        const SizedBox(width: 15),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '2 % de recompensa',
                style: TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Sobre las primas de Decesos y Vida que genere el candidato recomendado.',
                style: TextStyle(
                  color: Color(0xFF526581),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _rewardNotice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4FF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFC6E0FF)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF1677FF)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'La campaña reconoce un 2 % sobre las primas de Decesos y Vida generadas por el candidato recomendado.',
            style: TextStyle(
              color: Color(0xFF23405F),
              height: 1.35,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _emptyCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: const Column(
      children: [
        Icon(Icons.person_search_rounded, color: Color(0xFF7A8BA4), size: 45),
        SizedBox(height: 12),
        Text(
          'Aún no has recomendado a nadie',
          style: TextStyle(
            color: Color(0xFF172033),
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Cuando registres un candidato, podrás seguirlo desde aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), height: 1.35),
        ),
      ],
    ),
  );

  Widget _notEligibleCard() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B)),
        SizedBox(width: 13),
        Expanded(
          child: Text(
            'Puedes consultar la campaña. El alta de candidatos se reserva a la figura de agente.',
            style: TextStyle(
              color: Color(0xFF526581),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _referralCard(Map<String, dynamic> referral) {
    final name = [
      referral['nombre']?.toString() ?? '',
      referral['apellidos']?.toString() ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final status = referral['estado']?.toString() ?? 'PENDIENTE_REVISION';
    final colors = _statusColors(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFE8F3FF),
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF1677FF),
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  referral['email']?.toString() ?? '',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.$1,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    colors.$2,
                    style: TextStyle(
                      color: colors.$3,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  (Color, String, Color) _statusColors(String status) {
    switch (status) {
      case 'CONTACTADO':
        return (const Color(0xFFFFF4DE), 'Contactado', const Color(0xFF9A5B00));
      case 'EN_PROCESO':
        return (const Color(0xFFE9F2FF), 'En proceso', const Color(0xFF1E5FBF));
      case 'INCORPORADO':
        return (
          const Color(0xFFE5F8EE),
          'Incorporado',
          const Color(0xFF167A45),
        );
      case 'DESCARTADO':
        return (const Color(0xFFFDECEC), 'Descartado', const Color(0xFFB42318));
      default:
        return (
          const Color(0xFFF0F3F7),
          'Pendiente de revisión',
          const Color(0xFF526581),
        );
    }
  }
}
