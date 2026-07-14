import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool loading = true;
  bool editMode = false;

  Map<String, dynamic>? usuario;

  final nombreCtrl = TextEditingController();
  final apellidosCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final numeroCtrl = TextEditingController();
  final cpCtrl = TextEditingController();
  final provinciaCtrl = TextEditingController();
  final localidadCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;

    final data = await Supabase.instance.client
        .from('usuarios')
        .select()
        .eq('auth_id', authUser.id)
        .single();

    usuario = data;

    nombreCtrl.text = data['nombre'] ?? '';
    apellidosCtrl.text = data['apellidos'] ?? '';
    telefonoCtrl.text = data['telefono'] ?? '';
    direccionCtrl.text = data['direccion'] ?? '';
    numeroCtrl.text = data['numero_direccion'] ?? '';
    cpCtrl.text = data['codigo_postal'] ?? '';
    provinciaCtrl.text = data['provincia'] ?? '';
    localidadCtrl.text = data['localidad'] ?? '';

    setState(() {
      loading = false;
    });
  }

  Future<void> saveProfile() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;

    await Supabase.instance.client
        .from('usuarios')
        .update({
          'nombre': nombreCtrl.text,
          'apellidos': apellidosCtrl.text,
          'telefono': telefonoCtrl.text,
          'direccion': direccionCtrl.text,
          'numero_direccion': numeroCtrl.text,
          'codigo_postal': cpCtrl.text,
          'provincia': provinciaCtrl.text,
          'localidad': localidadCtrl.text,
        })
        .eq('auth_id', authUser.id);

    await loadUser();

    setState(() {
      editMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final email = usuario?['email'] ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF08121C),
                  Color(0xFF102331),
                  Color(0xFF16384D),
                ],
              ),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Mi Perfil",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.cyanAccent,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      Text(
                        "${nombreCtrl.text} ${apellidosCtrl.text}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        email,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                _sectionTitle("Información Personal"),
                const SizedBox(height: 10),

                _field("Teléfono", telefonoCtrl),
                _field("Dirección", direccionCtrl),
                _field("Número", numeroCtrl),
                _field("Código Postal", cpCtrl),
                _field("Provincia", provinciaCtrl),
                _field("Localidad", localidadCtrl),

                const SizedBox(height: 30),

                if (editMode)
                  SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: saveProfile,
                      icon: const Icon(Icons.save),
                      label: const Text("Guardar cambios"),
                    ),
                  )
                else
                  SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => editMode = true);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text("Editar perfil"),
                    ),
                  ),

                const SizedBox(height: 15),

                SizedBox(
                  height: 55,
                  child: ElevatedButton.icon(
                   onPressed: () async {
  await Supabase.instance.client.auth.signOut();

  if (!mounted) return;

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => LoginScreen()),
    (route) => false,
  );
},
                    icon: const Icon(Icons.logout),
                    label: const Text("Cerrar sesión"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: editMode
          ? TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: Colors.white70),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: TextStyle(color: Colors.white.withOpacity(0.7))),
                Text(controller.text,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}