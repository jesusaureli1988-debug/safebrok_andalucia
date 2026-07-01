class AgentDashboard extends StatefulWidget {
  const AgentDashboard({super.key});

  @override
  State<AgentDashboard> createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08121C),
      appBar: AppBar(
        title: const Text("Mi Panel Agente"),
        backgroundColor: Colors.transparent,
      ),
      body: const Center(
        child: Text(
          "Aquí van tus clientes + ventas",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}