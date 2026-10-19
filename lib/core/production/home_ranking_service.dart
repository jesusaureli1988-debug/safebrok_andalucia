import 'package:supabase_flutter/supabase_flutter.dart';

class HomeRanking {
  final int position;
  final int total;
  final int first;
  final int ownPolicies;
  const HomeRanking({
    this.position = 0,
    this.total = 0,
    this.first = 0,
    this.ownPolicies = 0,
  });
}

/// El ranking es complementario: un fallo suyo nunca invalida las primas.
class HomeRankingService {
  static Future<HomeRanking> load(
    SupabaseClient db,
    String userId, {
    void Function(Object error)? onError,
  }) async {
    try {
      final users = await db
          .rpc('app_ranking_usuarios_activos')
          .timeout(const Duration(seconds: 30));
      final counts = <String, int>{};
      for (final user in users) {
        final id = (user['auth_id'] ?? '').toString().trim();
        if (id.isNotEmpty && id.toLowerCase() != 'null') counts[id] = 0;
      }
      for (var offset = 0; ; offset += 1000) {
        final page = await db
            .from('ventas')
            .select('id, agente_auth_id')
            .order('id')
            .range(offset, offset + 999)
            .timeout(const Duration(seconds: 30));
        for (final row in page) {
          final id = row['agente_auth_id']?.toString();
          if (counts.containsKey(id)) counts[id!] = counts[id]! + 1;
        }
        if (page.length < 1000) break;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) {
          final comparison = b.value.compareTo(a.value);
          return comparison != 0 ? comparison : a.key.compareTo(b.key);
        });
      final index = sorted.indexWhere((entry) => entry.key == userId);
      return HomeRanking(
        position: index < 0 ? 0 : index + 1,
        total: sorted.length,
        first: sorted.isEmpty ? 0 : sorted.first.value,
        ownPolicies: counts[userId] ?? 0,
      );
    } catch (error) {
      onError?.call(error);
      return const HomeRanking();
    }
  }
}
