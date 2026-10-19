import 'package:supabase_flutter/supabase_flutter.dart';

class PendingPolicyAssignment {
  PendingPolicyAssignment(this.db);
  final SupabaseClient db;

  Future<int> assign(List<String> ids, String targetAuthId) async {
    final result = await db.rpc(
      'app_asignar_polizas_pendientes',
      params: {'p_ids': ids, 'p_agente_auth_id': targetAuthId},
    );
    if (result is! num || result < 0 || result > ids.length) {
      throw StateError('El servidor no confirmó la asignación de las pólizas');
    }
    // Never report success if the source records are still pending.
    final remaining = await db
        .from('polizas_pendientes_asignacion')
        .select('id')
        .inFilter('id', ids);
    if (remaining.isNotEmpty) {
      throw StateError(
        'Hay pólizas que siguen pendientes de asignación. Actualiza y reintenta.',
      );
    }
    return result.toInt();
  }
}
