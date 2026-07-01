import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CrearEventoScreen extends StatefulWidget {
  const CrearEventoScreen({super.key});

  @override
  State<CrearEventoScreen> createState() =>
      _CrearEventoScreenState();
}

class _CrearEventoScreenState
    extends State<CrearEventoScreen> {
  final supabase = Supabase.instance.client;

  final tituloController = TextEditingController();
  final descripcionController =
      TextEditingController();

  DateTime? fecha;
  TimeOfDay? hora;

  bool loading = false;

  Future<void> guardar() async {
    if (tituloController.text.trim().isEmpty ||
        fecha == null ||
        hora == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Completa título, fecha y hora",
          ),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      final inicio = DateTime(
        fecha!.year,
        fecha!.month,
        fecha!.day,
        hora!.hour,
        hora!.minute,
      );

      final fin = inicio.add(
        const Duration(hours: 1),
      );

      await supabase.from('agenda_eventos').insert({
        'auth_id': user!.id,
        'titulo': tituloController.text.trim(),
        'descripcion':
            descripcionController.text.trim(),
        'fecha_inicio': inicio.toIso8601String(),
        'fecha_fin': fin.toIso8601String(),
        'origen': 'manual',
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("ERROR EVENTO: $e");
    }

    setState(() => loading = false);
  }

  Future<void> seleccionarFecha() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now()
          .subtract(const Duration(days: 365)),
      lastDate: DateTime(2035),
    );

    if (d != null) {
      setState(() => fecha = d);
    }
  }

  Future<void> seleccionarHora() async {
    final h = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (h != null) {
      setState(() => hora = h);
    }
  }

  InputDecoration deco(String texto) {
    return InputDecoration(
      labelText: texto,
      labelStyle:
          const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide:
            const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Colors.cyanAccent,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme:
            const IconThemeData(color: Colors.white),
        title: const Text(
          "Nuevo evento",
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            TextField(
              controller: tituloController,
              style:
                  const TextStyle(color: Colors.white),
              decoration: deco("Título"),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: descripcionController,
              style:
                  const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: deco("Descripción"),
            ),

            const SizedBox(height: 15),

            InkWell(
              onTap: seleccionarFecha,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white24,
                  ),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                child: Text(
                  fecha == null
                      ? "Seleccionar fecha"
                      : "${fecha!.day}/${fecha!.month}/${fecha!.year}",
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            InkWell(
              onTap: seleccionarHora,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white24,
                  ),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                child: Text(
                  hora == null
                      ? "Seleccionar hora"
                      : hora!.format(context),
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    loading ? null : guardar,
                child: const Text(
                  "GUARDAR EVENTO",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}