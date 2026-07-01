import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RankingComercialScreen extends StatefulWidget {
  const RankingComercialScreen({super.key});

  @override
  State<RankingComercialScreen> createState() =>
      _RankingComercialScreenState();
}

class _RankingComercialScreenState extends State<RankingComercialScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> ranking = [];

  String rolSeleccionado = "agente";
  String productoFiltro = "Todos";
  String ordenFiltro = "Primas";

  bool cargando = true;

  @override
  void initState() {
    super.initState();
    cargarRanking();
  }

  Future<void> cargarRanking() async {
    setState(() {
      cargando = true;
      ranking = [];
    });

    try {
      final ventasRaw = await supabase
          .from('ventas')
          .select('agente_auth_id, producto, prima_anual_neta');

      final usuariosRaw = await supabase
          .from('usuarios')
          .select('id, auth_id, nombre, apellidos, rol_usuario, parent_id');

      final ventas = List<Map<String, dynamic>>.from(ventasRaw);
      final usuarios = List<Map<String, dynamic>>.from(usuariosRaw);

      final List<Map<String, dynamic>> resultado = [];

      final candidatos = usuarios.where((u) {
        final rol = _normalizarRol(u['rol_usuario']);
        return rol == rolSeleccionado;
      }).toList();

      for (final usuario in candidatos) {
        final authIdsEstructura = _obtenerAuthIdsEstructura(
          usuario,
          usuarios,
          rolSeleccionado,
        );

        if (authIdsEstructura.isEmpty) continue;

        final ventasUsuario = ventas.where((v) {
          final agenteAuthId = v['agente_auth_id']?.toString();
          final producto = _categoriaProducto(v['producto']);

          if (!authIdsEstructura.contains(agenteAuthId)) return false;

          if (productoFiltro != "Todos" && producto != productoFiltro) {
            return false;
          }

          return true;
        }).toList();

        double primas = 0;
        int totalVentas = ventasUsuario.length;

        final Map<String, int> ventasPorProducto = {
          'Decesos': 0,
          'Hogar': 0,
          'Vida': 0,
          'Salud': 0,
          'Auto': 0,
          'Otros': 0,
        };

        final Map<String, double> primasPorProducto = {
          'Decesos': 0,
          'Hogar': 0,
          'Vida': 0,
          'Salud': 0,
          'Auto': 0,
          'Otros': 0,
        };

        for (final v in ventasUsuario) {
          final prima = _toDouble(v['prima_anual_neta']);
          final producto = _categoriaProducto(v['producto']);

          primas += prima;
          ventasPorProducto[producto] = (ventasPorProducto[producto] ?? 0) + 1;
          primasPorProducto[producto] =
              (primasPorProducto[producto] ?? 0) + prima;
        }

        resultado.add({
          'id': usuario['id'],
          'auth_id': usuario['auth_id'],
          'nombre': usuario['nombre'] ?? '',
          'apellidos': usuario['apellidos'] ?? '',
          'rol': usuario['rol_usuario'] ?? '',
          'ventas': totalVentas,
          'primas': primas,
          'estructura': authIdsEstructura.length,
          'ventas_por_producto': ventasPorProducto,
          'primas_por_producto': primasPorProducto,
        });
      }

      setState(() {
        ranking = resultado;
        cargando = false;
      });
    } catch (e) {
      setState(() {
        cargando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error cargando ranking: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<String> _obtenerAuthIdsEstructura(
    Map<String, dynamic> usuario,
    List<Map<String, dynamic>> usuarios,
    String rol,
  ) {
    final List<String> ids = [];

    final userId = usuario['id']?.toString();
    final authId = usuario['auth_id']?.toString();

    if (rol == "agente") {
      if (authId != null && authId.isNotEmpty) {
        ids.add(authId);
      }
      return ids;
    }

    if (userId == null) return ids;

    if (rol == "jefe_equipo") {
      final agentes = usuarios.where((u) {
        final parentId = u['parent_id']?.toString();
        final rolUsuario = _normalizarRol(u['rol_usuario']);
        return parentId == userId && rolUsuario == "agente";
      });

      for (final a in agentes) {
        final auth = a['auth_id']?.toString();
        if (auth != null && auth.isNotEmpty) ids.add(auth);
      }

      return ids;
    }

    if (rol == "jefe_ventas") {
      final jefesEquipo = usuarios.where((u) {
        final parentId = u['parent_id']?.toString();
        final rolUsuario = _normalizarRol(u['rol_usuario']);
        return parentId == userId && rolUsuario == "jefe_equipo";
      }).toList();

      final jefeIds = jefesEquipo
          .map((j) => j['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toList();

      final agentes = usuarios.where((u) {
        final parentId = u['parent_id']?.toString();
        final rolUsuario = _normalizarRol(u['rol_usuario']);
        return jefeIds.contains(parentId) && rolUsuario == "agente";
      });

      for (final a in agentes) {
        final auth = a['auth_id']?.toString();
        if (auth != null && auth.isNotEmpty) ids.add(auth);
      }

      return ids;
    }

    return ids;
  }

  String _normalizarRol(dynamic rol) {
    final r = rol?.toString().toLowerCase().trim() ?? '';

    if (r.contains('jefe') && r.contains('venta')) return 'jefe_ventas';
    if (r.contains('jefe') && r.contains('equipo')) return 'jefe_equipo';
    if (r.contains('agente') || r.contains('comercial')) return 'agente';

    return r.replaceAll(' ', '_');
  }

  String _categoriaProducto(dynamic producto) {
    final p = producto?.toString().toLowerCase() ?? '';

    if (p.contains('deceso')) return 'Decesos';
    if (p.contains('hogar')) return 'Hogar';
    if (p.contains('vida')) return 'Vida';
    if (p.contains('salud')) return 'Salud';
    if (p.contains('auto') || p.contains('coche')) return 'Auto';

    return 'Otros';
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value.toString().replaceAll(',', '.'),
        ) ??
        0;
  }

  List<Map<String, dynamic>> get rankingOrdenado {
    final lista = [...ranking];

    if (ordenFiltro == "Ventas") {
      lista.sort((a, b) => (b['ventas'] ?? 0).compareTo(a['ventas'] ?? 0));
    } else {
      lista.sort((a, b) => _getPrimas(b).compareTo(_getPrimas(a)));
    }

    return lista;
  }

  double _getPrimas(Map<String, dynamic> r) {
    if (productoFiltro == "Todos") return _toDouble(r['primas']);

    final map = r['primas_por_producto'] as Map;
    return _toDouble(map[productoFiltro]);
  }

  int _getVentasProducto(Map<String, dynamic> r) {
    if (productoFiltro == "Todos") return r['ventas'] ?? 0;

    final map = r['ventas_por_producto'] as Map;
    return map[productoFiltro] ?? 0;
  }

  double get totalPrimasRanking {
    return ranking.fold<double>(0, (suma, r) => suma + _getPrimas(r));
  }

  int get totalVentasRanking {
    return ranking.fold<int>(0, (suma, r) => suma + _getVentasProducto(r));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF050B12),
                  Color(0xFF071A2E),
                  Color(0xFF123D63),
                ],
              ),
            ),
          ),

          Positioned(
            top: -140,
            right: -100,
            child: _glowRanking(330, Colors.cyanAccent, 0.16),
          ),

          Positioned(
            bottom: -150,
            left: -120,
            child: _glowRanking(360, Colors.blueAccent, 0.15),
          ),

          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: Container(color: Colors.black.withOpacity(0.08)),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          "Ranking Comercial",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: cargarRanking,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: cargando
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.cyanAccent,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            _headerRanking(),

                            const SizedBox(height: 18),

                            _panelFiltros(),

                            const SizedBox(height: 18),

                            _podium(),

                            const SizedBox(height: 18),

                            _rankingList(),
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

  Widget _headerRanking() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _glassRanking(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tituloRol(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Ranking por estructura, producción y ventas acumuladas",
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _kpiRanking(
                  "Participantes",
                  ranking.length.toString(),
                  Icons.groups_rounded,
                  Colors.cyanAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiRanking(
                  "Ventas",
                  totalVentasRanking.toString(),
                  Icons.shopping_cart_outlined,
                  Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiRanking(
                  "Primas",
                  "${totalPrimasRanking.toStringAsFixed(0)} €",
                  Icons.euro_rounded,
                  Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glassRanking(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Filtros profesionales",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),

          const SizedBox(height: 14),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipFiltroRol("agente", "Agentes", Icons.person_rounded),
                _chipFiltroRol("jefe_equipo", "Jefes Equipo", Icons.groups_rounded),
                _chipFiltroRol("jefe_ventas", "Jefes Ventas", Icons.workspace_premium_rounded),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipProducto("Todos"),
                _chipProducto("Decesos"),
                _chipProducto("Hogar"),
                _chipProducto("Vida"),
                _chipProducto("Salud"),
                _chipProducto("Auto"),
                _chipProducto("Otros"),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ordenButton("Primas", Icons.euro_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ordenButton("Ventas", Icons.shopping_bag_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _podium() {
    final top = rankingOrdenado.take(3).toList();

    if (top.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _glassRanking(24),
        child: Text(
          "No hay datos para este ranking.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _glassRanking(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Podio",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: List.generate(top.length, (index) {
              final r = top[index];

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index == top.length - 1 ? 0 : 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.055),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: index == 0
                          ? Colors.amberAccent.withOpacity(0.35)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        index == 0
                            ? "🥇"
                            : index == 1
                                ? "🥈"
                                : "🥉",
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${r['nombre']} ${r['apellidos']}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "${_getPrimas(r).toStringAsFixed(0)} €",
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _rankingList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glassRanking(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Clasificación completa",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 12),

          ...rankingOrdenado.asMap().entries.map((entry) {
            final index = entry.key;
            final r = entry.value;

            return _rankingRow(r, index);
          }),
        ],
      ),
    );
  }

  Widget _rankingRow(Map<String, dynamic> r, int index) {
    final nombre = "${r['nombre']} ${r['apellidos']}".trim();
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : "R";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: index == 0
            ? Colors.amberAccent.withOpacity(0.10)
            : Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: index == 0
              ? Colors.amberAccent.withOpacity(0.28)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: _medalla(index),
          ),

          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.cyanAccent.withOpacity(0.16),
            child: Text(
              inicial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre.isEmpty ? "Sin nombre" : nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "${_getVentasProducto(r)} ventas · ${r['estructura']} usuarios estructura",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${_getPrimas(r).toStringAsFixed(0)} €",
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                ordenFiltro,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _medalla(int index) {
    if (index == 0) return const Text("🥇", style: TextStyle(fontSize: 22));
    if (index == 1) return const Text("🥈", style: TextStyle(fontSize: 22));
    if (index == 2) return const Text("🥉", style: TextStyle(fontSize: 22));

    return Text(
      "${index + 1}",
      style: TextStyle(
        color: Colors.white.withOpacity(0.55),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _chipFiltroRol(String rol, String label, IconData icon) {
    final selected = rolSeleccionado == rol;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () async {
          setState(() {
            rolSeleccionado = rol;
          });

          await cargarRanking();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.cyanAccent : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected
                  ? Colors.cyanAccent
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipProducto(String producto) {
    final selected = productoFiltro == producto;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          setState(() {
            productoFiltro = producto;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.greenAccent : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected
                  ? Colors.greenAccent
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Text(
            producto,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ordenButton(String text, IconData icon) {
    final selected = ordenFiltro == text;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() {
          ordenFiltro = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Colors.cyanAccent.withOpacity(0.35)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.cyanAccent : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              "Ordenar por $text",
              style: TextStyle(
                color: selected ? Colors.cyanAccent : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiRanking(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.48),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _tituloRol() {
    if (rolSeleccionado == "jefe_equipo") {
      return "Ranking de Jefes de Equipo";
    }

    if (rolSeleccionado == "jefe_ventas") {
      return "Ranking de Jefes de Ventas";
    }

    return "Ranking de Agentes";
  }

  Widget _glowRanking(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }

  BoxDecoration _glassRanking(double radius) {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.075),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.09),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.16),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}