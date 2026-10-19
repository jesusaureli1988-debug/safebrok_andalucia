import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/features/admin/policy_edit_dialog.dart';

final policy = <String, dynamic>{
  'id': 'sale-id',
  'agente_auth_id': 'old-auth',
  'agente_nombre': 'Ana Actual',
  'numero_poliza': 'POL-123',
  'producto': 'Hogar',
  'compania': 'Aseguradora',
  'forma_pago': 'Anual',
  'fecha_efecto': '2026-10-01',
  'precio': 1300,
  'prima_anual': 1300,
  'prima_anual_neta': 1200,
  'prima_anual_bruta': 1300,
  'comision': 120,
  'numero_asegurados': 1,
};
final users = <Map<String, dynamic>>[
  {
    'id': 'old-id',
    'auth_id': 'old-auth',
    'nombre': 'Ana',
    'apellidos': 'Actual',
    'estado': 'activo',
    'rol_usuario': 'agente',
  },
  {
    'id': 'new-id',
    'auth_id': 'new-auth',
    'nombre': 'Luis',
    'apellidos': 'Nuevo',
    'estado': 'activo',
    'parent_id': 'boss-id',
    'rol_usuario': 'agente',
  },
  {
    'id': 'boss-id',
    'auth_id': 'boss-auth',
    'nombre': 'Jefe',
    'apellidos': 'Destino',
    'estado': 'activo',
    'rol_usuario': 'jefe_equipo',
  },
  {
    'id': 'inactive-id',
    'auth_id': 'inactive-auth',
    'nombre': 'Baja',
    'apellidos': 'Agente',
    'estado': 'baja',
  },
];
Future<void> open(
  WidgetTester tester,
  Future<void> Function(Map<String, dynamic>) save,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => PolicyEditDialog(
                policy: policy,
                allowedAuthIds: {'old-auth', 'new-auth'},
                agentsLoader: () async => users,
                saver: save,
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> saveButton(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Guardar cambios'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Guardar cambios'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Cambiar agente confirma auth_id, dependencia y columnas correctas',
    (tester) async {
      Map<String, dynamic>? saved;
      await open(tester, (data) async {
        saved = data;
      });
      await tester.tap(find.text('Cambiar agente'));
      await tester.pumpAndSettle();
      expect(find.text('Baja Agente'), findsNothing);
      expect(find.text('Jefe Destino'), findsNothing);
      await tester.tap(find.text('Luis Nuevo'));
      await tester.pumpAndSettle();
      expect(find.text('Depende de: Jefe Destino'), findsOneWidget);
      await saveButton(tester);
      expect(saved, isNull);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(saved!['agente_auth_id'], 'new-auth');
      expect(saved!['compania'], 'Aseguradora');
      expect(saved!['prima_anual_neta'], 1200);
      expect(saved!['prima_anual_bruta'], 1300);
      expect(saved!['comision'], 120);
      expect(saved!.containsKey('compañia'), isFalse);
      expect(saved!.containsKey('cliente_id'), isFalse);
      expect(saved!.containsKey('numero_poliza'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Editar sin reasignar conserva el agente', (tester) async {
    Map<String, dynamic>? saved;
    await open(tester, (data) async {
      saved = data;
    });
    await saveButton(tester);
    expect(saved!['agente_auth_id'], 'old-auth');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cancelar la confirmación no guarda', (tester) async {
    var calls = 0;
    await open(tester, (data) async {
      calls++;
    });
    await tester.tap(find.text('Cambiar agente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luis Nuevo'));
    await tester.pumpAndSettle();
    await saveButton(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancelar'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Fecha inexistente no se guarda', (tester) async {
    var calls = 0;
    await open(tester, (data) async {
      calls++;
    });
    final input = find.byKey(const ValueKey('policy-edit-fecha_efecto'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, '2026-02-31');
    await saveButton(tester);
    expect(calls, 0);
    expect(find.text('Usa una fecha válida: AAAA-MM-DD.'), findsOneWidget);
  });
}
