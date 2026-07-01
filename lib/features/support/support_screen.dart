import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Ayuda y Soporte"),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          /// HEADER
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.support_agent,
                  color: Colors.cyanAccent,
                  size: 60,
                ),
                SizedBox(height: 12),
                Text(
                  "¿Necesitas ayuda?",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Estamos aquí para ayudarte",
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          _sectionTitle("Centro de Ayuda"),

          _tile(
            icon: Icons.question_answer,
            title: "Preguntas Frecuentes",
            subtitle: "Resuelve dudas comunes",
            onTap: () {},
          ),

          _tile(
            icon: Icons.people,
            title: "Gestión de Clientes",
            subtitle: "Aprende a usar el CRM",
            onTap: () {},
          ),

          _tile(
            icon: Icons.euro,
            title: "Gestión de Ventas",
            subtitle: "Información sobre pólizas y ventas",
            onTap: () {},
          ),

          const SizedBox(height: 20),

          _sectionTitle("Soporte"),

          _tile(
            icon: Icons.report_problem,
            title: "Abrir Incidencia",
            subtitle: "Reporta un problema",
            onTap: () {},
          ),

          _tile(
            icon: Icons.email,
            title: "Correo de Soporte",
            subtitle: "soporte@safebrok.es",
            onTap: () {},
          ),

          _tile(
            icon: Icons.phone,
            title: "Teléfono de Soporte",
            subtitle: "+34 649 039 096",
            onTap: () {},
          ),

          const SizedBox(height: 20),

          _sectionTitle("Aplicación"),

          _tile(
            icon: Icons.info_outline,
            title: "Versión",
            subtitle: "v1.0.0",
            onTap: () {},
          ),

          _tile(
            icon: Icons.verified,
            title: "Estado",
            subtitle: "Producción",
            onTap: () {},
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

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
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
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white60,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white38,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }
}