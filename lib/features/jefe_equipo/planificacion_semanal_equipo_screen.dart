import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanificacionSemanalEquipoScreen extends StatefulWidget {
  const PlanificacionSemanalEquipoScreen({super.key});

  @override
  State<PlanificacionSemanalEquipoScreen> createState() =>
      _PlanificacionSemanalEquipoScreenState();
}

class _PlanificacionSemanalEquipoScreenState
    extends State<PlanificacionSemanalEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  List<Map<String, dynamic>> agentes = [];

  String? agenteSeleccionado;

  DateTime? inicioSemana;
  DateTime? finSemana;

  final lunesController = TextEditingController();
  final martesController = TextEditingController();
  final miercolesController = TextEditingController();
  final juevesController = TextEditingController();
  final viernesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargarAgentes();
  }

  @override
  void dispose() {
    lunesController.dispose();
    martesController.dispose();
    miercolesController.dispose();
    juevesController.dispose();
    viernesController.dispose();
    super.dispose();
  }

  Future<void> cargarAgentes() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => loading = false);
        return;
      }

      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      final data = await supabase
          .from('usuarios')
          .select()
          .eq('parent_id', jefe['id'])
          .eq('rol_usuario', 'agente')
          .order('nombre', ascending: true);

      if (!mounted) return;

      setState(() {
        agentes = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR CARGAR AGENTES PLANIFICACIÓN: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> guardar() async {
    if (saving) return;

    if (agenteSeleccionado == null || inicioSemana == null || finSemana == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Selecciona agente y semana"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      setState(() => saving = true);

      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => saving = false);
        return;
      }

      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      final existe = await supabase
          .from('planificacion_semanal_equipo')
          .select()
          .eq('jefe_id', jefe['id'])
          .eq('agente_id', agenteSeleccionado!)
          .eq('semana_inicio', inicioSemana!.toIso8601String())
          .maybeSingle();

      if (existe != null) {
        if (!mounted) return;
        setState(() => saving = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Este agente ya tiene planificación para esa semana"),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      await supabase.from('planificacion_semanal_equipo').insert({
        'jefe_id': jefe['id'],
        'agente_id': agenteSeleccionado,
        'semana_inicio': inicioSemana!.toIso8601String(),
        'semana_fin': finSemana!.toIso8601String(),
        'lunes': lunesController.text.trim(),
        'martes': martesController.text.trim(),
        'miercoles': miercolesController.text.trim(),
        'jueves': juevesController.text.trim(),
        'viernes': viernesController.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Planificación guardada correctamente"),
          backgroundColor: Color(0xFF22C55E),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("ERROR GUARDAR PLANIFICACION: $e");

      if (!mounted) return;
      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al guardar planificación: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> seleccionarSemana() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22D3EE),
              surface: Color(0xFF071A3A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null) return;

    setState(() {
      inicioSemana = date;
      finSemana = date.add(const Duration(days: 4));
    });
  }

  String formatoFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/"
        "${fecha.month.toString().padLeft(2, '0')}/"
        "${fecha.year}";
  }

  String nombreAgenteSeleccionado() {
    try {
      final agente = agentes.firstWhere(
        (a) => a['id'].toString() == agenteSeleccionado,
      );

      return "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();
    } catch (_) {
      return "Selecciona agente";
    }
  }

  int get diasPlanificados {
    int total = 0;

    if (lunesController.text.trim().isNotEmpty) total++;
    if (martesController.text.trim().isNotEmpty) total++;
    if (miercolesController.text.trim().isNotEmpty) total++;
    if (juevesController.text.trim().isNotEmpty) total++;
    if (viernesController.text.trim().isNotEmpty) total++;

    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020B1F),
      bottomNavigationBar: loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
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
                        color: const Color(0xFF22D3EE).withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
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
                      saving ? "Guardando..." : "Guardar planificación",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF22D3EE),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargarAgentes,
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF071A3A),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                      child: _resumenPanel(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Column(
                        children: [
                          _selectorAgente(),
                          const SizedBox(height: 14),
                          _selectorSemana(),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.edit_calendar_rounded,
                            color: Color(0xFF22D3EE),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Plan semanal",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                      child: Column(
                        children: [
                          _diaCard(
                            dia: "Lunes",
                            subtitulo: "Inicio de semana",
                            icono: Icons.looks_one_rounded,
                            controller: lunesController,
                            color: const Color(0xFF22D3EE),
                          ),
                          _diaCard(
                            dia: "Martes",
                            subtitulo: "Prospección y llamadas",
                            icono: Icons.looks_two_rounded,
                            controller: martesController,
                            color: const Color(0xFF2563EB),
                          ),
                          _diaCard(
                            dia: "Miércoles",
                            subtitulo: "Seguimiento comercial",
                            icono: Icons.looks_3_rounded,
                            controller: miercolesController,
                            color: const Color(0xFF8B5CF6),
                          ),
                          _diaCard(
                            dia: "Jueves",
                            subtitulo: "Visitas y cierres",
                            icono: Icons.looks_4_rounded,
                            controller: juevesController,
                            color: const Color(0xFFF59E0B),
                          ),
                          _diaCard(
                            dia: "Viernes",
                            subtitulo: "Revisión y objetivos",
                            icono: Icons.looks_5_rounded,
                            controller: viernesController,
                            color: const Color(0xFF22C55E),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF020B1F),
            Color(0xFF061A3D),
            Color(0xFF020B1F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: 20,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22D3EE).withOpacity(0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
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
                  const Spacer(),
                  IconButton(
                    onPressed: cargarAgentes,
                    icon: const Icon(
                      Icons.refresh_rounded,
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
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
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
                          color: const Color(0xFF22D3EE).withOpacity(0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: "Crear\n",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: "plan semanal",
                            style: TextStyle(
                              color: Color(0xFF22D3EE),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                "Define la planificación semanal de trabajo para cada agente del equipo.",
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumenPanel() {
    final semanaTexto = inicioSemana == null
        ? "Semana no seleccionada"
        : "${formatoFecha(inicioSemana!)} - ${formatoFecha(finSemana!)}";

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            icono: Icons.person_rounded,
            valor: agenteSeleccionado == null ? "—" : "OK",
            titulo: nombreAgenteSeleccionado(),
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            icono: Icons.date_range_rounded,
            valor: "${diasPlanificados}/5",
            titulo: semanaTexto,
            color: const Color(0xFF14B8A6),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icono,
    required String valor,
    required String titulo,
    required Color color,
  }) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.32),
            const Color(0xFF061329),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Colors.white, size: 28),
          const Spacer(),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorAgente() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(const Color(0xFF22D3EE)),
      child: DropdownButtonFormField<String>(
        value: agenteSeleccionado,
        dropdownColor: const Color(0xFF071A3A),
        iconEnabledColor: const Color(0xFF22D3EE),
        decoration: _inputDecoration(
          label: "Agente",
          icono: Icons.person_search_rounded,
        ),
        items: agentes.map<DropdownMenuItem<String>>((a) {
          final nombre = "${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}".trim();

          return DropdownMenuItem(
            value: a['id'].toString(),
            child: Text(
              nombre.isEmpty ? "Agente sin nombre" : nombre,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
        onChanged: (v) {
          setState(() => agenteSeleccionado = v);
        },
      ),
    );
  }

  Widget _selectorSemana() {
    final texto = inicioSemana == null
        ? "Seleccionar semana"
        : "${formatoFecha(inicioSemana!)} - ${formatoFecha(finSemana!)}";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: seleccionarSemana,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(const Color(0xFF8B5CF6)),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.42),
                  ),
                ),
                child: const Icon(
                  Icons.date_range_rounded,
                  color: Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diaCard({
    required String dia,
    required String subtitulo,
    required IconData icono,
    required TextEditingController controller,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF071A3A),
                Color(0xFF061329),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: color.withOpacity(0.34)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 96,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.95),
                      const Color(0xFF7C3AED),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icono, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: dia,
                    hintText: subtitulo,
                    alignLabelWithHint: true,
                    labelStyle: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                    hintStyle: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(Color color) {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF071A3A),
          Color(0xFF061329),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.34)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icono,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, color: const Color(0xFF22D3EE)),
      labelStyle: const TextStyle(
        color: Color(0xFFCBD5E1),
        fontWeight: FontWeight.w800,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(18),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Color(0xFF22D3EE),
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}