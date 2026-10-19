import 'avant2_access.dart';
import 'multitarificador/multitarificador_screen.dart';
import '../../core/auth/login_screen.dart';
import 'quotation_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'quotation_directory.dart';

const _navy = Color(0xFF12364A);
const _teal = Color(0xFF087F86);

class CotizacionesScreen extends StatefulWidget {
  const CotizacionesScreen({super.key, this.loadCompany});
  final Future<QuotationCompany> Function(QuotationCompany)? loadCompany;
  @override
  State<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends State<CotizacionesScreen> {
  String search = '';
  String normalized(String s) => s
      .toLowerCase()
      .replaceAll('í', 'i')
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  @override
  Widget build(BuildContext context) {
    final companies =
        quotationCompanies
            .where(
              (c) =>
                  normalized(c.displayName).contains(normalized(search.trim())),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      appBar: AppBar(title: const Text('Cotizaciones')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_navy, _teal],
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.calculate_outlined,
                              color: Colors.white,
                              size: 32,
                            ),
                            SizedBox(height: 14),
                            Text(
                              'Todas tus compañías, en un lugar',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Accede a sus portales de tarificación y contacta con sus ejecutivos.',
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      Card(
                        color: Colors.white,
                        child: ListTile(
                          key: const Key('open-avant2'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: const Icon(
                            Icons.open_in_browser_rounded,
                            color: _teal,
                            size: 30,
                          ),
                          title: const Text(
                            'Avant2',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          subtitle: const Text('Acceso directo al portal'),
                          trailing: const Icon(Icons.open_in_new, color: _teal),
                          onTap: () => openAvant2(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('open-multitarificador'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const MultitarificadorScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.compare_arrows),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Abrir multitarificador'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('quotation-search'),
                        onChanged: (v) => setState(() => search = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar compañía',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${companies.length} ${companies.length == 1 ? 'compañía' : 'compañías'}',
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (companies.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No hay compañías con ese nombre.'),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.crossAxisExtent >= 900
                          ? 3
                          : constraints.crossAxisExtent >= 560
                          ? 2
                          : 1,
                      mainAxisExtent:
                          190 *
                          MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final company = companies[index];
                      return Card(
                        color: Colors.white,
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFE0E8ED)),
                        ),
                        child: InkWell(
                          key: ValueKey('quotation-${company.name}'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => QuotationCompanyScreen(
                                company: company,
                                loadCompany: widget.loadCompany,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color:
                                            const [
                                              'Pelayo',
                                              'Globality',
                                            ].contains(company.name)
                                            ? _navy
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Image.asset(
                                        company.logoAsset,
                                        width: 200,
                                        height: 82,
                                        fit: BoxFit.contain,
                                        semanticLabel:
                                            'Logo de ${company.displayName}',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  company.displayName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: companies.length),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotationCompanyDetails extends StatefulWidget {
  const _QuotationCompanyDetails({required this.company});
  final QuotationCompany company;
  @override
  State<_QuotationCompanyDetails> createState() =>
      _QuotationCompanyDetailsState();
}

class _QuotationCompanyDetailsState extends State<_QuotationCompanyDetails> {
  bool showPassword = false;
  QuotationCompany get company => widget.company;
  Future<void> open(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No disponible');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se ha podido abrir el enlace. Puedes copiarlo e intentarlo desde otra aplicación.',
            ),
          ),
        );
      }
    }
  }

  Future<void> copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copiado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final portal = quotationPortalUri(company.portalUrl);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      appBar: AppBar(title: Text(company.displayName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                company.displayName,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Portal de cotización y equipo de contacto',
                style: TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.open_in_browser, color: _teal),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Portal de tarificación',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        portal == null
                            ? 'Pendiente de incorporar el enlace de acceso de esta compañía.'
                            : 'Entra al portal de la compañía para consultar y tarificar sus productos.',
                      ),
                      if (portal != null) ...[
                        const SizedBox(height: 10),
                        SelectableText(portal.toString()),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: portal == null
                                ? null
                                : () => open(context, portal),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Entrar al portal'),
                          ),
                          if (portal != null)
                            OutlinedButton.icon(
                              onPressed: () => copy(context, portal.toString()),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copiar enlace'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (company.portalUsername.isNotEmpty ||
                  company.portalPassword.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Datos de acceso',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Usuario'),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                company.portalUsername.isEmpty
                                    ? 'No facilitado'
                                    : company.portalUsername,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar usuario',
                              onPressed: () =>
                                  copy(context, company.portalUsername),
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Contraseña'),
                        Row(
                          children: [
                            Expanded(
                              child: company.portalPassword.isEmpty
                                  ? const Text('No facilitada')
                                  : showPassword
                                  ? SelectableText(company.portalPassword)
                                  : const Text('••••••••'),
                            ),
                            IconButton(
                              tooltip: showPassword
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                              onPressed: company.portalPassword.isEmpty
                                  ? null
                                  : () => setState(
                                      () => showPassword = !showPassword,
                                    ),
                              icon: Icon(
                                showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar contraseña',
                              onPressed: company.portalPassword.isEmpty
                                  ? null
                                  : () => copy(context, company.portalPassword),
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
              ],
              if (company.mediatorCode.isNotEmpty)
                _information(
                  context,
                  'Código de mediador',
                  company.mediatorCode,
                  Icons.badge_outlined,
                ),
              if (company.management.isNotEmpty)
                _information(
                  context,
                  'Contactos y gestión',
                  company.management,
                  Icons.support_agent,
                ),
              if (company.notes.isNotEmpty)
                _information(
                  context,
                  'Observaciones',
                  company.notes,
                  Icons.info_outline,
                ),
              if (company.payments.isNotEmpty)
                _information(
                  context,
                  'Formas de pago',
                  company.payments,
                  Icons.payments_outlined,
                ),
              const Text(
                'Ejecutivos de la compañía',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 12),
              if (company.executives.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.contact_phone_outlined,
                          size: 30,
                          color: _teal,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Todavía no hay contactos incorporados',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Aquí aparecerán el nombre, teléfono y email de cada ejecutivo de esta compañía.',
                        ),
                      ],
                    ),
                  ),
                ),
              for (final executive in company.executives)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          executive.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        if (executive.area.isNotEmpty) Text(executive.area),
                        const SizedBox(height: 12),
                        if (executive.phone.isNotEmpty)
                          _contact(
                            context,
                            Icons.phone_outlined,
                            executive.phone,
                            Uri(
                              scheme: 'tel',
                              path: executive.phone.replaceAll(
                                RegExp(r'[\s().-]'),
                                '',
                              ),
                            ),
                          ),
                        if (executive.email.isNotEmpty)
                          _contact(
                            context,
                            Icons.email_outlined,
                            executive.email,
                            Uri(scheme: 'mailto', path: executive.email),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _information(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar $title',
                  onPressed: () => copy(context, value),
                  icon: const Icon(Icons.copy, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(value, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    ),
  );
  Widget _contact(BuildContext context, IconData icon, String value, Uri uri) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: _teal),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(value)),
            IconButton(
              tooltip: 'Copiar',
              onPressed: () => copy(context, value),
              icon: const Icon(Icons.copy, size: 20),
            ),
            IconButton(
              tooltip: 'Abrir',
              onPressed: () => open(context, uri),
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
          ],
        ),
      );
}

class QuotationCompanyScreen extends StatefulWidget {
  const QuotationCompanyScreen({
    super.key,
    required this.company,
    this.loadCompany,
  });
  final QuotationCompany company;
  final Future<QuotationCompany> Function(QuotationCompany)? loadCompany;
  @override
  State<QuotationCompanyScreen> createState() => _QuotationCompanyScreenState();
}

class _QuotationCompanyScreenState extends State<QuotationCompanyScreen> {
  late Future<QuotationCompany> data;
  @override
  void initState() {
    super.initState();
    data = (widget.loadCompany ?? loadQuotationCompany)(widget.company);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<QuotationCompany>(
    future: data,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return _QuotationCompanyDetails(company: snapshot.data!);
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.company.displayName)),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.error is QuotationSessionRequired
                          ? 'Tu sesión de SafeBrok ha caducado. Vuelve a iniciar sesión para consultar los datos de acceso.'
                          : 'No se ha podido cargar la información de la compañía. Comprueba la conexión y vuelve a intentarlo.',
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.error is QuotationSessionRequired)
                      FilledButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión'),
                        onPressed: () =>
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute<void>(
                                builder: (_) => const LoginScreen(),
                              ),
                              (_) => false,
                            ),
                      )
                    else
                      FilledButton(
                        onPressed: () => setState(() {
                          data = (widget.loadCompany ?? loadQuotationCompany)(
                            widget.company,
                          );
                        }),
                        child: const Text('Reintentar'),
                      ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
