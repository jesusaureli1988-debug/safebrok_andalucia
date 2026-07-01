import 'package:supabase_flutter/supabase_flutter.dart';

class PayrollService {
  static final supabase = Supabase.instance.client;

  // =========================
  // 📅 PERIODO 24 → 24 REAL
  // =========================
  static DateTime startPeriod(int mes, int anio) {
    return DateTime(anio, mes - 1, 24);
  }

  static DateTime endPeriod(int mes, int anio) {
    return DateTime(anio, mes, 23, 59, 59);
  }

  // =========================
  // 🧮 GENERAR NÓMINA AGENTE
  // =========================
  static Future<void> generarNominaAgente({
    required String authId,
    required int mes,
    required int anio,
  }) async {

    final inicio = startPeriod(mes, anio);
    final fin = endPeriod(mes, anio);

    // =========================
    // 🔥 VENTAS DEL PERIODO
    // =========================
    final ventas = await supabase
        .from('ventas')
        .select()
        .eq('agente_auth_id', authId)
        .gte('fecha_efecto', inicio.toIso8601String())
        .lte('fecha_efecto', fin.toIso8601String());

    double primaBrutaTotal = 0;
    double primaNetaTotal = 0;
    double comisiones = 0;
    double primasDecesosVida = 0;

    for (final v in ventas) {

      final bruta = (v['prima_anual_bruta'] ?? 0);
      final neta = (v['prima_anual_neta'] ?? 0);
      final com = (v['comision'] ?? 0);

      primaBrutaTotal += (bruta is num) ? bruta.toDouble() : 0;
      primaNetaTotal += (neta is num) ? neta.toDouble() : 0;
      comisiones += (com is num) ? com.toDouble() : 0;

      final producto = (v['producto'] ?? '').toString();

      if (producto == 'Decesos' || producto == 'Vida') {
        primasDecesosVida += (neta is num) ? neta.toDouble() : 0;
      }
    }

    // =========================
    // 📊 % DECESOS + VIDA
    // =========================
    double porcentajeDecesosVida = 0;

    if (primaNetaTotal > 0) {
      porcentajeDecesosVida =
          (primasDecesosVida / primaNetaTotal) * 100;
    }

    // =========================
    // 💰 RAPPEL
    // =========================
    double rappel = 0;

    if (porcentajeDecesosVida >= 30) {
      if (primaNetaTotal >= 12000) {
        rappel = 1500;
      } else if (primaNetaTotal >= 9000) {
        rappel = 1200;
      } else if (primaNetaTotal >= 6000) {
        rappel = 800;
      } else if (primaNetaTotal >= 4000) {
        rappel = 600;
      } else if (primaNetaTotal >= 2500) {
        rappel = 400;
      } else if (primaNetaTotal >= 1500) {
        rappel = 200;
      }
    }

    // =========================
    // 💵 TOTAL
    // =========================
    final totalCobrar = comisiones + rappel;

    // =========================
    // 💾 GUARDAR NÓMINA
    // =========================
    await supabase.from('nominas_mensuales').insert({
      'auth_id': authId,
      'mes': mes,
      'anio': anio,
      'rol': 'agente',

      'primas_total': primaNetaTotal,
      'prima_bruta_total': primaBrutaTotal,
      'prima_neta_total': primaNetaTotal,

      'primas_decesos_vida': primasDecesosVida,
      'porcentaje_decesos_vida': porcentajeDecesosVida,

      'comisiones': comisiones,
      'rappel': rappel,
      'total_cobrar': totalCobrar,

      'sueldo_fijo': 0,
    });
  }
}