import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class ProductionPeriod {
  final String? id;
  final int year;
  final int month;
  final DateTime from;
  final DateTime to;
  final String status;
  final bool configured;

  const ProductionPeriod({
    required this.id,
    required this.year,
    required this.month,
    required this.from,
    required this.to,
    required this.status,
    required this.configured,
  });

  DateTime get start => DateTime(from.year, from.month, from.day);

  DateTime get endInclusive =>
      DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

  DateTime get endExclusive {
    final dayAfter = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    return DateTime(dayAfter.year, dayAfter.month, dayAfter.day);
  }

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  bool contains(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return !date.isBefore(start) &&
        !date.isAfter(DateTime(to.year, to.month, to.day));
  }

  Map<String, DateTime> asRange() => {'inicio': start, 'fin': endExclusive};
}

class ProductionPeriodService {
  ProductionPeriodService._();

  static final ProductionPeriodService instance = ProductionPeriodService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  ProductionPeriod? _currentCache;
  DateTime? _currentCacheAt;

  Future<ProductionPeriod> current({
    DateTime? now,
    bool forceRefresh = false,
  }) async {
    final reference = now ?? DateTime.now();
    final cached = _currentCache;
    final cachedAt = _currentCacheAt;

    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 5) &&
        cached.contains(reference)) {
      return cached;
    }

    final period = await forDate(reference);
    _currentCache = period;
    _currentCacheAt = DateTime.now();
    return period;
  }

  Future<ProductionPeriod> forDate(DateTime date) async {
    final day = _databaseDate(date);

    try {
      final row = await _supabase
          .from('cierres_produccion')
          .select('id, anio, mes, fecha_desde, fecha_hasta, estado')
          .lte('fecha_desde', day)
          .gte('fecha_hasta', day)
          .limit(1)
          .maybeSingle();

      if (row != null) return _fromRow(row);
    } catch (error) {
      debugPrint('ERROR CONSULTANDO CIERRE DE PRODUCCIÓN: $error');
    }

    return _legacyFallback(date);
  }

  Future<ProductionPeriod> forMonth({
    required int year,
    required int month,
  }) async {
    try {
      final row = await _supabase
          .from('cierres_produccion')
          .select('id, anio, mes, fecha_desde, fecha_hasta, estado')
          .eq('anio', year)
          .eq('mes', month)
          .maybeSingle();

      if (row != null) return _fromRow(row);
    } catch (error) {
      debugPrint('ERROR CONSULTANDO PERIODO $year-$month: $error');
    }

    return _legacyFallback(DateTime(year, month, 1));
  }

  void invalidateCache() {
    _currentCache = null;
    _currentCacheAt = null;
  }

  ProductionPeriod _fromRow(Map<String, dynamic> row) {
    final from = DateTime.parse(row['fecha_desde'].toString());
    final to = DateTime.parse(row['fecha_hasta'].toString());
    return ProductionPeriod(
      id: row['id']?.toString(),
      year: int.parse(row['anio'].toString()),
      month: int.parse(row['mes'].toString()),
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day),
      status: (row['estado'] ?? 'abierto').toString(),
      configured: true,
    );
  }

  ProductionPeriod _legacyFallback(DateTime date) {
    final from = date.day >= 24
        ? DateTime(date.year, date.month, 24)
        : DateTime(date.year, date.month - 1, 24);
    final exclusiveTo = DateTime(from.year, from.month + 1, 24);
    final to = exclusiveTo.subtract(const Duration(days: 1));

    debugPrint(
      'AVISO: no existe cierre configurado para ${_databaseDate(date)}. '
      'Se usa temporalmente el ciclo histórico 24–23.',
    );

    return ProductionPeriod(
      id: null,
      year: exclusiveTo.year,
      month: exclusiveTo.month,
      from: from,
      to: to,
      status: 'abierto',
      configured: false,
    );
  }

  String _databaseDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
