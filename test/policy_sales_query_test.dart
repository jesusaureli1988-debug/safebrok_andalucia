import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/policy_sales_query.dart';

void main() {
  test(
    'Incluye la póliza 1001 y filtra por efecto sin usar creación',
    () async {
      final requests = <Uri>[];
      final db = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final count = offset == 0 ? 1000 : 1;
          return http.Response(
            jsonEncode(
              List.generate(
                count,
                (i) => {'id': '${offset + i}', 'fecha_efecto': '2026-09-23'},
              ),
            ),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final rows = await PolicySalesQuery.load(
        db,
        authIds: ['agente'],
        start: DateTime(2026, 8, 24),
        endExclusive: DateTime(2026, 9, 24),
      );
      expect(rows.length, 1001);
      expect(requests.length, 2);
      expect(requests.last.queryParameters['offset'], '1000');
      for (final uri in requests) {
        expect(
          uri.queryParametersAll['fecha_efecto'],
          containsAll([
            'gte.2026-08-24T00:00:00.000',
            'lt.2026-09-24T00:00:00.000',
          ]),
        );
        expect(uri.queryParameters.containsKey('created_at'), isFalse);
      }
      await db.dispose();
    },
  );
}
