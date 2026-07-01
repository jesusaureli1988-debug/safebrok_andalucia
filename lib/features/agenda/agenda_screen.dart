import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crear_evento_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  int vista = 0;
 

  List eventos = [];
  Map<DateTime, List> eventosPorDia = {};

  DateTime focusedDay = DateTime.now();
  DateTime selectedDay = DateTime.now();

  @override
void initState() {
  super.initState();
  cargarTodo();
   
}
Future<void> cargarTodo() async {
  setState(() => loading = true);

  eventos.clear();
eventosPorDia.clear();

  await cargarReuniones();
  await cargarEventos();
  await cargarVisitas();
  await cargarPlanificacion();

  

  setState(() => loading = false);
}


 Future<void> cargarEventos() async {
  try {
    final user = supabase.auth.currentUser;

    final eventosData = await supabase
        .from('agenda_eventos')
        .select()
        .eq('auth_id', user!.id);

    final visitasData = await supabase
        .from('visitas')
        .select()
        .eq('auth_id', user.id);

   eventos.addAll([
  ...eventosData.map((e) => {
        'titulo': e['titulo'],
        'descripcion': e['descripcion'],
        'fecha': e['fecha_inicio'],
        'tipo': 'manual',
      }),

  ...visitasData.map((v) => {
        'titulo': 'Visita: ${v['nombre_cliente']}',
        'descripcion': v['direccion'],
        'fecha': '${v['fecha_visita']}T${v['hora_visita'] ?? "00:00"}',
        'tipo': 'visita',
      }),
]);

    

    loading = false;
    setState(() {});
  } catch (e) {
    debugPrint("ERROR AGENDA: $e");
  }
}

 List eventosDelDia(DateTime dia) {
  return eventos.where((e) {
    final raw = e['fecha'];
    if (raw == null) return false;

    final fecha = DateTime.parse(raw.toString());

    return fecha.year == dia.year &&
        fecha.month == dia.month &&
        fecha.day == dia.day;
  }).toList();
}

  Future<void> cargarPlanificacion() async {
  final user = supabase.auth.currentUser;

  final agente = await supabase
      .from('usuarios')
      .select('id')
      .eq('auth_id', user!.id)
      .single();

  final data = await supabase
      .from('planificacion_semanal_equipo')
      .select()
      .eq('agente_id', agente['id']);

  for (final p in data) {
    final inicio = DateTime.parse(p['semana_inicio']);

    eventos.addAll([
  {
    'fecha': inicio.add(const Duration(days: 0)).toIso8601String(),
    'titulo': p['lunes'],
    'tipo': 'planificacion'
  },
  {
    'fecha': inicio.add(const Duration(days: 1)).toIso8601String(),
    'titulo': p['martes'],
    'tipo': 'planificacion'
  },
  {
    'fecha': inicio.add(const Duration(days: 2)).toIso8601String(),
    'titulo': p['miercoles'],
    'tipo': 'planificacion'
  },
  {
    'fecha': inicio.add(const Duration(days: 3)).toIso8601String(),
    'titulo': p['jueves'],
    'tipo': 'planificacion'
  },
  {
    'fecha': inicio.add(const Duration(days: 4)).toIso8601String(),
    'titulo': p['viernes'],
    'tipo': 'planificacion'
  },
]);
  }

  agruparEventos();
}

  Future<void> cargarVisitas() async {
  final data = await supabase
      .from('visitas')
      .select()
      .order('fecha_visita', ascending: true);

  eventos.addAll(data);

  
}
void agruparEventos() {
  eventosPorDia.clear();

  for (final e in eventos) {
    debugPrint("AGRUPANDO => ${e['titulo']}");
  debugPrint("FECHA => ${e['fecha']}");
    final raw = e['fecha'];
    if (raw == null) continue;

    final fecha = DateTime.parse(raw.toString()).toLocal();
    final key = DateTime(fecha.year, fecha.month, fecha.day);

    eventosPorDia.putIfAbsent(key, () => []);
    eventosPorDia[key]!.add(e);
  }
  debugPrint("EVENTOS POR DIA => $eventosPorDia");

  setState(() {});
}


Future<void> cargarReuniones() async {
  final user = supabase.auth.currentUser;
  final authId = user!.id;

  final data = await supabase
      .from('reuniones')
      .select('*');

  debugPrint("TODAS REUNIONES => $data");

  final filtradas = data.where((r) {
    final invitados = (r['invitados'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final creador = r['creador_auth_id'];

    final pertenece = invitados.contains(authId) || creador == authId;

    debugPrint("INVITADOS => $invitados");
    debugPrint("PERMITE => $pertenece");

    return pertenece;
  }).toList();

  setState(() {
    eventos.removeWhere((e) => e['tipo'] == 'reunion');

    eventos.addAll(filtradas.map((r) => {
          'titulo': r['titulo'],
          'descripcion': r['descripcion'],
          'fecha': r['fecha_inicio'],
          'tipo': 'reunion',
          'room_id': r['room_id'],
        }));
  });
  debugPrint("EVENTOS DESPUES => $eventos");
  agruparEventos();
}

Widget vistaDiaPro() {
  final eventosDia = eventosPorDia[
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day)] ??
      [];

  return ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: 24,
    itemBuilder: (context, hour) {
      final eventosHora = eventosDia.where((e) {
        final fecha = DateTime.parse(e['fecha']);
        return fecha.hour == hour;
      }).toList();

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50,
              child: Text(
                "${hour.toString().padLeft(2, '0')}:00",
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            Expanded(
              child: Column(
                children: eventosHora.map((e) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: e['tipo'] == 'visita'
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      e['titulo'] ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        title: const Text(
          "Agenda",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.cyanAccent,
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const CrearEventoScreen(),
            ),
          );

          if (res == true) {
            cargarEventos();
          }
        },
        child: const Icon(
          Icons.add,
          color: Colors.black,
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [

                const SizedBox(height: 10),

                 Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _botonVista("MES", 0),
        _botonVista("SEMANA", 1),
        _botonVista("DÍA", 2),
      ],
    ),

               if (vista == 0)
  TableCalendar(
  locale: 'es_ES',
    firstDay: DateTime(2020),
    lastDay: DateTime(2035),
    focusedDay: focusedDay,
    headerStyle: const HeaderStyle(
  formatButtonVisible: false,
  titleCentered: true,
  leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
  rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
  titleTextStyle: TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),
    calendarStyle: const CalendarStyle(
  todayDecoration: BoxDecoration(
    color: Colors.cyanAccent,
    shape: BoxShape.circle,
  ),

  selectedDecoration: BoxDecoration(
    color: Colors.orange,
    shape: BoxShape.circle,
  ),



  defaultTextStyle: TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
  ),

  weekendTextStyle: TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
  ),

  outsideTextStyle: TextStyle(
    color: Colors.white38,
  ),

  todayTextStyle: TextStyle(
    color: Colors.black,
    fontWeight: FontWeight.bold,
  ),

  selectedTextStyle: TextStyle(
    color: Colors.black,
    fontWeight: FontWeight.bold,
  ),
),
    selectedDayPredicate: (day) => isSameDay(selectedDay, day),
    onDaySelected: (selected, focused) {
      setState(() {
        selectedDay = selected;
        focusedDay = focused;
      });
    },
    eventLoader: (day) {
      final d = DateTime(day.year, day.month, day.day);
      return eventosPorDia[DateTime(d.year, d.month, d.day)] ?? [];
    },
    calendarBuilders: CalendarBuilders(
      markerBuilder: (context, day, events) {
        if (events.isEmpty) return null;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: events.take(3).map((e) {
            final tipo = (e as Map)['tipo'];

Color color;

if (tipo == 'visita') {
  color = Colors.blue;
} 
else if (tipo == 'planificacion') {
  color = Colors.orange;
} 
else if (tipo == 'reunion') {
  color = Colors.purple;
} 
else {
  color = Colors.green;
}

return Container(
  margin: const EdgeInsets.symmetric(horizontal: 1),
  width: 6,
  height: 6,
  decoration: BoxDecoration(
    color: color,
    shape: BoxShape.circle,
  ),
);
          }).toList(),
        );
      },
    ),
  )
else if (vista == 1)
  vistaSemana()
else
  Expanded(child: vistaDiaPro()),

                const SizedBox(height: 10),

                Expanded(
                  child: eventosDelDia(
                          selectedDay)
                      .isEmpty
                      ? const Center(
                          child: Text(
                            "No hay eventos este día",
                            style: TextStyle(
                              color:
                                  Colors.white70,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets
                                  .all(16),

                          itemCount:
                              eventosDelDia(
                                      selectedDay)
                                  .length,

                          itemBuilder:
                              (context, i) {
                            final evento =
                                eventosDelDia(
                                        selectedDay)[i];

                            return Container(
                              margin:
                                  const EdgeInsets
                                      .only(
                                          bottom:
                                              12),

                              padding:
                                  const EdgeInsets
                                      .all(14),

                              decoration:
                                  BoxDecoration(
                                color: Colors
                                    .white
                                    .withOpacity(
                                        0.06),

                                borderRadius:
                                    BorderRadius
                                        .circular(
                                            16),

                                border:
                                    Border.all(
                                  color: Colors
                                      .white10,
                                ),
                              ),

                              child: ListTile(
  onTap: () {
    abrirEvento(evento);
  },

  leading: Icon(
    evento['tipo'] == 'reunion'
        ? Icons.video_call
        : Icons.event,
    color: evento['tipo'] == 'reunion'
        ? Colors.purple
        : Colors.cyanAccent,
  ),

  title: Text(
    evento['titulo'] ?? '',
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  ),

  subtitle: Text(
    evento['descripcion'] ?? '',
    style: const TextStyle(
      color: Colors.white70,
    ),
  ),
),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
  Widget _botonVista(String texto, int index) {
  return GestureDetector(
    onTap: () {
      setState(() {
        vista = index;
      });
    },
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: vista == index
            ? Colors.cyanAccent
            : Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: vista == index
              ? Colors.black
              : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
Widget vistaDiaSeleccionado() {
  final key = DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day,
  );

  final eventos = eventosPorDia[key] ?? [];

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        "Eventos del día",
        style: const TextStyle(color: Colors.white),
      ),

      const SizedBox(height: 10),

      ...eventos.map((e) {
        return ListTile(
          title: Text(
            (e['titulo'] ?? '').toString(),
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            (e['tipo'] ?? '').toString(),
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }).toList(),
    ],
  );
}
Widget _bloqueDia(String titulo, List eventos, Color color) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        if (eventos.isEmpty)
          const Text(
            "Sin eventos",
            style: TextStyle(color: Colors.white38),
          )
        else
          ...eventos.map((e) {
  return GestureDetector(
    onTap: () {
      abrirEvento(e);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          e['titulo'] ?? 'Sin título',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
}).toList(),
      ],
    ),
  );
}
void abrirEvento(Map e) {
  final tipo = (e['tipo'] ?? '').toString();

  if (tipo == 'visita') {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Visita"),
        content: Text(
          "Cliente: ${e['titulo'] ?? ''}\n"
          "Estado: ${e['estado'] ?? ''}",
        ),
      ),
    );
  } 
  else if (tipo == 'planificacion') {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Planificación"),
        content: Text((e['titulo'] ?? '').toString()),
      ),
    );
  } 
  else if (tipo == 'reunion') {
  final roomId = e['room_id'];

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(e['titulo'] ?? 'Reunión'),
      content: Text(
        e['descripcion'] ?? '',
      ),
      actions: [

        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Cerrar"),
        ),

        ElevatedButton.icon(
          icon: const Icon(Icons.video_call),
          label: const Text("Entrar"),
          onPressed: () async {

            Navigator.pop(context);

            final url = Uri.parse(
              "https://meet.jit.si/$roomId",
            );

            await launchUrl(
              url,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ],
    ),
  );
}
  else {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Evento"),
        content: Text((e['titulo'] ?? '').toString()),
      ),
    );
  }

}
Widget vistaSemana() {
  final diasSemana = List.generate(7, (i) {
    return DateTime.now().add(Duration(days: i));
  });

  return Expanded(
    child: Row(
      children: diasSemana.map((dia) {
        final eventos = eventosPorDia[
                DateTime(dia.year, dia.month, dia.day)] ??
            [];

        return Expanded(
          child: Container(
            margin: const EdgeInsets.all(2),
            color: Colors.white10,
            child: Column(
              children: [
                Text(
                  "${dia.day}/${dia.month}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                ...eventos.map((e) {
                  return Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    color: e['tipo'] == 'visita'
    ? Colors.blue
    : e['tipo'] == 'reunion'
        ? Colors.purple
        : Colors.green,
                    child: Text(
                      (e['titulo'] ?? '').toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}
Widget vistaDia() {
  final eventos = eventosPorDia[
          DateTime(selectedDay.year, selectedDay.month, selectedDay.day)] ??
      [];

  return ListView(
  padding: const EdgeInsets.all(16),
      children: eventos.map((e) {
        final evento = e as Map;

        return ListTile(
          leading: Icon(
            Icons.event,
            color: evento['tipo'] == 'visita'
    ? Colors.blue
    : evento['tipo'] == 'reunion'
        ? Colors.purple
        : Colors.green,
          ),
          title: Text(
            evento['titulo'] ?? '',
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            evento['descripcion'] ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }).toList(),
   
  );
}
}