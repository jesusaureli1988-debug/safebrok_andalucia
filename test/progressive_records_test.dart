import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/widgets/progressive_records.dart';

void main() {
  testWidgets('La cuadrícula también crece por bloques de diez', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressiveGridView.builder(
            itemCount: 31,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 150,
            ),
            itemBuilder: (_, i) => Text('Documento $i'),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<GridView>(find.byType(GridView))
          .childrenDelegate
          .estimatedChildCount,
      10,
    );
    await tester.drag(find.byType(GridView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GridView>(find.byType(GridView))
          .childrenDelegate
          .estimatedChildCount,
      greaterThan(10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Los filtros horizontales no pierden opciones', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 60,
            child: ProgressiveListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 35,
              itemBuilder: (_, i) => SizedBox(width: 100, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ListView>(find.byType(ListView))
          .childrenDelegate
          .estimatedChildCount,
      35,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Carga más si diez filas no llenan una pantalla grande', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressiveListView.builder(
            itemCount: 100,
            itemExtent: 20,
            itemBuilder: (_, i) => Text('$i'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final count = tester
        .widget<ListView>(find.byType(ListView))
        .childrenDelegate
        .estimatedChildCount!;
    expect(count, greaterThan(10));
    expect(count, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('El listado empieza con diez y amplía al bajar', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressiveListView.builder(
            controller: controller,
            itemCount: 35,
            itemExtent: 100,
            itemBuilder: (_, i) => Text('Fila $i'),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ListView>(find.byType(ListView))
          .childrenDelegate
          .estimatedChildCount,
      10,
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<ListView>(find.byType(ListView))
          .childrenDelegate
          .estimatedChildCount,
      20,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('La tabla solo construye diez filas y conserva el total', (
    tester,
  ) async {
    var built = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProgressiveRecords(
              count: 4000,
              showFooter: true,
              builder: (_, visible) {
                built = visible;
                return DataTable(
                  columns: const [DataColumn(label: Text('Póliza'))],
                  rows: List.generate(
                    visible,
                    (i) => DataRow(cells: [DataCell(Text('$i'))]),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(built, 10);
    expect(find.text('Mostrar 10 más · 10 de 4000'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextButton));
    await tester.pump();
    expect(built, greaterThanOrEqualTo(10));
    expect(built, lessThan(4000));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'El sliver amplía sin errores de layout y vuelve a diez al filtrar',
    (tester) async {
      final controller = ScrollController();
      Widget page(Object filter, int count) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              ProgressiveSliverList.builder(
                resetKey: filter,
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(height: 100, child: Text('Póliza $i')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page('todos', 31));
      expect(
        tester
            .widget<SliverList>(find.byType(SliverList))
            .delegate
            .estimatedChildCount,
        10,
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<SliverList>(find.byType(SliverList))
            .delegate
            .estimatedChildCount,
        20,
      );
      controller.jumpTo(0);
      await tester.pumpWidget(page('otros', 31));
      expect(
        tester
            .widget<SliverList>(find.byType(SliverList))
            .delegate
            .estimatedChildCount,
        10,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('Listados pequeños y vacíos no agregan filas', (tester) async {
    for (final count in [0, 3, 10]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressiveListView.separated(
              itemCount: count,
              itemBuilder: (_, i) => Text('Fila $i'),
              separatorBuilder: (_, __) => const Divider(),
            ),
          ),
        ),
      );
      expect(find.text('Fila 10'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
