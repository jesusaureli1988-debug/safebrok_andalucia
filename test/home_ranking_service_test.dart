import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/home_ranking_service.dart';

void main() {
  for (final failingStep in ['rpc', 'ventas']) {
    test(
      'El fallo de $failingStep no propaga errores a la produccion',
      () async {
        Object? error;
        final db = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            final isRpc = request.url.path.contains('/rpc/');
            final fail = failingStep == 'rpc' ? isRpc : !isRpc;
            return http.Response(
              jsonEncode(
                fail
                    ? {'message': 'Consulta no disponible', 'code': 'PGRST202'}
                    : [
                        {'auth_id': 'agente'},
                      ],
              ),
              fail ? 404 : 200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final ranking = await HomeRankingService.load(
          db,
          'agente',
          onError: (value) => error = value,
        );
        expect(error, isNotNull);
        expect(ranking.position, 0);
        expect(ranking.total, 0);
        await db.dispose();
      },
    );
  }
  test(
    'El ranking incluye mas de 1000 polizas sin cambiar el calculo de primas',
    () async {
      final db = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          final isRpc = request.url.path.contains('/rpc/');
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final rows = isRpc
              ? [
                  {'auth_id': 'agente'},
                  {'auth_id': 'otro'},
                ]
              : List.generate(
                  offset == 0 ? 1000 : 1,
                  (index) => {'id': offset + index, 'agente_auth_id': 'agente'},
                );
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final ranking = await HomeRankingService.load(db, 'agente');
      expect(ranking.position, 1);
      expect(ranking.total, 2);
      expect(ranking.first, 1001);
      expect(ranking.ownPolicies, 1001);
      await db.dispose();
    },
  );
}
