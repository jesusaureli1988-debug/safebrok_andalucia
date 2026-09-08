import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../settings/settings_screen.dart';
import '../business/business_screen.dart';
import '../safecloud/safecloud_screen.dart';
import '../chat/internal_chat_screen.dart';
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
      backgroundColor: const Color(0xFFF2FCFD),
      extendBody: true,
      body: pages[index],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.97),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFBDEDEF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF071A3A).withOpacity(0.10),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BottomNavigationBar(
              currentIndex: index,
              onTap: (i) => setState(() => index = i),
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              backgroundColor: Colors.transparent,
              selectedItemColor: const Color(0xFF0AAEAE),
              unselectedItemColor: const Color(0xFF53627A),
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Inicio',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_rounded),
                  label: 'Chat',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.euro),
                  label: 'Negocio',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.cloud_done_rounded),
                  label: 'SafeCloud',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Ajustes',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
