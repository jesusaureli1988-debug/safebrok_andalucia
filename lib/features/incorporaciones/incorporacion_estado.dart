/// Separates awaiting a signature from awaiting Administration's confirmation.
/// A signed upload does not itself confirm the contract or complete the hire.
String incorporacionEstadoVisible(Map<String, dynamic> expediente) {
  final estado = expediente['estado']?.toString() ?? '';
  if (estado != 'PENDIENTE_FIRMA' && estado != 'CONTRATO_DISPONIBLE') {
    return estado;
  }
  final documentos = List<Map<String, dynamic>>.from(
    expediente['documentos'] ?? const [],
  );
  final firmadoSubido = documentos.any(
    (doc) => doc['tipo'] == 'CONTRATO_FIRMADO' && doc['estado'] == 'SUBIDO',
  );
  return firmadoSubido ? 'PENDIENTE_CONFIRMACION' : estado;
}
