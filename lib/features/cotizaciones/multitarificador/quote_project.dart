import '../quotation_directory.dart';

const quoteLines = ['Decesos', 'Salud', 'Vida'];
int? quoteCents(String text) {
  final clean = text.trim().replaceAll('€', '').replaceAll(' ', '');
  if (!RegExp(r'^\d{1,8}([.,]\d{1,2})?$').hasMatch(clean)) return null;
  final parts = clean.replaceAll(',', '.').split('.');
  final value =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return value > 0 ? value : null;
}

String quoteMoney(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
String quoteDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class ManualQuoteOffer {
  const ManualQuoteOffer({
    required this.company,
    required this.product,
    required this.premiumCents,
    required this.monthly,
    required this.reference,
    required this.coverages,
    required this.limitations,
    required this.enteredAt,
    this.validUntil,
    required this.riskRevision,
  });
  final String company, product, reference, coverages, limitations;
  final int premiumCents, riskRevision;
  final bool monthly;
  final DateTime enteredAt;
  final DateTime? validUntil;
  int get annualEquivalent => premiumCents * (monthly ? 12 : 1);
  bool expired(DateTime now) =>
      validUntil != null &&
      DateTime(now.year, now.month, now.day).isAfter(validUntil!);
  bool currentFor(QuoteProject project, DateTime now) =>
      riskRevision == project.riskRevision && !expired(now);
  Map<String, dynamic> toJson() => {
    'company': company,
    'product': product,
    'premiumCents': premiumCents,
    'monthly': monthly,
    'reference': reference,
    'coverages': coverages,
    'limitations': limitations,
    'enteredAt': enteredAt.toIso8601String(),
    'validUntil': validUntil?.toIso8601String(),
    'riskRevision': riskRevision,
    'source': 'manual',
  };
  factory ManualQuoteOffer.fromJson(Map<String, dynamic> data) =>
      ManualQuoteOffer(
        company: data['company'] as String,
        product: data['product'] as String,
        premiumCents: data['premiumCents'] as int,
        monthly: data['monthly'] as bool,
        reference: data['reference'] as String? ?? '',
        coverages: data['coverages'] as String? ?? '',
        limitations: data['limitations'] as String? ?? '',
        enteredAt: DateTime.parse(data['enteredAt'] as String),
        validUntil: DateTime.tryParse(data['validUntil'] as String? ?? ''),
        riskRevision: data['riskRevision'] as int? ?? 1,
      );
}

class QuoteProject {
  QuoteProject({
    this.id,
    this.version = 1,
    this.title = '',
    this.line = 'Decesos',
    this.postalCode = '',
    this.modality = '',
    this.capital = '',
    DateTime? effectDate,
    List<DateTime>? births,
    List<String>? companies,
    List<ManualQuoteOffer>? offers,
    this.riskRevision = 1,
  }) : effectDate = effectDate ?? DateTime.now().add(const Duration(days: 1)),
       births = births ?? [],
       companies = companies ?? [],
       offers = offers ?? [];
  String? id;
  int version, riskRevision;
  String title, line, postalCode, modality, capital;
  DateTime effectDate;
  final List<DateTime> births;
  final List<String> companies;
  final List<ManualQuoteOffer> offers;
  void riskChanged() {
    riskRevision++;
  }

  List<ManualQuoteOffer> comparableOffers(DateTime now) =>
      offers
          .where(
            (o) => companies.contains(o.company) && o.currentFor(this, now),
          )
          .toList()
        ..sort((a, b) => a.annualEquivalent.compareTo(b.annualEquivalent));
  Map<String, dynamic> toJson() => {
    'title': title,
    'line': line,
    'postalCode': postalCode,
    'modality': modality,
    'capital': capital,
    'effectDate': effectDate.toIso8601String(),
    'births': births.map((d) => d.toIso8601String()).toList(),
    'companies': companies,
    'offers': offers.map((o) => o.toJson()).toList(),
    'riskRevision': riskRevision,
  };
  factory QuoteProject.fromJson(
    Map<String, dynamic> data, {
    String? id,
    int version = 1,
  }) => QuoteProject(
    id: id,
    version: version,
    title: data['title'] as String? ?? '',
    line: data['line'] as String? ?? 'Decesos',
    postalCode: data['postalCode'] as String? ?? '',
    modality: data['modality'] as String? ?? '',
    capital: data['capital'] as String? ?? '',
    effectDate: DateTime.tryParse(data['effectDate'] as String? ?? ''),
    births: ((data['births'] as List?) ?? [])
        .map((d) => DateTime.parse(d as String))
        .toList(),
    companies: List<String>.from(data['companies'] as List? ?? []),
    offers: ((data['offers'] as List?) ?? [])
        .map(
          (o) => ManualQuoteOffer.fromJson(Map<String, dynamic>.from(o as Map)),
        )
        .toList(),
    riskRevision: data['riskRevision'] as int? ?? 1,
  );
  QuoteProject copy() =>
      QuoteProject.fromJson(toJson(), id: id, version: version);
}

/// Cada integración futura debe declarar productos y operar contra nuestro servidor.
/// Ninguna compañía está habilitada por API por tener un usuario de portal.
abstract interface class InsuranceQuoteConnector {
  String get company;
  Set<String> get lines;
  Future<List<ManualQuoteOffer>> quote(QuoteProject project);
}

final List<InsuranceQuoteConnector> enabledQuoteConnectors = List.unmodifiable(
  [],
);
List<QuotationCompany> get quoteCompanyDirectory => quotationCompanies;
