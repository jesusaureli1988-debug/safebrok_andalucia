import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlEquiposJefeVentasScreen extends StatefulWidget {
  const ControlEquiposJefeVentasScreen({super.key});

  @override
  State<ControlEquiposJefeVentasScreen> createState() =>
      _ControlEquiposJefeVentasScreenState();
}

class _ControlEquiposJefeVentasScreenState
    extends State<ControlEquiposJefeVentasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  Map<String, dynamic>? usuarioLogueado;
  List<Map<String, dynamic>> usuariosEstructura = [];
  List<Map<String, dynamic>> equipos = [];

  final DateTime inicioSistema = DateTime(2026, 6, 1);

  @override
  void initState() {
    super.initState();
    cargarEstado();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _idTexto(dynamic value) {
    final id = (value ?? '').toString().trim();

    if (id.isEmpty || id.toLowerCase() == 'null') {
      return '';
    }

    return id;
  }

  String _nombreCompleto(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Sin nombre';

    final nombre =
        usuario['nombre']?.toString().trim() ?? '';

    final apellidos =
        usuario['apellidos']?.toString().trim() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;

    final email =
        usuario['email']?.toString().trim() ?? '';

    return email.isNotEmpty ? email : 'Sin nombre';
  }

  String _rolTexto(dynamic rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente';
      case 'administracion':
        return 'Administración';
      default:
        return (rol ?? '').toString().replaceAll('_', ' ');
    }
  }

  bool _relacionPermitida({
    required String rolPadre,
    required String rolHijo,
  }) {
    final padre = _normalizarRol(rolPadre);
    final hijo = _normalizarRol(rolHijo);

    switch (padre) {
      case 'director_nacional':
        return hijo == 'director_zona' ||
            hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'director_zona':
        return hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_ventas':
        return hijo == 'jefe_equipo' ||
            hijo == 'agente';

      case 'jefe_equipo':
        return hijo == 'agente';

      default:
        return false;
    }
  }

  List<Map<String, dynamic>> _construirEstructura({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolPerfil =
        _normalizarRol(perfil['rol_usuario']);

    if (rolPerfil == 'administracion' ||
        rolPerfil == 'administrador' ||
        rolPerfil == 'admin') {
      return todosUsuarios.where((usuario) {
        return _idTexto(usuario['id']).isNotEmpty &&
            _idTexto(usuario['auth_id']).isNotEmpty;
      }).toList();
    }

    final hijosPorParentId =
        <String, List<Map<String, dynamic>>>{};

    for (final usuario in todosUsuarios) {
      final parentId =
          _idTexto(usuario['parent_id']);

      if (parentId.isEmpty) continue;

      hijosPorParentId
          .putIfAbsent(
            parentId,
            () => <Map<String, dynamic>>[],
          )
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final idActual = _idTexto(actual['id']);

      if (idActual.isEmpty ||
          visitados.contains(idActual)) {
        return;
      }

      visitados.add(idActual);
      resultado.add(actual);

      final rolActual =
          _normalizarRol(actual['rol_usuario']);

      final hijos = hijosPorParentId[idActual] ??
          const <Map<String, dynamic>>[];

      for (final hijo in hijos) {
        final rolHijo =
            _normalizarRol(hijo['rol_usuario']);

        if (!_relacionPermitida(
          rolPadre: rolActual,
          rolHijo: rolHijo,
        )) {
          debugPrint(
            'CONTROL EQUIPOS: usuario bloqueado '
            '${_nombreCompleto(hijo)} '
            '| rol=$rolHijo '
            '| parent=${hijo['parent_id']} '
            '| padre=$rolActual',
          );

          continue;
        }

        recorrer(hijo);
      }
    }

    recorrer(perfil);

    return resultado;
  }

  Future<void> cargarEstado() async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = 'No hay ningún usuario conectado.';
        equipos = [];
        usuariosEstructura = [];
      });

      return;
    }

    try {
      if (mounted) {
        setState(() {
          loading = true;
          error = null;
        });
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception(
          'No se encontró el perfil del usuario conectado.',
        );
      }

      final perfil =
          Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          );

      final todosUsuarios =
          List<Map<String, dynamic>>.from(usuariosData);

      final estructura = _construirEstructura(
        perfil: perfil,
        todosUsuarios: todosUsuarios,
      );

      final mapaPorId =
          <String, Map<String, dynamic>>{};

      for (final usuario in estructura) {
        final id = _idTexto(usuario['id']);

        if (id.isNotEmpty) {
          mapaPorId[id] = usuario;
        }
      }

      /*
       * Cada agente se agrupa con el jefe de equipo más cercano
       * que tenga por encima dentro de la estructura.
       *
       * Si no existe jefe de equipo, se crea un grupo directo con
       * su responsable inmediato. De esta forma también aparecen:
       *
       * - agentes directos de un jefe de ventas;
       * - agentes directos de un director de zona;
       * - agentes directos de un director nacional.
       */
      final grupos =
          <String, Map<String, dynamic>>{};

      Map<String, dynamic>? buscarResponsableGrupo(
        Map<String, dynamic> agente,
      ) {
        var parentId =
            _idTexto(agente['parent_id']);

        Map<String, dynamic>? primerResponsable;

        final visitados = <String>{};

        while (parentId.isNotEmpty &&
            !visitados.contains(parentId)) {
          visitados.add(parentId);

          final padre = mapaPorId[parentId];

          if (padre == null) break;

          primerResponsable ??= padre;

          if (_normalizarRol(
                padre['rol_usuario'],
              ) ==
              'jefe_equipo') {
            return padre;
          }

          parentId =
              _idTexto(padre['parent_id']);
        }

        return primerResponsable ?? perfil;
      }

      final agentes = estructura.where(
        (usuario) =>
            _normalizarRol(usuario['rol_usuario']) ==
            'agente',
      );

      for (final agente in agentes) {
        final responsable =
            buscarResponsableGrupo(agente);

        if (responsable == null) continue;

        final responsableId =
            _idTexto(responsable['id']);

        if (responsableId.isEmpty) continue;

        final key =
            '${_normalizarRol(responsable['rol_usuario'])}:$responsableId';

        grupos.putIfAbsent(
          key,
          () => <String, dynamic>{
            'jefe':
                Map<String, dynamic>.from(responsable),
            'agentes':
                <Map<String, dynamic>>[],
            'esEquipoDirecto':
                _normalizarRol(
                      responsable['rol_usuario'],
                    ) !=
                    'jefe_equipo',
          },
        );

        final tareas = await _analizarTareas(
          _idTexto(agente['auth_id']),
        );

        final incidencias = tareas
            .where((tarea) => tarea['ok'] == false)
            .length;

        final lista =
            grupos[key]!['agentes']
                as List<Map<String, dynamic>>;

        lista.add({
          'agente':
              Map<String, dynamic>.from(agente),
          'tareas': tareas,
          'incidencias': incidencias,
        });
      }

      final resultado =
          <Map<String, dynamic>>[];

      for (final grupo in grupos.values) {
        final agentesGrupo =
            List<Map<String, dynamic>>.from(
          grupo['agentes'],
        );

        agentesGrupo.sort((a, b) {
          final incA =
              (a['incidencias'] ?? 0) as int;

          final incB =
              (b['incidencias'] ?? 0) as int;

          final porIncidencias =
              incB.compareTo(incA);

          if (porIncidencias != 0) {
            return porIncidencias;
          }

          final nombreA = _nombreCompleto(
            Map<String, dynamic>.from(
              a['agente'],
            ),
          );

          final nombreB = _nombreCompleto(
            Map<String, dynamic>.from(
              b['agente'],
            ),
          );

          return nombreA
              .toLowerCase()
              .compareTo(nombreB.toLowerCase());
        });

        final agentesConIncidencias =
            agentesGrupo.where((item) {
          return ((item['incidencias'] ?? 0) as int) >
              0;
        }).length;

        resultado.add({
          'jefe': grupo['jefe'],
          'agentes': agentesGrupo,
          'totalAgentes': agentesGrupo.length,
          'incidenciasEquipo':
              agentesConIncidencias,
          'esEquipoDirecto':
              grupo['esEquipoDirecto'] == true,
        });
      }

      resultado.sort((a, b) {
        final incA =
            (a['incidenciasEquipo'] ?? 0) as int;

        final incB =
            (b['incidenciasEquipo'] ?? 0) as int;

        final porIncidencias =
            incB.compareTo(incA);

        if (porIncidencias != 0) {
          return porIncidencias;
        }

        final jefeA =
            Map<String, dynamic>.from(a['jefe']);

        final jefeB =
            Map<String, dynamic>.from(b['jefe']);

        return _nombreCompleto(jefeA)
            .toLowerCase()
            .compareTo(
              _nombreCompleto(jefeB).toLowerCase(),
            );
      });

      debugPrint(
        '======= CONTROL EQUIPOS ESTRUCTURA REAL =======',
      );
      debugPrint(
        'USUARIO: ${_nombreCompleto(perfil)}',
      );
      debugPrint(
        'ROL: ${perfil['rol_usuario']}',
      );
      debugPrint(
        'PERSONAS EN ESTRUCTURA: ${estructura.length}',
      );
      debugPrint(
        'EQUIPOS GENERADOS: ${resultado.length}',
      );
      debugPrint(
        'AGENTES CONTROLADOS: '
        '${resultado.fold<int>(0, (total, equipo) => total + ((equipo['totalAgentes'] ?? 0) as int))}',
      );

      for (final equipo in resultado) {
        final responsable =
            Map<String, dynamic>.from(
          equipo['jefe'],
        );

        debugPrint(
          '- ${_nombreCompleto(responsable)} '
          '| rol=${responsable['rol_usuario']} '
          '| agentes=${equipo['totalAgentes']} '
          '| directo=${equipo['esEquipoDirecto']}',
        );
      }

      debugPrint(
        '==============================================',
      );

      if (!mounted) return;

      setState(() {
        usuarioLogueado = perfil;
        usuariosEstructura = estructura;
        equipos = resultado;
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR CONTROL EQUIPOS: $e',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        loading = false;
        error = e.toString();
        equipos = [];
        usuariosEstructura = [];
      });
    }
  }

  Future<List<Map<String, dynamic>>> _analizarTareas(
    String authId,
  ) async {
    if (authId.isEmpty) {
      return [
        {
          'titulo': 'Referencias diarias',
          'ok': false,
          'detalle': 'Usuario sin auth_id válido',
          'icon': Icons.people_alt_rounded,
        },
        {
          'titulo': 'Contactos diarios',
          'ok': false,
          'detalle': 'Usuario sin auth_id válido',
          'icon': Icons.phone_in_talk_rounded,
        },
        {
          'titulo': 'Seguimientos vencidos',
          'ok': false,
          'detalle': 'Usuario sin auth_id válido',
          'icon': Icons.notification_important_rounded,
        },
        {
          'titulo': 'Entrada en tareas',
          'ok': false,
          'detalle': 'Usuario sin auth_id válido',
          'icon': Icons.task_alt_rounded,
        },
      ];
    }

    final now = DateTime.now();
    final inicioMes =
        DateTime(now.year, now.month, 1);

    final referencias = await supabase
        .from('referencias_viables')
        .select('created_at')
        .eq('auth_id', authId)
        .gte(
          'created_at',
          inicioMes.toIso8601String(),
        );

    final refsPorDia = <String, int>{};

    for (final referencia in referencias) {
      final fecha = DateTime.tryParse(
        referencia['created_at']?.toString() ?? '',
      );

      if (fecha == null) continue;

      final key =
          '${fecha.year}-${fecha.month}-${fecha.day}';

      refsPorDia[key] =
          (refsPorDia[key] ?? 0) + 1;
    }

    int diasMalReferencias = 0;

    for (int dia = 1; dia <= now.day; dia++) {
      final key =
          '${now.year}-${now.month}-$dia';

      if ((refsPorDia[key] ?? 0) < 3) {
        diasMalReferencias++;
      }
    }

    final contactos = await supabase
        .from('contactos_diarios')
        .select('created_at, contactos_positivos')
        .eq('auth_id', authId)
        .gte(
          'created_at',
          inicioMes.toIso8601String(),
        );

    final contactosPorDia = <String, int>{};

    for (final contacto in contactos) {
      final fecha = DateTime.tryParse(
        contacto['created_at']?.toString() ?? '',
      );

      if (fecha == null) continue;

      final key =
          '${fecha.year}-${fecha.month}-${fecha.day}';

      final positivos = contacto['contactos_positivos'];

      final cantidad = positivos is num
          ? positivos.toInt()
          : int.tryParse(
                positivos?.toString() ?? '',
              ) ??
              0;

      contactosPorDia[key] =
          (contactosPorDia[key] ?? 0) + cantidad;
    }

    int diasMalContactos = 0;

    for (int dia = 1; dia <= now.day; dia++) {
      final key =
          '${now.year}-${now.month}-$dia';

      if ((contactosPorDia[key] ?? 0) < 6) {
        diasMalContactos++;
      }
    }

    final seguimientos = await supabase
        .from('seguimiento_clientes')
        .select('proxima_llamada, estado')
        .eq('auth_id', authId)
        .eq('estado', 'Pendiente');

    int seguimientosVencidos = 0;

    for (final seguimiento in seguimientos) {
      final fecha = DateTime.tryParse(
        seguimiento['proxima_llamada']
                ?.toString() ??
            '',
      );

      if (fecha != null && fecha.isBefore(now)) {
        seguimientosVencidos++;
      }
    }

    final actividad = await supabase
        .from('actividad_agentes')
        .select('created_at')
        .eq('auth_id', authId)
        .eq('pantalla', 'mis_tareas')
        .order('created_at', ascending: false)
        .limit(1);

    DateTime fechaBase = inicioSistema;

    if (actividad.isNotEmpty) {
      fechaBase = DateTime.tryParse(
            actividad.first['created_at']
                    ?.toString() ??
                '',
          ) ??
          inicioSistema;
    }

    final diasSinEntrar =
        now.difference(fechaBase).inDays;

    return [
      {
        'titulo': 'Referencias diarias',
        'ok': diasMalReferencias == 0,
        'detalle':
            '$diasMalReferencias días por debajo de 3 referencias',
        'icon': Icons.people_alt_rounded,
      },
      {
        'titulo': 'Contactos diarios',
        'ok': diasMalContactos == 0,
        'detalle':
            '$diasMalContactos días por debajo de 6 contactos',
        'icon': Icons.phone_in_talk_rounded,
      },
      {
        'titulo': 'Seguimientos vencidos',
        'ok': seguimientosVencidos == 0,
        'detalle':
            '$seguimientosVencidos pendientes',
        'icon':
            Icons.notification_important_rounded,
      },
      {
        'titulo': 'Entrada en tareas',
        'ok': diasSinEntrar < 3,
        'detalle':
            '$diasSinEntrar días sin entrar a tareas',
        'icon': Icons.task_alt_rounded,
      },
    ];
  }

  int get totalEquipos => equipos.length;

  int get totalAgentes {
    return equipos.fold<int>(
      0,
      (total, equipo) =>
          total +
          ((equipo['totalAgentes'] ?? 0) as int),
    );
  }

  int get totalAgentesConIncidencias {
    return equipos.fold<int>(
      0,
      (total, equipo) =>
          total +
          ((equipo['incidenciasEquipo'] ?? 0)
              as int),
    );
  }

  int get totalIncidencias {
    int total = 0;

    for (final equipo in equipos) {
      final agentes =
          List<Map<String, dynamic>>.from(
        equipo['agentes'],
      );

      for (final item in agentes) {
        total +=
            (item['incidencias'] ?? 0) as int;
      }
    }

    return total;
  }

  double get cumplimientoGlobal {
    if (totalAgentes == 0) return 1;

    final totalTareas = totalAgentes * 4;

    return ((totalTareas - totalIncidencias) /
            totalTareas)
        .clamp(0.0, 1.0);
  }

  Color _estadoColorPorIncidencias(
    int incidencias,
  ) {
    if (incidencias == 0) {
      return const Color(0xFF16A34A);
    }

    if (incidencias <= 2) {
      return const Color(0xFFF59E0B);
    }

    return const Color(0xFFDC2626);
  }

  String _estadoTextoPorIncidencias(
    int incidencias,
  ) {
    if (incidencias == 0) {
      return 'Todo correcto';
    }

    if (incidencias <= 2) {
      return 'Revisar';
    }

    return 'Crítico';
  }

  double _cumplimientoAgente(
    List<Map<String, dynamic>> tareas,
  ) {
    if (tareas.isEmpty) return 1;

    final correctas = tareas
        .where((tarea) => tarea['ok'] == true)
        .length;

    return (correctas / tareas.length)
        .clamp(0.0, 1.0);
  }

  double _cumplimientoEquipo(
    Map<String, dynamic> equipo,
  ) {
    final agentes =
        List<Map<String, dynamic>>.from(
      equipo['agentes'],
    );

    if (agentes.isEmpty) return 1;

    int totalTareas = 0;
    int tareasCorrectas = 0;

    for (final item in agentes) {
      final tareas =
          List<Map<String, dynamic>>.from(
        item['tareas'],
      );

      totalTareas += tareas.length;

      tareasCorrectas += tareas
          .where((tarea) => tarea['ok'] == true)
          .length;
    }

    if (totalTareas == 0) return 1;

    return (tareasCorrectas / totalTareas)
        .clamp(0.0, 1.0);
  }

  String _iniciales(String nombre) {
    final partes = nombre
        .trim()
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';

    if (partes.length == 1) {
      return partes.first[0].toUpperCase();
    }

    return '${partes[0][0]}${partes[1][0]}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          const _ControlBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF111827),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF111827),
                    onRefresh: cargarEstado,
                    child: ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.fromLTRB(
                        18,
                        12,
                        18,
                        30,
                      ),
                      children: [
                        _header(),
                        const SizedBox(height: 24),
                        if (error != null)
                          _errorCard()
                        else ...[
                          _hero(),
                          const SizedBox(height: 18),
                          _kpiResumen(),
                          const SizedBox(height: 24),
                          _sectionTitle(),
                          const SizedBox(height: 14),
                          if (equipos.isEmpty)
                            _emptyCard()
                          else
                            ...equipos.map(
                              _equipoControlCard,
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          elevation: 5,
          shadowColor:
              Colors.black.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () =>
                Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF111827),
                size: 29,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Control de equipos',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Auditoría comercial y tareas',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: cargarEstado,
          icon: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF111827)
                      .withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    final porcentaje = cumplimientoGlobal;

    final color = porcentaje >= 0.80
        ? const Color(0xFF16A34A)
        : porcentaje >= 0.55
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);

    final texto = porcentaje >= 0.80
        ? 'Estructura controlada'
        : porcentaje >= 0.55
            ? 'Necesita seguimiento'
            : 'Riesgo alto';

    final usuario =
        _nombreCompleto(usuarioLogueado);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
            Color(0xFFF59E0B),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF111827),
              Color(0xFF1E293B),
              Color(0xFF172554),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -16,
              child: Icon(
                Icons.health_and_safety_rounded,
                size: 135,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONTROL DE ACTIVIDAD',
                  style: TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  texto,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$usuario · ${usuariosEstructura.length} personas en tu estructura',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: porcentaje,
                          minHeight: 11,
                          backgroundColor:
                              Colors.white.withOpacity(0.15),
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(porcentaje * 100).round()}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiResumen() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.black.withOpacity(0.045),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 22,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _kpiBox(
              title: 'Equipos',
              value: totalEquipos.toString(),
              icon: Icons.account_tree_rounded,
              color: const Color(0xFF7C3AED),
            ),
          ),
          _separator(),
          Expanded(
            child: _kpiBox(
              title: 'Agentes',
              value: totalAgentes.toString(),
              icon: Icons.groups_rounded,
              color: const Color(0xFF2563EB),
            ),
          ),
          _separator(),
          Expanded(
            child: _kpiBox(
              title: 'Alertas',
              value:
                  totalAgentesConIncidencias.toString(),
              icon: Icons.warning_rounded,
              color: totalAgentesConIncidencias == 0
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Widget _separator() {
    return Container(
      width: 1,
      height: 58,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                const Color(0xFF2563EB).withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.fact_check_rounded,
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Panel de incidencias',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Control por equipo y agente',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$totalIncidencias',
          style: TextStyle(
            color: totalIncidencias == 0
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _equipoControlCard(
    Map<String, dynamic> equipo,
  ) {
    final jefe =
        Map<String, dynamic>.from(equipo['jefe']);

    final agentes =
        List<Map<String, dynamic>>.from(
      equipo['agentes'],
    );

    final nombreJefe =
        _nombreCompleto(jefe);

    final incidenciasEquipo =
        (equipo['incidenciasEquipo'] ?? 0) as int;

    final totalAgentesEquipo =
        (equipo['totalAgentes'] ?? 0) as int;

    final cumplimiento =
        _cumplimientoEquipo(equipo);

    final color =
        _estadoColorPorIncidencias(
      incidenciasEquipo,
    );

    final esDirecto =
        equipo['esEquipoDirecto'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: const Color(0xFF2563EB),
          collapsedIconColor:
              const Color(0xFF64748B),
          tilePadding: const EdgeInsets.all(17),
          childrenPadding:
              const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16,
          ),
          title: Row(
            children: [
              _avatar(
                nombreJefe,
                esDirecto
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF7C3AED),
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreJefe,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      esDirecto
                          ? 'Equipo directo · ${_rolTexto(jefe['rol_usuario'])}'
                          : 'Jefe de equipo',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$incidenciasEquipo agentes con incidencias de $totalAgentesEquipo',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                _estadoTextoPorIncidencias(
                  incidenciasEquipo,
                ),
                color,
              ),
            ],
          ),
          subtitle: Padding(
            padding:
                const EdgeInsets.only(top: 13),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: cumplimiento,
                      minHeight: 8,
                      backgroundColor:
                          const Color(0xFFE2E8F0),
                      color: cumplimiento >= 0.80
                          ? const Color(0xFF16A34A)
                          : cumplimiento >= 0.55
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFDC2626),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(cumplimiento * 100).round()}%',
                  style: TextStyle(
                    color: cumplimiento >= 0.80
                        ? const Color(0xFF16A34A)
                        : cumplimiento >= 0.55
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFDC2626),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          children: agentes.isEmpty
              ? [_emptyAgents()]
              : agentes
                  .map(_agenteControlNode)
                  .toList(),
        ),
      ),
    );
  }

  Widget _agenteControlNode(
    Map<String, dynamic> item,
  ) {
    final agente =
        Map<String, dynamic>.from(item['agente']);

    final tareas =
        List<Map<String, dynamic>>.from(
      item['tareas'],
    );

    final incidencias =
        (item['incidencias'] ?? 0) as int;

    final nombreAgente =
        _nombreCompleto(agente);

    final cumplimiento =
        _cumplimientoAgente(tareas);

    final color =
        _estadoColorPorIncidencias(incidencias);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          iconColor: const Color(0xFF2563EB),
          collapsedIconColor:
              const Color(0xFF94A3B8),
          tilePadding: const EdgeInsets.all(14),
          childrenPadding:
              const EdgeInsets.fromLTRB(
            14,
            0,
            14,
            14,
          ),
          title: Row(
            children: [
              _avatar(
                nombreAgente,
                const Color(0xFF2563EB),
                size: 46,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreAgente,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      incidencias == 0
                          ? 'Sin incidencias'
                          : '$incidencias incidencias detectadas',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                incidencias == 0
                    ? Icons.verified_rounded
                    : incidencias <= 2
                        ? Icons.manage_search_rounded
                        : Icons.warning_rounded,
                color: color,
              ),
            ],
          ),
          subtitle: Padding(
            padding:
                const EdgeInsets.only(top: 11),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: cumplimiento,
                      minHeight: 7,
                      backgroundColor:
                          const Color(0xFFE2E8F0),
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '${(cumplimiento * 100).round()}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          children:
              tareas.map(_taskTile).toList(),
        ),
      ),
    );
  }

  Widget _taskTile(
    Map<String, dynamic> tarea,
  ) {
    final ok = tarea['ok'] == true;

    final color = ok
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    final icon = tarea['icon'] is IconData
        ? tarea['icon'] as IconData
        : Icons.task_alt_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(0.17),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              ok
                  ? Icons.check_circle_rounded
                  : Icons.warning_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            icon,
            color: const Color(0xFF64748B),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  tarea['titulo']?.toString() ?? '',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tarea['detalle']?.toString() ?? '',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    height: 1.25,
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

  Widget _statusPill(
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _avatar(
    String nombre,
    Color color, {
    double size = 50,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius:
            BorderRadius.circular(size * 0.34),
        border: Border.all(
          color: color.withOpacity(0.20),
        ),
      ),
      child: Center(
        child: Text(
          _iniciales(nombre),
          style: TextStyle(
            color: color,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _emptyAgents() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(17),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF64748B),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este responsable todavía no tiene agentes asignados.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        children: [
          Icon(
            Icons.fact_check_outlined,
            color: Color(0xFF94A3B8),
            size: 62,
          ),
          SizedBox(height: 12),
          Text(
            'Sin agentes en tu estructura',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Cuando haya agentes asignados a ti o a responsables de tu estructura aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color:
              Colors.redAccent.withOpacity(0.18),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 52,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar el control',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBackground extends StatelessWidget {
  const _ControlBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFFF4F6FB),
        ),
        Positioned(
          top: -110,
          right: -85,
          child: _Glow(
            color:
                const Color(0xFF2563EB).withOpacity(0.10),
            size: 280,
          ),
        ),
        Positioned(
          top: 330,
          left: -140,
          child: _Glow(
            color:
                const Color(0xFF7C3AED).withOpacity(0.07),
            size: 310,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _Glow(
            color:
                const Color(0xFFF59E0B).withOpacity(0.07),
            size: 290,
          ),
        ),
        BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: 55, sigmaY: 55),
          child: Container(
            color: Colors.white.withOpacity(0.02),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}