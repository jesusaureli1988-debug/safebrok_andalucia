import 'package:supabase_flutter/supabase_flutter.dart';

class HierarchyService {
  final supabase = Supabase.instance.client;

  Future<List<String>> getAllChildren(String parentAuthId) async {
    final result = <String>{};

    Future<void> fetch(String authId) async {
      final res = await supabase
          .from('usuarios')
          .select('auth_id')
          .eq('parent_id', authId);

      for (final row in res) {
        final childAuthId = row['auth_id'];

        if (childAuthId == null) continue;
        if (result.contains(childAuthId)) continue;

        result.add(childAuthId);
        await fetch(childAuthId);
      }
    }

    await fetch(parentAuthId);

    return result.toList();
  }
}