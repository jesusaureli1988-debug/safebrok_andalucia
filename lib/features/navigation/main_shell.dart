import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../../core/permissions/role_permissions.dart';
import '../team/team_screen.dart';
import 'package:safebrok_andalucia/features/settings/settings_screen.dart';
import 'package:safebrok_andalucia/features/business/business_screen.dart';
import 'package:safebrok_andalucia/features/safecloud/safecloud_screen.dart';
import 'package:safebrok_andalucia/features/chat/internal_chat_screen.dart';
import '../../core/auth/app_role.dart';

class MainShell extends StatefulWidget {
  final String role;

  const MainShell({super.key, required this.role});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  String get role => AppRole.normalize(widget.role);

  bool get isDirector => role == AppRole.directorZona.value;
  bool get isJefeVentas => role == AppRole.jefeVentas.value;
  bool get isJefeEquipo => role == AppRole.jefeEquipo.value;
  bool get isAgente => role == AppRole.agente.value;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(role: role),
      const InternalChatScreen(),
      BusinessScreen(role: role),
      const SafeCloudScreen(),
      SettingsScreen(role: role),
    ];

    return Scaffold(
      body: pages[index],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        type: BottomNavigationBarType.fixed,

        backgroundColor: const Color(0xFF0B1C2A),
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.white60,

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Inicio"),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: "Chat",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.euro), label: "Negocio"),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_done_rounded),
            label: "SafeCloud",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Ajustes"),
        ],
      ),
    );
  }
}
