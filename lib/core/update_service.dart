import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class UpdateService {

  static const String versionUrl =
      "https://drive.google.com/uc?export=download&id=TU_JSON_ID";

  static Future<Map<String, dynamic>?> checkUpdate() async {
    try {

      final res = await Dio().get(versionUrl);
      return jsonDecode(res.data);

    } catch (e) {
      print("Error update: $e");
      return null;
    }
  }

  static Future<bool> isUpdateAvailable(int remoteVersion) async {

    final info = await PackageInfo.fromPlatform();
    final currentVersion = int.parse(info.buildNumber);

    return remoteVersion > currentVersion;
  }

  static Future<void> downloadAndInstall(String url) async {

    final dir = await getTemporaryDirectory();
    final filePath = "${dir.path}/update.apk";

    await Dio().download(url, filePath);

    await OpenFile.open(filePath);
  }
}