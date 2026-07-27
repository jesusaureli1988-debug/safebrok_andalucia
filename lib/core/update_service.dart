import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static final supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> checkUpdate() async {
    return await supabase
        .from('app_versions')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<bool> isUpdateAvailable(String remoteVersion) async {
    final info = await PackageInfo.fromPlatform();

    final localVersion = '${info.version}+${info.buildNumber}';

    print('REMOTE: [$remoteVersion]');
    print('LOCAL : [$localVersion]');

    return _compareVersions(remoteVersion, localVersion) > 0;
  }

  static int _compareVersions(String first, String second) {
    final firstParts = _versionParts(first);
    final secondParts = _versionParts(second);
    final length = firstParts.length > secondParts.length
        ? firstParts.length
        : secondParts.length;

    for (var index = 0; index < length; index++) {
      final firstValue = index < firstParts.length ? firstParts[index] : 0;
      final secondValue = index < secondParts.length ? secondParts[index] : 0;

      if (firstValue != secondValue) {
        return firstValue.compareTo(secondValue);
      }
    }

    return 0;
  }

  static List<int> _versionParts(String value) {
    return RegExp(r'\d+')
        .allMatches(value.trim())
        .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .toList();
  }

  static String? getPlatformUpdateUrl(Map<String, dynamic> update) {
    if (Platform.isWindows) {
      return update['windows_url']?.toString();
    }

    if (Platform.isAndroid) {
      return update['url']?.toString();
    }

    // iOS se actualiza mediante TestFlight.
    return null;
  }

  static Future<void> downloadAndInstall(String url) async {
    final cleanUrl = url.trim();

    if (cleanUrl.isEmpty) {
      throw Exception('El enlace de actualización está vacío.');
    }

    if (Platform.isWindows) {
      await _downloadAndInstallWindows(cleanUrl);
      return;
    }

    if (Platform.isAndroid) {
      await _downloadAndInstallAndroid(cleanUrl);
      return;
    }

    throw UnsupportedError(
      'La actualización se gestiona externamente '
      'en esta plataforma.',
    );
  }

  static Future<void> _downloadAndInstallWindows(String url) async {
    final tempDir = await getTemporaryDirectory();

    final installerPath = '${tempDir.path}\\SafeBrokUpdate.exe';

    final response = await Dio().download(
      url,
      installerPath,
      deleteOnError: true,
    );

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception(
        'Error descargando el instalador '
        '(${response.statusCode}).',
      );
    }

    final installer = File(installerPath);

    if (!await installer.exists()) {
      throw Exception('No se encontró el instalador descargado.');
    }

    final size = await installer.length();

    if (size <= 0) {
      throw Exception('El instalador descargado está vacío.');
    }

    await Process.start(
      installerPath,
      const [
        '/SP-',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );

    // Damos tiempo a Windows para iniciar el instalador.
    await Future<void>.delayed(const Duration(seconds: 3));

    // Cerramos SafeBrok para que el instalador pueda
    // sustituir los archivos.
    exit(0);
  }

  static Future<void> _downloadAndInstallAndroid(String url) async {
    final tempDir = await getTemporaryDirectory();
    final apkPath = '${tempDir.path}/update.apk';

    final response = await Dio().download(url, apkPath, deleteOnError: true);

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception(
        'Error descargando el APK '
        '(${response.statusCode}).',
      );
    }

    final apk = File(apkPath);

    if (!await apk.exists() || await apk.length() <= 0) {
      throw Exception('El APK descargado no es válido.');
    }

    final result = await OpenFilex.open(apkPath);

    if (result.type != ResultType.done) {
      throw Exception(
        'No se pudo abrir el instalador de Android: '
        '${result.message}',
      );
    }
  }
}
