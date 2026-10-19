import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/incorporaciones/incorporacion_repository.dart';
import 'package:safebrok_andalucia/features/incorporaciones/incorporaciones_screen.dart';

class FakeRepository extends IncorporacionRepository {
  FakeRepository()
    : super(
        client: SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  String? discardedId;
  String? reason;
  bool fail = false;
  @override
  Future<void> decline(String id, String reason) async {
    if (fail) throw StateError('Sin conexión');
    discardedId = id;
    this.reason = reason;
  }
}

Map<String, dynamic> expediente(String state) => {
  'id': 'expediente-test',
  'nombre': 'Candidato',
  'apellidos': 'Prueba',
  'estado': state,
  'figura': 'agente',
  'documentos': <Map<String, dynamic>>[],
};

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeRepository repo, {
    bool admin = true,
    String state = 'EN_REVISION',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Abrir candidato'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => IncorporacionDetail(
                    expediente: expediente(state),
                    admin: admin,
                    repository: repo,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir candidato'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirma el descarte con motivo y vuelve a la lista', (
    tester,
  ) async {
    final repo = FakeRepository();
    await open(tester, repo);
    await tester.tap(find.text('Declinar incorporación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar descarte'));
    await tester.pump();
    expect(find.text('Indica el motivo del descarte'), findsOneWidget);
    expect(repo.discardedId, isNull);
    await tester.enterText(
      find.byType(TextFormField),
      '  Perfil no adecuado  ',
    );
    await tester.tap(find.text('Confirmar descarte'));
    await tester.pumpAndSettle();
    expect(repo.discardedId, 'expediente-test');
    expect(repo.reason, 'Perfil no adecuado');
    expect(find.text('Abrir candidato'), findsOneWidget);
  });
  testWidgets('cancelar conserva el expediente', (tester) async {
    final repo = FakeRepository();
    await open(tester, repo);
    await tester.tap(find.text('Declinar incorporación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.discardedId, isNull);
    expect(find.text('Declinar incorporación'), findsOneWidget);
  });
  testWidgets('un responsable no dispone de la acción', (tester) async {
    await open(tester, FakeRepository(), admin: false);
    expect(find.text('Declinar incorporación'), findsNothing);
  });
  for (final state in ['ALTA_COMPLETADA', 'DESCARTADO']) {
    testWidgets('no permite declinar un expediente $state', (tester) async {
      await open(tester, FakeRepository(), state: state);
      expect(find.text('Declinar incorporación'), findsNothing);
    });
  }
  testWidgets('si falla el servidor mantiene el candidato abierto', (
    tester,
  ) async {
    final repo = FakeRepository()..fail = true;
    await open(tester, repo);
    await tester.tap(find.text('Declinar incorporación'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'No continúa');
    await tester.tap(find.text('Confirmar descarte'));
    await tester.pumpAndSettle();
    expect(repo.discardedId, isNull);
    expect(find.textContaining('No se pudo declinar'), findsOneWidget);
    expect(find.text('Declinar incorporación'), findsOneWidget);
  });
}
