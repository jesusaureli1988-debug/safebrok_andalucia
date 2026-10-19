import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/features/cotizaciones/multitarificador/quote_project.dart';
import 'package:safebrok_andalucia/features/cotizaciones/multitarificador/quote_repository.dart';
import 'package:safebrok_andalucia/features/cotizaciones/multitarificador/multitarificador_screen.dart';

class MemoryQuotes implements QuoteProjectRepository {
  final List<QuoteProject> saved = [];
  bool fail = false;
  @override
  Future<List<QuoteProject>> list() async =>
      saved.map((p) => p.copy()).toList();
  @override
  Future<QuoteProject> save(QuoteProject project) async {
    if (fail) throw StateError('Fallo de prueba');
    final copy = project.copy()
      ..id = 'test-project'
      ..title = (project.title.isEmpty
          ? 'Proyecto de ${project.line}'
          : project.title);
    saved
      ..clear()
      ..add(copy);
    return copy.copy();
  }
}

ManualQuoteOffer offer(
  String company,
  int cents, {
  bool monthly = false,
  int revision = 1,
  DateTime? until,
}) => ManualQuoteOffer(
  company: company,
  product: 'Producto de prueba',
  premiumCents: cents,
  monthly: monthly,
  reference: 'TEST',
  coverages: 'Garantías de prueba',
  limitations: 'Límites de prueba',
  enteredAt: DateTime(2026, 10, 18),
  validUntil: until,
  riskRevision: revision,
);
void main() {
  test('Importes exactos sin coma flotante y comparación anual homogénea', () {
    expect(quoteCents('24,90'), 2490);
    expect(quoteCents('24.9'), 2490);
    expect(quoteCents('-1'), isNull);
    expect(quoteCents('0'), isNull);
    expect(quoteCents('1.234,00'), isNull);
    final project = QuoteProject(
      companies: ['Aura', 'Helvetia'],
      offers: [offer('Aura', 2490, monthly: true), offer('Helvetia', 30000)],
    );
    expect(
      project.comparableOffers(DateTime(2026, 10, 18)).first.annualEquivalent,
      29880,
    );
    project.riskChanged();
    expect(project.comparableOffers(DateTime(2026, 10, 18)), isEmpty);
  });
  test('Vigencia incluye el día final y copia no altera el original', () {
    final project = QuoteProject(
      companies: ['Aura'],
      offers: [offer('Aura', 100, until: DateTime(2026, 10, 18))],
    );
    expect(project.comparableOffers(DateTime(2026, 10, 18, 23)).length, 1);
    expect(project.comparableOffers(DateTime(2026, 10, 19)), isEmpty);
    final copy = project.copy();
    copy.companies.add('Helvetia');
    copy.offers.clear();
    expect(project.companies.length, 1);
    expect(project.offers.length, 1);
  });
  testWidgets('Crear proyecto, guardar y volver a abrirlo', (tester) async {
    final repo = MemoryQuotes();
    await tester.pumpWidget(
      MaterialApp(home: MultitarificadorScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-quote-project')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Cliente de prueba');
    await tester.tap(find.byKey(const Key('save-quote-project')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.title, 'Cliente de prueba');
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.text('Cliente de prueba'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cliente de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente de prueba'));
    await tester.pumpAndSettle();
    expect(find.text('Proyecto de cotización'), findsOneWidget);
    expect(find.text('Cliente de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Añadir presupuesto y comparar; cambiar riesgo invalida el anterior',
    (tester) async {
      final project = QuoteProject(companies: ['Aura', 'Helvetia']);
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteProjectScreen(
            repository: MemoryQuotes(),
            project: project,
          ),
        ),
      );
      await tester.tap(find.text('Presupuestos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-manual-offer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('offer-product')),
        'Decesos ejemplo',
      );
      await tester.enterText(find.byKey(const Key('offer-amount')), '125,50');
      await tester.tap(find.byKey(const Key('confirm-manual-offer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comparativa'));
      await tester.pumpAndSettle();
      expect(
        find.text('1 presupuestos no caducados del riesgo actual.'),
        findsOneWidget,
      );
      expect(find.text('Decesos ejemplo'), findsOneWidget);
      await tester.tap(find.text('Datos'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Código postal del riesgo',
        ),
        '41001',
      );
      await tester.tap(find.text('Comparativa'));
      await tester.pumpAndSettle();
      expect(
        find.text('0 presupuestos no caducados del riesgo actual.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Fallo al guardar conserva cambios y permite reintentar', (
    tester,
  ) async {
    final repo = MemoryQuotes()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: QuoteProjectScreen(repository: repo, project: QuoteProject()),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Proyecto no perdido');
    await tester.tap(find.byKey(const Key('save-quote-project')));
    await tester.pumpAndSettle();
    expect(find.text('Proyecto no perdido'), findsOneWidget);
    expect(repo.saved, isEmpty);
    repo.fail = false;
    await tester.tap(find.byKey(const Key('save-quote-project')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.title, 'Proyecto no perdido');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Móvil: datos y selección de compañías sin desbordamientos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: QuoteProjectScreen(
          repository: MemoryQuotes(),
          project: QuoteProject(),
        ),
      ),
    );
    final select = find.byKey(const Key('select-quote-companies'));
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.text('Compañías a consultar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Salir de proyecto modificado permite descartar sin guardar', (
    tester,
  ) async {
    final repo = MemoryQuotes();
    await tester.pumpWidget(
      MaterialApp(home: MultitarificadorScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-quote-project')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Borrador descartado');
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Mis proyectos'), findsOneWidget);
    expect(repo.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
