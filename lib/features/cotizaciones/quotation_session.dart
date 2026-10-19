import 'package:supabase_flutter/supabase_flutter.dart';

class QuotationSessionRequired implements Exception {
  const QuotationSessionRequired();
}

/// Nunca consulta credenciales como anon. Renueva una sesión expirada o rechazada
/// una sola vez; los errores de red o de permisos no se convierten en datos vacíos.
Future<T> withQuotationSession<T>({
  required bool Function() hasSession,
  required bool Function() isExpired,
  required Future<void> Function() refresh,
  required Future<T> Function() query,
}) async {
  Future<void> renew() async {
    try {
      await refresh();
    } on AuthRetryableFetchException {
      rethrow;
    } on AuthException {
      throw const QuotationSessionRequired();
    }
    if (!hasSession()) throw const QuotationSessionRequired();
  }

  if (!hasSession()) throw const QuotationSessionRequired();
  var renewed = false;
  if (isExpired()) {
    await renew();
    renewed = true;
  }
  try {
    return await query();
  } on PostgrestException catch (error) {
    final rejected =
        error.code == 'PGRST301' ||
        error.code == 'PGRST303' ||
        error.code == '401';
    if (!hasSession()) throw const QuotationSessionRequired();
    if (!rejected) rethrow;
    if (renewed) throw const QuotationSessionRequired();
    await renew();
    try {
      return await query();
    } on PostgrestException catch (retryError) {
      if (['PGRST301', 'PGRST303', '401'].contains(retryError.code)) {
        throw const QuotationSessionRequired();
      }
      rethrow;
    }
  }
}
