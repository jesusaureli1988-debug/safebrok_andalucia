import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores bucket paths instead of permanent public URLs and resolves them to a
/// short-lived signed URL when the user opens the file.
class PrivateStorageReference {
  const PrivateStorageReference._();

  static String encode(String bucket, String path) => 'storage://$bucket/$path';

  static Future<String> resolve(String value, {int expiresIn = 900}) async {
    final reference = _parse(value.trim());
    if (reference == null) return value.trim();

    return Supabase.instance.client.storage
        .from(reference.$1)
        .createSignedUrl(reference.$2, expiresIn);
  }

  static (String, String)? _parse(String value) {
    if (value.startsWith('storage://')) {
      final remainder = value.substring('storage://'.length);
      final separator = remainder.indexOf('/');
      if (separator <= 0 || separator == remainder.length - 1) return null;
      return (
        remainder.substring(0, separator),
        Uri.decodeFull(remainder.substring(separator + 1)),
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    const marker = '/storage/v1/object/public/';
    final markerIndex = uri.path.indexOf(marker);
    if (markerIndex < 0) return null;
    final remainder = uri.path.substring(markerIndex + marker.length);
    final separator = remainder.indexOf('/');
    if (separator <= 0 || separator == remainder.length - 1) return null;
    return (
      remainder.substring(0, separator),
      Uri.decodeFull(remainder.substring(separator + 1)),
    );
  }
}
