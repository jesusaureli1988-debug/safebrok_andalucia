import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

import 'package:safebrok_andalucia/features/payroll/nominas_screen.dart';
import 'objetivo_screen.dart';
import 'package:safebrok_andalucia/features/sales/create_sale_wizard.dart';
import 'package:safebrok_andalucia/features/sales/my_sales_screen.dart';
import 'package:safebrok_andalucia/features/referrals/referral_screen.dart';
import 'referencias_screen.dart';
import 'package:safebrok_andalucia/features/business/mejora_produccion_screen.dart';
import 'package:safebrok_andalucia/features/business/ranking_comercial_screen.dart';
import 'package:safebrok_andalucia/features/team/team_dashboard_screen.dart';

class BusinessScreen extends StatefulWidget {
  final String role;

  const BusinessScreen({super.key, required this.role});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool _objetivoCumplido = false;

  double saldoTotal = 0;
  double esteMes = 0;
  double objetivo = 0;

  double variacionMesAnterior = 0;
  bool variacionPositiva = true;

  double primasPropiasJefe = 0;
  double comisionesPropiasJefe = 0;
  double primasTotalesJefe = 0;
  double rappelJefeVentas = 0;
  double extornoPrimasMes = 0;
  double extornoComisionesMes = 0;

  List<Map<String, dynamic>> ventas = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  String _idTexto(dynamic value) {
    if (value == null) return '';

    final texto = value.toString().trim();

    if (texto.isEmpty || texto.toLowerCase() == 'null') {
      return '';
    }

    return texto;
  }

  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  double _numero(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final texto = value.toString().trim();

    if (texto.isEmpty) return 0;

    final normalizado = texto.contains(',') && texto.contains('.')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto.replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  DateTime? _fechaVenta(Map<String, dynamic> venta) {
    final valores = [
      venta['fecha_efecto'],
      venta['fecha'],
      venta['created_at'],
      venta['fecha_registro'],
    ];

    for (final valor in valores) {
      if (valor == null) continue;

      final fecha = DateTime.tryParse(valor.toString());

      if (fecha != null) {
        return fecha;
      }
    }

    return null;
  }

  int _nivelRol(dynamic rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 5;
      case 'director_zona':
        return 4;
      case 'jefe_ventas':
        return 3;
      case 'jefe_equipo':
        return 2;
      case 'agente':
        return 1;
      default:
        return 0;
    }
  }

  List<Map<String, dynamic>> _construirEstructuraValida({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolRaiz = _normalizarRol(perfil['rol_usuario']);
    final idRaiz = _idTexto(perfil['id']);
    if (idRaiz.isEmpty) {
      throw Exception(
        'El usuario conectado no tiene un id válido en usuarios.',
      );
    }
    if (rolRaiz == 'administracion' || rolRaiz == 'director_nacional') {
      return todosUsuarios.where((usuario) {
        return _idTexto(usuario['id']).isNotEmpty &&
            _idTexto(usuario['auth_id']).isNotEmpty;
      }).toList();
    }
    final hijosPorParent = <String, List<Map<String, dynamic>>>{};
    for (final fila in todosUsuarios) {
      final usuario = Map<String, dynamic>.from(fila);
      final parentId = _idTexto(usuario['parent_id']);
      if (parentId.isEmpty) continue;
      hijosPorParent
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }
    final resultado = <Map<String, dynamic>>[Map<String, dynamic>.from(perfil)];
    final visitados = <String>{idRaiz};
    final pendientes = <Map<String, dynamic>>[
      Map<String, dynamic>.from(perfil),
    ];
    while (pendientes.isNotEmpty) {
      final padre = pendientes.removeAt(0);
      final padreId = _idTexto(padre['id']);
      final nivelPadre = _nivelRol(padre['rol_usuario']);
      final hijos = hijosPorParent[padreId] ?? <Map<String, dynamic>>[];
      for (final hijoOriginal in hijos) {
        final hijo = Map<String, dynamic>.from(hijoOriginal);
        final hijoId = _idTexto(hijo['id']);
        final nivelHijo = _nivelRol(hijo['rol_usuario']);
        if (hijoId.isEmpty || visitados.contains(hijoId)) continue;
        if (nivelPadre <= 0 || nivelHijo <= 0 || nivelHijo >= nivelPadre)
          continue;
        visitados.add(hijoId);
        resultado.add(hijo);
        pendientes.add(hijo);
      }
    }
    return resultado;
  }

  Future<void> loadData() async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      return;
    }

    try {
      if (mounted) {
        setState(() {
          loading = true;
        });
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception('No se encontró el perfil del usuario conectado.');
      }

      final perfil = Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          );

      final todosUsuarios = List<Map<String, dynamic>>.from(usuariosData);

      final estructura = _construirEstructuraValida(
        perfil: perfil,
        todosUsuarios: todosUsuarios,
      );

      final authIdsEstructura = estructura
          .map((usuario) => _idTexto(usuario['auth_id']))
          .where((authId) => authId.isNotEmpty)
          .toSet()
          .toList();

      if (authIdsEstructura.isEmpty) {
        throw Exception('La estructura no contiene auth_id válidos.');
      }

      final productionPeriod = await ProductionPeriodService.instance.current();
      final inicioActual = productionPeriod.start;
      final finActual = productionPeriod.endExclusive;

      final inicioAnterior = DateTime(
        inicioActual.year,
        inicioActual.month - 1,
        24,
      );

      final finAnterior = inicioActual;

      final ventasActualData = await supabase
          .from('ventas')
          .select(
            'id, agente_auth_id, prima_anual_neta, comision, producto, '
            'precio, cliente_id, fecha_efecto, created_at',
          )
          .inFilter('agente_auth_id', authIdsEstructura)
          .gte('fecha_efecto', inicioActual.toIso8601String())
          .lt('fecha_efecto', finActual.toIso8601String());

      final ventasAnteriorData = await supabase
          .from('ventas')
          .select(
            'id, agente_auth_id, prima_anual_neta, comision, producto, '
            'fecha_efecto, created_at',
          )
          .inFilter('agente_auth_id', authIdsEstructura)
          .gte('fecha_efecto', inicioAnterior.toIso8601String())
          .lt('fecha_efecto', finAnterior.toIso8601String());

      final ventasActuales = List<Map<String, dynamic>>.from(ventasActualData)
          .where((venta) {
            return authIdsEstructura.contains(
              _idTexto(venta['agente_auth_id']),
            );
          })
          .toList();

      final ventasAnteriores =
          List<Map<String, dynamic>>.from(ventasAnteriorData).where((venta) {
            return authIdsEstructura.contains(
              _idTexto(venta['agente_auth_id']),
            );
          }).toList();

      final extornosActuales = await getExtornosPeriodo(
        start: inicioActual,
        end: finActual,
        authIds: authIdsEstructura,
        authIdSoloComision: authUser.id,
      );

      final extornosAnteriores = await getExtornosPeriodo(
        start: inicioAnterior,
        end: finAnterior,
        authIds: authIdsEstructura,
        authIdSoloComision: authUser.id,
      );

      final calculoActual = _calcularPeriodoEconomico(
        role: _normalizarRol(perfil['rol_usuario']),
        myAuthId: authUser.id,
        ventasPeriodo: ventasActuales,
        extornos: extornosActuales,
      );

      final calculoAnterior = _calcularPeriodoEconomico(
        role: _normalizarRol(perfil['rol_usuario']),
        myAuthId: authUser.id,
        ventasPeriodo: ventasAnteriores,
        extornos: extornosAnteriores,
      );

      final ultimasVentasData = await supabase
          .from('ventas')
          .select(
            'producto, precio, cliente_id, agente_auth_id, '
            'fecha_efecto, created_at',
          )
          .inFilter('agente_auth_id', authIdsEstructura)
          .order('fecha_efecto', ascending: false)
          .limit(2);

      final ultimasVentasRaw =
          List<Map<String, dynamic>>.from(ultimasVentasData).where((venta) {
            return authIdsEstructura.contains(
              _idTexto(venta['agente_auth_id']),
            );
          }).toList();

      final clienteIds = ultimasVentasRaw
          .map((venta) => _idTexto(venta['cliente_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final clientesMap = <String, String>{};

      if (clienteIds.isNotEmpty) {
        final clientesData = await supabase
            .from('clientes')
            .select('id, nombre')
            .inFilter('id', clienteIds);

        for (final cliente in List<Map<String, dynamic>>.from(clientesData)) {
          final id = _idTexto(cliente['id']);

          if (id.isEmpty) continue;

          clientesMap[id] =
              cliente['nombre']?.toString().trim().isNotEmpty == true
              ? cliente['nombre'].toString().trim()
              : 'Sin cliente';
        }
      }

      final ultimasVentasConNombre = ultimasVentasRaw.map((venta) {
        final clienteId = _idTexto(venta['cliente_id']);

        return {
          ...venta,
          'cliente_nombre': clientesMap[clienteId] ?? 'Sin cliente',
        };
      }).toList();

      final sueldoActual = calculoActual['sueldo'] ?? 0;
      final sueldoAnterior = calculoAnterior['sueldo'] ?? 0;

      final variacion = sueldoAnterior > 0
          ? ((sueldoActual - sueldoAnterior) / sueldoAnterior) * 100
          : sueldoActual > 0
          ? 100.0
          : 0.0;

      final primasNetasActuales = calculoActual['primas_netas'] ?? 0;

      final primasDVActuales = calculoActual['primas_dv'] ?? 0;

      final objetivoPrimas = _objetivoPrimasPorRol(perfil['rol_usuario']);

      final porcentajeDV = primasNetasActuales > 0
          ? (primasDVActuales / primasNetasActuales) * 100
          : 0.0;

      final objetivoCumplido =
          primasNetasActuales >= objetivoPrimas && porcentajeDV >= 30;

      final progreso = objetivoPrimas <= 0
          ? 0.0
          : (primasNetasActuales / objetivoPrimas).clamp(0.0, 1.0);

      debugPrint('=========================================');
      debugPrint('BUSINESS SCREEN');
      debugPrint('ROL: ${perfil['rol_usuario']}');
      debugPrint('PERSONAS EN ESTRUCTURA: ${estructura.length}');
      debugPrint('AUTH IDS AUTORIZADOS: ${authIdsEstructura.length}');
      debugPrint('VENTAS PERIODO ACTUAL: ${ventasActuales.length}');
      debugPrint('PRIMAS NETAS: $primasNetasActuales');
      debugPrint(
        'COMISIÓN PROPIA NETA: '
        '${calculoActual['comision_propia']}',
      );
      debugPrint('RAPPEL/SUELDO ROL: ${calculoActual['incentivo']}');
      debugPrint('SUELDO GENERADO: $sueldoActual');
      debugPrint('=========================================');

      if (!mounted) return;

      setState(() {
        primasPropiasJefe = calculoActual['primas_propias'] ?? 0;

        comisionesPropiasJefe = calculoActual['comision_propia'] ?? 0;

        primasTotalesJefe = primasNetasActuales;

        rappelJefeVentas = calculoActual['incentivo'] ?? 0;

        extornoPrimasMes = extornosActuales['prima'] ?? 0;

        extornoComisionesMes = extornosActuales['comision_propia'] ?? 0;

        /*
         * Los dos bloques muestran exactamente el mismo sueldo generado.
         */
        saldoTotal = sueldoActual;
        esteMes = sueldoActual;

        objetivo = progreso * 100;
        ventas = ultimasVentasConNombre;
        _objetivoCumplido = objetivoCumplido;

        variacionMesAnterior = variacion;
        variacionPositiva = variacion >= 0;

        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR BUSINESS SCREEN: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        saldoTotal = 0;
        esteMes = 0;
        objetivo = 0;
        ventas = [];
        loading = false;
      });
    }
  }

  bool _esProductoDV(dynamic productoValue) {
    final producto = (productoValue ?? '').toString().trim().toLowerCase();

    return producto.contains('vida') ||
        producto.contains('decesos') ||
        producto.contains('prima única') ||
        producto.contains('prima unica');
  }

  Map<String, double> _calcularPeriodoEconomico({
    required String role,
    required String myAuthId,
    required List<Map<String, dynamic>> ventasPeriodo,
    required Map<String, double> extornos,
  }) {
    double primasTotales = 0;
    double primasDV = 0;
    double primasPropias = 0;
    double comisionPropia = 0;

    for (final venta in ventasPeriodo) {
      final prima = _numero(venta['prima_anual_neta']);

      final authId = _idTexto(venta['agente_auth_id']);

      final producto = (venta['producto'] ?? '').toString().toLowerCase();

      primasTotales += prima;

      if (_esProductoDV(producto)) {
        primasDV += prima;
      }

      if (authId == myAuthId) {
        primasPropias += prima;
        comisionPropia += _numero(venta['comision']);
      }
    }

    primasTotales -= extornos['prima'] ?? 0;
    primasDV -= extornos['prima_dv'] ?? 0;
    comisionPropia -= extornos['comision_propia'] ?? 0;

    if (primasTotales < 0) primasTotales = 0;
    if (primasDV < 0) primasDV = 0;
    if (primasPropias < 0) primasPropias = 0;
    if (comisionPropia < 0) comisionPropia = 0;

    double incentivo = 0;
    double sueldo = 0;

    switch (_normalizarRol(role)) {
      case 'agente':
        incentivo = calcularRappelAgente(
          primasTotales: primasTotales,
          primasDV: primasDV,
        );
        sueldo = comisionPropia + incentivo;
        break;

      case 'jefe_equipo':
        incentivo = calcularRappelJefe(primasTotales);
        sueldo = comisionPropia + incentivo;
        break;

      case 'jefe_ventas':
        incentivo = calcularRappelJefeVentas(primasTotales);
        sueldo = comisionPropia + incentivo;
        break;

      case 'director_zona':
        incentivo = primasTotales * 0.10;
        sueldo = comisionPropia + incentivo;
        break;

      case 'director_nacional':
        incentivo = primasTotales * 0.05;
        sueldo = comisionPropia + incentivo;
        break;

      case 'administracion':
        incentivo = 0;
        sueldo = 0;
        break;

      default:
        sueldo = comisionPropia;
        break;
    }

    return {
      'primas_netas': primasTotales,
      'primas_dv': primasDV,
      'primas_propias': primasPropias,
      'comision_propia': comisionPropia,
      'incentivo': incentivo,
      'sueldo': sueldo,
    };
  }

  double _objetivoPrimasPorRol(dynamic rol) {
    switch (_normalizarRol(rol)) {
      case 'jefe_equipo':
        return 10000;
      case 'jefe_ventas':
        return 11500;
      case 'director_zona':
        return 15000;
      case 'director_nacional':
        return 25000;
      case 'agente':
      default:
        return 12000;
    }
  }

  double calcularRappelAgente({
    required double primasTotales,
    required double primasDV,
  }) {
    if (primasTotales <= 0) return 0;

    final porcentajeDV = (primasDV / primasTotales) * 100;

    /*
     * Tramos de 1.500 € y 2.500 €:
     * el 100% de la producción debe ser Vida o Decesos.
     */
    final cumpleCienPorCienDV = porcentajeDV >= 99.999;

    /*
     * Desde 4.000 €:
     * al menos el 30% de la producción debe ser Vida o Decesos.
     */
    final cumpleTreintaPorCientoDV = porcentajeDV >= 30;

    if (primasTotales >= 12000 && cumpleTreintaPorCientoDV) {
      return 1500;
    }

    if (primasTotales >= 9000 && cumpleTreintaPorCientoDV) {
      return 1200;
    }

    if (primasTotales >= 6000 && cumpleTreintaPorCientoDV) {
      return 800;
    }

    if (primasTotales >= 4000 && cumpleTreintaPorCientoDV) {
      return 600;
    }

    if (primasTotales >= 2500 && cumpleCienPorCienDV) {
      return 400;
    }

    if (primasTotales >= 1500 && cumpleCienPorCienDV) {
      return 200;
    }

    return 0;
  }

  double calcularRappelJefe(double primasTotales) {
    if (primasTotales < 4000) return 0;

    if (primasTotales >= 10000) {
      return 2000 + ((primasTotales - 10000) ~/ 1000) * 100;
    }

    if (primasTotales >= 9000) return 1800;
    if (primasTotales >= 8000) return 1600;
    if (primasTotales >= 7000) return 1400;
    if (primasTotales >= 6000) return 1200;
    if (primasTotales >= 5000) return 1000;
    if (primasTotales >= 4000) return 800;

    return 0;
  }

  double calcularRappelJefeVentas(double primasTotales) {
    if (primasTotales >= 11500) {
      return 2500 + ((primasTotales - 11500) ~/ 1000) * 100;
    }

    if (primasTotales >= 10500) return 2300;
    if (primasTotales >= 9500) return 2100;
    if (primasTotales >= 8500) return 1900;
    if (primasTotales >= 7500) return 1700;
    if (primasTotales >= 6500) return 1500;

    return 0;
  }

  Future<Map<String, double>> getExtornosPeriodo({
    required DateTime start,
    required DateTime end,
    required List<String> authIds,
    required String authIdSoloComision,
  }) async {
    if (authIds.isEmpty) {
      return {'prima': 0, 'prima_dv': 0, 'comision_propia': 0};
    }

    final anulacionesData = await supabase
        .from('anulaciones_polizas')
        .select(
          'venta_id, prima_extornada, comision_extornada, fecha_anulacion',
        )
        .gte('fecha_anulacion', start.toIso8601String())
        .lt('fecha_anulacion', end.toIso8601String());

    final anulaciones = List<Map<String, dynamic>>.from(anulacionesData);

    if (anulaciones.isEmpty) {
      return {'prima': 0, 'prima_dv': 0, 'comision_propia': 0};
    }

    final ventaIds = anulaciones
        .map((anulacion) => _idTexto(anulacion['venta_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ventaIds.isEmpty) {
      return {'prima': 0, 'prima_dv': 0, 'comision_propia': 0};
    }

    final ventasData = await supabase
        .from('ventas')
        .select('id, agente_auth_id, producto')
        .inFilter('id', ventaIds);

    final ventasMap = <String, Map<String, dynamic>>{};

    for (final venta in List<Map<String, dynamic>>.from(ventasData)) {
      final id = _idTexto(venta['id']);

      if (id.isNotEmpty) {
        ventasMap[id] = venta;
      }
    }

    final authIdsSet = authIds.toSet();

    double prima = 0;
    double primaDV = 0;
    double comisionPropia = 0;

    for (final anulacion in anulaciones) {
      final ventaId = _idTexto(anulacion['venta_id']);

      final venta = ventasMap[ventaId];

      if (venta == null) continue;

      final agenteAuthId = _idTexto(venta['agente_auth_id']);

      if (!authIdsSet.contains(agenteAuthId)) {
        continue;
      }

      final primaExtornada = _numero(anulacion['prima_extornada']);

      final comisionExtornada = _numero(anulacion['comision_extornada']);

      prima += primaExtornada;

      final producto = (venta['producto'] ?? '').toString().toLowerCase();

      if (_esProductoDV(producto)) {
        primaDV += primaExtornada;
      }

      if (agenteAuthId == authIdSoloComision) {
        comisionPropia += comisionExtornada;
      }
    }

    return {
      'prima': prima,
      'prima_dv': primaDV,
      'comision_propia': comisionPropia,
    };
  }

  @override
  Widget build(BuildContext context) {
    final progresoObjetivo = (objetivo / 100).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        elevation: 0,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSaleWizard()),
          );
        },
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF20E070), Color(0xFF1D7CFF), Color(0xFF7A3CFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.45),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 38),
        ),
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                    children: [
                      _header(),

                      const SizedBox(height: 22),

                      _saldoPrincipal(),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _metricCard(
                              title: "Este mes",
                              value: "${esteMes.toStringAsFixed(0)} €",
                              subtitle: "Importe generado",
                              icon: Icons.trending_up_rounded,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _metricCard(
                              title: "Objetivo",
                              value: "${objetivo.toStringAsFixed(1)}%",
                              subtitle: _objetivoCumplido
                                  ? "Objetivo cumplido"
                                  : "En progreso",
                              icon: Icons.track_changes_rounded,
                              color: _objetivoCumplido
                                  ? Colors.greenAccent
                                  : Colors.purpleAccent,
                              circularValue: progresoObjetivo,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      _objetivoCard(progresoObjetivo),

                      const SizedBox(height: 24),

                      _quickActions(),

                      const SizedBox(height: 24),

                      _businessSection(
                        title: "Últimas ventas",
                        icon: Icons.receipt_long_outlined,
                        trailing: TextButton(
                          onPressed: () {
                            if (widget.role == 'jefe_equipo') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamDashboardScreen(),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MySalesScreen(),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            "Ver todas",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        child: ventas.isEmpty
                            ? _emptySales()
                            : Column(
                                children: ventas
                                    .map(
                                      (v) => _saleRow(
                                        producto:
                                            v['producto']?.toString() ??
                                            'Venta',
                                        cliente:
                                            v['cliente_nombre']?.toString() ??
                                            'Sin cliente',
                                        importe: "${v['precio']}€",
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),

                      const SizedBox(height: 20),

                      _businessSection(
                        title: "Descubre más",
                        icon: Icons.explore_outlined,
                        child: Column(
                          children: [
                            _discoverRow(
                              icon: Icons.card_giftcard_rounded,
                              title: "Trae a un amigo",
                              color: Colors.orangeAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ReferralScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.people_alt_rounded,
                              title: "Referencias viables",
                              color: Colors.purpleAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ReferenciasScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.rocket_launch_rounded,
                              title: "Mejora tu producción",
                              color: Colors.greenAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MejoraProduccionScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.emoji_events_rounded,
                              title: "Ranking comercial",
                              color: Colors.amberAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RankingComercialScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: const Icon(
            Icons.account_circle_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Negocio",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                "Panel económico y producción comercial",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Icon(
            _objetivoCumplido
                ? Icons.verified_rounded
                : Icons.trending_up_rounded,
            color: _objetivoCumplido ? Colors.greenAccent : Colors.orangeAccent,
            size: 25,
          ),
        ),
      ],
    );
  }

  Widget _saldoPrincipal() {
    return Container(
      width: double.infinity,
      height: 238,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF062C68), Color(0xFF071B3E), Color(0xFF050B12)],
        ),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.22),
            blurRadius: 35,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 4,
            right: -8,
            top: 86,
            child: CustomPaint(
              size: const Size(double.infinity, 90),
              painter: _MiniChartPainter(positive: variacionPositiva),
            ),
          ),

          Positioned(
            right: -18,
            top: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.15),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color:
                      (variacionPositiva
                              ? Colors.greenAccent
                              : Colors.redAccent)
                          .withOpacity(0.34),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (variacionPositiva
                                ? Colors.greenAccent
                                : Colors.redAccent)
                            .withOpacity(0.18),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    variacionPositiva
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: variacionPositiva
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    "${variacionMesAnterior.abs().toStringAsFixed(1)}%",
                    style: TextStyle(
                      color: variacionPositiva
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            right: -30,
            bottom: -34,
            child: Icon(
              variacionPositiva
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 155,
              color: (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                  .withOpacity(0.055),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "SALDO GENERADO",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "${saldoTotal.toStringAsFixed(0)} €",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 50,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),

              const Spacer(),

              Row(
                children: [
                  Text(
                    "vs mes anterior",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "Periodo actual",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.42),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? circularValue,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 142),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.18), Colors.white.withOpacity(0.045)],
        ),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _hexIcon(icon, color, 42),
              const Spacer(),
              if (circularValue != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: circularValue,
                    strokeWidth: 7,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.64),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _objetivoCard(double progresoObjetivo) {
    final bool objetivoOk = _objetivoCumplido || progresoObjetivo >= 1;

    final Color colorBase = objetivoOk
        ? Colors.amberAccent
        : progresoObjetivo >= 0.80
        ? Colors.purpleAccent
        : Colors.cyanAccent;

    final IconData iconoCentro = objetivoOk
        ? Icons.workspace_premium_rounded
        : progresoObjetivo >= 0.80
        ? Icons.emoji_events_rounded
        : Icons.shield_rounded;

    return Container(
      height: 250,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF061B36),
            colorBase.withOpacity(0.15),
            const Color(0xFF080A18),
          ],
        ),
        border: Border.all(color: colorBase.withOpacity(0.34)),
        boxShadow: [
          BoxShadow(
            color: colorBase.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -8,
            top: 10,
            bottom: 8,
            child: _objetivoEscudoPremium(color: colorBase, icon: iconoCentro),
          ),

          Positioned(
            right: 8,
            bottom: 10,
            child: Container(
              width: 130,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(100),
                color: colorBase.withOpacity(0.12),
                boxShadow: [
                  BoxShadow(
                    color: colorBase.withOpacity(0.26),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          SizedBox(
            width: MediaQuery.of(context).size.width * 0.48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "OBJETIVO DEL MES",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "Tu progreso actual",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 22),

                ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [Colors.white, colorBase],
                    ).createShader(bounds);
                  },
                  child: Text(
                    "${objetivo.toStringAsFixed(1)}%",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 47,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                    ),
                  ),
                ),

                Text(
                  "del objetivo",
                  style: TextStyle(
                    color: colorBase,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 18),

                ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: LinearProgressIndicator(
                    value: progresoObjetivo,
                    minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(colorBase),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _objetivoEscudoPremium({
    required Color color,
    required IconData icon,
  }) {
    return SizedBox(
      width: 155,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.22),
                  blurRadius: 34,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),

          CustomPaint(
            size: const Size(132, 155),
            painter: _ShieldPainter(color),
          ),

          Positioned(
            top: 47,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.22),
                    color.withOpacity(0.42),
                    color.withOpacity(0.10),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.30)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 42),
            ),
          ),

          Positioned(
            left: 2,
            bottom: 28,
            child: Icon(
              Icons.spa_rounded,
              color: color.withOpacity(0.60),
              size: 44,
            ),
          ),

          Positioned(
            right: 2,
            bottom: 28,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(3.1416),
              child: Icon(
                Icons.spa_rounded,
                color: color.withOpacity(0.60),
                size: 44,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: _premiumAction(
            icon: Icons.calendar_month_rounded,
            title: "Mes",
            color: Colors.cyanAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NominasScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _premiumAction(
            icon: Icons.track_changes_rounded,
            title: "Objetivo",
            color: Colors.purpleAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ObjetivoScreen(role: widget.role),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _premiumAction(
            icon: Icons.more_horiz_rounded,
            title: "Más",
            color: Colors.orangeAccent,
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const MoreMenuSheet(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _premiumAction({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.06),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.18),
                Colors.white.withOpacity(0.045),
              ],
            ),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _hexIcon(icon, color, 45),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessSection({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _hexIcon(icon, Colors.cyanAccent, 42),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _emptySales() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        "Sin ventas registradas todavía",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.58),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _saleRow({
    required String producto,
    required String cliente,
    required String importe,
  }) {
    final color = producto.toLowerCase().contains('vida')
        ? Colors.purpleAccent
        : Colors.greenAccent;

    final icon = producto.toLowerCase().contains('vida')
        ? Icons.favorite_rounded
        : Icons.home_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _hexIcon(icon, color, 48),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cliente,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            importe,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _discoverRow({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.06),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              _hexIcon(icon, color, 46),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.35),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hexIcon(IconData icon, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.34),
            color.withOpacity(0.10),
            Colors.white.withOpacity(0.025),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF050B12), Color(0xFF071A2E), Color(0xFF050B12)],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -100,
          child: _glow(Colors.cyanAccent, 330, 0.16),
        ),
        Positioned(
          bottom: -170,
          left: -110,
          child: _glow(Colors.blueAccent, 370, 0.15),
        ),
        Positioned(
          top: 330,
          left: -120,
          child: _glow(Colors.purpleAccent, 240, 0.08),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.black.withOpacity(0.05)),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}

class MoreMenuSheet extends StatelessWidget {
  const MoreMenuSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF071421),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Más opciones",
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _item(Icons.bar_chart_rounded, "Estadísticas avanzadas"),
          _item(Icons.people_alt_rounded, "Equipo y jerarquía"),
          _item(Icons.history_rounded, "Histórico completo"),
          _item(Icons.calculate_outlined, "Simulador de comisiones"),
          _item(Icons.settings_rounded, "Configuración"),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.cyanAccent),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Colors.white38,
        ),
        onTap: () {},
      ),
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  final bool positive;

  _MiniChartPainter({required this.positive});

  @override
  void paint(Canvas canvas, Size size) {
    final color = positive ? Colors.greenAccent : Colors.redAccent;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.055)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);

      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = color.withOpacity(0.98)
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = color.withOpacity(0.20)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.23),
          color.withOpacity(0.08),
          color.withOpacity(0.00),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();

    if (positive) {
      path.moveTo(0, size.height * 0.72);
      path.cubicTo(
        size.width * 0.10,
        size.height * 0.67,
        size.width * 0.16,
        size.height * 0.36,
        size.width * 0.28,
        size.height * 0.44,
      );
      path.cubicTo(
        size.width * 0.40,
        size.height * 0.52,
        size.width * 0.44,
        size.height * 0.78,
        size.width * 0.56,
        size.height * 0.58,
      );
      path.cubicTo(
        size.width * 0.68,
        size.height * 0.34,
        size.width * 0.76,
        size.height * 0.22,
        size.width * 0.88,
        size.height * 0.30,
      );
      path.cubicTo(
        size.width * 0.94,
        size.height * 0.34,
        size.width * 0.97,
        size.height * 0.16,
        size.width,
        size.height * 0.18,
      );
    } else {
      path.moveTo(0, size.height * 0.26);
      path.cubicTo(
        size.width * 0.10,
        size.height * 0.31,
        size.width * 0.16,
        size.height * 0.58,
        size.width * 0.28,
        size.height * 0.48,
      );
      path.cubicTo(
        size.width * 0.40,
        size.height * 0.38,
        size.width * 0.44,
        size.height * 0.20,
        size.width * 0.56,
        size.height * 0.42,
      );
      path.cubicTo(
        size.width * 0.68,
        size.height * 0.66,
        size.width * 0.76,
        size.height * 0.76,
        size.width * 0.88,
        size.height * 0.68,
      );
      path.cubicTo(
        size.width * 0.94,
        size.height * 0.64,
        size.width * 0.97,
        size.height * 0.84,
        size.width,
        size.height * 0.82,
      );
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, linePaint);

    final dot = positive
        ? Offset(size.width, size.height * 0.18)
        : Offset(size.width, size.height * 0.82);

    final glowPaint = Paint()
      ..color = color.withOpacity(0.24)
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(dot, 11, glowPaint);
    canvas.drawCircle(dot, 5, dotPaint);
    canvas.drawCircle(dot, 6.5, dotBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    return oldDelegate.positive != positive;
  }
}

class _ShieldPainter extends CustomPainter {
  final Color color;

  _ShieldPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.50, 0)
      ..lineTo(size.width * 0.88, size.height * 0.18)
      ..lineTo(size.width * 0.82, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height,
        size.width * 0.18,
        size.height * 0.70,
      )
      ..lineTo(size.width * 0.12, size.height * 0.18)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.28),
          color.withOpacity(0.45),
          color.withOpacity(0.12),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
