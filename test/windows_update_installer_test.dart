import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/windows_update_installer.dart';

void main() {
  test(
    'Windows no ofrece la actualización de Android si su paquete no cambió',
    () {
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.3+14',
          'https://example.com/windows/SafeBrokSetup_1.2.2_13.exe',
        ),
        '1.2.2+13',
      );
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.2+14',
          'https://example.com/windows/SafeBrokSetup_1.2.2_13.exe',
        ),
        '1.2.2+13',
      );
    },
  );
  test('El paquete Windows nuevo informa su propia versión y build', () {
    expect(
      WindowsUpdateInstaller.remoteVersion(
        '1.2.2+13',
        'https://example.com/windows/SafeBrokSetup_1.2.3_14.exe',
      ),
      '1.2.3+14',
    );
  });
  test(
    'Los enlaces antiguos sin build son compatibles sin avisos de otro mes',
    () {
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.2+13',
          'https://example.com/windows/SafeBrokSetup_1.2.1.exe',
        ),
        '1.2.1',
      );
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.1+12',
          'https://example.com/windows/SafeBrokSetup_1.2.1.exe',
        ),
        '1.2.1+12',
      );
    },
  );
  test('Enlaces con parámetros conservan la versión del paquete', () {
    expect(
      WindowsUpdateInstaller.remoteVersion(
        '1.2.3+14',
        'https://example.com/windows/SafeBrokSetup_1.2.2_13.exe?cache=1',
      ),
      '1.2.2+13',
    );
  });
  test(
    'URLs sin versión usan la versión explícita o global sin pedir nuevas columnas',
    () {
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.2+13',
          'https://example.com/Setup.exe',
        ),
        '1.2.2+13',
      );
      expect(
        WindowsUpdateInstaller.remoteVersion(
          '1.2.2+13',
          'https://example.com/Setup.exe',
          explicitVersion: '1.2.1+12',
        ),
        '1.2.1+12',
      );
    },
  );

  for (final cancelled in [false, true]) {
    test(
      'Helper PowerShell: ${cancelled ? 'cancelar permiso no cierra la app' : 'reabre una sola vez con el usuario original'}',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'safebrok-update-test-',
        );
        try {
          final marker = '${temp.path}\\started.txt';
          final script = WindowsUpdateInstaller.launchScript(
            r'C:\Temp\SafeBrokSetup.exe',
            WindowsUpdateInstaller.arguments(
              installDirectory: r'C:\Program Files\SafeBrok',
            ),
            acknowledgementPath: marker,
            applicationPath:
                r'C:\Program Files\SafeBrok\safebrok_andalucia.exe',
          ).replaceAll('exit 0', 'return').replaceAll('exit 1', 'return');
          // Sustitutos locales: NO se ejecuta un instalador, UAC, registro ni la app.
          final harness =
              '''
\$script:launches = 0
function Get-ItemProperty { [CmdletBinding()] param([string]\$LiteralPath) return \$null }
function Start-Process {
  [CmdletBinding()] param([string]\$FilePath, [string]\$ArgumentList, [string]\$Verb,
    [string]\$WindowStyle, [switch]\$PassThru, [string]\$WorkingDirectory)
  if (\$Verb -eq 'RunAs') {
    ${cancelled ? "throw 'UAC cancelled'" : ''}
    if (-not \$ArgumentList.Contains('"/DIR=C:\\Program Files\\SafeBrok"')) { throw 'Lost quoted directory' }
    \$p = [PSCustomObject]@{ ExitCode = 0 }
    \$p | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {} -PassThru
    return
  }
  if (\$Verb) { throw 'App must not be elevated' }
  \$script:launches++
}
& { $script }
if (\$script:launches -ne ${cancelled ? 0 : 1}) { exit 3 }
exit 0
''';
          final encoded = base64Encode(
            harness.codeUnits
                .expand((unit) => [unit & 255, (unit >> 8) & 255])
                .toList(),
          );
          final result = await Process.run('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-EncodedCommand',
            encoded,
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          expect(
            await File(marker).readAsString(),
            cancelled ? 'FAILED' : 'STARTED',
          );
        } finally {
          // Solo este directorio temporal creado por el test, nunca una instalación.
          await temp.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  test('Rechaza páginas web o MZ sin cabecera PE', () {
    expect(
      WindowsUpdateInstaller.isExecutable('<html>Error</html>'.codeUnits),
      isFalse,
    );
    expect(WindowsUpdateInstaller.isExecutable([0x4d, 0x5a]), isFalse);
    final header = List<int>.filled(128, 0);
    header[0] = 0x4d;
    header[1] = 0x5a;
    header[60] = 64;
    expect(WindowsUpdateInstaller.isExecutable(header), isFalse);
    header.setRange(64, 68, [0x50, 0x45, 0, 0]);
    expect(WindowsUpdateInstaller.isExecutable(header), isTrue);
    header[63] = 255;
    expect(WindowsUpdateInstaller.isExecutable(header), isFalse);
  });

  test('Actualiza sin asistente y conserva la carpeta instalada', () {
    final args = WindowsUpdateInstaller.arguments(
      installDirectory: r'C:\Program Files\SafeBrok',
      logPath: r'C:\Users\Prueba\Temp\installation.log',
    );
    expect(
      args,
      containsAll([
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/DIR=C:\\Program Files\\SafeBrok',
        '/NORESTARTAPPLICATIONS',
      ]),
    );
    expect(args.any((a) => a.contains('http')), isFalse);
  });

  test('Rutas con espacios y apóstrofes se citan en PowerShell', () {
    final args = WindowsUpdateInstaller.arguments(
      installDirectory: r'C:\Program Files\SafeBrok',
    );
    final script = WindowsUpdateInstaller.launchScript(
      "C:\\Users\\O'Brien\\Temp\\SafeBrokUpdate.exe",
      args,
      acknowledgementPath: r'C:\Users\Prueba\Temp\started.txt',
      applicationPath: r'C:\Program Files\SafeBrok\safebrok_andalucia.exe',
    );
    expect(script, contains("O''Brien"));
    expect(script, contains('"/DIR=C:\\Program Files\\SafeBrok"'));
    expect(script, contains('-Verb RunAs'));
    expect(script, contains('-WindowStyle Hidden'));
    expect(script, contains('exit 1'));
    expect(script, contains('STARTED'));
    expect(script, contains('FAILED'));
    expect(script, contains('WaitForExit'));
    expect(script, contains('-WindowStyle Normal'));
  });

  test('No permite rutas relativas, comillas ni raíz del disco', () {
    for (final path in [
      'SafeBrok',
      'C:\\',
      'C:\\app"\\SafeBrok',
      'C:\\app\nSafeBrok',
    ]) {
      expect(
        () => WindowsUpdateInstaller.arguments(installDirectory: path),
        throwsFormatException,
      );
    }
  });
}
