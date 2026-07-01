import 'package:flutter/material.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Información de la App"),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          /// CABECERA
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.shield,
                  size: 70,
                  color: Colors.cyanAccent,
                ),
                SizedBox(height: 12),
                Text(
                  "SafeBrok Andalucía",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Sistema de gestión comercial",
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          _sectionTitle("Aplicación"),

          _infoTile(
            "Versión",
            "1.0.0",
            Icons.info_outline,
          ),

          _infoTile(
            "Entorno",
            "Producción",
            Icons.verified,
          ),

          _infoTile(
            "Estado",
            "Operativo",
            Icons.check_circle,
          ),

          const SizedBox(height: 20),

          _sectionTitle("Empresa"),

          _infoTile(
            "Desarrollado para",
            "SafeBrok Andalucía",
            Icons.business,
          ),

          _infoTile(
            "Copyright",
            "© 2026 SafeBrok",
            Icons.copyright,
          ),

          const SizedBox(height: 20),

          _sectionTitle("Legal"),

          _clickableTile(
            context,
            "Política de privacidad",
            Icons.privacy_tip,
          ),

          _clickableTile(
            context,
            "Términos y condiciones",
            Icons.gavel,
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoTile(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.cyanAccent,
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        trailing: Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _clickableTile(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.cyanAccent,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white38,
          size: 16,
        ),
        onTap: () {},
      ),
    );
  }
}