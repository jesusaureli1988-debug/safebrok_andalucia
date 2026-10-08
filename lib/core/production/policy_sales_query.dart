import 'package:supabase_flutter/supabase_flutter.dart';

/// Descarga todas las páginas, sin perder pólizas al superar 1.000 registros.
class PolicySalesQuery {
  static Future<List<Map<String, dynamic>>> load(
    SupabaseClient db, {
    List<String>? authIds,
    DateTime? start,
    DateTime? endExclusive,
    String select = '*',
  }) async {
    final ids = authIds?.toSet().toList();
    if (ids != null && ids.isEmpty) return [];
    final blocks = <List<String>?>[];
    if (ids == null) {
      blocks.add(null);
    } else {
      for (var i = 0; i < ids.length; i += 80) {
        blocks.add(ids.sublist(i, i + 80 < ids.length ? i + 80 : ids.length));
      }
    }
    final result = <Map<String, dynamic>>[];
    for (final block in blocks) {
      for (var offset = 0; ; offset += 1000) {
        var query = db.from('ventas').select(select);
        if (block != null) query = query.inFilter('agente_auth_id', block);
        if (start != null)
          query = query.gte('fecha_efecto', start.toIso8601String());
        if (endExclusive != null)
          query = query.lt('fecha_efecto', endExclusive.toIso8601String());
        final page = await query.order('id').range(offset, offset + 999);
        result.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 1000) break;
      }
    }
    return result;
  }
}
