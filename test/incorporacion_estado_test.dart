import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/features/incorporaciones/incorporacion_estado.dart';

void main() {
  Map<String, dynamic> row(String state, {String? tipo, String? docState}) => {
    'estado': state,
    'documentos': [
      if (tipo != null) {'tipo': tipo, 'estado': docState},
    ],
  };
  for (final state in ['PENDIENTE_FIRMA', 'CONTRATO_DISPONIBLE']) {
    test('$state con firmado subido espera confirmación', () {
      expect(
        incorporacionEstadoVisible(
          row(state, tipo: 'CONTRATO_FIRMADO', docState: 'SUBIDO'),
        ),
        'PENDIENTE_CONFIRMACION',
      );
    });
    test('$state sin contrato firmado no cambia', () {
      expect(incorporacionEstadoVisible(row(state)), state);
      expect(
        incorporacionEstadoVisible(
          row(state, tipo: 'CONTRATO', docState: 'SUBIDO'),
        ),
        state,
      );
    });
    test('$state con firmado rechazado no espera confirmación', () {
      expect(
        incorporacionEstadoVisible(
          row(
            state,
            tipo: 'CONTRATO_FIRMADO',
            docState: 'CORRECCION_REQUERIDA',
          ),
        ),
        state,
      );
    });
  }
  for (final state in [
    'CONTRATO_FIRMADO',
    'ALTA_COMPLETADA',
    'DESCARTADO',
    'DOCUMENTACION_VALIDADA',
  ]) {
    test('no altera $state aunque conserve el contrato firmado', () {
      expect(
        incorporacionEstadoVisible(
          row(state, tipo: 'CONTRATO_FIRMADO', docState: 'SUBIDO'),
        ),
        state,
      );
    });
  }
}
