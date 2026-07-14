import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsultarPolizaScreen extends StatefulWidget {
  const ConsultarPolizaScreen({super.key});

  @override
  State<ConsultarPolizaScreen> createState() => _ConsultarPolizaScreenState();
}

class _ConsultarPolizaScreenState extends State<ConsultarPolizaScreen> {
  final supabase = Supabase.instance.client;

  final numeroPolizaCtrl = TextEditingController();
  final dniCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  bool loading = false;
  Map<String, dynamic>? venta;
  Map<String, dynamic>? cliente;

  @override
  void dispose() {
    numeroPolizaCtrl.dispose();
    dniCtrl.dispose();
    emailCtrl.dispose();
    super.dispose();
  }

  Future<void> consultarPoliza() async {
  setState(() {
    loading = true;
    venta = null;
    cliente = null;
  });

  try {
    final numeroPoliza = numeroPolizaCtrl.text.trim().toLowerCase();
    final dni = dniCtrl.text.trim().toLowerCase();
    final email = emailCtrl.text.trim().toLowerCase();

    final ventasData = await supabase.from('ventas').select();
    final clientesData = await supabase.from('clientes').select();

    debugPrint('========================');
debugPrint('VENTAS: ${(ventasData as List).length}');
debugPrint('CLIENTES: ${(clientesData as List).length}');
debugPrint('========================');

    final ventas = (ventasData as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final clientes = (clientesData as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

        if (ventas.isNotEmpty) {
  debugPrint('COLUMNAS VENTAS');
  debugPrint(ventas.first.keys.toString());
  debugPrint(ventas.first.toString());
}

if (clientes.isNotEmpty) {
  debugPrint('COLUMNAS CLIENTES');
  debugPrint(clientes.first.keys.toString());
  debugPrint(clientes.first.toString());
}

    Map<String, dynamic>? ventaEncontrada;
    Map<String, dynamic>? clienteEncontrado;

    String normalizar(dynamic v) {
      return (v ?? '').toString().trim().toLowerCase();
    }

    dynamic clienteIdVenta(Map<String, dynamic> v) {
      return v['cliente_id'] ??
          v['id_cliente'] ??
          v['clienteId'] ??
          v['CLIENTE_ID'];
    }

    String numeroPolizaVenta(Map<String, dynamic> v) {
      return normalizar(
        v['numero_poliza'] ??
            v['poliza'] ??
            v['POLIZA'] ??
            v['N_POLIZA'] ??
            v['n_poliza'] ??
            v['numeroPoliza'],
      );
    }
    debugPrint('BUSCANDO...');
debugPrint('Poliza: $numeroPoliza');
debugPrint('DNI: $dni');
debugPrint('EMAIL: $email');

    if (numeroPoliza.isNotEmpty) {
      for (final v in ventas) {
        if (numeroPolizaVenta(v) == numeroPoliza) {
          ventaEncontrada = v;
          debugPrint('VENTA ENCONTRADA');
debugPrint(v.toString());
          break;
        }
      }
    }

    if (ventaEncontrada == null && dni.isNotEmpty) {
      for (final c in clientes) {
        final dniCliente = normalizar(
          c['dni'] ??
              c['DNI'] ??
              c['documento'] ??
              c['numero_documento'],
        );

        if (dniCliente == dni) {
          clienteEncontrado = c;
          debugPrint('CLIENTE DNI ENCONTRADO');
debugPrint(c.toString());
          break;
        }
      }

      if (clienteEncontrado != null) {
        final idCliente = clienteEncontrado['id']?.toString();

        for (final v in ventas) {
          if (clienteIdVenta(v)?.toString() == idCliente) {
            ventaEncontrada = v;
            break;
          }
        }
      }
    }

    if (ventaEncontrada == null && email.isNotEmpty) {
      for (final c in clientes) {
        final emailCliente = normalizar(
          c['email'] ??
              c['EMAIL'] ??
              c['correo'] ??
              c['correo_electronico'],
        );

        if (emailCliente == email) {
          clienteEncontrado = c;
          debugPrint('CLIENTE EMAIL ENCONTRADO');
debugPrint(c.toString());
          break;
        }
      }

      if (clienteEncontrado != null) {
        final idCliente = clienteEncontrado['id']?.toString();

        for (final v in ventas) {
          if (clienteIdVenta(v)?.toString() == idCliente) {
            ventaEncontrada = v;
            break;
          }
        }
      }
    }

    if (ventaEncontrada != null && clienteEncontrado == null) {
      final idCliente = clienteIdVenta(ventaEncontrada)?.toString();

      if (idCliente != null) {
        for (final c in clientes) {
          if (c['id']?.toString() == idCliente) {
            clienteEncontrado = c;
            break;
          }
        }
      }
    }

    setState(() {
      venta = ventaEncontrada;
      cliente = clienteEncontrado;
      loading = false;
    });

    if (ventaEncontrada == null && clienteEncontrado == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se ha encontrado ninguna póliza con esos datos'),
        ),
      );
    }
  } catch (e) {
    debugPrint('ERROR CONSULTAR POLIZA: $e');

    if (!mounted) return;

    setState(() => loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error consultando póliza: $e')),
    );
  }
}

  String _text(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  void _accionCliente(String accion) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$accion preparado para próxima fase')),
    );
  }

  void _abrirGestiones() {
   showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 70, 18, 18),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF102331),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Wrap(
              runSpacing: 12,
              children: [
                const Text(
                  'Gestiones del cliente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                _gestionItem(
                  Icons.email_rounded,
                  'Enviar email',
                  'Enviar comunicación al email del cliente.',
                  () => _accionCliente('Enviar email'),
                ),

                _gestionItem(
                  Icons.sms_rounded,
                  'Enviar SMS',
                  'Enviar aviso rápido al teléfono del cliente.',
                  () => _accionCliente('Enviar SMS'),
                ),

                _gestionItem(
                  Icons.assignment_turned_in_rounded,
                  'Enviar consentimiento',
                  'Preparar consentimiento digital.',
                  () => _accionCliente('Enviar consentimiento'),
                ),

                _gestionItem(
                  Icons.download_rounded,
                  'Descargar fichón',
                  'Generar y descargar el fichón completo del cliente.',
                  () => _accionCliente('Descargar fichón'),
                ),

                _gestionItem(
                  Icons.folder_zip_rounded,
                  'Descargar documentación',
                  'Descargar documentación vinculada al cliente.',
                  () => _accionCliente('Descargar documentación'),
                ),

                _gestionItem(
                  Icons.description_rounded,
                  'Descargar póliza',
                  'Descargar o preparar copia de la póliza.',
                  () => _accionCliente('Descargar póliza'),
                ),

                _gestionItem(
                  Icons.receipt_long_rounded,
                  'Consultar recibos',
                  'Revisar estado de cobro o incidencias.',
                  () => _accionCliente('Consultar recibos'),
                ),

                _gestionItem(
                  Icons.history_rounded,
                  'Historial de gestiones',
                  'Ver actividad comercial del cliente.',
                  () => _accionCliente('Historial de gestiones'),
                ),

                _gestionItem(
                  Icons.event_note_rounded,
                  'Ver seguimientos',
                  'Consultar llamadas y seguimientos programados.',
                  () => _accionCliente('Ver seguimientos'),
                ),

                _gestionItem(
                  Icons.person_search_rounded,
                  'Abrir ficha completa',
                  'Abrir la ficha completa del cliente.',
                  () => _accionCliente('Abrir ficha completa'),
                ),

                _gestionItem(
                  Icons.warning_amber_rounded,
                  'Ver incidencias',
                  'Consultar incidencias asociadas al cliente.',
                  () => _accionCliente('Ver incidencias'),
                ),

                _gestionItem(
                  Icons.edit_rounded,
                  'Modificar datos',
                  'Editar información del cliente o póliza.',
                  () => _accionCliente('Modificar datos'),
                ),

                _gestionItem(
                  Icons.cancel_rounded,
                  'Solicitar baja',
                  'Iniciar solicitud de baja o anulación.',
                  () => _accionCliente('Solicitar baja'),
                ),

                _gestionItem(
                  Icons.swap_horiz_rounded,
                  'Cambiar mediador',
                  'Reasignar cliente o póliza a otro mediador.',
                  () => _accionCliente('Cambiar mediador'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
},
    );
  }

  Widget _gestionItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: Colors.cyanAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoClaroPremium(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  _topHeader(),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 390,
                          child: _formularioConsulta(),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _resultadoConsulta(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topHeader() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Consultar póliza',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                'Consulta rápida de pólizas, datos del cliente y gestiones disponibles.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formularioConsulta() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitle(
            Icons.policy_rounded,
            'Datos de búsqueda',
            'Introduce uno de los datos para localizar la póliza.',
          ),
          const SizedBox(height: 22),
          _input(numeroPolizaCtrl, 'Número de póliza', Icons.confirmation_number_rounded),
          _input(dniCtrl, 'DNI / NIE', Icons.badge_rounded),
          _input(emailCtrl, 'Email', Icons.email_rounded),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: loading ? null : consultarPoliza,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                loading ? 'Consultando...' : 'Consultar póliza',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Puedes buscar por número de póliza, DNI o email. Si hay varias pólizas para el mismo cliente, se mostrará la primera encontrada.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultadoConsulta() {
    if (venta == null && cliente == null) {
      return _glassPanel(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.manage_search_rounded,
                size: 92,
                color: const Color(0xFF0284C7).withOpacity(0.28),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sin póliza seleccionada',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Introduce los datos de búsqueda para consultar la ficha completa.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _moduleTitle(
                    Icons.verified_rounded,
                    'Resultado de póliza',
                    'Datos encontrados en ventas y clientes.',
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _abrirGestiones,
                    icon: const Icon(Icons.more_vert_rounded),
                    color: const Color(0xFF0F172A),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _dataCard('Póliza', _text(venta?['numero_poliza']), Icons.confirmation_number_rounded),
                  _dataCard('Producto', _text(venta?['producto']), Icons.inventory_2_rounded),
                  _dataCard('Compañía', _text(venta?['compania']), Icons.business_rounded),
                  _dataCard('Forma de pago', _text(venta?['forma_pago']), Icons.payments_rounded),
                  _dataCard('Fecha efecto', _text(venta?['fecha_efecto']).split('T').first, Icons.calendar_month_rounded),
                  _dataCard('Asegurados', _text(venta?['numero_asegurados']), Icons.groups_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                'Prima neta',
                '${_money(venta?['prima_anual_neta']).toStringAsFixed(2)} €',
                Icons.trending_up_rounded,
                const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _metricCard(
                'Comisión',
                '${_money(venta?['comision']).toStringAsFixed(2)} €',
                Icons.euro_rounded,
                const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _moduleTitle(
                Icons.person_rounded,
                'Datos del cliente',
                'Ficha principal vinculada a la póliza.',
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _dataCard('Nombre', '${_text(cliente?['nombre'])} ${_text(cliente?['apellidos'])}', Icons.person_rounded),
                  _dataCard('DNI', _text(cliente?['dni']), Icons.badge_rounded),
                  _dataCard('Teléfono', _text(cliente?['telefono']), Icons.phone_rounded),
                  _dataCard('Email', _text(cliente?['email']), Icons.email_rounded),
                  _dataCard('Dirección', '${_text(cliente?['direccion'])}, ${_text(cliente?['numero'])}', Icons.home_rounded),
                  _dataCard('Población', '${_text(cliente?['poblacion'])} - ${_text(cliente?['provincia'])}', Icons.location_city_rounded),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _input(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFF0284C7)),
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _moduleTitle(IconData icon, String title, String subtitle) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0284C7),
              Color(0xFF22D3EE),
            ],
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 29),
      ),
      const SizedBox(width: 13),
      Flexible(
        fit: FlexFit.loose,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

  Widget _dataCard(String title, String value, IconData icon) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0284C7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B))),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }
}

class _FondoClaroPremium extends StatelessWidget {
  const _FondoClaroPremium();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFFF4F7FB)),
        Positioned(
          top: -140,
          right: -120,
          child: _orb(330, const Color(0xFF7DD3FC)),
        ),
        Positioned(
          bottom: -150,
          left: -130,
          child: _orb(360, const Color(0xFFC4B5FD)),
        ),
        Positioned(
          top: 260,
          left: 360,
          child: _orb(230, const Color(0xFFBBF7D0)),
        ),
      ],
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.45),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.38),
            blurRadius: 120,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }
}