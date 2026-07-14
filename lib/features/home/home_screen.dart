import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sales/create_sale_wizard.dart';
import '../sales/my_sales_screen.dart';
import '../clients/my_clients_screen.dart';
import 'package:safebrok_andalucia/features/team/team_dashboard_screen.dart';
import 'package:safebrok_andalucia/features/team/team_agents_screen.dart';
import 'package:safebrok_andalucia/features/team/team_tracking_screen.dart';
import 'package:safebrok_andalucia/features/tareas/mis_tareas_screen.dart';
import '../core/update_service.dart';
import 'package:safebrok_andalucia/features/tareas/jefe_equipo_tareas_screen.dart';
import 'package:safebrok_andalucia/features/agenda/agenda_screen.dart';
import 'package:safebrok_andalucia/features/team/mis_equipos_jefe_ventas_screen.dart';
import 'package:safebrok_andalucia/features/jefe_ventas/control_equipos_jefe_ventas_screen.dart';
import 'package:safebrok_andalucia/features/jefe_ventas/seguimiento_jefe_ventas_screen.dart';
import 'package:safebrok_andalucia/features/jefe_ventas/agenda_jefe_ventas_screen.dart';
import 'package:safebrok_andalucia/features/team/agenda_jefe_equipo_screen.dart';
import 'dart:async';
import 'package:safebrok_andalucia/features/chat/internal_chat_screen.dart';
import 'package:safebrok_andalucia/features/recibos/recibos_agente_screen.dart';
import 'package:safebrok_andalucia/features/ia/safebrok_ai_screen.dart';
import 'package:safebrok_andalucia/features/director_nacional/director_nacional_kpis_screen.dart';
import 'package:safebrok_andalucia/features/director_nacional/director_nacional_usuarios_screen.dart';
import 'package:safebrok_andalucia/features/business/ranking_comercial_screen.dart';
import 'package:safebrok_andalucia/features/business/cuadro_mandos_screen.dart';
import 'package:safebrok_andalucia/features/business/cargar_gestiones_screen.dart';
import 'package:safebrok_andalucia/features/business/mis_gestiones_screen.dart';
import 'package:url_launcher/url_launcher.dart';


class DashboardItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String subtitle;
  final Color color;

  DashboardItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle = "Abrir módulo",
    this.color = const Color(0xFF22D3EE),
  });
}

class ProductionCountdown extends StatefulWidget {
  const ProductionCountdown({super.key});

  @override
  State<ProductionCountdown> createState() => _ProductionCountdownState();
}

class _ProductionCountdownState extends State<ProductionCountdown> {
  late DateTime targetDate;
  late Duration remaining;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    if (now.day >= 24) {
      targetDate = DateTime(now.year, now.month + 1, 24, 23, 59, 59);
    } else {
      targetDate = DateTime(now.year, now.month, 24, 23, 59, 59);
    }

    _updateRemaining();

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _updateRemaining();
      return true;
    });
   
  }


  void _updateRemaining() {
    final now = DateTime.now();
    setState(() {
      remaining = targetDate.difference(now);
    });
  }

  String format(Duration d) {
    if (d.isNegative) return "Cerrado";

    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    return "${days}d ${hours}h ${minutes}m ${seconds}s";
  }

 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF7A00).withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF7A00).withOpacity(0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF7A00).withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_rounded,
            color: Color(0xFFFF9F1C),
            size: 20,
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Producción cierra en",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                format(remaining),
                style: const TextStyle(
                  color: Color(0xFFFFB020),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String role;

  const HomeScreen({
    super.key,
    required this.role,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
final supabase = Supabase.instance.client;

  int totalClientes = 0;
int totalVentas = 0;
int totalTareas = 0;

double primasSemana = 0.0;
int clientesSemana = 0;
double objetivoSemana = 1250.0;
int rachaSemanas = 0;

int rankingPosicion = 0;
int rankingTotal = 0;
int rankingPrimero = 0;
int misPolizasTotales = 0;

  bool loadingKpis = true;
  bool _checkingUpdate = false;
  bool _updateDialogShown = false;

  int chatUnreadCount = 0;
int systemUnreadCount = 0;
Timer? chatTimer;

final List<List<String>> frasesMotivadoras = [

  [
    "Hoy es un gran día",
    "para cerrar ventas."
  ],

  [
    "Cada puerta",
    "es una oportunidad."
  ],

  [
    "No vendes seguros,",
    "proteges familias."
  ],

  [
    "El éxito empieza",
    "con una visita más."
  ],

  [
    "Cada conversación",
    "puede cambiar tu mes."
  ],

  [
    "Hoy puede ser",
    "tu mejor día del año."
  ],

  [
    "La disciplina",
    "vence al talento."
  ],

  [
    "Nunca sabes",
    "dónde está la siguiente venta."
  ],

  [
    "La confianza",
    "es tu mejor argumento."
  ],

  [
    "Cada cliente",
    "merece la mejor protección."
  ],

  [
    "El mejor comercial",
    "nunca deja de aprender."
  ],

  [
    "Hoy toca",
    "crear oportunidades."
  ],

  [
    "No esperes",
    "haz que ocurra."
  ],

  [
    "Cada visita",
    "te acerca al objetivo."
  ],

  [
    "Construye relaciones,",
    "las ventas llegarán."
  ],

  [
    "El esfuerzo de hoy",
    "es la comisión de mañana."
  ],

  [
    "Haz una llamada más.",
    "Puede cambiar tu semana."
  ],

  [
    "La constancia",
    "siempre gana."
  ],

  [
    "Cada sí",
    "empieza con muchos no."
  ],

  [
    "Hoy es un buen día",
    "para crecer."
  ],

];
late List<String> fraseDelDia;

 @override
void initState() {
  super.initState();

  final hoy = DateTime.now();

  final indice =
      (hoy.year * 1000 + hoy.month * 100 + hoy.day) %
          frasesMotivadoras.length;

  fraseDelDia = frasesMotivadoras[indice];

  WidgetsBinding.instance.addPostFrameCallback((_) {
    loadKpis();
    checkForUpdate();
    loadChatUnreadCount();

    comprobarAlertasSeguimientoJefe().then((_) {
      loadSystemUnreadCount();
    });

    chatTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        await loadChatUnreadCount();
        await comprobarAlertasSeguimientoJefe();
        await loadSystemUnreadCount();
      },
    );
  });
}
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    Future.delayed(Duration.zero, () {
      loadKpis();
    });
  }
  @override
void dispose() {
  chatTimer?.cancel();
  super.dispose();
}

Future<void> loadChatUnreadCount() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final res = await supabase
        .from('chat_mensajes')
        .select('id')
        .eq('receiver_auth_id', user.id)
        .eq('leido', false);

    if (!mounted) return;

    setState(() {
      chatUnreadCount = res.length;
    });
  } catch (e) {
    debugPrint('ERROR CHAT UNREAD HOME: $e');
  }
}

Future<void> loadSystemUnreadCount() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final alertas = await supabase
        .from('alertas')
        .select('id')
        .eq('auth_id_destino', user.id)
        .eq('leida', false);

    final notificaciones = await supabase
    .from('notificaciones')
    .select('id')
    .eq('auth_id_destino', user.id)
    .eq('leida', false);

    if (!mounted) return;

    setState(() {
      systemUnreadCount = alertas.length + notificaciones.length;
    });
  } catch (e) {
    debugPrint('ERROR SYSTEM UNREAD HOME: $e');
  }
}

Future<void> comprobarAlertasSeguimientoJefe() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final miUsuario = await supabase
        .from('usuarios')
        .select('id, auth_id, rol_usuario')
        .eq('auth_id', user.id)
        .maybeSingle();

    if (miUsuario == null) return;

    if (miUsuario['rol_usuario'] != 'jefe_equipo') return;

    final miUserId = miUsuario['id'];

    final agentes = await supabase
        .from('usuarios')
        .select('id, auth_id, nombre, apellidos, parent_id, rol_usuario')
        .eq('parent_id', miUserId)
        .eq('rol_usuario', 'agente');

    final hoy = DateTime.now();

    final limite = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    ).subtract(const Duration(days: 3));

    final limiteString =
        "${limite.year.toString().padLeft(4, '0')}-"
        "${limite.month.toString().padLeft(2, '0')}-"
        "${limite.day.toString().padLeft(2, '0')}";

    for (final agente in agentes) {
      final authIdAgente = agente['auth_id'];

      if (authIdAgente == null) continue;

      final seguimientosAtrasados = await supabase
          .from('seguimiento_clientes')
          .select('id')
          .eq('auth_id', authIdAgente)
          .eq('estado', 'Pendiente')
          .lte('proxima_llamada', limiteString);

      if (seguimientosAtrasados.isEmpty) continue;

      final inicioDia = DateTime(
  hoy.year,
  hoy.month,
  hoy.day,
);

final inicioDiaString = inicioDia.toIso8601String();

final alertaExistenteHoy = await supabase
    .from('alertas')
    .select('id')
    .eq('auth_id_destino', user.id)
    .eq('auth_id_origen', authIdAgente)
    .eq('tipo', 'seguimiento_atrasado')
    .gte('created_at', inicioDiaString)
    .maybeSingle();

if (alertaExistenteHoy != null) continue;

      final nombreAgente =
          "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();

      await supabase.from('alertas').insert({
        'auth_id_destino': user.id,
        'auth_id_origen': authIdAgente,
        'tipo': 'seguimiento_atrasado',
        'titulo': 'Seguimiento atrasado',
        'mensaje':
            '${nombreAgente.isEmpty ? 'Un agente de tu equipo' : nombreAgente} tiene ${seguimientosAtrasados.length} seguimiento(s) pendiente(s) atrasado(s) más de 3 días. Revisa con él que gestione esas llamadas cuanto antes.',
      });
    }
  } catch (e) {
    debugPrint("ERROR ALERTA SEGUIMIENTO JEFE: $e");
  }
}

Future<List<Map<String, dynamic>>> cargarAlertasSistema() async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  try {
    final alertas = await supabase
        .from('alertas')
        .select()
        .eq('auth_id_destino', user.id)
        .eq('leida', false)
        .order('created_at', ascending: false);

    final notificaciones = await supabase
    .from('notificaciones')
    .select()
    .eq('auth_id_destino', user.id)
    .eq('leida', false)
    .order('created_at', ascending: false);

    final lista = <Map<String, dynamic>>[
      ...List<Map<String, dynamic>>.from(alertas).map((e) => {
            ...e,
            '_tabla': 'alertas',
          }),
      ...List<Map<String, dynamic>>.from(notificaciones).map((e) => {
            ...e,
            '_tabla': 'notificaciones',
          }),
    ];

    lista.sort((a, b) {
      final fa = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
      final fb = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
      return fb.compareTo(fa);
    });

    return lista;
  } catch (e) {
    debugPrint("ERROR CARGAR ALERTAS SISTEMA: $e");
    return [];
  }
}

Future<void> _abrirArchivoNotificacion(String? url) async {
  if (url == null || url.trim().isEmpty) return;

  final uri = Uri.tryParse(url.trim());
  if (uri == null) return;

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openNotificationsPanel() async {
  final alertasSistema = await cargarAlertasSistema();

  if (!mounted) return;

  setState(() {
    systemUnreadCount = alertasSistema.length;
  });

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.65),
    isScrollControlled: true,
    builder: (modalContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.38,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF061329).withOpacity(0.97),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withOpacity(0.25),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Row(
                        children: [
                          Icon(
                            Icons.notifications_active_rounded,
                            color: Color(0xFF22D3EE),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Notificaciones",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      if (chatUnreadCount > 0)
                        _notificationItem(
                          icon: Icons.chat_bubble_rounded,
                          color: const Color(0xFF22D3EE),
                          title: "Chats pendientes",
                          subtitle:
                              "Tienes $chatUnreadCount mensaje${chatUnreadCount == 1 ? '' : 's'} sin leer",
                          onTap: () async {
                            Navigator.pop(modalContext);

                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const InternalChatScreen(),
                              ),
                            );

                            await loadChatUnreadCount();
                          },
                        ),

                      if (chatUnreadCount > 0 && alertasSistema.isNotEmpty)
                        const SizedBox(height: 12),

                      for (final alerta in alertasSistema) ...[
                        _notificationItem(
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orangeAccent,
                          title: alerta['titulo'] ?? 'Alerta',
                          subtitle: alerta['mensaje'] ?? '',
                          onTap: () async {
                            try {
                             final tabla = alerta['_tabla']?.toString() ?? 'alertas';

await supabase
    .from(tabla)
    .update({'leida': true})
    .eq('id', alerta['id']);

                              await loadSystemUnreadCount();

                              if (!mounted) return;

                              Navigator.pop(modalContext);

                              if (alerta['_tabla'] == 'notificaciones') {
  final archivoUrl = alerta['archivo_url']?.toString();

  if (archivoUrl != null && archivoUrl.isNotEmpty) {
    await _abrirArchivoNotificacion(archivoUrl);
  } else if (alerta['pantalla_destino'] == 'mis_gestiones' ||
      alerta['pantalla_destino'] == 'gestiones_asignadas') {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MisGestionesScreen(),
      ),
    );
  }
}
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    "Aviso marcado como leído",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFF16A34A),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } catch (e) {
                              debugPrint("ERROR MARCANDO ALERTA LEÍDA: $e");
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (chatUnreadCount == 0 && alertasSistema.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.mark_chat_read_rounded,
                                color: Colors.white38,
                                size: 42,
                              ),
                              SizedBox(height: 10),
                              Text(
                                "No tienes notificaciones pendientes",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
Widget _notificationItem({
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color.withOpacity(0.28),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    ),
  );
}


Future<List<String>> getTeamAuthIds(String myAuthId) async {
  final usersData = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos');

  String rolNorm(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String? rolHijoEsperado(String rolPadre) {
    switch (rolNorm(rolPadre)) {
      case 'director_nacional':
        return 'director_zona';
      case 'director_zona':
        return 'jefe_ventas';
      case 'jefe_ventas':
        return 'jefe_equipo';
      case 'jefe_equipo':
        return 'agente';
      default:
        return null;
    }
  }

  final usuarios = List<Map<String, dynamic>>.from(usersData).map((u) {
    return <String, dynamic>{
      'id': u['id']?.toString().trim(),
      'auth_id': u['auth_id']?.toString().trim(),
      'parent_id': u['parent_id']?.toString().trim(),
      'rol': rolNorm(u['rol_usuario']),
      'nombre': u['nombre']?.toString() ?? '',
      'apellidos': u['apellidos']?.toString() ?? '',
    };
  }).toList();

  final yo = usuarios.firstWhere(
    (u) => u['auth_id'] == myAuthId,
    orElse: () => <String, dynamic>{},
  );

  if (yo.isEmpty) {
    debugPrint('HOME PRIMAS: no se encontró el perfil conectado.');
    return [myAuthId];
  }

  final resultado = <String>{};
  final idsVisitados = <String>{};

  final hijosPorParentId = <String, List<Map<String, dynamic>>>{};

  for (final usuario in usuarios) {
    final parentId = usuario['parent_id']?.toString();

    if (parentId == null ||
        parentId.isEmpty ||
        parentId.toLowerCase() == 'null') {
      continue;
    }

    hijosPorParentId
        .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
        .add(usuario);
  }

  void recorrerEstructura(Map<String, dynamic> usuario) {
    final id = usuario['id']?.toString();
    final authId = usuario['auth_id']?.toString();
    final rolUsuario = rolNorm(usuario['rol']);

    if (id == null || id.isEmpty || idsVisitados.contains(id)) return;

    idsVisitados.add(id);

    if (authId != null &&
        authId.isNotEmpty &&
        authId.toLowerCase() != 'null') {
      resultado.add(authId);
    }

    final siguienteRol = rolHijoEsperado(rolUsuario);
    if (siguienteRol == null) return;

    final hijosValidos = (hijosPorParentId[id] ?? <Map<String, dynamic>>[])
        .where((hijo) => rolNorm(hijo['rol']) == siguienteRol)
        .toList();

    for (final hijo in hijosValidos) {
      recorrerEstructura(hijo);
    }
  }

  final rol = rolNorm(yo['rol']);

  if (rol == 'administracion') {
    for (final usuario in usuarios) {
      final authId = usuario['auth_id']?.toString();
      if (authId != null &&
          authId.isNotEmpty &&
          authId.toLowerCase() != 'null') {
        resultado.add(authId);
      }
    }
  } else {
    recorrerEstructura(yo);
  }

  debugPrint('======= HOME PRIMAS ESTRUCTURA REAL =======');
  debugPrint('USUARIO: ${yo['nombre']} ${yo['apellidos']}');
  debugPrint('ROL: $rol');
  debugPrint('ID USUARIO: ${yo['id']}');
  debugPrint('TOTAL PERSONAS INCLUIDAS: ${resultado.length}');

  for (final usuario in usuarios.where(
    (u) => resultado.contains(u['auth_id']?.toString()),
  )) {
    debugPrint(
      '- ${usuario['nombre']} ${usuario['apellidos']} '
      '| ${usuario['rol']} | parent_id=${usuario['parent_id']}',
    );
  }

  debugPrint('===========================================');

  return resultado.toList();
}

  double _money(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    final texto = value.toString().trim();
    if (texto.isEmpty) return 0.0;

    final normalizado = texto.contains(',')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto;

    return double.tryParse(normalizado) ?? 0.0;
  }

  double _primaNetaVenta(Map<String, dynamic> venta) {
    return _money(
      venta['prima_anual_neta'] ??
          venta['prima_neta'] ??
          venta['PRIMA_ANUAL_NETA'] ??
          venta['PRIMA NETA'],
    );
  }

  double _objetivoPrimasSemanalPorRol(String role) {
    switch (role.trim().toLowerCase()) {
      case 'agente':
        return 1250.0;
      case 'jefe_equipo':
        return 3125.0;
      case 'jefe_ventas':
        return 5208.0;
      case 'director_zona':
        return 10416.0;
      case 'director_nacional':
        return 25000.0;
      case 'administracion':
        return 25000.0;
      default:
        return 1250.0;
    }
  }

  String _formatearEuros(double value, {bool decimales = false}) {
    final absoluto = value.abs();
    final textoBase = decimales
        ? absoluto.toStringAsFixed(2)
        : absoluto.round().toString();

    final partes = textoBase.split('.');
    final entero = partes.first;
    final buffer = StringBuffer();

    for (int i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(entero[i]);
    }

    final signo = value < 0 ? '-' : '';
    if (decimales) {
      return '$signo${buffer.toString()},${partes.length > 1 ? partes[1] : '00'} €';
    }

    return '$signo${buffer.toString()} €';
  }

  Future<void> loadKpis() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) return;

  try {
    setState(() => loadingKpis = true);

    final authIds = await getTeamAuthIds(user.id);

    final clientes = await supabase
    .from('clientes')
    .select()
    .inFilter('auth_id', authIds);

final ventas = await supabase
    .from('ventas')
    .select()
    .inFilter('agente_auth_id', authIds);

    List tareas = [];

    try {
      tareas = widget.role == 'director_zona'
          ? await supabase.from('tareas').select()
          : await supabase
              .from('tareas')
              .select()
              .inFilter('auth_id', authIds);
    } catch (e) {
      debugPrint("AVISO TAREAS: $e");
      tareas = [];
    }

    final ventasSemanaData = ventas
        .where((v) => _esDeEstaSemana(Map<String, dynamic>.from(v)))
        .map((v) => Map<String, dynamic>.from(v))
        .toList();

    final primasNetasSemana = ventasSemanaData.fold<double>(
      0.0,
      (total, venta) => total + _primaNetaVenta(venta),
    );

    final objetivoPrimasSemana =
        _objetivoPrimasSemanalPorRol(widget.role);

    final clientesSemanaData = clientes
        .where((c) => _esDeEstaSemana(Map<String, dynamic>.from(c)))
        .toList();

    final tareasPendientes = tareas
        .where((t) => _tareaPendiente(Map<String, dynamic>.from(t)))
        .toList();

    final usuariosRanking = await supabase
    .from('usuarios')
    .select('id, auth_id, nombre, apellidos, rol_usuario');

final todasLasVentas = await supabase
    .from('ventas')
    .select('agente_auth_id');

final Map<String, int> polizasPorAuthId = {};

for (final usuario in usuariosRanking) {
  final authId = usuario['auth_id']?.toString();

  if (authId == null || authId.isEmpty || authId == 'null') continue;

  polizasPorAuthId[authId] = 0;
}

for (final venta in todasLasVentas) {
  final authId = venta['agente_auth_id']?.toString();

  if (authId == null || authId.isEmpty || authId == 'null') continue;

  polizasPorAuthId[authId] = (polizasPorAuthId[authId] ?? 0) + 1;
}

final rankingOrdenado = polizasPorAuthId.entries.toList()
  ..sort((a, b) {
    final comparePolizas = b.value.compareTo(a.value);
    if (comparePolizas != 0) return comparePolizas;
    return a.key.compareTo(b.key);
  });

int posicion = 0;
int misPolizas = 0;

for (int i = 0; i < rankingOrdenado.length; i++) {
  final entry = rankingOrdenado[i];

  if (entry.key == user.id) {
    posicion = i + 1;
    misPolizas = entry.value;
    break;
  }
}

final primero = rankingOrdenado.isEmpty ? 0 : rankingOrdenado.first.value;

debugPrint("========== RANKING DEBUG ==========");
debugPrint("USER AUTH ID: ${user.id}");
debugPrint("USUARIOS RANKING: ${usuariosRanking.length}");
debugPrint("VENTAS RANKING: ${todasLasVentas.length}");
debugPrint("RANKING TOTAL: ${rankingOrdenado.length}");
debugPrint("MI POSICION: $posicion");
debugPrint("MIS POLIZAS: $misPolizas");
debugPrint("PRIMERO: $primero");
    final racha = await calcularRachaSemanal(
      authIds,
      objetivoPrimasSemana,
    );

    if (!mounted) return;

    setState(() {
      totalClientes = clientes.length;
      totalVentas = ventas.length;
      totalTareas = tareasPendientes.length;

      objetivoSemana = objetivoPrimasSemana;
      primasSemana = primasNetasSemana;
      clientesSemana = clientesSemanaData.length;

      rankingPosicion = posicion;
      rankingTotal = rankingOrdenado.length;
      rankingPrimero = primero;
      misPolizasTotales = misPolizas;

      rachaSemanas = racha;

      loadingKpis = false;
    });
  } catch (e) {
    debugPrint("ERROR KPI: $e");

    if (!mounted) return;

    setState(() {
      totalClientes = 0;
      totalVentas = 0;
      totalTareas = 0;

      primasSemana = 0.0;
      clientesSemana = 0;
      rachaSemanas = 0;
      objetivoSemana = _objetivoPrimasSemanalPorRol(widget.role);

      rankingPosicion = 0;
      rankingTotal = 0;
      rankingPrimero = 0;
      misPolizasTotales = 0;

      loadingKpis = false;
    });
  }
}
Future<int> calcularRachaSemanal(
  List<String> authIds,
  double objetivoPrimas,
) async {
  try {
    final ventas = await supabase
        .from('ventas')
        .select()
        .inFilter('agente_auth_id', authIds);

    int racha = 0;
    DateTime inicio = inicioSemanaActual;

    while (true) {
      final fin = inicio.add(const Duration(days: 5));

      double primasSemanaCheck = 0.0;

      for (final item in ventas) {
        final venta = Map<String, dynamic>.from(item);
        final fecha = _parseFecha(venta);

        if (fecha == null) continue;

        final limpia = DateTime(fecha.year, fecha.month, fecha.day);
        final perteneceSemana = limpia.isAtSameMomentAs(inicio) ||
            (limpia.isAfter(inicio) && limpia.isBefore(fin));

        if (perteneceSemana) {
          primasSemanaCheck += _primaNetaVenta(venta);
        }
      }

      if (primasSemanaCheck >= objetivoPrimas) {
        racha++;
        inicio = inicio.subtract(const Duration(days: 7));
      } else {
        break;
      }
    }

    return racha;
  } catch (e) {
    debugPrint('ERROR RACHA SEMANAL POR PRIMAS: $e');
    return 0;
  }
}

  Future<void> checkForUpdate() async {
    if (_checkingUpdate) return;

    _checkingUpdate = true;

    try {
      final update = await UpdateService.checkUpdate();

      if (update == null) return;

      final remoteVersion = update["version"];
      final url = update["url"];

      final hasUpdate = await UpdateService.isUpdateAvailable(remoteVersion);

      if (!mounted) return;

      if (hasUpdate && !_updateDialogShown) {
        _updateDialogShown = true;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) {
            return AlertDialog(
              title: const Text("Actualización disponible"),
              content: const Text(
                "Hay una nueva versión de la app. Debes actualizar para continuar.",
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await UpdateService.downloadAndInstall(url);
                  },
                  child: const Text("Actualizar"),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint("ERROR UPDATE CHECK: $e");
    } finally {
      _checkingUpdate = false;
    }
  }

 double get produccionPorcentaje {
  if (objetivoSemana == 0) return 0;

  final value = primasSemana / objetivoSemana;

  if (value.isNaN || value.isInfinite) return 0;

  return value.clamp(0.0, 1.0);
}

int get produccionTexto {
  return (produccionPorcentaje * 100).round();
}

DateTime get inicioSemanaActual {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - 1));
}

DateTime get finSemanaActual {
  return inicioSemanaActual.add(const Duration(days: 5));
}

DateTime? _parseFecha(Map<String, dynamic> row) {
  final posiblesCampos = [
    row['fecha'],
    row['FECHA'],
    row['created_at'],
    row['fecha_registro'],
    row['FECHA REGISTRO'],
  ];

  for (final value in posiblesCampos) {
    if (value == null) continue;

    final parsed = DateTime.tryParse(value.toString());

    if (parsed != null) return parsed;
  }

  return null;
}

bool _esDeEstaSemana(Map<String, dynamic> row) {
  final fecha = _parseFecha(row);

  if (fecha == null) return false;

  final limpia = DateTime(fecha.year, fecha.month, fecha.day);

  return limpia.isAtSameMomentAs(inicioSemanaActual) ||
      (limpia.isAfter(inicioSemanaActual) &&
          limpia.isBefore(finSemanaActual));
}

bool _tareaPendiente(Map<String, dynamic> tarea) {
  final estado = (tarea['estado'] ??
          tarea['status'] ??
          tarea['ESTADO'] ??
          tarea['STATUS'] ??
          '')
      .toString()
      .toLowerCase()
      .trim();

  final completada = tarea['completada'] ??
      tarea['finalizada'] ??
      tarea['is_done'] ??
      tarea['done'];

  if (completada == true) return false;

  if (estado.contains('completada') ||
      estado.contains('finalizada') ||
      estado.contains('hecha') ||
      estado.contains('cerrada')) {
    return false;
  }

  return true;
}

  @override
  Widget build(BuildContext context) {
    final items = _getDashboardItems(widget.role, context);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      extendBody: true,
floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
floatingActionButton: widget.role == 'director_nacional' ||
        widget.role == 'administracion'
    ? null
    : _bigSaleButton(),
      body: Stack(
        children: [
          _background(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: loadKpis,
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF071A3A),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 130),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _topBar(),
                    const SizedBox(height: 30),
                    _hero(),
                    const SizedBox(height: 24),
                    _sectionTitle(
                      "Tu rendimiento esta semana",
                      Icons.trending_up_rounded,
                    ),
                    const SizedBox(height: 14),
                    _kpiGrid(isWide),
                    const SizedBox(height: 18),
                    if (widget.role != 'director_nacional') ...[
  _goalAndStreak(),
  const SizedBox(height: 20),
  _rankingCard(),
  const SizedBox(height: 26),
] else ...[
  _dailyGoalCard(),
  const SizedBox(height: 26),
],
                    _sectionTitle(
                      "Accesos rápidos",
                      Icons.flash_on_rounded,
                    ),
                    const SizedBox(height: 14),
                    _moduleGrid(items, isWide),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _background() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF020617),
                Color(0xFF061B3A),
                Color(0xFF020617),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _glow(const Color(0xFF2563EB), 260),
        ),
        Positioned(
          top: 260,
          right: -120,
          child: _glow(const Color(0xFF7C3AED), 280),
        ),
        Positioned(
          bottom: -90,
          left: -80,
          child: _glow(const Color(0xFF22D3EE), 240),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(color: Colors.black.withOpacity(0.08)),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.34),
            color.withOpacity(0.10),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

 Widget _topBar() {
  final totalNotifications = chatUnreadCount + systemUnreadCount;

  return Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF22D3EE), Color(0xFF2563EB)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.shield_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),

      const SizedBox(width: 8),

      const Expanded(
        child: Text(
          "SafeBrok",
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: () {
              _openNotificationsPanel();
            },
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),

          if (totalNotifications > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 22,
                  minHeight: 22,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: const Color(0xFF061018),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    totalNotifications > 99
                        ? '+99'
                        : totalNotifications.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF22D3EE).withOpacity(0.35),
            const Color(0xFF7C3AED).withOpacity(0.45),
            const Color(0xFFFF7A00).withOpacity(0.35),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF061329),
              Color(0xFF071A3A),
              Color(0xFF120A2E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -15,
              child: Icon(
                Icons.rocket_launch_rounded,
                color: const Color(0xFF22D3EE).withOpacity(0.18),
                size: 120,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(
   fraseDelDia[0],
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                 Text(
  "${fraseDelDia[1]} 🚀",
                  style: TextStyle(
                    color: Color(0xFF22D3EE),
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.person_pin_rounded,
                      color: Color(0xFF22D3EE),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _roleTitle(widget.role),
                        style: const TextStyle(
                          color: Color(0xFF67E8F9),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const ProductionCountdown(),
              ],
            ),
          ],
        ),
      ),
    );
  }
    Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF22D3EE), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _kpiGrid(bool isWide) {
    final cards = [
      _metricCard(
        title: "Primas semana",
        value: _formatearEuros(primasSemana),
        subtitle: "prima neta · lunes a viernes",
        icon: Icons.euro_rounded,
        color: const Color(0xFF2563EB),
      ),
      _metricCard(
        title: "Clientes semana",
value: "$clientesSemana",
subtitle: "nuevos esta semana",
        icon: Icons.groups_rounded,
        color: const Color(0xFF14B8A6),
      ),
      _metricCard(
        title: "Pendientes",
        value: "$totalTareas",
        subtitle: "tareas",
        icon: Icons.assignment_rounded,
        color: const Color(0xFFFF7A00),
      ),
      _productionMetricCard(),
    ];

    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
     childAspectRatio: isWide ? 1.2 : 0.82,
      children: cards,
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
      padding: const EdgeInsets.all(16),
      decoration: _premiumCard(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBubble(icon, color),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loadingKpis ? "..." : value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: color == const Color(0xFFFF7A00)
                  ? Colors.white70
                  : const Color(0xFF2DD4BF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _miniSparkline(color),
        ],
      ),
    );
  }

  Widget _productionMetricCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumCard(const Color(0xFF8B5CF6)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconBubble(
                  Icons.track_changes_rounded,
                  const Color(0xFF8B5CF6),
                ),
                const Spacer(),
                const Text(
                  "Producción",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "$produccionTexto%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "del objetivo",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 54,
            height: 54,
            child: CircularProgressIndicator(
              value: produccionPorcentaje,
              strokeWidth: 7,
              backgroundColor: Colors.white.withOpacity(0.10),
              color: const Color(0xFFA855F7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalAndStreak() {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 430;

      if (isNarrow) {
        return Column(
          children: [
            _dailyGoalCard(),
            const SizedBox(height: 14),
            _streakCard(),
          ],
        );
      }

      return Row(
        children: [
          Expanded(child: _dailyGoalCard()),
          const SizedBox(width: 14),
          Expanded(child: _streakCard()),
        ],
      );
    },
  );
}

  Widget _dailyGoalCard() {
  final conseguido =
      primasSemana > objetivoSemana ? objetivoSemana : primasSemana;

  final quedan =
      (objetivoSemana - conseguido).clamp(0.0, objetivoSemana).toDouble();

  final progreso = objetivoSemana == 0 ? 0.0 : conseguido / objetivoSemana;

  return Container(
    height: 190,
    padding: const EdgeInsets.all(18),
    decoration: _premiumCard(const Color(0xFF22D3EE)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.track_changes_rounded, color: Color(0xFF22D3EE)),
            SizedBox(width: 8),
            Text(
              "OBJETIVO DE LA SEMANA",
              style: TextStyle(
                color: Color(0xFF67E8F9),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          _formatearEuros(objetivoSemana),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progreso,
            minHeight: 9,
            backgroundColor: Colors.white.withOpacity(0.10),
            color: const Color(0xFF2DD4BF),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _goalMini(
              "Has conseguido",
              _formatearEuros(primasSemana),
              const Color(0xFF2DD4BF),
            ),
            Container(
              width: 1,
              height: 30,
              color: Colors.white.withOpacity(0.10),
            ),
            _goalMini(
              "Te quedan",
              _formatearEuros(quedan),
              Colors.white,
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _goalMini(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _streakCard() {
  final textoSemana = rachaSemanas == 1 ? "semana" : "semanas";

  return Container(
    height: 190,
    padding: const EdgeInsets.all(18),
    decoration: _premiumCard(const Color(0xFFA855F7)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: Color(0xFFFF7A00),
            ),
            SizedBox(width: 8),
            Text(
              "RACHA ACTUAL",
              style: TextStyle(
                color: Color(0xFFC084FC),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          "$rachaSemanas $textoSemana",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "cumpliendo objetivos",
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          rachaSemanas == 0
              ? "🔥"
              : List.filled(rachaSemanas.clamp(1, 6), "🔥").join(" "),
          style: const TextStyle(fontSize: 20),
        ),
      ],
    ),
  );
}

 Widget _rankingCard() {
  final sinUsuarios = rankingTotal == 0 || rankingPosicion == 0;

  final diferenciaPrimero = rankingPrimero - misPolizasTotales;

  final progreso = rankingPrimero == 0
      ? 0.0
      : (misPolizasTotales / rankingPrimero).clamp(0.0, 1.0);

  String mensaje;

  if (sinUsuarios) {
    mensaje = "Ranking pendiente de cargar";
  } else if (rankingPosicion == 1) {
    mensaje = "Vas liderando el ranking";
  } else if (diferenciaPrimero <= 0) {
    mensaje = "Empatado con el primero";
  } else if (rankingPosicion <= 3) {
    mensaje = "Estás en el podio, a $diferenciaPrimero pólizas del primero";
  } else {
    mensaje = "Estás a $diferenciaPrimero pólizas del primero";
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _premiumCard(const Color(0xFF2563EB)),
    child: Row(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB020), Color(0xFFFF7A00)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB020).withOpacity(0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.emoji_events_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TU POSICIÓN",
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              sinUsuarios ? "—" : "#$rankingPosicion",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            Text(
              sinUsuarios ? "cargando" : "de $rankingTotal",
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Ranking de Ventas",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "$misPolizasTotales pólizas emitidas",
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 9,
                  backgroundColor: Colors.white.withOpacity(0.10),
                  color: const Color(0xFF22D3EE),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mensaje,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _moduleGrid(List<DashboardItem> items, bool isWide) {
    final allItems = [
  DashboardItem(
    title: "Nueva venta",
    icon: Icons.add_rounded,
    subtitle: "Crear oportunidad",
    color: const Color(0xFF2563EB),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreateSaleWizard()),
      );
    },
  ),

  DashboardItem(
    title: "Safebrok IA",
    icon: Icons.auto_awesome_rounded,
    subtitle: "Asistente inteligente",
    color: const Color(0xFF22D3EE),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SafebrokAiScreen(),
        ),
      );
    },
  ),

  DashboardItem(
  title: "Mis gestiones",
  icon: Icons.assignment_turned_in_rounded,
  subtitle: "Gestiones asignadas",
  color: const Color(0xFFFF7A00),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MisGestionesScreen(),
      ),
    );
  },
),

  ...items,
];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allItems.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isWide ? 1.45 : 0.95,
      ),
      itemBuilder: (context, index) {
        final item = allItems[index];
        return _moduleCard(item);
      },
    );
  }

  Widget _moduleCard(DashboardItem item) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(24),
      splashColor: item.color.withOpacity(0.18),
      highlightColor: item.color.withOpacity(0.08),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: _premiumCard(item.color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconBubble(
                  item.icon,
                  item.color,
                  size: 54,
                ),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: item.color.withOpacity(0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ],
            ),

            const Spacer(),

            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.10,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _bigSaleButton() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [
            Color(0xFF22D3EE),
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.50),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FloatingActionButton(
        elevation: 0,
        backgroundColor: Colors.transparent,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSaleWizard()),
          );
        },
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 46,
        ),
      ),
    );
  }

  
  

  Widget _iconBubble(IconData icon, Color color, {double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.95),
            color.withOpacity(0.28),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: color.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }

  Widget _miniSparkline(Color color) {
    return SizedBox(
      height: 22,
      child: CustomPaint(
        painter: _SparklinePainter(color),
        child: const SizedBox.expand(),
      ),
    );
  }

  BoxDecoration _premiumCard(Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withOpacity(0.22),
          const Color(0xFF061329).withOpacity(0.96),
          const Color(0xFF020617).withOpacity(0.92),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.42)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.12),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  List<DashboardItem> _getDashboardItems(String role, BuildContext context) {
    switch (role) {
    case 'director_nacional':
  return [
    DashboardItem(
      title: "KPIs Globales",
      subtitle: "Toda la compañía",
      icon: Icons.bar_chart_rounded,
      color: const Color(0xFF22D3EE),
      onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const DirectorNacionalKpisScreen(),
    ),
  );
},
    ),
    DashboardItem(
      title: "Usuarios",
      subtitle: "Toda la estructura",
      icon: Icons.groups_rounded,
      color: const Color(0xFF14B8A6),
      onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>  const MisEquiposJefeVentasScreen(),
    ),
  );
},
    ),
    DashboardItem(
  title: "Cuadro de mandos",
  subtitle: "Gobierno comercial",
  icon: Icons.admin_panel_settings_rounded,
  color: const Color(0xFF0284C7),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CuadroMandosScreen(),
      ),
    );
  },
),
    DashboardItem(
      title: "Ventas Totales",
      subtitle: "Producción global",
      icon: Icons.euro_rounded,
      color: const Color(0xFF22C55E),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MySalesScreen()),
        );
      },
    ),
    DashboardItem(
      title: "Clientes Globales",
      subtitle: "Cartera completa",
      icon: Icons.person_search_rounded,
      color: const Color(0xFF8B5CF6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyClientsScreen()),
        );
      },
    ),
  ];

case 'administracion':
  return [
    DashboardItem(
      title: "Ventas Totales",
      subtitle: "Control producción",
      icon: Icons.euro_rounded,
      color: const Color(0xFF22C55E),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MySalesScreen()),
        );
      },
    ),
    DashboardItem(
      title: "Clientes",
      subtitle: "Gestión cartera",
      icon: Icons.people_alt_rounded,
      color: const Color(0xFF14B8A6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyClientsScreen()),
        );
      },
    ),
    DashboardItem(
      title: "Tareas",
      subtitle: "Control interno",
      icon: Icons.assignment_rounded,
      color: const Color(0xFFFF7A00),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MisTareasScreen()),
        );
      },
    ),
    DashboardItem(
      title: "Agenda",
      subtitle: "Organización",
      icon: Icons.calendar_month_rounded,
      color: const Color(0xFF8B5CF6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AgendaScreen()),
        );
      },
    ),
  ];
      case 'director_zona':
        return [
         DashboardItem(
  title: "KPIs Globales",
  subtitle: "Ver métricas",
  icon: Icons.bar_chart_rounded,
  color: const Color(0xFF22D3EE),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DirectorNacionalKpisScreen(),
      ),
    );
  },
),
         DashboardItem(
  title: "Equipos",
  subtitle: "Gestionar zona",
  icon: Icons.groups_rounded,
  color: const Color(0xFF14B8A6),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MisEquiposJefeVentasScreen(),
      ),
    );
  },
),
DashboardItem(
  title: "Cuadro de mandos",
  subtitle: "Gobierno de zona",
  icon: Icons.admin_panel_settings_rounded,
  color: const Color(0xFF0284C7),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CuadroMandosScreen(),
      ),
    );
  },
),
          DashboardItem(
            title: "Ventas Totales",
            subtitle: "Ver producción",
            icon: Icons.euro_rounded,
            color: const Color(0xFF22C55E),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MySalesScreen()),
              );
            },
          ),
          
           DashboardItem(
  title: "Ranking",
  subtitle: "Clasificación",
  icon: Icons.emoji_events_rounded,
  color: const Color(0xFFFFB020),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RankingComercialScreen(),
      ),
    );
  },
),
        ];

      case 'jefe_ventas':
        return [
          DashboardItem(
            title: "Mis Equipos",
            subtitle: "Gestionar equipos",
            icon: Icons.groups_rounded,
            color: const Color(0xFF14B8A6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MisEquiposJefeVentasScreen(),
                ),
              );
            },
          ),
          DashboardItem(
            title: "Control Equipos",
            subtitle: "Ver estado",
            icon: Icons.monitor_heart_rounded,
            color: const Color(0xFF22D3EE),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ControlEquiposJefeVentasScreen(),
                ),
              );
            },
          ),
          DashboardItem(
  title: "Cuadro de mandos",
  subtitle: "Gobierno equipos",
  icon: Icons.admin_panel_settings_rounded,
  color: const Color(0xFF0284C7),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CuadroMandosScreen(),
      ),
    );
  },
),
          DashboardItem(
            title: "Rendimiento",
            subtitle: "Seguimiento",
            icon: Icons.show_chart_rounded,
            color: const Color(0xFF8B5CF6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SeguimientoJefeVentasScreen(),
                ),
              );
            },
          ),
          DashboardItem(
            title: "Agenda",
            subtitle: "Organizar citas",
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFFA855F7),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AgendaJefeVentasScreen(),
                ),
              );
            },
          ),
        ];

      case 'jefe_equipo':
        return [
          DashboardItem(
            title: "Mis Agentes",
            subtitle: "Gestionar agentes",
            icon: Icons.people_rounded,
            color: const Color(0xFF2563EB),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeamAgentsScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Clientes Equipo",
            subtitle: "Cartera equipo",
            icon: Icons.person_rounded,
            color: const Color(0xFF14B8A6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeamDashboardScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Seguimiento",
            subtitle: "Ver rendimiento",
            icon: Icons.track_changes_rounded,
            color: const Color(0xFFEC4899),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeamTrackingScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Tareas",
            subtitle: "Pendientes",
            icon: Icons.assignment_rounded,
            color: const Color(0xFFFF7A00),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JefeEquipoTareasScreen()),
              );
            },
          ),
          DashboardItem(
  title: "Agenda",
  subtitle: "Organizar agenda",
  icon: Icons.calendar_month_rounded,
  color: const Color(0xFF8B5CF6),
  onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AgendaJefeEquipoScreen(),
    ),
  );
},
),
        ];

      case 'agente':
        return [
          DashboardItem(
            title: "Mis Clientes",
            subtitle: "Ver cartera",
            icon: Icons.person_rounded,
            color: const Color(0xFF14B8A6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyClientsScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Mis Ventas",
            subtitle: "Ver ventas",
            icon: Icons.shopping_cart_rounded,
            color: const Color(0xFF22C55E),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MySalesScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Mis Tareas",
            subtitle: "Pendientes",
            icon: Icons.task_alt_rounded,
            color: const Color(0xFFFF7A00),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MisTareasScreen()),
              );
            },
          ),
          DashboardItem(
            title: "Agenda",
            subtitle: "Ver citas",
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF8B5CF6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AgendaScreen()),
              );
            },
          ),
          DashboardItem(
  title: "Recibos",
  subtitle: "Gestión de pagos",
  icon: Icons.receipt_long_rounded,
  color: const Color(0xFF06B6D4),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RecibosAgenteScreen(),
      ),
    );
  },
),
        ];

      default:
        return [];
    }
  }

  String _roleTitle(String role) {
    switch (role) {
    case 'director_nacional':
  return "Director nacional";
case 'administracion':
  return "Administración";
      case 'director_zona':
        return "Director de zona";
      case 'jefe_ventas':
        return "Jefe de ventas";
      case 'jefe_equipo':
        return "Jefe de equipo";
      case 'agente':
        return "Agente comercial";
      default:
        return "Usuario";
    }
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;

  _SparklinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    path.moveTo(0, size.height * 0.72);
    path.cubicTo(
      size.width * 0.15,
      size.height * 0.82,
      size.width * 0.22,
      size.height * 0.28,
      size.width * 0.35,
      size.height * 0.50,
    );
    path.cubicTo(
      size.width * 0.48,
      size.height * 0.78,
      size.width * 0.54,
      size.height * 0.18,
      size.width * 0.67,
      size.height * 0.42,
    );
    path.cubicTo(
      size.width * 0.80,
      size.height * 0.65,
      size.width * 0.86,
      size.height * 0.18,
      size.width,
      size.height * 0.22,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}