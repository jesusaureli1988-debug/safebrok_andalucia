import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/policy_sales_query.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:safebrok_andalucia/core/payroll/role_compensation.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

class PayrollService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// 🔥 GENERAR NÓMINA DE UN USUARIO PARA UN MES (24–24)
  Future<void> generateNomina({
    required String authId,
    required int mes,
    required int anio,
  }) async {
    print("========== PAYROLL ==========");
    print("AUTH ID: $authId");
    print("MES RECIBIDO: $mes");
    print("ANIO RECIBIDO: $anio");

    // 1️⃣ OBTENER USUARIO Y SU ESTRUCTURA
    final user = await supabase
        .from('usuarios')
        .select()
        .eq('auth_id', authId)
        .single();

    final rol = user['rol_usuario'];

    final period = await ProductionPeriodService.instance.forMonth(
      year: anio,
      month: mes,
    );
    final inicio = period.start;
    final fin = period.endExclusive;

    // 2️⃣ OBTENER TODAS LAS VENTAS DEL PERIODO (FECHA EFECTO 24-24)
    final listaIds = await _getEstructura(authId);
    final ventas = await PolicySalesQuery.load(
      supabase,
      authIds: listaIds,
      start: inicio,
      endExclusive: fin,
      select: '''
      prima_anual_bruta,
      prima_anual_neta,
      comision,
      producto,
      fecha_efecto,
      agente_auth_id
    ''',
    );

    print("VENTAS PAYROLL:");
    print(ventas.length);

    for (final v in ventas) {
      print(v);
    }

    // 3️⃣ FILTRAR POR JERARQUÍA (IMPORTANTE)

    final ventasFiltradas = ventas.where((v) {
      final id = v['agente_auth_id']?.toString();
      return listaIds.contains(id);
    }).toList();

    // 4️⃣ CALCULAR PRIMA BRUTA Y NETA
    double primaBrutaTotal = 0;
    double primaNetaTotal = 0;
    double primasDecesosVida = 0;

    for (final v in ventasFiltradas) {
      final bruta = PremiumWeighting.gross(Map<String, dynamic>.from(v));
      final neta = PremiumWeighting.net(Map<String, dynamic>.from(v));

      primaBrutaTotal += bruta;
      primaNetaTotal += neta;

      final producto = (v['producto'] ?? '').toString();

      if (producto == 'Decesos' || producto == 'Vida') {
        primasDecesosVida += neta;
      }
    }

    // 5️⃣ COMISIONES
    double comisiones = 0;

    for (final v in ventasFiltradas) {
      if (v['agente_auth_id']?.toString() != authId) continue;
      comisiones += ((v['comision'] ?? 0) as num).toDouble();
    }

    double porcentajeDecesosVida = 0;

    if (primaNetaTotal > 0) {
      porcentajeDecesosVida = (primasDecesosVida / primaNetaTotal) * 100;
    }

    print("========== DEBUG RAPPEL ==========");
    print("PRIMA NETA TOTAL: $primaNetaTotal");
    print("PRIMAS DECESOS + VIDA: $primasDecesosVida");
    print("PORCENTAJE DV: $porcentajeDecesosVida");
    print("ROL: $rol");

    print("========== ENTRANDO RAPPEL ==========");
    print("PRIMA NETA QUE ENTRA AL RAPPEL: $primaNetaTotal");
    // 6️⃣ RAPPEL
    final compensation = RoleCompensationRules.calculate(
      role: rol?.toString() ?? '',
      premiums: primaNetaTotal,
      deathAndLifePremiums: primasDecesosVida,
    );
    final rappel = compensation.total;

    print("RAPPEL RESULTADO: $rappel");
    // 7️⃣ SUELDO FIJO
    const double sueldoFijo = 0;

    // 8️⃣ TOTAL
    double totalCobrar = sueldoFijo + comisiones + rappel;

    // 9️⃣ GUARDAR NÓMINA
    await supabase.from('nominas_mensuales').upsert({
      'auth_id': authId,
      'mes': mes,
      'anio': anio,
      'rol': rol,
      'prima_bruta_total': primaBrutaTotal,
      'prima_neta_total': primaNetaTotal,
      'primas_total': primaNetaTotal,
      'primas_decesos_vida': primasDecesosVida,
      'porcentaje_decesos_vida': porcentajeDecesosVida,
      'comisiones': comisiones,
      'rappel': rappel,
      'rappel_base': compensation.rappel,
      'diferencial_variable': compensation.variable,
      'sueldo_fijo': sueldoFijo,
      'total_cobrar': totalCobrar,
      'created_at': DateTime.now().toIso8601String(),
    });

    final nomina = await supabase
        .from('nominas_mensuales')
        .select()
        .eq('auth_id', authId)
        .order('created_at', ascending: false)
        .limit(1)
        .single();

    final nominaId = nomina['id'];

    await supabase.from('detalle_nomina').delete().eq('nomina_id', nominaId);

    await supabase.from('detalle_nomina').insert([
      {
        'nomina_id': nominaId,
        'concepto': 'Primas netas',
        'importe': primaNetaTotal,
      },
      {'nomina_id': nominaId, 'concepto': 'Comisiones', 'importe': comisiones},
      {
        'nomina_id': nominaId,
        'concepto': 'Rappel',
        'importe': compensation.rappel,
      },
      {
        'nomina_id': nominaId,
        'concepto': 'Diferencial variable',
        'importe': compensation.variable,
      },
      {'nomina_id': nominaId, 'concepto': 'Sueldo fijo', 'importe': sueldoFijo},
    ]);
  }

  /// 🔥 COMISIONES SEGÚN PRODUCTO / ROL
  double _calcularComision(double primaNeta, String rol) {
    switch (rol) {
      case 'director':
        return primaNeta * 0.04;

      case 'jefe_ventas':
        return primaNeta * 0.06;

      case 'jefe_equipo':
        return primaNeta * 0.10;

      case 'agente':
      default:
        return primaNeta * 0.15;
    }
  }

  /// Devuelve los auth_id del usuario y de toda su estructura.
  /// parent_id referencia usuarios.id (ID interno), no auth_id.
  Future<List<String>> _getEstructura(String authId) async {
    final raiz = await supabase
        .from('usuarios')
        .select('id, auth_id')
        .eq('auth_id', authId)
        .maybeSingle();

    if (raiz == null) return [authId];

    final resultado = <String>{authId};
    await _agregarDescendientes(raiz['id'].toString(), resultado, <String>{});
    return resultado.toList();
  }

  Future<void> _agregarDescendientes(
    String usuarioId,
    Set<String> authIds,
    Set<String> visitados,
  ) async {
    if (!visitados.add(usuarioId)) return;

    final directos = await supabase
        .from('usuarios')
        .select('id, auth_id')
        .eq('parent_id', usuarioId);

    for (final u in directos) {
      final hijoId = u['id']?.toString();
      final hijoAuthId = u['auth_id']?.toString();
      if (hijoAuthId != null && hijoAuthId.isNotEmpty) {
        authIds.add(hijoAuthId);
      }
      if (hijoId != null && hijoId.isNotEmpty) {
        await _agregarDescendientes(hijoId, authIds, visitados);
      }
    }
  }
}
