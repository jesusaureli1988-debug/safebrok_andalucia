import 'quotation_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/catalogs/insurance_companies.dart';

class CompanyExecutive {
  const CompanyExecutive({
    required this.name,
    this.phone = '',
    this.email = '',
    this.area = '',
  });
  final String name, phone, email, area;
}

class QuotationCompany {
  const QuotationCompany({
    required this.name,
    this.portalUrl = '',
    this.executives = const [],
    this.portalUsername = '',
    this.portalPassword = '',
    this.mediatorCode = '',
    this.management = '',
    this.notes = '',
    this.payments = '',
  });
  final String name, portalUrl, portalUsername, portalPassword;
  final String mediatorCode, management, notes, payments;
  String get displayName => name == 'Fiact' ? 'FIATC' : name;
  String get logoAsset => 'assets/images/companies/${_companyLogos[name]}.png';
  final List<CompanyExecutive> executives;
}

/// Incorporar aquí únicamente los contactos y portales facilitados por SafeBrok.
/// No se utilizan teléfonos genéricos ni enlaces de acceso supuestos.
final quotationCompanies = List<QuotationCompany>.unmodifiable(
  insuranceCompanies.map((name) => QuotationCompany(name: name)),
);

Uri? quotationPortalUri(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

const _companyLogos = <String, String>{
  'Ocaso': 'ocaso',
  'Santalucía': 'santalucia',
  'DKV': 'dkv',
  'Adeslas': 'adeslas',
  'Mapfre': 'mapfre',
  'Generali': 'generali',
  'Helvetia': 'helvetia',
  'Axa': 'axa',
  'Allianz': 'allianz',
  'Zurich': 'zurich',
  'Active': 'active',
  'Aura': 'aura',
  'Occident': 'occident',
  'Fiact': 'fiatc',
  'Asisa': 'asisa',
  'Pelayo': 'pelayo',
  'Reale Seguros': 'reale',
  'Sanitas': 'sanitas',
  'Fidelidade': 'fidelidade',
  'Onlygal': 'onlygal',
  'P. Mallorquina': 'mallorquina',
  'Globality': 'globality',
  'ERGO': 'ergo',
  'Surne': 'surne',
};

Future<QuotationCompany> loadQuotationCompany(QuotationCompany base) async {
  final client = Supabase.instance.client;
  final data = await withQuotationSession<Map<String, dynamic>?>(
    hasSession: () => client.auth.currentSession != null,
    isExpired: () => client.auth.currentSession?.isExpired ?? true,
    refresh: () async {
      await client.auth.refreshSession();
    },
    query: () => client
        .from('cotizaciones_companias')
        .select(
          'portal_url,usuario_portal,clave_portal,ejecutivos,codigo_mediador,gestion,observaciones,formas_pago',
        )
        .eq('compania', base.name)
        .maybeSingle(),
  );
  if (data == null) return base;
  return QuotationCompany(
    name: base.name,
    portalUrl: data['portal_url'] as String? ?? '',
    portalUsername: data['usuario_portal'] as String? ?? '',
    portalPassword: data['clave_portal'] as String? ?? '',
    mediatorCode: data['codigo_mediador'] as String? ?? '',
    management: data['gestion'] as String? ?? '',
    notes: data['observaciones'] as String? ?? '',
    payments: data['formas_pago'] as String? ?? '',
    executives: ((data['ejecutivos'] as List?) ?? []).map((item) {
      final e = Map<String, dynamic>.from(item as Map);
      return CompanyExecutive(
        name: e['nombre'] as String? ?? '',
        phone: e['telefono'] as String? ?? '',
        email: e['email'] as String? ?? '',
        area: e['area'] as String? ?? '',
      );
    }).toList(),
  );
}
