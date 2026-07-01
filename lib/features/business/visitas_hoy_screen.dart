import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detalle_visita_screen.dart';

class VisitasHoyScreen extends StatefulWidget {
  const VisitasHoyScreen({super.key});

  @override
  State<VisitasHoyScreen> createState() => _VisitasHoyScreenState();
}

class _VisitasHoyScreenState extends State<VisitasHoyScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> visitas = [];

  @override
  void initState() {
    super.initState();
    cargarVisitasHoy();
  }

  Future<void> cargarVisitasHoy() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('visitas')
        .select()
        .eq('auth_id', user.id);

    final now = DateTime.now();

    final hoy = DateTime(now.year, now.month, now.day);

    final filtradas = List<Map<String, dynamic>>.from(data).where((v) {
      final fecha = DateTime.parse(v['fecha_visita']);

      return fecha.year == hoy.year &&
          fecha.month == hoy.month &&
          fecha.day == hoy.day &&
          v['estado'] == 'Pendiente';
    }).toList();

    setState(() {
      visitas = filtradas;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),
      appBar: AppBar(title: const Text("Visitas de hoy")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visitas.length,
        itemBuilder: (context, index) {
          final v = visitas[index];

          return InkWell(
           onTap: () {
  if (v['id'] == null) return;

  Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => DetalleVisitaScreen(
      visita: v,
    ),
  ),
).then((_) {
  cargarVisitasHoy();
});
},
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                   "${v['nombre_cliente'] ?? ''}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "📍 ${v['direccion']}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                 Text(
  "🕒 ${v['hora_visita'] ?? ''}",
  style: const TextStyle(color: Colors.cyanAccent),
),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void gestionarVisita(Map<String, dynamic> visita) {
  String resultado = "Realizada";
  String estado = "Realizada";
  String observaciones = "";

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF102331),
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text(
                  "Gestionar visita",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),

                const SizedBox(height: 15),

                DropdownButtonFormField<String>(
                  value: resultado,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: "Venta realizada",
                      child: Text("Venta realizada"),
                    ),
                    DropdownMenuItem(
                      value: "Venta no realizada",
                      child: Text("Venta no realizada"),
                    ),
                    DropdownMenuItem(
                      value: "Venta pospuesta",
                      child: Text("Venta pospuesta"),
                    ),
                  ],
                  onChanged: (v) {
                    setModal(() {
                      resultado = v!;
                    });
                  },
                ),

                const SizedBox(height: 10),

                TextField(
                  onChanged: (v) => observaciones = v,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: "Observaciones",
                  ),
                  maxLines: 3,
                ),

                const SizedBox(height: 15),

                ElevatedButton(
               onPressed: () async {

               final v = visita;
               

  await supabase
      .from('visitas')
      .update({
        'estado': estado,
        'resultado': resultado,
        'observaciones': observaciones,
      })
      .eq('id', v['id']);

  Navigator.pop(context);
  cargarVisitasHoy();
},
                  child: const Text("Guardar"),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
}