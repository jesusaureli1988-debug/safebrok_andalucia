import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamScreen extends StatefulWidget {

  final String role;

  const TeamScreen({
    super.key,
    required this.role,
  });

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {

  List users = [];

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) return;

    // 👤 obtener usuario actual desde tabla usuarios
    final myUser = await Supabase.instance.client
        .from('usuarios')
        .select()
        .eq('auth_id', currentUser.id)
        .single();

    final myId = myUser['id'];

    // 👑 DIRECTOR VE TODO
    if (widget.role == 'director_zona') {

      final res = await Supabase.instance.client
          .from('usuarios')
          .select();

      setState(() {
        users = res;
      });

      return;
    }

    // 💼 JEFE VENTAS
    if (widget.role == 'jefe_ventas') {

      // 🔥 obtener jefes de equipo
      final equipos = await Supabase.instance.client
          .from('usuarios')
          .select()
          .eq('parent_id', myId);

      List<dynamic> allUsers = [];

      allUsers.addAll(equipos);

      // 🔥 obtener agentes de esos equipos
      for (var equipo in equipos) {

        final agentes = await Supabase.instance.client
            .from('usuarios')
            .select()
            .eq('parent_id', equipo['id']);

        allUsers.addAll(agentes);
      }

      setState(() {
        users = allUsers;
      });

      return;
    }

    // 👥 JEFE EQUIPO
    if (widget.role == 'jefe_equipo') {

      final agentes = await Supabase.instance.client
          .from('usuarios')
          .select()
          .eq('parent_id', myId);

      setState(() {
        users = agentes;
      });

      return;
    }

    // 👤 AGENTE
    if (widget.role == 'agente') {

      setState(() {
        users = [myUser];
      });

      return;
    }
  }

  Color getRoleColor(String role) {

    switch (role) {

      case 'director_zona':
        return Colors.purpleAccent;

      case 'jefe_ventas':
        return Colors.blueAccent;

      case 'jefe_equipo':
        return Colors.orangeAccent;

      case 'agente':
        return Colors.greenAccent;

      default:
        return Colors.white;
    }
  }

  IconData getRoleIcon(String role) {

    switch (role) {

      case 'director_zona':
        return Icons.workspace_premium;

      case 'jefe_ventas':
        return Icons.bar_chart;

      case 'jefe_equipo':
        return Icons.groups;

      case 'agente':
        return Icons.person;

      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF08121C),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Mi Equipo",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: users.length,
        itemBuilder: (context, index) {

          final user = users[index];

          final role = user['rol_usuario'] ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),

              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.04),
                ],
              ),

              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),

            child: Row(
              children: [

                // 🔥 ICONO
                Container(
                  width: 60,
                  height: 60,

                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: getRoleColor(role).withOpacity(0.15),
                  ),

                  child: Icon(
                    getRoleIcon(role),
                    color: getRoleColor(role),
                    size: 30,
                  ),
                ),

                const SizedBox(width: 15),

                // 👤 DATOS
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        "${user['nombre'] ?? ''} ${user['apellidos'] ?? ''}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        role,
                        style: TextStyle(
                          color: getRoleColor(role),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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