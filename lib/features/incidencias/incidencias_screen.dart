import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncidenciasScreen extends StatefulWidget {
  const IncidenciasScreen({super.key});

  @override
  State<IncidenciasScreen> createState() => _IncidenciasScreenState();
}

class _IncidenciasScreenState extends State<IncidenciasScreen> {
  List<dynamic> incidencias = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadIncidencias();
  }

  Future<void> loadIncidencias() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    final role = await supabase
        .from('usuarios')
        .select('rol_usuario')
        .eq('auth_id', user.id)
        .single();

    // 👑 director ve todo
    if (role['rol_usuario'] == 'director_zona') {
      final data = await supabase
          .from('incidencias')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        incidencias = data;
        loading = false;
      });
      return;
    }

    // 👤 resto solo las suyas
    final data = await supabase
        .from('incidencias')
        .select()
        .eq('auth_id', user.id)
        .order('created_at', ascending: false);

    setState(() {
      incidencias = data;
      loading = false;
    });
  }

  Color getColor(String estado) {
    switch (estado) {
      case 'cerrada':
        return Colors.green;
      case 'progreso':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NuevaIncidenciaScreen(),
            ),
          ).then((_) => loadIncidencias());
        },
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: incidencias.length,
              itemBuilder: (context, i) {
                final item = incidencias[i];

                return Container(
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
                        item['titulo'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        item['descripcion'] ?? '',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: getColor(item['estado']).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item['estado'] ?? 'abierta',
                          style: TextStyle(
                            color: getColor(item['estado']),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
  class NuevaIncidenciaScreen extends StatefulWidget {
  const NuevaIncidenciaScreen({super.key});

  @override
  State<NuevaIncidenciaScreen> createState() =>
      _NuevaIncidenciaScreenState();
}

class _NuevaIncidenciaScreenState extends State<NuevaIncidenciaScreen> {
  final titulo = TextEditingController();
  final descripcion = TextEditingController();

  bool loading = false;

  Future<void> crear() async {
    setState(() => loading = true);

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    await supabase.from('incidencias').insert({
      'titulo': titulo.text,
      'descripcion': descripcion.text,
      'estado': 'abierta',
      'auth_id': user!.id,
    });

    setState(() => loading = false);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),
      appBar: AppBar(title: const Text("Nueva incidencia")),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            TextField(
              controller: titulo,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Título",
              ),
            ),

            TextField(
              controller: descripcion,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Descripción",
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: loading ? null : crear,
              child: Text(loading ? "Creando..." : "Crear"),
            ),
          ],
        ),
      ),
    );
  }
}
