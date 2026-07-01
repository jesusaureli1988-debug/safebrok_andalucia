import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

class UpdateService {
  static final supabase = Supabase.instance.client;

  // 1. Traer última versión activa
  static Future<Map<String, dynamic>?> checkUpdate() async {
    final res = await supabase
        .from('app_versions')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return res;
  }

  // 2. Comparar versiones
static Future<bool> isUpdateAvailable(String remoteVersion) async {
  final info = await PackageInfo.fromPlatform();

  final localVersion =
      "${info.version}+${info.buildNumber}";

  print("REMOTE: [$remoteVersion]");
  print("LOCAL : [$localVersion]");

  return remoteVersion.trim() != localVersion.trim();
}
  // 3. Descargar APK (Drive)
  static Future<void> downloadAndInstall(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw "No se pudo abrir el enlace de actualización";
    }
  }
}