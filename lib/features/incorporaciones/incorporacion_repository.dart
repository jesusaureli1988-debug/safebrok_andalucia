import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncorporacionRepository {
  IncorporacionRepository({SupabaseClient? client})
    : db = client ?? Supabase.instance.client;
  final SupabaseClient db;
  static const bucket = 'incorporaciones';
  static const requiredTypes = <String>[
    'DNI_ANVERSO',
    'DNI_REVERSO',
    'FOTO_CORPORATIVA',
    'CERTIFICADO_TITULARIDAD',
    'CV',
  ];
  String normalRole(dynamic v) => (v ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  int roleLevel(dynamic v) =>
      const {
        'agente': 1,
        'jefe_equipo': 2,
        'jefe_ventas': 3,
        'director_zona': 4,
        'director_nacional': 5,
        'administracion': 6,
      }[normalRole(v)] ??
      0;
  Future<Map<String, dynamic>> myProfile() async => Map<String, dynamic>.from(
    await db
        .from('usuarios')
        .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,email')
        .eq('auth_id', db.auth.currentUser!.id)
        .single(),
  );
  Future<List<Map<String, dynamic>>> allowedResponsibles(String figure) async {
    final me = await myProfile();
    final rows = List<Map<String, dynamic>>.from(
      await db
          .from('usuarios')
          .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,email'),
    );
    if (normalRole(me['rol_usuario']) == 'administracion')
      return rows
          .where((u) => roleLevel(figure) < roleLevel(u['rol_usuario']))
          .toList();
    final children = <String, List<Map<String, dynamic>>>{};
    for (final u in rows) {
      final p = u['parent_id']?.toString();
      if (p != null && p.isNotEmpty) children.putIfAbsent(p, () => []).add(u);
    }
    final visible = <Map<String, dynamic>>[];
    final seen = <String>{};
    void walk(Map<String, dynamic> u) {
      final id = u['id'].toString();
      if (!seen.add(id)) return;
      visible.add(u);
      for (final c in children[id] ?? const []) {
        if (roleLevel(c['rol_usuario']) < roleLevel(u['rol_usuario'])) walk(c);
      }
    }

    walk(me);
    return visible
        .where((u) => roleLevel(figure) < roleLevel(u['rol_usuario']))
        .toList();
  }

  Future<List<String>> allowedFigures() async {
    final role = normalRole((await myProfile())['rol_usuario']);
    const all = [
      'agente',
      'jefe_equipo',
      'jefe_ventas',
      'director_zona',
      'director_nacional',
      'administracion',
    ];
    if (role == 'administracion') return all;
    return all.where((r) => roleLevel(r) < roleLevel(role)).toList();
  }

  Future<Map<String, dynamic>> saveDraft(
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final candidateId = data['candidato_captacion_id']?.toString().trim();
    final payload = <String, dynamic>{
      ...data,
      'candidato_captacion_id': candidateId?.isEmpty == true
          ? null
          : candidateId,
      'solicitante_auth_id': db.auth.currentUser!.id,
    };

    String? draftId = id;
    if (draftId == null && candidateId != null && candidateId.isNotEmpty) {
      final existing = await db
          .from('incorporaciones')
          .select('id,estado')
          .eq('candidato_captacion_id', candidateId)
          .neq('estado', 'ALTA_COMPLETADA')
          .maybeSingle();
      if (existing != null) {
        final state = existing['estado']?.toString();
        if (state != 'BORRADOR' && state != 'CORRECCION_REQUERIDA') {
          throw StateError(
            'Este candidato ya tiene un expediente en estado $state',
          );
        }
        draftId = existing['id'].toString();
      }
    }

    if (draftId != null) {
      final row = await db
          .from('incorporaciones')
          .update(payload)
          .eq('id', draftId)
          .select()
          .single();
      return Map<String, dynamic>.from(row);
    }

    try {
      final row = await db
          .from('incorporaciones')
          .insert({...payload, 'estado': 'BORRADOR'})
          .select()
          .single();
      return Map<String, dynamic>.from(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError(
          'Ya existe una incorporación activa para este candidato o DNI. Ábrela desde la lista de Incorporaciones.',
        );
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>>
  list() async => List<Map<String, dynamic>>.from(
    await db
        .from('incorporaciones')
        .select(
          '*, responsable:usuarios!incorporaciones_responsable_id_fkey(id,nombre,apellidos,rol_usuario), documentos:incorporacion_documentos(*)',
        )
        .order('updated_at', ascending: false),
  );
  Future<List<Map<String, dynamic>>> history(String id) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('incorporacion_historial')
            .select()
            .eq('incorporacion_id', id)
            .order('created_at', ascending: false),
      );
  Future<void> upload(
    String incorporationId,
    String type,
    PlatformFile file,
  ) async {
    final bytes = file.bytes;
    if (bytes == null)
      throw StateError('No se pudieron leer los bytes del archivo');
    final safe = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$incorporationId/$type-${DateTime.now().millisecondsSinceEpoch}-$safe';
    await db.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mime(file.extension)),
        );
    await db.from('incorporacion_documentos').upsert({
      'incorporacion_id': incorporationId,
      'tipo': type,
      'storage_path': path,
      'nombre_archivo': file.name,
      'mime_type': _mime(file.extension),
      'tamano_bytes': file.size,
      'estado': 'SUBIDO',
      'subido_por': db.auth.currentUser!.id,
    }, onConflict: 'incorporacion_id,tipo');
  }

  String _mime(String? e) {
    switch (e?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> signedUrl(String path) =>
      db.storage.from(bucket).createSignedUrl(path, 900);
  Future<void> reviewDocument(String id, bool valid, String? notes) => db
      .from('incorporacion_documentos')
      .update({
        'estado': valid ? 'VALIDADO' : 'CORRECCION_REQUERIDA',
        'observaciones': notes,
        'revisado_por': db.auth.currentUser!.id,
        'revisado_at': DateTime.now().toIso8601String(),
      })
      .eq('id', id);
  Future<void> rejectSignedContract(String id, String observations) => db.rpc(
    'incorporacion_rechazar_contrato_firmado',
    params: {'p_id': id, 'p_observaciones': observations},
  );

  Future<void> setState(String id, String state, {String? observations}) =>
      db.rpc(
        'incorporacion_set_estado',
        params: {
          'p_id': id,
          'p_estado': state,
          'p_observaciones': observations,
        },
      );
}
