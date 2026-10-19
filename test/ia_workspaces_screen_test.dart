import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safebrok_andalucia/features/ia/safebrok_ai_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SafebrokAiScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Escritorio: accesos especializados y bots debajo de nueva conversación',
    (tester) async {
      await open(tester, const Size(1280, 900));
      expect(find.text('¿Qué hacemos hoy?'), findsOneWidget);
      final newY = tester.getTopLeft(find.text('Nueva conversación')).dy;
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('ia-space-bots'))).dy,
        greaterThan(newY),
      );
      await tester.tap(find.byKey(const ValueKey('ia-space-ventas')));
      await tester.pumpAndSettle();
      expect(find.text('Comparar compañías'), findsOneWidget);
      expect(find.text('Trabajar en ventas y producción…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ia-space-bots')));
      await tester.pumpAndSettle();
      expect(find.text('Tu trabajo, en automático'), findsOneWidget);
      await tester.tap(find.text('Crear con IA'));
      await tester.pumpAndSettle();
      expect(find.text('Actividad semanal por usuario'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets('Ventana compacta de Mac mantiene los espacios a la vista', (
    tester,
  ) async {
    await open(tester, const Size(800, 640));
    expect(find.byKey(const ValueKey('ia-space-bots')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets('Móvil: menú y espacio SafeCloud sin desbordamientos', (
    tester,
  ) async {
    await open(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    final safecloud = find.byKey(const ValueKey('ia-space-safecloud'));
    await tester.scrollUntilVisible(
      safecloud,
      260,
      scrollable: find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(safecloud);
    await tester.pumpAndSettle();
    expect(find.text('Crear una carpeta'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
