/// Parámetros y validación del instalador de Windows, sin ejecutar procesos.
class WindowsUpdateInstaller {
  /// La fila global puede avanzar por Android antes de publicar Windows.
  /// El nombre con versión y build identifica el paquete Windows disponible.
  static String remoteVersion(
    String globalVersion,
    String installerUrl, {
    String? explicitVersion,
  }) {
    if (explicitVersion != null && explicitVersion.trim().isNotEmpty) {
      return explicitVersion.trim();
    }
    final uri = Uri.tryParse(installerUrl);
    final fileName = uri == null || uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last;
    final match = RegExp(
      r'^SafeBrokSetup_(\d+\.\d+\.\d+)(?:_(\d+))?\.exe$',
      caseSensitive: false,
    ).firstMatch(fileName);
    if (match == null) return globalVersion.trim();
    final version = match.group(1)!;
    final build = match.group(2);
    if (build != null) return '$version+$build';
    final globalName = RegExp(
      r'\d+\.\d+\.\d+',
    ).firstMatch(globalVersion)?.group(0);
    return globalName == version ? globalVersion.trim() : version;
  }

  static bool isExecutable(List<int> header) {
    if (header.length < 64 || header[0] != 0x4d || header[1] != 0x5a) {
      return false;
    }
    final offset =
        header[60] |
        (header[61] << 8) |
        (header[62] << 16) |
        (header[63] << 24);
    return offset >= 64 &&
        offset + 4 <= header.length &&
        header[offset] == 0x50 &&
        header[offset + 1] == 0x45 &&
        header[offset + 2] == 0 &&
        header[offset + 3] == 0;
  }

  static List<String> arguments({String? installDirectory, String? logPath}) {
    return [
      '/SP-',
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/NORESTARTAPPLICATIONS',
      '/SAFEBROKUPDATE=1',
      if (installDirectory != null) '/DIR=${_path(installDirectory)}',
      if (logPath != null) '/LOG=${_path(logPath)}',
    ];
  }

  static String _path(String path) {
    if (!RegExp(r'^[a-zA-Z]:\\.+').hasMatch(path) ||
        path.contains('"') ||
        path.contains('\n') ||
        path.contains('\r')) {
      throw const FormatException(
        'La ruta del instalador de Windows no es válida.',
      );
    }
    return path.replaceFirst(RegExp(r'\\+$'), '');
  }

  static String _literal(String value) => "'${value.replaceAll("'", "''")}'";

  /// ShellExecute RunAs solicita permiso a Windows; no se omite el UAC.
  /// Cada argumento se cita para preservar rutas como C:\Program Files\SafeBrok.
  static String launchScript(
    String installerPath,
    List<String> args, {
    required String acknowledgementPath,
    required String applicationPath,
  }) {
    _path(installerPath);
    _path(acknowledgementPath);
    _path(applicationPath);
    final commandLine = args.map((arg) => '"$arg"').join(' ');
    return "\$ErrorActionPreference = 'Stop'; \$accepted = \$false; try { "
        '\$setup = Start-Process -FilePath ${_literal(installerPath)} '
        '-ArgumentList ${_literal(commandLine)} '
        '-Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop; '
        '[IO.File]::WriteAllText(${_literal(acknowledgementPath)}, '
        "'STARTED', [Text.Encoding]::ASCII); \$accepted = \$true; "
        '\$setup.WaitForExit(); '
        'if (\$setup.ExitCode -ne 0 -and \$setup.ExitCode -ne 3010) { '
        "(New-Object -ComObject WScript.Shell).Popup('No se ha completado la "
        "actualización. Puedes reintentarlo desde SafeBrok.', 0, 'SafeBrok', 16) | Out-Null; } "
        '\$app = ${_literal(applicationPath)}; '
        // Una ejecución portable puede actualizar una instalación ya existente.
        '\$installed = Get-ItemProperty -LiteralPath '
        "'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
        "{995791D6-79B9-4AE0-858D-C4470AE4BA3C}_is1' -ErrorAction SilentlyContinue; "
        'if (\$installed.InstallLocation) { '
        "\$candidate = Join-Path \$installed.InstallLocation 'safebrok_andalucia.exe'; "
        'if (Test-Path -LiteralPath \$candidate) { \$app = \$candidate; } } '
        // Este helper NO está elevado: reabre con el usuario que estaba usando la app.
        'Start-Process -FilePath \$app -WorkingDirectory (Split-Path -Parent \$app) '
        '-WindowStyle Normal -ErrorAction Stop; exit 0 '
        '} catch { if (-not \$accepted) { '
        '[IO.File]::WriteAllText(${_literal(acknowledgementPath)}, '
        "'FAILED', [Text.Encoding]::ASCII); } else { "
        "(New-Object -ComObject WScript.Shell).Popup('No se ha podido reabrir "
        "SafeBrok. Abre el acceso directo del escritorio.', 0, 'SafeBrok', 16) | Out-Null; } exit 1 }";
  }
}
