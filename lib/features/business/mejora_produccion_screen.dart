import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

class MejoraProduccionScreen extends StatefulWidget {
  const MejoraProduccionScreen({super.key});

  @override
  State<MejoraProduccionScreen> createState() => _MejoraProduccionScreenState();
}

class _MejoraProduccionScreenState extends State<MejoraProduccionScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  static const List<String> _productos = <String>[
    'Decesos',
    'Hogar',
    'Vida',
    'Salud',
    'Auto',
    'Prima única',
  ];

  bool cargando = true;
  String? error;

  String rolLogueado = '';
  String nombreLogueado = '';
  int usuariosIncluidos = 0;

  double produccionActual = 0;
  double objetivo = 12000;
  double totalPrimasPositivas = 0;
  double totalExtornos = 0;
  int referenciasActivas = 0;

  Map<String, int> ventasPorProducto = <String, int>{
    for (final producto in _productos) producto: 0,
  };

  Map<String, double> primasPorProducto = <String, double>{
    for (final producto in _productos) producto: 0,
  };

  Map<String, double> primaMediaPorProducto = <String, double>{
    for (final producto in _productos) producto: 0,
  };

  ProductionPeriod? _productionPeriod;

  DateTime get inicioCiclo => _productionPeriod?.start ?? DateTime.now();

  DateTime get finCiclo => _productionPeriod?.endExclusive ?? DateTime.now();

  double get faltante => math.max(0, objetivo - produccionActual);

  double get porcentajeObjetivo {
    if (objetivo <= 0) return 0;
    return (produccionActual / objetivo).clamp(0.0, 1.0);
  }

  int get totalVentasNetas {
    return ventasPorProducto.values.fold<int>(0, (a, b) => a + b);
  }

  double get primaMix {
    return (primasPorProducto['Decesos'] ?? 0) +
        (primasPorProducto['Vida'] ?? 0) +
        (primasPorProducto['Prima única'] ?? 0);
  }

  double get porcentajeMix {
    if (produccionActual <= 0) return 0;
    return ((primaMix / produccionActual) * 100).clamp(0.0, 100.0);
  }

  bool get objetivoCumplido => produccionActual >= objetivo;

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  String _limpiar(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text == 'null' ? '' : text;
  }

  String _normalizar(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _nombrePerfil(Map<String, dynamic> perfil) {
    final nombreCompleto = _limpiar(perfil['nombre_completo']);
    if (nombreCompleto.isNotEmpty) return nombreCompleto;

    final nombre = _limpiar(perfil['nombre']);
    final apellidos = _limpiar(perfil['apellidos']);
    final compuesto = '$nombre $apellidos'.trim();

    if (compuesto.isNotEmpty) return compuesto;

    final email = _limpiar(perfil['email']);
    if (email.isNotEmpty) return email;

    return 'Usuario';
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;

    final normalized = raw.contains(',') && raw.contains('.')
        ? raw.replaceAll('.', '').replaceAll(',', '.')
        : raw.replaceAll(',', '.');

    return double.tryParse(normalized) ?? 0;
  }

  String _euros(double value, {int decimales = 0}) {
    final negativo = value < 0;
    final absoluto = value.abs();

    final partes = absoluto.toStringAsFixed(decimales).split('.');
    final entero = partes.first;
    final buffer = StringBuffer();

    for (int i = 0; i < entero.length; i++) {
      final posicion = entero.length - i;

      buffer.write(entero[i]);

      if (posicion > 1 && posicion % 3 == 1) {
        buffer.write('.');
      }
    }

    final decimal = decimales > 0 && partes.length > 1 ? ',${partes.last}' : '';

    return '${negativo ? '-' : ''}${buffer.toString()}$decimal €';
  }

  String _rolBonito(String rol) {
    switch (_normalizar(rol)) {
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
      case 'administrador':
      case 'admin':
        return 'Administración';
      default:
        return rol.isEmpty ? 'Usuario' : rol;
    }
  }

  double _objetivoPorRol(String rol) {
    switch (_normalizar(rol)) {
      case 'director_nacional':
        return 25000;
      case 'director_zona':
        return 15000;
      case 'jefe_ventas':
        return 11500;
      case 'jefe_equipo':
        return 10000;
      case 'agente':
        return 12000;
      case 'administracion':
      case 'administrador':
      case 'admin':
        return 25000;
      default:
        return 12000;
    }
  }

  String _clasificarProducto(dynamic value) {
    final producto = _normalizar(_limpiar(value));

    if (producto.isEmpty) return '';

    if (producto.contains('prima_unica') ||
        producto.contains('primaunica') ||
        producto.contains('p_u') ||
        producto == 'pu') {
      return 'Prima única';
    }

    if (producto.contains('deceso')) return 'Decesos';
    if (producto.contains('hogar')) return 'Hogar';
    if (producto.contains('vida')) return 'Vida';
    if (producto.contains('salud')) return 'Salud';

    if (producto.contains('auto') ||
        producto.contains('coche') ||
        producto.contains('vehiculo')) {
      return 'Auto';
    }

    return '';
  }

  bool _rolDescendientePermitido({
    required String rolLogueado,
    required String rolCandidato,
  }) {
    final logueado = _normalizar(rolLogueado);
    final candidato = _normalizar(rolCandidato);

    // Nunca se incorporan compañeros del mismo rango ni superiores.
    switch (logueado) {
      case 'director_nacional':
        return candidato == 'director_zona' ||
            candidato == 'jefe_ventas' ||
            candidato == 'jefe_equipo' ||
            candidato == 'agente';

      case 'director_zona':
        // Un DZ puede tener directamente JV, JE o agentes.
        return candidato == 'jefe_ventas' ||
            candidato == 'jefe_equipo' ||
            candidato == 'agente';

      case 'jefe_ventas':
        // Un JV puede tener directamente JE o agentes.
        return candidato == 'jefe_equipo' || candidato == 'agente';

      case 'jefe_equipo':
        return candidato == 'agente';

      case 'agente':
        return false;

      default:
        // Ante un rol desconocido se aplica cierre seguro:
        // únicamente sus propios datos.
        return false;
    }
  }

  Future<Set<String>> _obtenerAuthIdsPermitidos({
    required String usuarioId,
    required String usuarioAuthId,
    required String rolLogueado,
  }) async {
    /*
      FILTRO CERRADO DESDE SUPABASE

      No se descarga toda la organización.

      1. Se añade únicamente el auth_id del usuario logueado.
      2. Se pregunta a Supabase por usuarios cuyo parent_id sea EXACTAMENTE
         el usuarios.id del logueado.
      3. Después se repite únicamente con los hijos válidos encontrados.
      4. Se rechazan roles iguales, superiores o no permitidos.
      5. Nunca se consulta el padre del logueado, por tanto no pueden entrar
         compañeros ni otras ramas.
    */

    final permitidos = <String>{usuarioAuthId};
    final idsVisitados = <String>{usuarioId};
    final padresPendientes = <String>[usuarioId];

    while (padresPendientes.isNotEmpty) {
      final parentIdActual = padresPendientes.removeAt(0);

      final hijosData = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario')
          .eq('parent_id', parentIdActual);

      final hijos = List<Map<String, dynamic>>.from(hijosData);

      for (final hijo in hijos) {
        final hijoId = _limpiar(hijo['id']);
        final hijoAuthId = _limpiar(hijo['auth_id']);
        final hijoParentId = _limpiar(hijo['parent_id']);
        final hijoRol = _normalizar(_limpiar(hijo['rol_usuario']));

        // Comprobación redundante intencionada: el registro tiene que declarar
        // exactamente como padre al nodo desde el que se está recorriendo.
        if (hijoId.isEmpty ||
            hijoParentId != parentIdActual ||
            idsVisitados.contains(hijoId)) {
          continue;
        }

        // Bloquea compañeros, superiores y roles que no pueden colgar
        // jerárquicamente del usuario logueado.
        if (!_rolDescendientePermitido(
          rolLogueado: rolLogueado,
          rolCandidato: hijoRol,
        )) {
          continue;
        }

        idsVisitados.add(hijoId);

        if (hijoAuthId.isNotEmpty) {
          permitidos.add(hijoAuthId);
        }

        // Continuamos solamente desde un hijo que ha sido validado.
        padresPendientes.add(hijoId);
      }
    }

    debugPrint(
      '[MejoraProduccion] usuarioId=$usuarioId '
      'rol=$rolLogueado usuariosPermitidos=${permitidos.length}',
    );

    return permitidos;
  }

  Future<void> cargarDatos() async {
    final productionPeriod = await ProductionPeriodService.instance.current(
      forceRefresh: true,
    );
    _productionPeriod = productionPeriod;
    if (!mounted) return;

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        throw Exception('No hay ningún usuario autenticado.');
      }

      final perfilData = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, email')
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception('No se encontró el perfil del usuario logueado.');
      }

      final perfil = Map<String, dynamic>.from(perfilData);
      final usuarioId = _limpiar(perfil['id']);
      final usuarioAuthId = _limpiar(perfil['auth_id']);
      final rol = _normalizar(_limpiar(perfil['rol_usuario']));

      if (usuarioId.isEmpty || usuarioAuthId.isEmpty) {
        throw Exception(
          'El perfil no tiene correctamente informados id o auth_id.',
        );
      }

      final authIdsPermitidos = await _obtenerAuthIdsPermitidos(
        usuarioId: usuarioId,
        usuarioAuthId: usuarioAuthId,
        rolLogueado: rol,
      );

      final objetivoLocal = _objetivoPorRol(rol);

      final conteoProductos = <String, int>{
        for (final producto in _productos) producto: 0,
      };

      final primasProductos = <String, double>{
        for (final producto in _productos) producto: 0,
      };

      double produccion = 0;
      double primasPositivas = 0;
      double extornosTotales = 0;
      int referencias = 0;

      if (authIdsPermitidos.isNotEmpty) {
        final ventasData = await supabase
            .from('ventas')
            .select(
              'id, prima_anual_neta, producto, fecha_efecto, agente_auth_id',
            )
            .inFilter('agente_auth_id', authIdsPermitidos.toList())
            .gte('fecha_efecto', inicioCiclo.toIso8601String())
            .lt('fecha_efecto', finCiclo.toIso8601String());

        final ventas = List<Map<String, dynamic>>.from(ventasData);

        for (final venta in ventas) {
          final prima = _toDouble(venta['prima_anual_neta']);
          final producto = _clasificarProducto(venta['producto']);

          produccion += prima;
          primasPositivas += prima;

          if (producto.isNotEmpty) {
            conteoProductos[producto] = (conteoProductos[producto] ?? 0) + 1;
            primasProductos[producto] =
                (primasProductos[producto] ?? 0) + prima;
          }
        }

        final extornosData = await supabase
            .from('anulaciones_polizas')
            .select('venta_id, prima_extornada, fecha_anulacion, estado')
            .eq('estado', 'ANULADA')
            .gte('fecha_anulacion', inicioCiclo.toIso8601String())
            .lt('fecha_anulacion', finCiclo.toIso8601String());

        final extornos = List<Map<String, dynamic>>.from(extornosData);

        final ventaIds = extornos
            .map((e) => _limpiar(e['venta_id']))
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        if (ventaIds.isNotEmpty) {
          final ventasOriginalesData = await supabase
              .from('ventas')
              .select('id, agente_auth_id, producto')
              .inFilter('id', ventaIds);

          final ventasOriginales = <String, Map<String, dynamic>>{
            for (final venta in List<Map<String, dynamic>>.from(
              ventasOriginalesData,
            ))
              _limpiar(venta['id']): venta,
          };

          for (final extorno in extornos) {
            final ventaId = _limpiar(extorno['venta_id']);
            final ventaOriginal = ventasOriginales[ventaId];

            if (ventaOriginal == null) continue;

            final agenteAuthId = _limpiar(ventaOriginal['agente_auth_id']);

            if (!authIdsPermitidos.contains(agenteAuthId)) continue;

            final primaExtornada = math.max(
              0.0,
              _toDouble(extorno['prima_extornada']),
            );

            if (primaExtornada <= 0) continue;

            produccion -= primaExtornada;
            extornosTotales += primaExtornada;

            final producto = _clasificarProducto(ventaOriginal['producto']);

            if (producto.isNotEmpty) {
              primasProductos[producto] = math.max(
                0.0,
                (primasProductos[producto] ?? 0) - primaExtornada,
              );

              conteoProductos[producto] = math.max(
                0,
                (conteoProductos[producto] ?? 0) - 1,
              );
            }
          }
        }

        final referenciasData = await supabase
            .from('referencias_viables')
            .select('id')
            .inFilter('auth_id', authIdsPermitidos.toList());

        referencias = referenciasData.length;
      }

      produccion = math.max(0, produccion);

      final medias = <String, double>{
        for (final producto in _productos)
          producto: (conteoProductos[producto] ?? 0) > 0
              ? (primasProductos[producto] ?? 0) /
                    (conteoProductos[producto] ?? 1)
              : 0,
      };

      if (!mounted) return;

      setState(() {
        rolLogueado = rol;
        nombreLogueado = _nombrePerfil(perfil);
        usuariosIncluidos = authIdsPermitidos.length;

        produccionActual = produccion;
        objetivo = objetivoLocal;
        totalPrimasPositivas = primasPositivas;
        totalExtornos = extornosTotales;
        referenciasActivas = referencias;

        ventasPorProducto = conteoProductos;
        primasPorProducto = primasProductos;
        primaMediaPorProducto = medias;

        cargando = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        cargando = false;
        error = 'Error de Supabase: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cargando = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  double _primaReferencia(String producto) {
    final mediaReal = primaMediaPorProducto[producto] ?? 0;

    if (mediaReal > 0) {
      return mediaReal;
    }

    switch (producto) {
      case 'Decesos':
        return 420;
      case 'Hogar':
        return 300;
      case 'Vida':
        return 360;
      case 'Salud':
        return 650;
      case 'Auto':
        return 450;
      case 'Prima única':
        return 3000;
      default:
        return 400;
    }
  }

  List<_RecomendacionVenta> _crearRecomendaciones() {
    if (faltante <= 0) return const [];

    final recomendaciones = <_RecomendacionVenta>[];
    final mixMinimoEuros = objetivo * 0.30;
    final faltaParaMix = math.max(0.0, mixMinimoEuros - primaMix);

    double restante = faltante;

    if (faltaParaMix > 0) {
      final primaPU = _primaReferencia('Prima única');
      final cantidadPU = math.max(1, (faltaParaMix / primaPU).ceil());
      final aportacionPU = math.min(restante, cantidadPU * primaPU);

      recomendaciones.add(
        _RecomendacionVenta(
          producto: 'Prima única',
          cantidad: cantidadPU,
          primaEstimada: primaPU,
          aportacionEstimada: aportacionPU,
          motivo:
              'Ayuda a recuperar el mix mínimo del 30% y acelera el objetivo.',
        ),
      );

      restante = math.max(0, restante - aportacionPU);
    }

    if (restante > 0) {
      final candidatos = <String>['Decesos', 'Vida', 'Hogar', 'Salud', 'Auto']
        ..sort((a, b) => _primaReferencia(b).compareTo(_primaReferencia(a)));

      for (final producto in candidatos) {
        if (restante <= 0) break;

        final primaEstimada = _primaReferencia(producto);
        final maxUnidades = producto == 'Decesos' || producto == 'Vida' ? 4 : 3;

        final cantidadNecesaria = math.max(
          1,
          (restante / primaEstimada).ceil(),
        );
        final cantidad = math.min(maxUnidades, cantidadNecesaria);
        final aportacion = math.min(restante, cantidad * primaEstimada);

        recomendaciones.add(
          _RecomendacionVenta(
            producto: producto,
            cantidad: cantidad,
            primaEstimada: primaEstimada,
            aportacionEstimada: aportacion,
            motivo: producto == 'Decesos' || producto == 'Vida'
                ? 'Suma producción y refuerza el mix estratégico.'
                : 'Completa la producción pendiente con tu prima media estimada.',
          ),
        );

        restante = math.max(0, restante - aportacion);
      }
    }

    if (restante > 0) {
      final primaPU = _primaReferencia('Prima única');
      final cantidad = math.max(1, (restante / primaPU).ceil());

      recomendaciones.add(
        _RecomendacionVenta(
          producto: 'Prima única',
          cantidad: cantidad,
          primaEstimada: primaPU,
          aportacionEstimada: restante,
          motivo: 'Alternativa directa para cubrir el importe restante.',
        ),
      );
    }

    return recomendaciones;
  }

  IconData _iconoProducto(String producto) {
    switch (producto) {
      case 'Decesos':
        return Icons.shield_rounded;
      case 'Hogar':
        return Icons.home_rounded;
      case 'Vida':
        return Icons.favorite_rounded;
      case 'Salud':
        return Icons.medical_services_rounded;
      case 'Auto':
        return Icons.directions_car_rounded;
      case 'Prima única':
        return Icons.savings_rounded;
      default:
        return Icons.sell_rounded;
    }
  }

  Color _colorProducto(String producto) {
    switch (producto) {
      case 'Decesos':
        return Colors.purpleAccent;
      case 'Hogar':
        return Colors.greenAccent;
      case 'Vida':
        return Colors.pinkAccent;
      case 'Salud':
        return Colors.blueAccent;
      case 'Auto':
        return Colors.orangeAccent;
      case 'Prima única':
        return Colors.amberAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: cargarDatos,
              backgroundColor: const Color(0xFF0F172A),
              color: Colors.cyanAccent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  _header(),
                  if (cargando) ...[
                    const SizedBox(height: 130),
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ] else if (error != null) ...[
                    const SizedBox(height: 30),
                    _errorCard(),
                  ] else ...[
                    const SizedBox(height: 16),
                    _scopeCard(),
                    const SizedBox(height: 16),
                    _mainMetrics(),
                    const SizedBox(height: 18),
                    _portfolioCard(),
                    const SizedBox(height: 18),
                    _smartNeedsCard(),
                    const SizedBox(height: 18),
                    _referencesCard(),
                    const SizedBox(height: 18),
                    _motivationCard(),
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
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.maybePop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.18),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mejora tu producción',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.query_stats_rounded,
                    color: Colors.cyanAccent,
                    size: 28,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Ciclo del ${inicioCiclo.day}/${inicioCiclo.month}/${inicioCiclo.year} '
                'al ${finCiclo.subtract(const Duration(days: 1)).day}/'
                '${finCiclo.subtract(const Duration(days: 1)).month}/'
                '${finCiclo.subtract(const Duration(days: 1)).year}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorCard() {
    return _glassCard(
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.orangeAccent,
            size: 44,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudieron cargar los datos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: cargarDatos,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _scopeCard() {
    return _glassCard(
      padding: const EdgeInsets.all(15),
      borderColor: Colors.cyanAccent.withOpacity(0.24),
      child: Row(
        children: [
          _circleIcon(Icons.account_tree_rounded, Colors.cyanAccent, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreLogueado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_rolBonito(rolLogueado)} · '
                  '$usuariosIncluidos usuario${usuariosIncluidos == 1 ? '' : 's'} '
                  'incluido${usuariosIncluidos == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_user_rounded, color: Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _mainMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;

        final produccionCard = _bigMetricCard(
          title: 'Producción actual',
          value: _euros(produccionActual),
          icon: Icons.trending_up_rounded,
          accent: Colors.cyanAccent,
          footer: objetivoCumplido
              ? 'Objetivo superado'
              : 'Faltan ${_euros(faltante)}',
        );

        final objetivoCard = _objectiveCard();

        if (wide) {
          return Row(
            children: [
              Expanded(child: produccionCard),
              const SizedBox(width: 12),
              Expanded(child: objetivoCard),
            ],
          );
        }

        return Column(
          children: [produccionCard, const SizedBox(height: 12), objetivoCard],
        );
      },
    );
  }

  Widget _bigMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    required String footer,
  }) {
    return _glassCard(
      borderColor: accent.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _circleIcon(icon, accent),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                footer,
                objetivoCumplido ? Colors.greenAccent : Colors.orangeAccent,
              ),
              if (totalExtornos > 0)
                _pill('Extornos: -${_euros(totalExtornos)}', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _objectiveCard() {
    return _glassCard(
      borderColor: Colors.purpleAccent.withOpacity(0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _circleIcon(Icons.track_changes_rounded, Colors.purpleAccent),
          const SizedBox(height: 14),
          Text(
            'Objetivo ${_rolBonito(rolLogueado).toLowerCase()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _euros(objetivo),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: porcentajeObjetivo,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(porcentajeObjetivo * 100).toStringAsFixed(1)}% completado',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            objetivoCumplido
                ? 'Objetivo cumplido'
                : 'Te faltan ${_euros(faltante)}',
            style: TextStyle(
              color: objetivoCumplido
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard() {
    return _glassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.business_center_rounded,
            title: 'Producción por producto',
            subtitle:
                'Pólizas y prima anual neta del ciclo, descontando extornos',
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 720;

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _productsList()),
                    Container(
                      width: 1,
                      height: 360,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: Colors.white.withOpacity(0.12),
                    ),
                    SizedBox(width: 285, child: _mixCard()),
                  ],
                );
              }

              return Column(
                children: [
                  _productsList(),
                  const SizedBox(height: 16),
                  _mixCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _productsList() {
    return Column(
      children: [for (final producto in _productos) _productRow(producto)],
    );
  }

  Widget _productRow(String producto) {
    final cantidad = ventasPorProducto[producto] ?? 0;
    final prima = primasPorProducto[producto] ?? 0;
    final color = _colorProducto(producto);
    final maxPrima = math.max(
      1.0,
      primasPorProducto.values.fold<double>(
        0,
        (maximo, value) => math.max(maximo, value),
      ),
    );
    final progreso = (prima / maxPrima).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _smallIcon(_iconoProducto(producto), color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        producto,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      _euros(prima),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$cantidad póliza${cantidad == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
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

  Widget _mixCard() {
    final cumple = porcentajeMix >= 30;
    final valor = (porcentajeMix / 100).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cumple
              ? Colors.greenAccent.withOpacity(0.30)
              : Colors.orangeAccent.withOpacity(0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _circleIcon(
                Icons.pie_chart_rounded,
                Colors.purpleAccent,
                size: 44,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Mix Decesos + Vida + Prima única',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 130,
            width: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 130,
                  width: 130,
                  child: CircularProgressIndicator(
                    value: valor,
                    strokeWidth: 13,
                    backgroundColor: Colors.white.withOpacity(0.13),
                    valueColor: AlwaysStoppedAnimation(
                      cumple ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${porcentajeMix.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: cumple
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'mínimo 30%',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _euros(primaMix),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'prima computable en el mix',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 14),
          _pill(
            cumple ? 'Mix correcto' : 'Refuerza Decesos, Vida o Prima única',
            cumple ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ],
      ),
    );
  }

  Widget _smartNeedsCard() {
    final recomendaciones = _crearRecomendaciones();

    return _glassCard(
      padding: const EdgeInsets.all(20),
      borderColor: Colors.purpleAccent.withOpacity(0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: 'Plan inteligente de producción',
            subtitle: objetivoCumplido
                ? 'Tu objetivo de este ciclo ya está cumplido'
                : 'Calculado según tu rol, producción, mix y prima media',
          ),
          const SizedBox(height: 18),
          if (objetivoCumplido)
            _successPlan()
          else ...[
            _planSummary(recomendaciones),
            const SizedBox(height: 14),
            for (int i = 0; i < recomendaciones.length; i++) ...[
              _recommendationTile(
                index: i + 1,
                recomendacion: recomendaciones[i],
              ),
              if (i < recomendaciones.length - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            Text(
              'Estimación orientativa basada en la prima media real del ciclo. '
              'Cuando no existe histórico se utiliza una prima de referencia.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.48),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planSummary(List<_RecomendacionVenta> recomendaciones) {
    final unidades = recomendaciones.fold<int>(
      0,
      (total, item) => total + item.cantidad,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purpleAccent.withOpacity(0.16),
            Colors.cyanAccent.withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: Colors.cyanAccent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Para alcanzar los ${_euros(objetivo)} te faltan '
              '${_euros(faltante)}. El plan propone aproximadamente '
              '$unidades póliza${unidades == 1 ? '' : 's'}.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationTile({
    required int index,
    required _RecomendacionVenta recomendacion,
  }) {
    final color = _colorProducto(recomendacion.producto);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.16),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _iconoProducto(recomendacion.producto),
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${recomendacion.cantidad} '
                        '${recomendacion.producto}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  recomendacion.motivo,
                  style: const TextStyle(
                    color: Colors.white60,
                    height: 1.35,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _miniTag(
                      'Prima media ${_euros(recomendacion.primaEstimada)}',
                    ),
                    _miniTag(
                      'Aporta ≈ ${_euros(recomendacion.aportacionEstimada)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _successPlan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.28)),
      ),
      child: const Row(
        children: [
          Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 42),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Objetivo conseguido. Mantén el ritmo, protege el mix y '
              'convierte las referencias activas en nueva producción.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _referencesCard() {
    return _glassCard(
      borderColor: Colors.cyanAccent.withOpacity(0.32),
      child: Row(
        children: [
          _circleIcon(Icons.groups_rounded, Colors.cyanAccent, size: 58),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Referencias activas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Oportunidades de tu estructura en curso',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          Text(
            referenciasActivas.toString(),
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _motivationCard() {
    final mensaje = objetivoCumplido
        ? 'Objetivo cumplido. Ahora toca consolidar y superar.'
        : faltante <= objetivo * 0.20
        ? 'Estás muy cerca. Un último impulso puede cerrar el objetivo.'
        : porcentajeMix < 30
        ? 'Prioriza Decesos, Vida y Prima única para mejorar producción y mix.'
        : 'Sigue el plan inteligente y convierte cada oportunidad.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.purpleAccent.withOpacity(0.24),
            Colors.cyanAccent.withOpacity(0.18),
          ],
        ),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(color: Colors.cyanAccent.withOpacity(0.16), blurRadius: 28),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        _circleIcon(icon, Colors.cyanAccent, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _miniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, Color color, {double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.32), color.withOpacity(0.08)],
        ),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }

  Widget _smallIcon(IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.16),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _RecomendacionVenta {
  final String producto;
  final int cantidad;
  final double primaEstimada;
  final double aportacionEstimada;
  final String motivo;

  const _RecomendacionVenta({
    required this.producto,
    required this.cantidad,
    required this.primaEstimada,
    required this.aportacionEstimada,
    required this.motivo,
  });
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF020617), Color(0xFF061A2D), Color(0xFF0B1026)],
            ),
          ),
        ),
        Positioned(top: -120, right: -90, child: _glow(260, Colors.cyanAccent)),
        Positioned(
          bottom: 180,
          left: -120,
          child: _glow(280, Colors.purpleAccent),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: _glow(240, Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}
