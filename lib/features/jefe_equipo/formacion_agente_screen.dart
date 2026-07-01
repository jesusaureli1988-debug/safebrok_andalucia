import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormacionAgenteScreen extends StatefulWidget {
  final Map agente;

  const FormacionAgenteScreen({
    super.key,
    required this.agente,
  });

  @override
  State<FormacionAgenteScreen> createState() => _FormacionAgenteScreenState();
}

class _FormacionAgenteScreenState extends State<FormacionAgenteScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  bool habilidades = false;
  bool decesos = false;
  bool hogar = false;
  bool vida = false;
  bool accidente = false;
  bool auto = false;
  bool comunidad = false;
  bool salud = false;
  bool comercio = false;

  static const int totalModulos = 9;

  @override
  void initState() {
    super.initState();
    cargarFormacion();
  }

  Future<void> cargarFormacion() async {
    try {
      final data = await supabase
          .from('formacion_agentes')
          .select()
          .eq('agente_id', widget.agente['id']);

      if (data.isNotEmpty) {
        final f = data.first;

        habilidades = f['habilidades_comerciales'] ?? false;
        decesos = f['decesos'] ?? false;
        hogar = f['hogar'] ?? false;
        vida = f['vida'] ?? false;
        accidente = f['accidente'] ?? false;
        auto = f['auto'] ?? false;
        comunidad = f['comunidad'] ?? false;
        salud = f['salud'] ?? false;
        comercio = f['comercio_pymes'] ?? false;
      }

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      debugPrint("❌ ERROR cargar formación: $e");

      if (!mounted) return;
      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al cargar formación: $e")),
      );
    }
  }

  int get progreso {
    int total = 0;

    if (habilidades) total++;
    if (decesos) total++;
    if (hogar) total++;
    if (vida) total++;
    if (accidente) total++;
    if (auto) total++;
    if (comunidad) total++;
    if (salud) total++;
    if (comercio) total++;

    return total;
  }

  double get porcentaje => progreso / totalModulos;

  Color get colorProgreso {
    if (progreso == totalModulos) return const Color(0xFF22C55E);
    if (progreso >= 5) return const Color(0xFFF59E0B);
    if (progreso > 0) return const Color(0xFF38BDF8);
    return const Color(0xFF64748B);
  }

  String get estadoTexto {
    if (progreso == totalModulos) return "Formación completada";
    if (progreso == 0) return "Formación pendiente";
    return "Formación en curso";
  }

  Future<void> guardar() async {
    if (saving) return;

    try {
      setState(() => saving = true);

      final existe = await supabase
          .from('formacion_agentes')
          .select()
          .eq('agente_id', widget.agente['id']);

      final datos = {
        'agente_id': widget.agente['id'],
        'habilidades_comerciales': habilidades,
        'decesos': decesos,
        'hogar': hogar,
        'vida': vida,
        'accidente': accidente,
        'auto': auto,
        'comunidad': comunidad,
        'salud': salud,
        'comercio_pymes': comercio,
      };

      if (existe.isEmpty) {
        await supabase.from('formacion_agentes').insert(datos);
      } else {
        await supabase
            .from('formacion_agentes')
            .update(datos)
            .eq('agente_id', widget.agente['id']);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Formación guardada correctamente"),
          backgroundColor: Color(0xFF16A34A),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("❌ ERROR guardar formación: $e");

      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al guardar formación: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void cambiarModulo(String key, bool value) {
    setState(() {
      switch (key) {
        case 'habilidades':
          habilidades = value;
          break;
        case 'decesos':
          decesos = value;
          break;
        case 'hogar':
          hogar = value;
          break;
        case 'vida':
          vida = value;
          break;
        case 'accidente':
          accidente = value;
          break;
        case 'auto':
          auto = value;
          break;
        case 'comunidad':
          comunidad = value;
          break;
        case 'salud':
          salud = value;
          break;
        case 'comercio':
          comercio = value;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.agente['nombre'] ?? 'Agente';
    final email = widget.agente['email'] ?? '';

    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF061018),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF38BDF8),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      appBar: AppBar(
        title: const Text(
          "Ficha de formación",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF061018),
        elevation: 0,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: saving ? null : guardar,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                saving ? "Guardando..." : "Guardar formación",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF061018),
                disabledBackgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _cabeceraAgente(nombre, email),
          const SizedBox(height: 18),
          _panelProgreso(),
          const SizedBox(height: 18),
          const Text(
            "Módulos formativos",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),

          _modulo(
            keyModulo: 'habilidades',
            titulo: "Habilidades comerciales",
            descripcion: "Prospección, argumentario, visita y cierre.",
            icono: Icons.record_voice_over_rounded,
            valor: habilidades,
          ),
          _modulo(
            keyModulo: 'decesos',
            titulo: "Decesos",
            descripcion: "Producto principal, garantías y comparativa.",
            icono: Icons.shield_rounded,
            valor: decesos,
          ),
          _modulo(
            keyModulo: 'hogar',
            titulo: "Hogar",
            descripcion: "Coberturas, continente, contenido y objeciones.",
            icono: Icons.home_rounded,
            valor: hogar,
          ),
          _modulo(
            keyModulo: 'vida',
            titulo: "Vida",
            descripcion: "Protección familiar y capital asegurado.",
            icono: Icons.favorite_rounded,
            valor: vida,
          ),
          _modulo(
            keyModulo: 'accidente',
            titulo: "Accidente",
            descripcion: "Indemnizaciones, escenarios y contratación.",
            icono: Icons.health_and_safety_rounded,
            valor: accidente,
          ),
          _modulo(
            keyModulo: 'auto',
            titulo: "Auto",
            descripcion: "Modalidades, comparativa y oportunidades.",
            icono: Icons.directions_car_rounded,
            valor: auto,
          ),
          _modulo(
            keyModulo: 'comunidad',
            titulo: "Comunidad",
            descripcion: "Comunidades, administradores y captación.",
            icono: Icons.apartment_rounded,
            valor: comunidad,
          ),
          _modulo(
            keyModulo: 'salud',
            titulo: "Salud",
            descripcion: "Cuadro médico, copagos y argumentación.",
            icono: Icons.local_hospital_rounded,
            valor: salud,
          ),
          _modulo(
            keyModulo: 'comercio',
            titulo: "Comercio y Pymes",
            descripcion: "Negocios, riesgos, RC y multirriesgo.",
            icono: Icons.storefront_rounded,
            valor: comercio,
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _cabeceraAgente(String nombre, String email) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: colorProgreso.withOpacity(0.18),
            child: Text(
              nombre.toString().isNotEmpty
                  ? nombre.toString().substring(0, 1).toUpperCase()
                  : "A",
              style: TextStyle(
                color: colorProgreso,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelProgreso() {
    final porcentajeTexto = (porcentaje * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F2537),
            Color(0xFF0B1722),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 82,
                    height: 82,
                    child: CircularProgressIndicator(
                      value: porcentaje,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      color: colorProgreso,
                    ),
                  ),
                  Text(
                    "$porcentajeTexto%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      estadoTexto,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "$progreso de $totalModulos módulos completados",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: porcentaje,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.08),
              color: colorProgreso,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modulo({
    required String keyModulo,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required bool valor,
  }) {
    final color = valor ? const Color(0xFF22C55E) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          hoverColor: Colors.white.withOpacity(0.04),
          splashColor: color.withOpacity(0.14),
          highlightColor: color.withOpacity(0.08),
          onTap: () => cambiarModulo(keyModulo, !valor),
          child: Ink(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A24),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: valor
                    ? color.withOpacity(0.55)
                    : Colors.white.withOpacity(0.07),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icono, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: valor ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: valor
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}