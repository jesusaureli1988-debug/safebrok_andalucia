import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'windows_update_installer.dart';

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
      for (final key in const ['android_url', 'apk_url', 'url']) {
        final value = update[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    // iOS se actualiza mediante TestFlight.
    return null;
  }

  static String getPlatformUpdateVersion(Map<String, dynamic> update) {
    final globalVersion = update['version']?.toString().trim() ?? '';
    if (Platform.isWindows) {
      return WindowsUpdateInstaller.remoteVersion(
        globalVersion,
        update['windows_url']?.toString().trim() ?? '',
      );
    }
    return globalVersion;
  }

  static Future<void> openUpdateExternally(String url) async {
    final uri = _validatedHttpsUri(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw Exception('No se pudo abrir el enlace de actualización.');
    }
  }

  static Future<void> downloadAndInstall(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final cleanUrl = _validatedHttpsUri(url).toString();

    if (Platform.isWindows) {
      await _downloadAndInstallWindows(cleanUrl, onProgress: onProgress);
      return;
    }

    if (Platform.isAndroid) {
      await _downloadAndInstallAndroid(cleanUrl, onProgress: onProgress);
      return;
    }

    throw UnsupportedError(
      'La actualización se gestiona externamente '
      'en esta plataforma.',
    );
  }

  static Future<void> _downloadAndInstallWindows(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final staging = await tempDir.createTemp('SafeBrokUpdate-');
    final installerPath = '${staging.path}\\SafeBrokUpdate.exe';
    final response =
        await Dio(
          BaseOptions(
            followRedirects: true,
            maxRedirects: 8,
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 10),
          ),
        ).download(
          url,
          installerPath,
          deleteOnError: true,
          onReceiveProgress: onProgress,
        );

    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
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

    final header = await installer
        .openRead(0, size < 8192 ? size : 8192)
        .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    if (size < 1024 * 1024 || !WindowsUpdateInstaller.isExecutable(header)) {
      throw Exception(
        'El enlace no ha descargado un instalador válido de Windows. '
        'Debe apuntar al archivo SafeBrokSetup, no a una página web.',
      );
    }
    final appDir = File(Platform.resolvedExecutable).parent;
    final installed = await File('${appDir.path}\\unins000.exe').exists();
    final args = WindowsUpdateInstaller.arguments(
      installDirectory: installed ? appDir.path : null,
      logPath: '${staging.path}\\installation.log',
    );
    final acknowledgement = File('${staging.path}\\started.txt');
    final script = WindowsUpdateInstaller.launchScript(
      installerPath,
      args,
      acknowledgementPath: acknowledgement.path,
      applicationPath: Platform.resolvedExecutable,
    );
    final encoded = base64Encode(
      script.codeUnits
          .expand((unit) => [unit & 0xff, (unit >> 8) & 0xff])
          .toList(),
    );
    final helper = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      encoded,
    ], mode: ProcessStartMode.detached);
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    var launchState = '';
    while (launchState != 'STARTED' && launchState != 'FAILED') {
      if (await acknowledgement.exists()) {
        try {
          launchState = (await acknowledgement.readAsString()).trim();
        } on FileSystemException {
          // El helper puede estar terminando de escribir la confirmación.
        }
      }
      if (launchState == 'STARTED' || launchState == 'FAILED') break;
      if (DateTime.now().isAfter(deadline)) {
        Process.killPid(
          helper.pid,
        ); // Solo el helper iniciado por esta actualización.
        throw Exception(
          'Windows no ha confirmado el inicio de la actualización. '
          'Cancela cualquier permiso pendiente y vuelve a intentarlo.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (launchState != 'STARTED') {
      throw Exception(
        'Windows no ha autorizado el inicio de la actualización. '
        'Acepta el permiso de administrador cuando aparezca. '
        'SafeBrok no se ha cerrado y puedes reintentarlo.',
      );
    }
    // Solo cerramos la app después de que Windows acepte y lance el instalador.
    // El helper espera a que termine el instalador y reabre la app sin elevarla.
    exit(0);
  }

  static Future<void> _downloadAndInstallAndroid(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final downloadUrl = _normaliseAndroidDownloadUrl(url);
    final tempDir = await getTemporaryDirectory();
    final apkPath = tempDir.path + '/SafeBrokUpdate.apk';
    final apk = File(apkPath);

    if (await apk.exists()) {
      await apk.delete();
    }

    final dio = Dio(
      BaseOptions(
        followRedirects: true,
        maxRedirects: 8,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        responseType: ResponseType.bytes,
        headers: const {
          'Accept':
              'application/vnd.android.package-archive,application/octet-stream,*/*',
        },
      ),
    );

    final response = await dio.download(
      downloadUrl,
      apkPath,
      deleteOnError: true,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true, responseType: ResponseType.bytes),
    );

    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw Exception(
        'La descarga del APK respondió con el código ' +
            (response.statusCode?.toString() ?? 'desconocido') +
            '.',
      );
    }

    if (!await apk.exists()) {
      throw Exception('No se encontró el APK después de descargarlo.');
    }

    final size = await apk.length();
    if (size < 1024 * 1024) {
      await apk.delete();
      throw Exception(
        'Google Drive no devolvió una APK válida. Comprueba que el archivo '
        'esté compartido como "Cualquier persona con el enlace".',
      );
    }

    final header = await apk
        .openRead(0, 4)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    final isZip = header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;

    if (!isZip) {
      await apk.delete();
      throw Exception(
        'El enlace ha descargado una página web en lugar del APK. '
        'Revisa el enlace público de Google Drive.',
      );
    }

    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw Exception(_androidOpenError(result));
    }
  }

  static Uri _validatedHttpsUri(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      throw const FormatException('El enlace de actualización está vacío.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      throw const FormatException(
        'El enlace de actualización debe ser una dirección HTTPS válida.',
      );
    }
    return uri;
  }

  static String _normaliseAndroidDownloadUrl(String rawUrl) {
    final url = rawUrl.trim();
    final uri = _validatedHttpsUri(url);

    if (uri.host.contains('dropbox.com')) {
      return uri
          .replace(queryParameters: {...uri.queryParameters, 'dl': '1'})
          .toString();
    }

    if (!uri.host.contains('drive.google.com') &&
        !uri.host.contains('drive.usercontent.google.com')) {
      return url;
    }

    String? fileId;

    final segments = uri.pathSegments;
    final dIndex = segments.indexOf('d');
    if (dIndex >= 0 && dIndex + 1 < segments.length) {
      fileId = segments[dIndex + 1];
    }

    fileId ??= uri.queryParameters['id'];

    if (fileId == null || fileId.trim().isEmpty) {
      throw const FormatException(
        'No se ha podido obtener el identificador del archivo de Google Drive.',
      );
    }

    return Uri.https('drive.usercontent.google.com', '/download', {
      'id': fileId.trim(),
      'export': 'download',
      'confirm': 't',
    }).toString();
  }

  static String _androidOpenError(OpenResult result) {
    final details = result.message.trim();

    if (details.isEmpty) {
      return 'Android no ha podido abrir el instalador. Autoriza a SafeBrok '
          'para instalar aplicaciones desconocidas en los ajustes del dispositivo.';
    }

    return 'Android no ha podido abrir el instalador: ' +
        details +
        '. Si aparece bloqueado, autoriza a SafeBrok para instalar '
            'aplicaciones desconocidas.';
  }
}
