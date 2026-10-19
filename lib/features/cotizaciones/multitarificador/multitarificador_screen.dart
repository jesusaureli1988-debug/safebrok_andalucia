import 'package:flutter/material.dart';
import '../../../core/auth/login_screen.dart';
import '../cotizaciones_screen.dart' show QuotationCompanyScreen;
import '../quotation_directory.dart';
import '../quotation_session.dart';
import 'quote_project.dart';
import 'quote_repository.dart';

const _navy = Color(0xFF12364A), _teal = Color(0xFF087F86);

class MultitarificadorScreen extends StatefulWidget {
  const MultitarificadorScreen({super.key, this.repository});
  final QuoteProjectRepository? repository;
  @override
  State<MultitarificadorScreen> createState() => _MultitarificadorScreenState();
}

class _MultitarificadorScreenState extends State<MultitarificadorScreen> {
  late final QuoteProjectRepository repository =
      widget.repository ?? SupabaseQuoteProjectRepository();
  late Future<List<QuoteProject>> projects = repository.list();
  Future<void> open([QuoteProject? project]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuoteProjectScreen(
          repository: repository,
          project: project ?? QuoteProject(),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        projects = repository.list();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F7FA),
    appBar: AppBar(title: const Text('Multitarificador')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('new-quote-project'),
      onPressed: () => open(),
      icon: const Icon(Icons.add),
      label: const Text('Nueva cotización'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_navy, _teal]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.compare_arrows, color: Colors.white, size: 34),
                  SizedBox(height: 12),
                  Text(
                    'Tu multitarificador SafeBrok',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Un proyecto por cliente. Prepara el riesgo, incorpora presupuestos y compara sus condiciones.',
                    style: TextStyle(color: Colors.white, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Primera fase: presupuestos introducidos desde los portales. Todavía no hay compañías conectadas para obtener precios automáticamente.',
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Mis proyectos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tus últimos 100 proyectos guardados. Solo son visibles en tu cuenta.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<QuoteProject>>(
              future: projects,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _LoadError(
                    error: snapshot.error!,
                    retry: () => setState(() {
                      projects = repository.list();
                    }),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.data!.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(26),
                      child: Text(
                        'Aún no tienes proyectos. Pulsa Nueva cotización para preparar el primero.',
                      ),
                    ),
                  );
                }
                return Column(
                  children: snapshot.data!
                      .map(
                        (p) => Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.description_outlined,
                              color: _teal,
                            ),
                            title: Text(p.title),
                            subtitle: Text(
                              '${p.line} · ${p.offers.length} presupuestos · Efecto ${quoteDate(p.effectDate)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open(p),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) {
    final auth = error is QuotationSessionRequired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              auth
                  ? 'Vuelve a iniciar sesión en SafeBrok para acceder a tus cotizaciones.'
                  : 'No se han podido cargar tus proyectos. Comprueba la conexión.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: auth
                  ? () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                      (_) => false,
                    )
                  : retry,
              child: Text(auth ? 'Iniciar sesión' : 'Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class QuoteProjectScreen extends StatefulWidget {
  const QuoteProjectScreen({
    super.key,
    required this.repository,
    required this.project,
  });
  final QuoteProjectRepository repository;
  final QuoteProject project;
  @override
  State<QuoteProjectScreen> createState() => _QuoteProjectScreenState();
}

class _QuoteProjectScreenState extends State<QuoteProjectScreen> {
  late QuoteProject project = widget.project.copy();
  late final title = TextEditingController(text: project.title);
  late final postal = TextEditingController(text: project.postalCode);
  late final modality = TextEditingController(text: project.modality);
  late final capital = TextEditingController(text: project.capital);
  bool dirty = false, saving = false;
  int tab = 0;
  @override
  void dispose() {
    title.dispose();
    postal.dispose();
    modality.dispose();
    capital.dispose();
    super.dispose();
  }

  void changed({bool risk = false}) => setState(() {
    dirty = true;
    if (risk) project.riskChanged();
  });
  void sync() {
    project.title = title.text.trim();
    project.postalCode = postal.text.trim();
    project.modality = modality.text.trim();
    project.capital = capital.text.trim();
  }

  Future<bool> save() async {
    if (saving) return false;
    sync();
    if (project.title.length > 180 || project.modality.length > 1000) {
      message('El nombre o las preferencias son demasiado largos.');
      return false;
    }
    if (project.postalCode.isNotEmpty &&
        !RegExp(r'^\d{5}$').hasMatch(project.postalCode)) {
      message('El código postal debe tener cinco cifras.');
      return false;
    }
    if (project.capital.isNotEmpty && quoteCents(project.capital) == null) {
      message(
        'Revisa el capital solicitado. Usa un importe positivo sin separadores de miles.',
      );
      return false;
    }
    setState(() => saving = true);
    try {
      final saved = await widget.repository.save(project.copy());
      if (!mounted) return false;
      setState(() {
        project = saved;
        dirty = false;
        saving = false;
      });
      message('Proyecto guardado');
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        message(
          error is QuotationSessionRequired
              ? 'Tu sesión ha caducado. Vuelve a entrar en SafeBrok.'
              : error is StateError
              ? error.message.toString()
              : 'No se pudo guardar. Conservamos tus cambios en esta pantalla; vuelve a intentarlo.',
        );
      }
      return false;
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> leave() async {
    if (saving) return;
    if (!dirty) {
      Navigator.pop(context);
      return;
    }
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text('¿Quieres guardar el proyecto antes de salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Salir sin guardar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Guardar y salir'),
          ),
        ],
      ),
    );
    if (answer == 'save' && !await save()) return;
    if (mounted && (answer == 'save' || answer == 'discard')) {
      setState(() => dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> pickCompanies() async {
    final selected = project.companies.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Compañías a consultar'),
          content: SizedBox(
            width: 440,
            height: 400,
            child: ListView(
              children: quoteCompanyDirectory
                  .map(
                    (c) => CheckboxListTile(
                      title: Text(c.displayName),
                      value: selected.contains(c.name),
                      onChanged: (value) => setDialog(() {
                        value == true
                            ? selected.add(c.name)
                            : selected.remove(c.name);
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        project.companies
          ..clear()
          ..addAll(result);
        dirty = true;
      });
    }
  }

  Future<void> addOffer() async {
    sync();
    if (project.companies.isEmpty) {
      message('Selecciona primero las compañías que quieres consultar.');
      setState(() => tab = 0);
      return;
    }
    if (project.offers.length >= 50) {
      message('Este proyecto admite hasta 50 presupuestos.');
      return;
    }
    final offer = await showDialog<ManualQuoteOffer>(
      context: context,
      builder: (_) => _OfferDialog(project: project),
    );
    if (offer != null && mounted) {
      setState(() {
        project.offers.add(offer);
        dirty = true;
      });
    }
  }

  Future<void> birth() async {
    if (project.births.length >= 8) {
      message('Esta primera versión admite hasta ocho asegurados.');
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 35, now.month, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Nacimiento del asegurado',
    );
    if (date != null && mounted) {
      setState(() {
        project.births.add(date);
        project.riskChanged();
        dirty = true;
      });
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool risk = false,
    TextInputType? keyboard,
    int maxLength = 180,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onChanged: (_) => changed(risk: risk),
    ),
  );
  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _navy,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: saving ? null : leave,
        ),
        title: Text(
          project.id == null ? 'Nueva cotización' : 'Proyecto de cotización',
        ),
        actions: [
          TextButton.icon(
            key: const Key('save-quote-project'),
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                if (saving) const LinearProgressIndicator(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in [
                      (0, 'Datos'),
                      (1, 'Presupuestos'),
                      (2, 'Comparativa'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: tab == entry.$1,
                        onSelected: (_) => setState(() => tab = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (tab == 0) ...[
                  section('1. Cliente y riesgo', [
                    field(title, 'Nombre o referencia del cliente'),
                    DropdownButtonFormField<String>(
                      initialValue: project.line,
                      decoration: const InputDecoration(labelText: 'Ramo'),
                      items: quoteLines
                          .map(
                            (l) => DropdownMenuItem(value: l, child: Text(l)),
                          )
                          .toList(),
                      onChanged: (line) {
                        if (line != null && line != project.line) {
                          project.line = line;
                          changed(risk: true);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    field(
                      postal,
                      'Código postal del riesgo',
                      risk: true,
                      keyboard: TextInputType.number,
                      maxLength: 5,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        'Fecha de efecto: ${quoteDate(project.effectDate)}',
                      ),
                      onPressed: () async {
                        final now = DateTime.now(),
                            first = DateUtils.dateOnly(DateTime.now());
                        final date = await showDatePicker(
                          context: context,
                          initialDate: project.effectDate.isBefore(first)
                              ? now
                              : project.effectDate,
                          firstDate: first,
                          lastDate: DateTime(now.year + 5),
                          helpText: 'Fecha de efecto solicitada',
                        );
                        if (date != null &&
                            mounted &&
                            date != project.effectDate) {
                          project.effectDate = date;
                          changed(risk: true);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    field(
                      modality,
                      project.line == 'Salud'
                          ? 'Preferencias: copago, hospitalización…'
                          : project.line == 'Decesos'
                          ? 'Modalidad o prestaciones solicitadas'
                          : 'Modalidad solicitada',
                      risk: true,
                      maxLength: 1000,
                    ),
                    if (project.line == 'Vida')
                      field(
                        capital,
                        'Capital solicitado (€)',
                        risk: true,
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    const Text(
                      'Asegurados',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (var i = 0; i < project.births.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Asegurado ${i + 1} · ${quoteDate(project.births[i])}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Quitar asegurado',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            project.births.removeAt(i);
                            changed(risk: true);
                          },
                        ),
                      ),
                    TextButton.icon(
                      onPressed: birth,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Añadir fecha de nacimiento'),
                    ),
                    const Text(
                      'La aseguradora puede requerir datos adicionales antes de emitir un precio o aceptar el riesgo.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ]),
                  section('2. Compañías', [
                    OutlinedButton.icon(
                      key: const Key('select-quote-companies'),
                      onPressed: pickCompanies,
                      icon: const Icon(Icons.business),
                      label: const Text('Seleccionar compañías'),
                    ),
                    const SizedBox(height: 12),
                    if (project.companies.isEmpty)
                      const Text(
                        'Todavía no has seleccionado ninguna compañía.',
                      ),
                    for (final name in project.companies)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(QuotationCompany(name: name).displayName),
                        subtitle: const Text(
                          'Consulta manual · API pendiente de habilitar',
                        ),
                        trailing: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => QuotationCompanyScreen(
                                company: QuotationCompany(name: name),
                              ),
                            ),
                          ),
                          child: const Text('Abrir ficha'),
                        ),
                      ),
                  ]),
                  if (project.offers.any(
                    (o) => o.riskRevision != project.riskRevision,
                  ))
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Has cambiado el riesgo. Los presupuestos anteriores quedan fuera de la comparativa; incorpora precios actualizados.',
                        ),
                      ),
                    ),
                ],
                if (tab == 1) ...[
                  section('Presupuestos del proyecto', [
                    const Text(
                      'Introduce el importe total del presupuesto obtenido en el portal. No se calculan precios estimados ni se envían datos a las compañías.',
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const Key('add-manual-offer'),
                      onPressed: addOffer,
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir presupuesto'),
                    ),
                    if (project.offers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('Aún no hay presupuestos para comparar.'),
                      ),
                  ]),
                  for (var i = 0; i < project.offers.length; i++)
                    offerCard(project.offers[i], index: i),
                ],
                if (tab == 2) ...comparison(),
                const SizedBox(height: 12),
                Text(
                  dirty
                      ? 'Cambios sin guardar'
                      : 'Proyecto ${project.id == null ? 'sin guardar' : 'guardado'}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget offerCard(ManualQuoteOffer offer, {int? index}) {
    final current = offer.currentFor(project, DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    QuotationCompany(name: offer.company).displayName,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ),
                if (index != null)
                  IconButton(
                    tooltip: 'Quitar presupuesto del proyecto',
                    onPressed: () {
                      project.offers.removeAt(index);
                      changed();
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Text(
              offer.product,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              '${quoteMoney(offer.premiumCents)} / ${offer.monthly ? 'mes' : 'año'}',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: _teal,
              ),
            ),
            Text(
              '${quoteMoney(offer.annualEquivalent)} al año${offer.monthly ? ' · equivalente a 12 mensualidades' : ''}',
            ),
            const SizedBox(height: 10),
            const Text(
              'Origen: presupuesto introducido manualmente',
              style: TextStyle(color: Colors.blueGrey),
            ),
            if (offer.reference.isNotEmpty)
              Text('Referencia: ${offer.reference}'),
            Text('Introducido el ${quoteDate(offer.enteredAt)}'),
            Text(
              offer.validUntil == null
                  ? 'Vigencia no facilitada'
                  : 'Válido hasta ${quoteDate(offer.validUntil!)}',
            ),
            if (!current)
              Text(
                offer.expired(DateTime.now())
                    ? 'Caducado · fuera de la comparativa'
                    : 'Riesgo modificado · necesita nueva cotización',
                style: const TextStyle(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const Divider(height: 26),
            const Text(
              'Coberturas',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(offer.coverages.isEmpty ? 'No facilitadas' : offer.coverages),
            const SizedBox(height: 10),
            const Text(
              'Franquicias, carencias y limitaciones',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              offer.limitations.isEmpty ? 'No facilitadas' : offer.limitations,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> comparison() {
    final offers = project.comparableOffers(DateTime.now());
    return [
      section('Comparativa de presupuestos', [
        Text('${offers.length} presupuestos no caducados del riesgo actual.'),
        const SizedBox(height: 8),
        const Text(
          'Ordenados por coste anual equivalente. El precio no determina por sí solo qué seguro se adapta al cliente; revisa coberturas, límites y modalidad.',
        ),
        if (offers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text('Añade presupuestos en la pestaña Presupuestos.'),
          ),
        if (offers.length == 1)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'Añade otro presupuesto para poder contrastar ofertas.',
            ),
          ),
      ]),
      ...offers.map((o) => offerCard(o)),
    ];
  }
}

class _OfferDialog extends StatefulWidget {
  const _OfferDialog({required this.project});
  final QuoteProject project;
  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  late String company = widget.project.companies.first;
  final form = GlobalKey<FormState>();
  final product = TextEditingController(),
      amount = TextEditingController(),
      reference = TextEditingController(),
      covers = TextEditingController(),
      limits = TextEditingController();
  bool monthly = false;
  DateTime? until;
  @override
  void dispose() {
    for (final c in [product, amount, reference, covers, limits]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Añadir presupuesto real'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: company,
                decoration: const InputDecoration(labelText: 'Compañía'),
                items: widget.project.companies
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(QuotationCompany(name: c).displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => company = value!),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('offer-product'),
                controller: product,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Producto y modalidad del presupuesto',
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Indica el producto' : null,
              ),
              TextFormField(
                key: const Key('offer-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Importe total (€)',
                  helperText:
                      'Con impuestos y recargos del presupuesto, sin separadores de miles',
                ),
                validator: (v) => quoteCents(v ?? '') == null
                    ? 'Introduce un importe positivo, por ejemplo 24,90'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(monthly ? 'Importe mensual' : 'Importe anual'),
                value: monthly,
                onChanged: (v) => setState(() => monthly = v),
              ),
              TextField(
                controller: reference,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Referencia del presupuesto (opcional)',
                ),
              ),
              TextField(
                controller: covers,
                maxLines: 3,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Coberturas del presupuesto',
                ),
              ),
              TextField(
                controller: limits,
                maxLines: 3,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Franquicias, carencias y limitaciones',
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text(
                  until == null
                      ? 'Indicar validez (opcional)'
                      : 'Válido hasta ${quoteDate(until!)}',
                ),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        until ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateUtils.dateOnly(DateTime.now()),
                    lastDate: DateTime(DateTime.now().year + 5),
                  );
                  if (date != null && mounted) setState(() => until = date);
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('confirm-manual-offer'),
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            ManualQuoteOffer(
              company: company,
              product: product.text.trim(),
              premiumCents: quoteCents(amount.text)!,
              monthly: monthly,
              reference: reference.text.trim(),
              coverages: covers.text.trim(),
              limitations: limits.text.trim(),
              enteredAt: DateTime.now(),
              validUntil: until,
              riskRevision: widget.project.riskRevision,
            ),
          );
        },
        child: const Text('Añadir'),
      ),
    ],
  );
}
