import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessSettingsScreen extends StatefulWidget {
  final String role;

  const BusinessSettingsScreen({super.key, required this.role});

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _corporateMode = false;
  String? _error;
  Map<String, dynamic>? _profile;
  Map<String, dynamic> _corporate = {};
  Map<String, dynamic> _personal = {};

  static const Map<String, dynamic> _defaults = {
    'home_density': 'ampliada',
    'initial_business_card': 'resumen',
    'show_weekly_premium': true,
    'show_mix': true,
    'show_pending': true,
    'show_production': true,
    'highlight_goal': true,
    'alert_goal_50': true,
    'alert_goal_75': true,
    'alert_goal_90': true,
    'alert_goal_100': true,
    'forecast_reminders': true,
    'mix_alerts': true,
    'production_drop_alerts': true,
    'notify_own_sale': true,
    'notify_team_sale': true,
    'notify_goal': true,
    'notify_rappel': true,
    'notify_closure': true,
    'notify_receipts': true,
    'notify_tasks': true,
    'amount_mode': 'neto',
    'show_irpf': true,
    'comparison_mode': 'mes_anterior',
    'decimals': '0',
    'hide_sensitive_amounts': false,
    'protect_economic_screens': false,
    'auto_hide_minutes': '5',
    'team_default_view': 'arbol',
    'team_depth': '2',
    'team_order': 'produccion',
    'report_period': 'mes',
    'report_format': 'pdf',
    'report_include_economic': true,
    'report_include_mix': true,
    'report_include_structure': true,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';
  String _role(dynamic value) => _text(value)
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  bool get _canManageCorporate => {
    'administracion',
    'director_nacional',
  }.contains(_role(_profile?['rol_usuario'] ?? widget.role));
  Map<String, dynamic> get _working => _corporateMode ? _corporate : _personal;

  Future<void> _load() async {
    final auth = _db.auth.currentUser;
    if (auth == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<dynamic>([
        _db
            .from('usuarios')
            .select('nombre,apellidos,rol_usuario')
            .eq('auth_id', auth.id)
            .maybeSingle(),
        _db
            .from('preferencias_negocio_corporativas')
            .select('configuracion')
            .eq('id', 'default')
            .maybeSingle(),
        _db
            .from('preferencias_negocio')
            .select('configuracion')
            .eq('usuario_auth_id', auth.id)
            .maybeSingle(),
      ]);
      _profile = result[0] == null
          ? null
          : Map<String, dynamic>.from(result[0] as Map);
      final corporateConfig = result[1] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              (result[1] as Map)['configuracion'] as Map? ?? {},
            );
      final personalConfig = result[2] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              (result[2] as Map)['configuracion'] as Map? ?? {},
            );
      _corporate = {..._defaults, ...corporateConfig};
      _personal = {..._defaults, ...corporateConfig, ...personalConfig};
      if (!mounted) return;
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final auth = _db.auth.currentUser;
    if (auth == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (_corporateMode) {
        await _db.from('preferencias_negocio_corporativas').upsert({
          'id': 'default',
          'configuracion': _corporate,
          'updated_by': auth.id,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _db.from('preferencias_negocio').upsert({
          'usuario_auth_id': auth.id,
          'configuracion': _personal,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _corporateMode
                ? 'Configuración corporativa guardada'
                : 'Tus preferencias se han guardado',
          ),
          backgroundColor: const Color(0xFF168259),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $error'),
          backgroundColor: const Color(0xFFC84040),
        ),
      );
    }
  }

  void _set(String key, dynamic value) {
    setState(() {
      _working[key] = value;
      _dirty = true;
    });
  }

  void _reset() {
    setState(() {
      if (_corporateMode) {
        _corporate = Map<String, dynamic>.from(_defaults);
      } else {
        _personal = {..._defaults, ..._corporate};
      }
      _dirty = true;
    });
  }

  bool _bool(String key) => _working[key] != false;
  String _value(String key) => _text(_working[key]).isEmpty
      ? _text(_defaults[key])
      : _text(_working[key]);

  BoxDecoration _card({bool strong = false}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFFE1E5EA)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF14213D).withValues(alpha: strong ? .13 : .07),
        blurRadius: strong ? 28 : 18,
        offset: Offset(0, strong ? 12 : 7),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _dirty) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F7),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2454D3)),
                )
              : _error != null
              ? _errorView()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 920;
                    return Stack(
                      children: [
                        ListView(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 28 : 16,
                            12,
                            wide ? 28 : 16,
                            110,
                          ),
                          children: [
                            _topBar(),
                            const SizedBox(height: 18),
                            _hero(),
                            const SizedBox(height: 18),
                            if (_canManageCorporate) _scopeSelector(),
                            if (_canManageCorporate) const SizedBox(height: 18),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _appearance(),
                                        const SizedBox(height: 18),
                                        _goals(),
                                        const SizedBox(height: 18),
                                        _economy(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _notifications(),
                                        const SizedBox(height: 18),
                                        _team(),
                                        const SizedBox(height: 18),
                                        _reports(),
                                        const SizedBox(height: 18),
                                        _privacy(),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              _appearance(),
                              const SizedBox(height: 18),
                              _goals(),
                              const SizedBox(height: 18),
                              _notifications(),
                              const SizedBox(height: 18),
                              _economy(),
                              const SizedBox(height: 18),
                              _team(),
                              const SizedBox(height: 18),
                              _reports(),
                              const SizedBox(height: 18),
                              _privacy(),
                            ],
                            const SizedBox(height: 18),
                            _resetCard(),
                          ],
                        ),
                        if (_dirty)
                          Positioned(
                            left: wide ? 28 : 16,
                            right: wide ? 28 : 16,
                            bottom: 14,
                            child: _saveBar(),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_dirty) {
              _confirmLeave();
            } else {
              Navigator.pop(context);
            }
          },
          child: const Padding(
            padding: EdgeInsets.all(13),
            child: Icon(Icons.arrow_back_rounded, color: Color(0xFF111C31)),
          ),
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Text(
          'Configuración de Negocio',
          style: TextStyle(
            color: Color(0xFF111C31),
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Recargar',
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded, color: Color(0xFF111C31)),
      ),
    ],
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF14213D), Color(0xFF2454D3)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2454D3).withValues(alpha: .22),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 650;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'TU EXPERIENCIA SAFEBROK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Negocio a tu medida.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Decide qué ves, cómo lo comparas y cuándo quieres recibir avisos.',
              style: TextStyle(
                color: Color(0xFFDDE6FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_done_rounded, color: Colors.white),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sincronización activa',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _corporateMode
                        ? 'Configuración corporativa'
                        : 'Preferencias personales',
                    style: const TextStyle(
                      color: Color(0xFFDDE6FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [copy, const SizedBox(height: 22), badge],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            badge,
          ],
        );
      },
    ),
  );

  Widget _scopeSelector() => Container(
    padding: const EdgeInsets.all(8),
    decoration: _card(),
    child: Row(
      children: [
        Expanded(
          child: _scopeButton(false, Icons.person_rounded, 'Mis preferencias'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _scopeButton(
            true,
            Icons.apartment_rounded,
            'Configuración corporativa',
          ),
        ),
      ],
    ),
  );

  Widget _scopeButton(bool corporate, IconData icon, String label) {
    final selected = _corporateMode == corporate;
    return Material(
      color: selected ? const Color(0xFF14213D) : const Color(0xFFF3F5F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (_dirty) {
            final proceed = await _discardChanges();
            if (!proceed) return;
          }
          setState(() {
            _corporateMode = corporate;
            _dirty = false;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF526078),
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF344158),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    IconData icon,
    String title,
    String subtitle,
    List<Widget> children,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _card(strong: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF2454D3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF111C31),
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF778195),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        ...children,
      ],
    ),
  );
  Widget _switchRow(
    String key,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) {
    final active = _bool(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled
                  ? const Color(0xFF2454D3)
                  : const Color(0xFFADB5C2),
              size: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFF1A2438)
                          : const Color(0xFF929BAB),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF778195),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: active,
              onChanged: enabled ? (value) => _set(key, value) : null,
              activeThumbColor: const Color(0xFF2454D3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow(
    String key,
    String title,
    String subtitle,
    Map<String, String> options,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1A2438),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF778195), fontSize: 12),
          ),
          const SizedBox(height: 11),
          DropdownButtonFormField<String>(
            initialValue: options.containsKey(_value(key))
                ? _value(key)
                : options.keys.first,
            isExpanded: true,
            dropdownColor: Colors.white,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF2454D3),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
            items: options.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        color: Color(0xFF27344C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _set(key, value);
            },
          ),
        ],
      ),
    ),
  );

  Widget _appearance() => _section(
    Icons.dashboard_customize_rounded,
    'Panel de negocio',
    'Organiza la información que necesitas primero.',
    [
      _choiceRow(
        'home_density',
        'Densidad de información',
        'Elige una vista más directa o más detallada.',
        const {'compacta': 'Compacta', 'ampliada': 'Ampliada'},
      ),
      _choiceRow(
        'initial_business_card',
        'Bloque principal',
        'Define qué información abre tu panel.',
        const {
          'resumen': 'Resumen comercial',
          'ventas': 'Ventas',
          'objetivos': 'Objetivos',
          'previsiones': 'Previsiones',
        },
      ),
      _switchRow(
        'show_weekly_premium',
        Icons.euro_rounded,
        'Primas semanales',
        'Muestra la producción computable de la semana.',
      ),
      _switchRow(
        'show_mix',
        Icons.donut_large_rounded,
        'Mix comercial',
        'Incluye el peso de Decesos y Vida.',
      ),
      _switchRow(
        'show_pending',
        Icons.task_alt_rounded,
        'Tareas pendientes',
        'Mantén visibles tus próximas acciones.',
      ),
      _switchRow(
        'show_production',
        Icons.trending_up_rounded,
        'Cumplimiento',
        'Muestra el avance frente al objetivo.',
      ),
      _switchRow(
        'highlight_goal',
        Icons.flag_rounded,
        'Objetivo destacado',
        'Prioriza el objetivo comercial en el resumen.',
      ),
    ],
  );

  Widget _goals() => _section(
    Icons.track_changes_rounded,
    'Objetivos y previsiones',
    'Elige los hitos que quieres vigilar.',
    [
      _switchRow(
        'alert_goal_50',
        Icons.looks_two_rounded,
        'Aviso al 50 %',
        'Te avisaremos al alcanzar la mitad del objetivo.',
      ),
      _switchRow(
        'alert_goal_75',
        Icons.stacked_line_chart_rounded,
        'Aviso al 75 %',
        'Recibe un impulso antes del tramo final.',
      ),
      _switchRow(
        'alert_goal_90',
        Icons.bolt_rounded,
        'Aviso al 90 %',
        'Activa el aviso cuando estés cerca de conseguirlo.',
      ),
      _switchRow(
        'alert_goal_100',
        Icons.emoji_events_rounded,
        'Objetivo conseguido',
        'Celebra el cumplimiento del 100 %.',
      ),
      _switchRow(
        'forecast_reminders',
        Icons.event_repeat_rounded,
        'Recordatorios de previsión',
        'Avisos para completar y revisar los compromisos del mes.',
      ),
      _switchRow(
        'mix_alerts',
        Icons.pie_chart_rounded,
        'Alertas de mix',
        'Detecta si Decesos y Vida se alejan del objetivo.',
      ),
      _switchRow(
        'production_drop_alerts',
        Icons.trending_down_rounded,
        'Caída de producción',
        'Avisa ante una desviación relevante del ritmo previsto.',
      ),
    ],
  );

  Widget _economy() => _section(
    Icons.account_balance_wallet_rounded,
    'Información económica',
    'Controla cómo se presentan importes y comparativas.',
    [
      _choiceRow(
        'amount_mode',
        'Importes principales',
        'Define el valor económico que se destaca.',
        const {'neto': 'Neto', 'bruto': 'Bruto'},
      ),
      _choiceRow(
        'comparison_mode',
        'Comparativa por defecto',
        'Contexto habitual de tus resultados.',
        const {
          'objetivo': 'Frente al objetivo',
          'mes_anterior': 'Mes anterior',
          'anio_anterior': 'Mismo periodo del año anterior',
        },
      ),
      _choiceRow(
        'decimals',
        'Precisión de importes',
        'Número de decimales mostrados.',
        const {'0': 'Sin decimales', '2': 'Dos decimales'},
      ),
      _switchRow(
        'show_irpf',
        Icons.receipt_long_rounded,
        'Mostrar retenciones',
        'Incluye el detalle de IRPF cuando esté disponible.',
      ),
    ],
  );

  Widget _notifications() {
    final hasTeam = !{
      'agente',
      'asesor',
      'comercial',
    }.contains(widget.role.toLowerCase());
    return _section(
      Icons.notifications_active_rounded,
      'Notificaciones',
      'Solo lo importante, en el momento adecuado.',
      [
        _switchRow(
          'notify_own_sale',
          Icons.sell_rounded,
          'Ventas propias',
          'Confirmación inmediata de cada nueva venta.',
        ),
        _switchRow(
          'notify_team_sale',
          Icons.groups_rounded,
          'Ventas del equipo',
          hasTeam
              ? 'Avisos de la producción de tu estructura.'
              : 'Disponible para responsables de estructura.',
          enabled: hasTeam,
        ),
        _switchRow(
          'notify_goal',
          Icons.flag_circle_rounded,
          'Objetivos',
          'Hitos, cumplimiento y desviaciones.',
        ),
        _switchRow(
          'notify_rappel',
          Icons.workspace_premium_rounded,
          'Rappel y comisiones',
          'Cambios relevantes en tu estimación económica.',
        ),
        _switchRow(
          'notify_closure',
          Icons.timer_rounded,
          'Cierre de producción',
          'Resumen cuando queden siete días para el cierre.',
        ),
        _switchRow(
          'notify_receipts',
          Icons.payments_rounded,
          'Nuevos recibos',
          'Avisos cuando se asigne un recibo pendiente.',
        ),
        _switchRow(
          'notify_tasks',
          Icons.checklist_rounded,
          'Nuevas tareas',
          'Notificación al recibir una acción pendiente.',
        ),
      ],
    );
  }

  Widget _team() => _section(
    Icons.account_tree_rounded,
    'Equipo y estructura',
    'Configura la lectura inicial de tu organización.',
    [
      _choiceRow(
        'team_default_view',
        'Vista inicial',
        'Cómo quieres abrir el rendimiento de equipo.',
        const {
          'arbol': 'Árbol jerárquico',
          'resumen': 'Resumen por estructuras',
          'personas': 'Listado de personas',
        },
      ),
      _choiceRow(
        'team_depth',
        'Nivel de detalle',
        'Profundidad inicial del árbol.',
        const {
          '1': 'Solo directos',
          '2': 'Dos niveles',
          'todos': 'Toda la estructura',
        },
      ),
      _choiceRow(
        'team_order',
        'Orden principal',
        'Prioriza los datos más útiles.',
        const {
          'produccion': 'Mayor producción',
          'cumplimiento': 'Mayor cumplimiento',
          'alfabetico': 'Orden alfabético',
        },
      ),
    ],
  );

  Widget _reports() => _section(
    Icons.summarize_rounded,
    'Informes rápidos',
    'Deja preparado tu formato habitual.',
    [
      _choiceRow(
        'report_period',
        'Periodo predeterminado',
        'Rango inicial al abrir informes.',
        const {'mes': 'Mes actual', 'trimestre': 'Trimestre', 'anio': 'Año'},
      ),
      _choiceRow(
        'report_format',
        'Formato de descarga',
        'Tipo de archivo para exportaciones.',
        const {'pdf': 'PDF', 'excel': 'Excel'},
      ),
      _switchRow(
        'report_include_economic',
        Icons.euro_rounded,
        'Datos económicos',
        'Incluye primas, comisiones y facturación.',
      ),
      _switchRow(
        'report_include_mix',
        Icons.pie_chart_outline_rounded,
        'Mix comercial',
        'Añade el detalle de Decesos y Vida.',
      ),
      _switchRow(
        'report_include_structure',
        Icons.hub_rounded,
        'Desglose de estructura',
        'Incluye resultados por responsable y agente.',
      ),
    ],
  );

  Widget _privacy() => _section(
    Icons.shield_rounded,
    'Privacidad en pantalla',
    'Protege la información sensible cuando trabajas acompañado.',
    [
      _switchRow(
        'hide_sensitive_amounts',
        Icons.visibility_off_rounded,
        'Ocultar importes sensibles',
        'Permite disimular cifras económicas en el panel.',
      ),
      _switchRow(
        'protect_economic_screens',
        Icons.lock_rounded,
        'Proteger pantallas económicas',
        'Solicita una comprobación al volver a información sensible.',
      ),
      _choiceRow(
        'auto_hide_minutes',
        'Ocultación automática',
        'Tiempo de espera antes de proteger los importes.',
        const {
          '1': 'Después de 1 minuto',
          '5': 'Después de 5 minutos',
          '15': 'Después de 15 minutos',
        },
      ),
    ],
  );

  Widget _resetCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8EE),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFF4D7A6)),
    ),
    child: Row(
      children: [
        const Icon(Icons.restart_alt_rounded, color: Color(0xFFB86A00)),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Restablecer configuración',
                style: TextStyle(
                  color: Color(0xFF51320B),
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Recupera la experiencia recomendada por SafeBrok.',
                style: TextStyle(color: Color(0xFF8A6739), fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _reset,
          child: const Text(
            'Restablecer',
            style: TextStyle(
              color: Color(0xFFB86A00),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _saveBar() => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF111C31),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .24),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        const Icon(Icons.edit_note_rounded, color: Colors.white),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Tienes cambios sin guardar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  setState(() {
                    if (_corporateMode) {
                      _corporate = Map<String, dynamic>.from(_defaults);
                    } else {
                      _personal = Map<String, dynamic>.from(_corporate);
                    }
                    _dirty = false;
                  });
                },
          child: const Text(
            'Descartar',
            style: TextStyle(
              color: Color(0xFFC9D5F3),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2454D3),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_done_rounded, size: 19),
          label: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFF2454D3),
            size: 54,
          ),
          const SizedBox(height: 14),
          const Text(
            'No hemos podido cargar tu configuración',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111C31),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF778195)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Volver a intentar'),
          ),
        ],
      ),
    ),
  );

  Future<bool> _discardChanges() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: const Text(
          'Las preferencias que no hayas guardado se perderán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _confirmLeave() async {
    final discard = await _discardChanges();
    if (discard && mounted) Navigator.pop(context);
  }
}
