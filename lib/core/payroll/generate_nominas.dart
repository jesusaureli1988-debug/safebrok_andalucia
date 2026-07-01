import 'package:supabase_flutter/supabase_flutter.dart';

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

print(
  "DESDE: ${DateTime(anio, mes, 24).toIso8601String()}",
);

print(
  "HASTA: ${DateTime(anio, mes + 1, 24).toIso8601String()}",
);
    // 1️⃣ OBTENER USUARIO Y SU ESTRUCTURA
    final user = await supabase
        .from('usuarios')
        .select()
        .eq('auth_id', authId)
        .single();

    final rol = user['rol_usuario'];

    final inicio = DateTime(anio, mes - 1, 24);
final fin = DateTime(anio, mes, 24, 23, 59, 59);

    // 2️⃣ OBTENER TODAS LAS VENTAS DEL PERIODO (FECHA EFECTO 24-24)
    final ventas = await supabase
    .from('ventas')
    .select('''
      prima_anual_bruta,
      prima_anual_neta,
      comision,
      producto,
      fecha_efecto,
      agente_auth_id
    ''')
    .gte('fecha_efecto', inicio.toIso8601String())
    .lte('fecha_efecto', fin.toIso8601String());
    
      

        print("VENTAS PAYROLL:");
print(ventas.length);

for (final v in ventas) {
  print(v);
}

    // 3️⃣ FILTRAR POR JERARQUÍA (IMPORTANTE)
    final listaIds = await _getEstructura(authId);

    final ventasFiltradas = ventas.where((v) {
  final id = v['agente_auth_id']?.toString();
  return listaIds.contains(id);
}).toList();

    // 4️⃣ CALCULAR PRIMA BRUTA Y NETA
   double primaBrutaTotal = 0;
double primaNetaTotal = 0;
double primasDecesosVida = 0;

    for (final v in ventasFiltradas) {
  final bruta =
      ((v['prima_anual_bruta'] ?? 0) as num).toDouble();

  final neta =
      ((v['prima_anual_neta'] ?? 0) as num).toDouble();

  primaBrutaTotal += bruta;
  primaNetaTotal += neta;

  final producto = (v['producto'] ?? '').toString();

  if (producto == 'Decesos' ||
      producto == 'Vida') {
    primasDecesosVida += neta;
  }
}

    // 5️⃣ COMISIONES
    double comisiones = 0;

for (final v in ventasFiltradas) {
  comisiones +=
      ((v['comision'] ?? 0) as num).toDouble();
}

double porcentajeDecesosVida = 0;

if (primaNetaTotal > 0) {
  porcentajeDecesosVida =
      (primasDecesosVida / primaNetaTotal) * 100;
}

print("========== DEBUG RAPPEL ==========");
print("PRIMA NETA TOTAL: $primaNetaTotal");
print("PRIMAS DECESOS + VIDA: $primasDecesosVida");
print("PORCENTAJE DV: $porcentajeDecesosVida");
print("ROL: $rol");

print("========== ENTRANDO RAPPEL ==========");
print("PRIMA NETA QUE ENTRA AL RAPPEL: $primaNetaTotal");
    // 6️⃣ RAPPEL
   double rappel = _calcularRappel(
  primaNeta: primaNetaTotal,
  porcentajeDV: porcentajeDecesosVida,
  rol: rol,
);

print("RAPPEL RESULTADO: $rappel");
    // 7️⃣ SUELDO FIJO
    double sueldoFijo = _getSueldoFijo(rol);

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

await supabase
    .from('detalle_nomina')
    .delete()
    .eq('nomina_id', nominaId);

    await supabase.from('detalle_nomina').insert([
  {
    'nomina_id': nominaId,
    'concepto': 'Primas netas',
    'importe': primaNetaTotal,
  },
  {
    'nomina_id': nominaId,
    'concepto': 'Comisiones',
    'importe': comisiones,
  },
  {
    'nomina_id': nominaId,
    'concepto': 'Rappel',
    'importe': rappel,
  },
  {
    'nomina_id': nominaId,
    'concepto': 'Sueldo fijo',
    'importe': sueldoFijo,
  },
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



  /// 🔥 RAPPEL (EJEMPLO ESCALABLE)
 double _calcularRappel({
  required double primaNeta,
  required double porcentajeDV,
  required String rol,
}) {

  // Obligatorio 30% Decesos + Vida
  if (porcentajeDV < 30) {
    return 0;
  }

  // ==========================
  // AGENTE
  // ==========================
  if (rol == 'agente') {

    if (primaNeta >= 12000) return 1500;
    if (primaNeta >= 9000) return 1200;
    if (primaNeta >= 6000) return 800;
    if (primaNeta >= 4000) return 600;
    if (primaNeta >= 2500) return 400;
    if (primaNeta >= 1500) return 200;

    return 0;
  }

  // ==========================
  // JEFE EQUIPO
  // ==========================
  if (rol == 'jefe_equipo') {

    if (primaNeta >= 10000) {
      return 2000 +
          (((primaNeta - 10000) ~/ 1000) * 100);
    }

    if (primaNeta >= 9000) return 1800;
    if (primaNeta >= 8000) return 1600;
    if (primaNeta >= 7000) return 1400;
    if (primaNeta >= 6000) return 1200;
    if (primaNeta >= 5000) return 1000;
    if (primaNeta >= 4000) return 800;

    return 0;
  }

  // ==========================
  // JEFE VENTAS
  // ==========================
  if (rol == 'jefe_ventas') {

    if (primaNeta >= 11500) {
      return 2500 +
          (((primaNeta - 11500) ~/ 1000) * 100);
    }

    if (primaNeta >= 10500) return 2300;
    if (primaNeta >= 9500) return 2100;
    if (primaNeta >= 8500) return 1900;
    if (primaNeta >= 7500) return 1700;
    if (primaNeta >= 6500) return 1500;

    return 0;
  }

  return 0;
}

  /// 🔥 SUELDOS FIJOS
  double _getSueldoFijo(String rol) {
    switch (rol) {
      case 'director':
        return 2500;

      case 'jefe_ventas':
        return 1500;

      case 'jefe_equipo':
        return 1000;

      case 'agente':
      default:
        return 0;
    }
  }

  /// 🔥 JERARQUÍA (parent_id RECURSIVO)
  Future<List<String>> _getEstructura(String authId) async {
    List<String> resultado = [authId];

    final directos = await supabase
        .from('usuarios')
        .select('auth_id')
        .eq('parent_id', authId);

    for (final u in directos) {
      resultado.add(u['auth_id']);
      resultado.addAll(await _getEstructura(u['auth_id']));
    }

    return resultado;
  }
}