import 'package:safebrok_andalucia/features/cotizaciones/quotation_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/catalogs/insurance_companies.dart';
import 'package:safebrok_andalucia/features/cotizaciones/quotation_directory.dart';
import 'package:safebrok_andalucia/features/cotizaciones/cotizaciones_screen.dart';

void main() {
  test('Catálogo compartido y portales HTTPS sin credenciales', () {
    expect(
      quotationCompanies.map((c) => c.name),
      containsAll(insuranceCompanies),
    );
    expect(quotationCompanies.length, 24);
    expect(insuranceCompanies.toSet().length, 24);
    expect(quotationPortalUri('javascript:alert(1)'), isNull);
    expect(quotationPortalUri('https://user:password@example.com'), isNull);
    expect(
      quotationPortalUri('https://example.com/portal')?.host,
      'example.com',
    );
  });
  testWidgets(
    'Buscar compañía y abrir ficha pendiente sin inventar contactos',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: CotizacionesScreen(loadCompany: (c) async => c)),
      );
      await tester.enterText(
        find.byKey(const Key('quotation-search')),
        'helvetia',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 compañía'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quotation-Helvetia')));
      await tester.pumpAndSettle();
      expect(find.text('Ejecutivos de la compañía'), findsOneWidget);
      expect(
        find.text('Todavía no hay contactos incorporados'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Entrar al portal'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Ficha preparada para varios ejecutivos y portal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationCompanyScreen(
          loadCompany: (c) async => c,
          company: QuotationCompany(
            name: 'Compañía de prueba',
            portalUrl: 'https://example.com/portal',
            executives: [
              CompanyExecutive(
                name: 'Ejecutivo de prueba',
                phone: '+34 600 000 000',
                email: 'ejecutivo@example.com',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ejecutivo de prueba'), findsOneWidget);
    expect(find.text('ejecutivo@example.com'), findsOneWidget);
    expect(find.text('+34 600 000 000'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Entrar al portal'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Credenciales ocultas y datos cargados desde servidor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationCompanyScreen(
          company: const QuotationCompany(name: 'Asisa'),
          loadCompany: (c) async => const QuotationCompany(
            name: 'Asisa',
            portalUrl: 'https://example.com/mediadores',
            portalUsername: 'usuario_prueba',
            portalPassword: 'clave_solo_test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('usuario_prueba'), findsOneWidget);
    expect(find.text('clave_solo_test'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('clave_solo_test'), findsOneWidget);
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('clave_solo_test'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Error de carga muestra Reintentar y se recupera', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationCompanyScreen(
          company: const QuotationCompany(name: 'Asisa'),
          loadCompany: (c) async {
            if (attempts++ == 0) throw Exception('red');
            return c;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Portal de tarificación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Sesión caducada muestra acceso en lugar del error genérico', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationCompanyScreen(
          company: const QuotationCompany(name: 'Asisa'),
          loadCompany: (_) async => throw const QuotationSessionRequired(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(
      find.textContaining('Tu sesión de SafeBrok ha caducado'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Ficha incluye código, gestión, observaciones y pagos; no inventa clave',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationCompanyScreen(
            company: const QuotationCompany(name: 'Santalucía'),
            loadCompany: (_) async => const QuotationCompany(
              name: 'Santalucía',
              portalUsername: 'usuario_sin_clave',
              mediatorCode: 'MED-TEST',
              management: 'gestion@example.com',
              notes: 'Observación de prueba',
              payments: 'Transferencia de prueba',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No facilitada'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Código de mediador'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MED-TEST'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Formas de pago'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Transferencia de prueba'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
