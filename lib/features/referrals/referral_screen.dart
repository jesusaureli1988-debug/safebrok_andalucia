import 'dart:ui';
import 'package:flutter/material.dart';

class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),

      /// 🔥 APPBAR ESTILO BANCO
      appBar: AppBar(
        title: const Text("Trae a un amigo"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const BackButton(color: Colors.white),
        ),
      ),

      body: Stack(
        children: [

          /// FONDO PREMIUM
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF061018),
                    Color(0xFF102A43),
                  ],
                ),
              ),
            ),
          ),

          /// CONTENIDO
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [

                const SizedBox(height: 10),

                /// TITULO
                const Text(
                  "Invita y gana",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Invita comerciales o clientes y gana recompensas automáticas",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 30),

                /// 👔 TARJETA COMERCIALES
                _card(
                  context,
                  icon: Icons.groups,
                  title: "Trae un comercial",
                  subtitle: "Gana por su producción",
                  color: Colors.cyanAccent,
                  onTap: () {},
                ),

                const SizedBox(height: 20),

                /// 👤 TARJETA CLIENTES
                _card(
                  context,
                  icon: Icons.person,
                  title: "Trae un cliente",
                  subtitle: "Gana por cada póliza",
                  color: Colors.greenAccent,
                  onTap: () {},
                ),

                const SizedBox(height: 30),

                /// INFO
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    "💡 Las recompensas se activan automáticamente cuando el invitado genera su primera actividad.",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [

            Icon(icon, color: color, size: 32),

            const SizedBox(width: 15),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}