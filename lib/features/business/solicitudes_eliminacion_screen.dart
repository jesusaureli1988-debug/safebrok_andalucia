import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SolicitudesEliminacionScreen extends StatefulWidget {
  const SolicitudesEliminacionScreen({super.key});

  @override
  State<SolicitudesEliminacionScreen> createState() =>
      _SolicitudesEliminacionScreenState();
}

class _SolicitudesEliminacionScreenState
    extends State<SolicitudesEliminacionScreen> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    loadRequests();
  }

  Future<void> loadRequests() async {
    final data = await supabase
        .from('solicitudes_eliminacion_cuenta')
        .select()
        .order('solicitado_at', ascending: false);
    if (!mounted) return;
    setState(() {
      requests = List<Map<String, dynamic>>.from(data);
      loading = false;
    });
  }

  Future<void> updateStatus(Map<String, dynamic> request, String status) async {
    final user = supabase.auth.currentUser;
    await supabase
        .from('solicitudes_eliminacion_cuenta')
        .update({
          'estado': status,
          'procesado_por': user?.id,
          'procesado_at': status == 'completada'
              ? DateTime.now().toIso8601String()
              : null,
        })
        .eq('id', request['id']);
    await loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eliminación de cuentas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
          ? const Center(child: Text('No hay solicitudes'))
          : RefreshIndicator(
              onRefresh: loadRequests,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  final status = request['estado']?.toString() ?? 'pendiente';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_remove_alt_1_rounded),
                      title: Text(request['email']?.toString() ?? 'Sin email'),
                      subtitle: Text(
                        'Estado: $status\nMotivo: ${request['motivo'] ?? 'No indicado'}\n'
                        'Límite: ${request['fecha_limite'] ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => updateStatus(request, value),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'en_proceso',
                            child: Text('Marcar en proceso'),
                          ),
                          PopupMenuItem(
                            value: 'completada',
                            child: Text('Marcar completada'),
                          ),
                          PopupMenuItem(
                            value: 'cancelada',
                            child: Text('Cancelar solicitud'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
