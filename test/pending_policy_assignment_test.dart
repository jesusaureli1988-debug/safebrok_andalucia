import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/admin/pending_policy_assignment.dart';

void main() {
  SupabaseClient client({
    Object? result = 2,
    List<Object> pending = const [],
    bool fail = false,
  }) {
    final db = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final rpc = request.url.path.endsWith('app_asignar_polizas_pendientes');
        if (rpc) {
          expect(request.method, 'POST');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['p_ids'], ['p1', 'p2']);
          expect(payload['p_agente_auth_id'], 'destination-auth');
        } else {
          expect(request.url.path, endsWith('/polizas_pendientes_asignacion'));
          expect(request.url.queryParameters['id'], contains('p1'));
          expect(request.url.queryParameters['id'], contains('p2'));
        }
        return http.Response(
          jsonEncode(
            fail
                ? {'code': 'P0001', 'message': 'No autorizado'}
                : rpc
                ? result
                : pending,
          ),
          fail ? 400 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(db.dispose);
    return db;
  }

  test(
    'confirma la asignación y comprueba que las fuentes desaparecen',
    () async {
      expect(
        await PendingPolicyAssignment(
          client(),
        ).assign(['p1', 'p2'], 'destination-auth'),
        2,
      );
    },
  );
  test(
    'no muestra éxito si el servidor conserva una póliza pendiente',
    () async {
      await expectLater(
        PendingPolicyAssignment(
          client(
            pending: [
              {'id': 'p1'},
            ],
          ),
        ).assign(['p1', 'p2'], 'destination-auth'),
        throwsStateError,
      );
    },
  );
  test('propaga el error del servidor sin ocultar las pendientes', () async {
    await expectLater(
      PendingPolicyAssignment(
        client(fail: true),
      ).assign(['p1', 'p2'], 'destination-auth'),
      throwsA(isA<PostgrestException>()),
    );
  });
  test(
    'un reintento ya procesado confirma la ausencia sin duplicar el total',
    () async {
      expect(
        await PendingPolicyAssignment(
          client(result: 0),
        ).assign(['p1', 'p2'], 'destination-auth'),
        0,
      );
    },
  );
  for (final invalid in [null, 'ok', -1, 3]) {
    test('rechaza una confirmación inválida: $invalid', () async {
      await expectLater(
        PendingPolicyAssignment(
          client(result: invalid),
        ).assign(['p1', 'p2'], 'destination-auth'),
        throwsStateError,
      );
    });
  }
}
