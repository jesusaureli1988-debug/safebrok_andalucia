import 'package:supabase_flutter/supabase_flutter.dart';
import '../quotation_session.dart';
import 'quote_project.dart';

abstract interface class QuoteProjectRepository {
  Future<List<QuoteProject>> list();
  Future<QuoteProject> save(QuoteProject project);
}

class SupabaseQuoteProjectRepository implements QuoteProjectRepository {
  SupabaseClient get client => Supabase.instance.client;
  Future<T> authenticated<T>(Future<T> Function() query) =>
      withQuotationSession(
        hasSession: () => client.auth.currentSession != null,
        isExpired: () => client.auth.currentSession?.isExpired ?? true,
        refresh: () async {
          await client.auth.refreshSession();
        },
        query: query,
      );
  @override
  Future<List<QuoteProject>> list() => authenticated(() async {
    final rows = await client
        .from('cotizaciones_proyectos')
        .select('id,version,datos')
        .eq('auth_id', client.auth.currentUser!.id)
        .order('actualizado_en', ascending: false)
        .limit(100);
    return rows
        .map(
          (row) => QuoteProject.fromJson(
            Map<String, dynamic>.from(row['datos'] as Map),
            id: row['id'] as String,
            version: row['version'] as int,
          ),
        )
        .toList();
  });
  @override
  Future<QuoteProject> save(QuoteProject project) => authenticated(() async {
    final title = project.title.trim().isEmpty
        ? 'Proyecto de ${project.line}'
        : project.title.trim();
    final clean = project.copy()..title = title;
    final values = {
      'titulo': title,
      'ramo': clean.line,
      'datos': clean.toJson(),
      'actualizado_en': DateTime.now().toUtc().toIso8601String(),
    };
    Map<String, dynamic>? row;
    if (project.id == null) {
      row = await client
          .from('cotizaciones_proyectos')
          .insert(values)
          .select('id,version,datos')
          .single();
    } else {
      row = await client
          .from('cotizaciones_proyectos')
          .update({...values, 'version': project.version + 1})
          .eq('id', project.id!)
          .eq('auth_id', client.auth.currentUser!.id)
          .eq('version', project.version)
          .select('id,version,datos')
          .maybeSingle();
      if (row == null) {
        throw StateError(
          'Este proyecto ha cambiado en otro dispositivo. Vuelve a abrirlo antes de guardar.',
        );
      }
    }
    return QuoteProject.fromJson(
      Map<String, dynamic>.from(row['datos'] as Map),
      id: row['id'] as String,
      version: row['version'] as int,
    );
  });
}
