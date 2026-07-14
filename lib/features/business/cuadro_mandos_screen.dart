import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/features/business/reasignar_mediador_screen.dart';
import 'package:safebrok_andalucia/features/business/reasignar_jefe_equipo_screen.dart';
import 'package:safebrok_andalucia/features/business/control_referencias_screen.dart';
import 'package:safebrok_andalucia/features/business/control_altas_screen.dart';
import 'package:safebrok_andalucia/features/business/control_bajas_screen.dart';
import 'package:safebrok_andalucia/features/business/cargar_gestiones_screen.dart';
import 'package:safebrok_andalucia/features/admin/modificar_comisiones_screen.dart';
import 'package:safebrok_andalucia/features/business/consultar_poliza_screen.dart';
import 'package:safebrok_andalucia/features/admin/tramitar_facturas_screen.dart';
import 'package:safebrok_andalucia/features/business/anular_poliza_screen.dart';

class CuadroMandosScreen extends StatefulWidget {
  const CuadroMandosScreen({super.key});

  @override
  State<CuadroMandosScreen> createState() => _CuadroMandosScreenState();
}

class _CuadroMandosScreenState extends State<CuadroMandosScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String role = '';
  String selectedModule = 'Resumen ejecutivo';

  final List<_ModuloMando> modulos = [
    _ModuloMando(
      title: 'Resumen ejecutivo',
      icon: Icons.dashboard_customize_rounded,
      description: 'Vista general de control de equipos.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Reasignar mediador',
      icon: Icons.swap_horiz_rounded,
      description: 'Mover agentes o clientes entre responsables.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Reasignar jefe de equipo',
      icon: Icons.manage_accounts_rounded,
      description: 'Cambiar la dependencia de un jefe de equipo entre distintos jefes de ventas.',
      blockedFor: ['jefe_ventas'],
    ),
    _ModuloMando(
      title: 'Control referencias',
      icon: Icons.hub_rounded,
      description: 'Supervisión de referencias por estructura.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Cargar gestiones',
      icon: Icons.playlist_add_check_rounded,
      description: 'Registro y control de gestiones comerciales.',
      blockedFor: [],
    ),
    _ModuloMando(
  title: 'Consultar póliza',
  icon: Icons.policy_rounded,
  description: 'Consulta rápida de pólizas, clientes, recibos y datos comerciales.',
  blockedFor: [],
),
_ModuloMando(
  title: 'Anular póliza',
  icon: Icons.cancel_presentation_rounded,
  description: 'Gestión y seguimiento de solicitudes de anulación de pólizas.',
  blockedFor: [
    'director_zona',
    'jefe_ventas',
    'jefe_equipo',
    'agente',
  ],
),
    _ModuloMando(
      title: 'Tramitar facturas',
      icon: Icons.receipt_long_rounded,
      description: 'Expedición y control de facturación.',
      blockedFor: ['director_zona', 'jefe_ventas'],
    ),
    _ModuloMando(
      title: 'Modificar comisiones',
      icon: Icons.euro_rounded,
      description: 'Ajustes económicos y porcentajes de comisión.',
      blockedFor: ['director_zona', 'jefe_ventas'],
    ),
    _ModuloMando(
      title: 'Documentación',
      icon: Icons.folder_copy_rounded,
      description: 'Documentos, solicitudes y plantillas.',
      blockedFor: [],
      children: [
        'Duplicado CCPP',
        'Generar recibo',
        'Solicitud de baja',
        'Consentimiento',
        'Cambio de cuenta bancaria',
        'Cambio de domicilio',
        'Autorización SEPA',
        'Parte de incidencia',
        'Certificado de póliza',
        'Solicitud de modificación',
      ],
    ),
    _ModuloMando(
      title: 'Altas',
      icon: Icons.person_add_alt_1_rounded,
      description: 'Control de altas de usuarios, agentes o clientes.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Bajas',
      icon: Icons.person_remove_alt_1_rounded,
      description: 'Seguimiento de bajas y motivos.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Incidencias',
      icon: Icons.warning_amber_rounded,
      description: 'Control de errores, recibos y gestiones pendientes.',
      blockedFor: [],
    ),
    _ModuloMando(
      title: 'Ranking equipos',
      icon: Icons.emoji_events_rounded,
      description: 'Rendimiento por estructura comercial.',
      blockedFor: [],
    ),
  ];

  @override
  void initState() {
    super.initState();
    loadRole();
  }

  Future<void> loadRole() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    final perfil = await supabase
        .from('usuarios')
        .select('rol_usuario')
        .eq('auth_id', user.id)
        .maybeSingle();

    setState(() {
      role = perfil?['rol_usuario']?.toString() ?? '';
      loading = false;
    });
  }

  bool _puedeVer(_ModuloMando modulo) {
    if (role == 'director_nacional' || role == 'administracion') {
      return true;
    }

    return !modulo.blockedFor.contains(role);
  }

  _ModuloMando get moduloSeleccionado {
    return modulos.firstWhere(
      (m) => m.title == selectedModule,
      orElse: () => modulos.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final modulo = moduloSeleccionado;
    final permitido = _puedeVer(modulo);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoClaroPremium(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0284C7),
                    ),
                  )
                : Row(
                    children: [
                      _sidebar(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _topHeader(),
                              const SizedBox(height: 20),
                              Expanded(
                                child: permitido
                                    ? _contenidoModulo(modulo)
                                    : _bloqueado(modulo),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    return Container(
      width: 290,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.14),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0284C7),
                          Color(0xFF22D3EE),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cuadro',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'de mandos',
                          style: TextStyle(
                            color: Color(0xFF0284C7),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _rolePill(),
              const SizedBox(height: 24),
              ...modulos.map(_menuItem),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rolePill() {
    final text = role.isEmpty ? 'Sin rol' : role.replaceAll('_', ' ').toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF0284C7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF075985),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(_ModuloMando modulo) {
    final selected = selectedModule == modulo.title;
    final permitido = _puedeVer(modulo);

    return Opacity(
      opacity: permitido ? 1 : 0.38,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: () {
            if (modulo.title == 'Reasignar mediador') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ReasignarMediadorScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Reasignar jefe de equipo') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ReasignarJefeEquipoScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Control referencias') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ControlReferenciasScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Cargar gestiones') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const CargarGestionesScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Consultar póliza') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ConsultarPolizaScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Anular póliza') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AnularPolizaScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Altas') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ControlAltasScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Modificar comisiones') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ModificarComisionesScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Tramitar facturas') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const TramitarFacturasScreen(),
    ),
  );
  return;
}

if (modulo.title == 'Bajas') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ControlBajasScreen(),
    ),
  );
  return;
}



setState(() => selectedModule = modulo.title);

setState(() => selectedModule = modulo.title);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0284C7)
                  : Colors.white.withOpacity(0.68),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0284C7)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withOpacity(0.20),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  modulo.icon,
                  color: selected ? Colors.white : const Color(0xFF0284C7),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    modulo.title,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!permitido)
                  Icon(
                    Icons.lock_rounded,
                    color: selected ? Colors.white70 : const Color(0xFF64748B),
                    size: 17,
                  ),
              ],
            ),
          ),
        ),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.blueGrey.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
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
                'Centro de gobierno comercial',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Control operativo de equipos, gestiones, documentación y estructura.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.shield_rounded,
                color: Color(0xFF16A34A),
              ),
              SizedBox(width: 8),
              Text(
                'Panel seguro',
                style: TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _contenidoModulo(_ModuloMando modulo) {
    if (modulo.title == 'Resumen ejecutivo') {
      return _resumenEjecutivo();
    }

    if (modulo.title == 'Documentación') {
      return _documentacion(modulo);
    }

    return _moduloGenerico(modulo);
  }

  Widget _resumenEjecutivo() {
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricCard(
                title: 'Estructura',
                value: 'Activa',
                subtitle: 'Control por rol aplicado',
                icon: Icons.account_tree_rounded,
                color: const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _metricCard(
                title: 'Referencias',
                value: 'CRM',
                subtitle: 'Supervisión comercial',
                icon: Icons.hub_rounded,
                color: const Color(0xFF9333EA),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _metricCard(
                title: 'Gestiones',
                value: 'Pendientes',
                subtitle: 'Seguimiento operativo',
                icon: Icons.task_alt_rounded,
                color: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qué podrás controlar desde aquí',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: modulos
                    .where((m) => m.title != 'Resumen ejecutivo')
                    .map(
                      (m) => _quickModuleChip(
                        title: m.title,
                        icon: m.icon,
                        enabled: _puedeVer(m),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _glassPanel(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permisos aplicados',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 14),
              _PermisoLine(
                role: 'Director nacional',
                text: 'Puede consultar y gestionar todos los módulos.',
              ),
              _PermisoLine(
                role: 'Director de zona',
                text: 'Puede consultar todo excepto modificar comisiones y tramitar facturas.',
              ),
              _PermisoLine(
                role: 'Jefe de ventas',
                text: 'No puede modificar comisiones, tramitar facturas ni reasignar jefes de ventas.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moduloGenerico(_ModuloMando modulo) {


    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitle(modulo),
          const SizedBox(height: 18),
          Text(
            modulo.description,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          _placeholderActions(modulo),
        ],
      ),
    );
  }

  Widget _documentacion(_ModuloMando modulo) {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitle(modulo),
          const SizedBox(height: 18),
          const Text(
            'Generación y consulta de documentos comerciales y administrativos.',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: modulo.children.map((doc) {
              return Container(
                width: 250,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueGrey.withOpacity(0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_rounded,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doc,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _bloqueado(_ModuloMando modulo) {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitle(modulo),
          const SizedBox(height: 26),
          Center(
            child: Column(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFFDC2626),
                    size: 50,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Módulo restringido',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu rol puede ver el acceso, pero no tiene permisos para consultar o modificar esta sección.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleTitle(_ModuloMando modulo) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF0284C7),
                Color(0xFF22D3EE),
              ],
            ),
          ),
          child: Icon(
            modulo.icon,
            color: Colors.white,
            size: 31,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                modulo.title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                modulo.description,
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

  Widget _placeholderActions(_ModuloMando modulo) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _actionCard(
          icon: Icons.visibility_rounded,
          title: 'Consultar',
          text: 'Ver datos disponibles de este módulo.',
        ),
        _actionCard(
          icon: Icons.tune_rounded,
          title: 'Filtrar',
          text: 'Filtrar por equipo, agente, fecha o estado.',
        ),
        _actionCard(
          icon: Icons.download_rounded,
          title: 'Exportar',
          text: 'Preparar informe o documento operativo.',
        ),
        _actionCard(
          icon: Icons.history_rounded,
          title: 'Historial',
          text: 'Revisar movimientos y actividad reciente.',
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      width: 245,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF0284C7),
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickModuleChip({
    required String title,
    required IconData icon,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: enabled ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? icon : Icons.lock_rounded,
              color: enabled ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: enabled ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: color, size: 31),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.12),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ModuloMando {
  final String title;
  final IconData icon;
  final String description;
  final List<String> blockedFor;
  final List<String> children;

  const _ModuloMando({
    required this.title,
    required this.icon,
    required this.description,
    required this.blockedFor,
    this.children = const [],
  });
}

class _FondoClaroPremium extends StatelessWidget {
  const _FondoClaroPremium();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFFF4F7FB),
        ),
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

class _PermisoLine extends StatelessWidget {
  final String role;
  final String text;

  const _PermisoLine({
    required this.role,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF16A34A),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$role: ',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}