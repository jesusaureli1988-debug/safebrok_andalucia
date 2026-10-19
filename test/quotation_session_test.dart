import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/cotizaciones/quotation_session.dart';

void main() {
  test(
    'Sin sesión no consulta las credenciales ni intenta renovarlas',
    () async {
      var queries = 0, refreshes = 0;
      await expectLater(
        withQuotationSession(
          hasSession: () => false,
          isExpired: () => true,
          refresh: () async {
            refreshes++;
          },
          query: () async {
            queries++;
            return 1;
          },
        ),
        throwsA(isA<QuotationSessionRequired>()),
      );
      expect(queries, 0);
      expect(refreshes, 0);
    },
  );
  test('Sesión caducada se renueva antes de consultar', () async {
    final calls = <String>[];
    expect(
      await withQuotationSession(
        hasSession: () => true,
        isExpired: () => true,
        refresh: () async {
          calls.add('refresh');
        },
        query: () async {
          calls.add('query');
          return 1;
        },
      ),
      1,
    );
    expect(calls, ['refresh', 'query']);
  });
  test('JWT rechazado renueva y reintenta solo una vez', () async {
    var queries = 0, refreshes = 0;
    final value = await withQuotationSession(
      hasSession: () => true,
      isExpired: () => false,
      refresh: () async {
        refreshes++;
      },
      query: () async {
        if (queries++ == 0)
          throw const PostgrestException(message: 'expired', code: 'PGRST301');
        return 1;
      },
    );
    expect(value, 1);
    expect(queries, 2);
    expect(refreshes, 1);
  });
  test(
    'Renovación inválida pide login; red y permisos no se ocultan',
    () async {
      await expectLater(
        withQuotationSession(
          hasSession: () => true,
          isExpired: () => true,
          refresh: () async {
            throw const AuthException('invalid refresh', statusCode: '400');
          },
          query: () async => 1,
        ),
        throwsA(isA<QuotationSessionRequired>()),
      );
      var refreshes = 0;
      await expectLater(
        withQuotationSession(
          hasSession: () => true,
          isExpired: () => false,
          refresh: () async {
            refreshes++;
          },
          query: () async {
            throw const PostgrestException(
              message: 'permission denied',
              code: '42501',
            );
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(refreshes, 0);
    },
  );
  test('Segundo JWT rechazado termina y no entra en bucle', () async {
    var refreshes = 0, queries = 0;
    await expectLater(
      withQuotationSession(
        hasSession: () => true,
        isExpired: () => false,
        refresh: () async {
          refreshes++;
        },
        query: () async {
          queries++;
          throw const PostgrestException(message: 'expired', code: 'PGRST301');
        },
      ),
      throwsA(isA<QuotationSessionRequired>()),
    );
    expect(queries, 2);
    expect(refreshes, 1);
  });
}
