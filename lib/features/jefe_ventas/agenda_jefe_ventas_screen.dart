import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:url_launcher/url_launcher.dart';

class AgendaJefeVentasScreen extends StatefulWidget {
  const AgendaJefeVentasScreen({super.key});

  @override
  State<AgendaJefeVentasScreen> createState() => _AgendaJefeVentasScreenState();
}

class _AgendaJefeVentasScreenState extends State<AgendaJefeVentasScreen> {
  final supabase = Supabase.instance.client;
  final CalendarController calendarController = CalendarController();

  bool loading = true;
  String? error;

  CalendarView currentView = CalendarView.month;
  DateTime displayDate = DateTime.now();

  String? myUserId;
  final Set<String> allowedAuthIds = {};

  List<Map<String, dynamic>> agenda = [];
  List<Map<String, dynamic>> reuniones = [];
  List<Appointment> appointments = [];

  @override
  void initState() {
    super.initState();
    loadAgenda();
  }

  Future<void> loadAgenda() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() {
        loading = true;
        error = null;
      });

      final me = await supabase
          .from('usuarios')
          .select('id, auth_id')
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          )
          .eq('auth_id', user.id)
          .single();

      myUserId = me['id']?.toString();

      final jefesEquipo = await supabase
          .from('usuarios')
          .select('id, auth_id')
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          )
          .eq('parent_id', myUserId!)
          .eq('rol_usuario', 'jefe_equipo');

      allowedAuthIds.clear();
      allowedAuthIds.add(user.id.toString());

      for (final jefe in jefesEquipo) {
        final jefeAuth = jefe['auth_id'];
        final jefeId = jefe['id'];

        if (jefeAuth != null) {
          allowedAuthIds.add(jefeAuth.toString());
        }

        final agentes = await supabase
            .from('usuarios')
            .select('auth_id')
            .or(
              'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
            )
            .eq('parent_id', jefeId)
            .eq('rol_usuario', 'agente');

        for (final agente in agentes) {
          final auth = agente['auth_id'];
          if (auth != null) {
            allowedAuthIds.add(auth.toString());
          }
        }
      }

      final agendaRes = await supabase
          .from('agenda_eventos')
          .select('*')
          .inFilter('auth_id', allowedAuthIds.toList())
          .order('fecha_inicio', ascending: true);

      final reunionesRes = await supabase
          .from('reuniones')
          .select('*')
          .order('fecha_inicio', ascending: true);

      agenda = List<Map<String, dynamic>>.from(agendaRes);
      reuniones = List<Map<String, dynamic>>.from(reunionesRes);

      setState(() {
        appointments = getAppointments();
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> refreshCalendar() async {
    try {
      final agendaRes = await supabase
          .from('agenda_eventos')
          .select('*')
          .inFilter('auth_id', allowedAuthIds.toList())
          .order('fecha_inicio', ascending: true);

      final reunionesRes = await supabase
          .from('reuniones')
          .select('*')
          .order('fecha_inicio', ascending: true);

      setState(() {
        agenda = List<Map<String, dynamic>>.from(agendaRes);
        reuniones = List<Map<String, dynamic>>.from(reunionesRes);
        appointments = getAppointments();
      });
    } catch (e) {
      debugPrint('ERROR REFRESH AGENDA => $e');
    }
  }

  List<Appointment> getAppointments() {
    final List<Appointment> eventos = [];

    for (final item in agenda) {
      final origen = (item['origen'] ?? '').toString();
      final esPropio = item['auth_id'] == supabase.auth.currentUser?.id;

      Color color;

      if (esPropio) {
        color = const Color(0xFF20C7C2);
      } else if (origen == 'manual') {
        color = Colors.orangeAccent;
      } else {
        color = Colors.greenAccent;
      }

      eventos.add(
        Appointment(
          id: item['id']?.toString(),
          startTime: DateTime.parse(item['fecha_inicio']),
          endTime: DateTime.parse(item['fecha_fin']),
          subject: item['titulo'] ?? '',
          notes: item['descripcion'] ?? '',
          color: color,
          location: item['id']?.toString(),
        ),
      );
    }

    for (final reunion in reuniones) {
      eventos.add(
        Appointment(
          id: reunion['id']?.toString(),
          startTime: DateTime.parse(reunion['fecha_inicio']),
          endTime: DateTime.parse(reunion['fecha_fin']),
          subject: reunion['titulo'] ?? 'Reunión',
          notes: reunion['descripcion'] ?? '',
          location: reunion['room_id']?.toString() ?? reunion['id'].toString(),
          color: Colors.purpleAccent,
        ),
      );
    }

    return eventos;
  }

  String _getHeaderTitle() {
    final current = calendarController.displayDate ?? displayDate;

    if (currentView == CalendarView.month) {
      final meses = [
        'Enero',
        'Febrero',
        'Marzo',
        'Abril',
        'Mayo',
        'Junio',
        'Julio',
        'Agosto',
        'Septiembre',
        'Octubre',
        'Noviembre',
        'Diciembre',
      ];

      return '${meses[current.month - 1]} ${current.year}';
    }

    if (currentView == CalendarView.week) {
      return 'Semana ${_weekNumber(current)}';
    }

    return '${current.day}/${current.month}/${current.year}';
  }

  int _weekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(firstDayOfYear).inDays;
    return (diff / 7).floor() + 1;
  }

  int get reunionesHoy {
    final now = DateTime.now();

    return appointments.where((a) {
      return a.startTime.year == now.year &&
          a.startTime.month == now.month &&
          a.startTime.day == now.day;
    }).length;
  }

  int get reunionesSemana {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 7));

    return appointments.where((a) {
      return a.startTime.isAfter(start.subtract(const Duration(seconds: 1))) &&
          a.startTime.isBefore(end);
    }).length;
  }

  void _goPrevious() {
    setState(() {
      final current = calendarController.displayDate ?? DateTime.now();

      if (currentView == CalendarView.month) {
        calendarController.displayDate = DateTime(
          current.year,
          current.month - 1,
          1,
        );
      } else if (currentView == CalendarView.week) {
        calendarController.displayDate = current.subtract(
          const Duration(days: 7),
        );
      } else {
        calendarController.displayDate = current.subtract(
          const Duration(days: 1),
        );
      }
    });
  }

  void _goNext() {
    setState(() {
      final current = calendarController.displayDate ?? DateTime.now();

      if (currentView == CalendarView.month) {
        calendarController.displayDate = DateTime(
          current.year,
          current.month + 1,
          1,
        );
      } else if (currentView == CalendarView.week) {
        calendarController.displayDate = current.add(const Duration(days: 7));
      } else {
        calendarController.displayDate = current.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _openMeetingDialog(DateTime selectedDate) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => MeetingCreateDialog(
        selectedDate: selectedDate,
        supabase: supabase,
        onSaved: refreshCalendar,
      ),
    );
  }

  Future<void> _openEventDetails(
    Appointment event,
    DateTime selectedDate,
  ) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withOpacity(0.96),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.12),
                      blurRadius: 36,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: event.color.withOpacity(0.18),
                            border: Border.all(
                              color: event.color.withOpacity(0.45),
                            ),
                          ),
                          child: Icon(
                            Icons.event_available_rounded,
                            color: event.color,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            event.subject,
                            style: const TextStyle(
                              color: const Color(0xFF111827),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    _detailLine(
                      Icons.calendar_month_rounded,
                      'Fecha',
                      '${event.startTime.day}/${event.startTime.month}/${event.startTime.year}',
                      const Color(0xFF2563EB),
                    ),

                    _detailLine(
                      Icons.access_time_rounded,
                      'Horario',
                      '${_formatTime(event.startTime)} - ${_formatTime(event.endTime)}',
                      Colors.orangeAccent,
                    ),

                    if ((event.notes ?? '').trim().isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          event.notes ?? '',
                          style: const TextStyle(
                            color: const Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ),

                    const SizedBox(height: 22),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('Editar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orangeAccent,
                              side: BorderSide(
                                color: Colors.orangeAccent.withOpacity(0.45),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(context);

                              showDialog(
                                context: context,
                                barrierColor: Colors.black.withOpacity(0.75),
                                builder: (_) => MeetingCreateDialog(
                                  supabase: supabase,
                                  selectedDate: selectedDate,
                                  editData: {
                                    'id': event.id?.toString(),
                                    'titulo': event.subject,
                                    'descripcion': event.notes,
                                    'room_id': event.location,
                                    'fecha_inicio': event.startTime
                                        .toIso8601String(),
                                    'fecha_fin': event.endTime
                                        .toIso8601String(),
                                  },
                                  onSaved: refreshCalendar,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.video_call_rounded),
                            label: const Text('Entrar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: const Color(0xFFFFFFFF),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final room =
                                  event.location ??
                                  event.id?.toString() ??
                                  'safebrok';

                              final url = Uri.parse(
                                'https://meet.jit.si/$room',
                              );

                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        icon: const Icon(Icons.delete_rounded),
                        label: const Text('Eliminar reunión'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);

                          final id = event.id?.toString();

                          if (id != null && id.isNotEmpty) {
                            await supabase
                                .from('reuniones')
                                .delete()
                                .eq('id', id);
                          } else {
                            await supabase
                                .from('reuniones')
                                .delete()
                                .eq(
                                  'room_id',
                                  event.location ?? event.id ?? '',
                                );
                          }

                          await refreshCalendar();

                          if (!mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Reunión eliminada')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _detailLine(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMeetingDialog(DateTime.now()),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nueva reunión',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          const _AgendaBackground(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF2563EB),
                    ),
                  )
                : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: _glassCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: const Color(0xFF2563EB),
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No se pudo cargar la agenda',
                              style: TextStyle(
                                color: const Color(0xFF111827),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                        child: Column(
                          children: [
                            _header(),
                            const SizedBox(height: 16),
                            _kpis(),
                            const SizedBox(height: 14),
                            _viewSelector(),
                            const SizedBox(height: 10),
                            _calendarNavigator(),
                          ],
                        ),
                      ),

                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: const Color(0xFFD7DFEA)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0F172A,
                                ).withOpacity(0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: SfCalendar(
                              key: ValueKey(currentView),
                              view: currentView,
                              controller: calendarController,
                              backgroundColor: Colors.white,
                              initialDisplayDate:
                                  calendarController.displayDate ??
                                  DateTime.now(),
                              dataSource: AgendaDataSource(appointments),

                              onViewChanged: (ViewChangedDetails details) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!mounted) return;

                                  setState(() {
                                    displayDate = details.visibleDates.first;
                                  });
                                });
                              },

                              onTap: (CalendarTapDetails details) {
                                final selectedDate =
                                    details.date ?? DateTime.now();
                                final appointment = details.appointments;

                                if (appointment != null &&
                                    appointment.isNotEmpty) {
                                  final event =
                                      appointment.first as Appointment;
                                  _openEventDetails(event, selectedDate);
                                } else {
                                  _openMeetingDialog(selectedDate);
                                }
                              },

                              todayHighlightColor: const Color(0xFF2563EB),
                              cellBorderColor: const Color(0xFFE2E8F0),

                              selectionDecoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF2563EB),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),

                              headerHeight: 0,

                              viewHeaderStyle: const ViewHeaderStyle(
                                backgroundColor: Color(0xFFF8FAFC),
                                dateTextStyle: TextStyle(
                                  color: const Color(0xFF111827),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                                dayTextStyle: TextStyle(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              timeSlotViewSettings: const TimeSlotViewSettings(
                                timeTextStyle: TextStyle(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                                dateFormat: 'd',
                                dayFormat: 'EEE',
                              ),

                              monthViewSettings: const MonthViewSettings(
                                showAgenda: true,
                                appointmentDisplayMode:
                                    MonthAppointmentDisplayMode.indicator,
                                dayFormat: 'EEE',
                                agendaStyle: AgendaStyle(
                                  backgroundColor: Color(0xFFF8FAFC),
                                  appointmentTextStyle: TextStyle(
                                    color: const Color(0xFF111827),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  dateTextStyle: TextStyle(
                                    color: const Color(0xFF2563EB),
                                    fontWeight: FontWeight.w900,
                                  ),
                                  dayTextStyle: TextStyle(
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                monthCellStyle: MonthCellStyle(
                                  backgroundColor: Color(0xFFFFFFFF),
                                  trailingDatesBackgroundColor: Color(
                                    0xFFF8FAFC,
                                  ),
                                  leadingDatesBackgroundColor: Color(
                                    0xFFF8FAFC,
                                  ),
                                  textStyle: TextStyle(
                                    color: const Color(0xFF111827),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  todayTextStyle: TextStyle(
                                    color: const Color(0xFF2563EB),
                                    fontWeight: FontWeight.w900,
                                  ),
                                  trailingDatesTextStyle: TextStyle(
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  leadingDatesTextStyle: TextStyle(
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withOpacity(0.16),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agenda Global',
                style: TextStyle(
                  color: const Color(0xFF111827),
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Reuniones, equipo y planificación comercial',
                style: TextStyle(color: const Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2563EB).withOpacity(0.12),
            border: Border.all(
              color: const Color(0xFF2563EB).withOpacity(0.38),
            ),
          ),
          child: const Icon(
            Icons.calendar_month_rounded,
            color: const Color(0xFF2563EB),
          ),
        ),
      ],
    );
  }

  Widget _kpis() {
    return Row(
      children: [
        Expanded(
          child: _kpiBox(
            title: 'Eventos',
            value: appointments.length.toString(),
            icon: Icons.event_available_rounded,
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: 'Hoy',
            value: reunionesHoy.toString(),
            icon: Icons.today_rounded,
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: 'Semana',
            value: reunionesSemana.toString(),
            icon: Icons.date_range_rounded,
            color: const Color(0xFF2563EB),
          ),
        ),
      ],
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _viewChip(
              'Mes',
              CalendarView.month,
              Icons.calendar_view_month_rounded,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _viewChip(
              'Semana',
              CalendarView.week,
              Icons.view_week_rounded,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _viewChip('Día', CalendarView.day, Icons.today_rounded),
          ),
        ],
      ),
    );
  }

  Widget _viewChip(String label, CalendarView view, IconData icon) {
    final isSelected = currentView == view;

    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () {
        setState(() {
          currentView = view;
          calendarController.view = view;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF334155),
              size: 19,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarNavigator() {
    return Row(
      children: [
        _navButton(Icons.chevron_left_rounded, _goPrevious),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              _getHeaderTitle(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: const Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _navButton(Icons.chevron_right_rounded, _goNext),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.28)),
        ),
        child: Icon(icon, color: const Color(0xFF111827), size: 30),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AgendaDataSource extends CalendarDataSource {
  AgendaDataSource(List<Appointment> source) {
    appointments = source;
  }
}

class MeetingCreateDialog extends StatefulWidget {
  final SupabaseClient supabase;
  final DateTime selectedDate;
  final Map<String, dynamic>? editData;
  final VoidCallback onSaved;

  const MeetingCreateDialog({
    super.key,
    required this.supabase,
    required this.selectedDate,
    this.editData,
    required this.onSaved,
  });

  @override
  State<MeetingCreateDialog> createState() => _MeetingCreateDialogState();
}

class _MeetingCreateDialogState extends State<MeetingCreateDialog> {
  final TextEditingController descripcionCtrl = TextEditingController();
  final TextEditingController tituloCtrl = TextEditingController();

  TimeOfDay startTime = TimeOfDay.now();
  TimeOfDay endTime = TimeOfDay.now();
  DateTime selectedDate = DateTime.now();

  List<Map<String, dynamic>> usuarios = [];
  List<String> invitados = [];

  bool saving = false;

  @override
  void initState() {
    super.initState();

    selectedDate = widget.selectedDate;

    final defaultEnd = DateTime.now().add(const Duration(hours: 1));
    endTime = TimeOfDay(hour: defaultEnd.hour, minute: defaultEnd.minute);

    if (widget.editData != null) {
      tituloCtrl.text = widget.editData!['titulo'] ?? '';
      descripcionCtrl.text = widget.editData!['descripcion'] ?? '';
      invitados = List<String>.from(widget.editData!['invitados'] ?? []);

      final inicio = DateTime.tryParse(
        widget.editData!['fecha_inicio']?.toString() ?? '',
      );
      final fin = DateTime.tryParse(
        widget.editData!['fecha_fin']?.toString() ?? '',
      );

      if (inicio != null) {
        selectedDate = inicio;
        startTime = TimeOfDay(hour: inicio.hour, minute: inicio.minute);
      }

      if (fin != null) {
        endTime = TimeOfDay(hour: fin.hour, minute: fin.minute);
      }
    }

    loadUsuarios();
  }

  @override
  void dispose() {
    tituloCtrl.dispose();
    descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> loadUsuarios() async {
    final res = await widget.supabase
        .from('usuarios')
        .select('id, nombre, apellidos, auth_id')
        .or(
          'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
        )
        .order('nombre', ascending: true);

    setState(() {
      usuarios = List<Map<String, dynamic>>.from(res);
    });
  }

  Future<DateTime?> _pickDate() {
    return showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2454D3),
              surface: Color(0xFFFFFFFF),
              onSurface: const Color(0xFF071A3A),
            ),
            dialogBackgroundColor: const Color(0xFFFFFFFF),
          ),
          child: child!,
        );
      },
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2454D3),
              surface: Color(0xFFFFFFFF),
              onSurface: const Color(0xFF071A3A),
            ),
            dialogBackgroundColor: const Color(0xFFFFFFFF),
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> saveMeeting() async {
    if (tituloCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un título para la reunión')),
      );
      return;
    }

    setState(() => saving = true);

    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      startTime.hour,
      startTime.minute,
    );

    var end = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      endTime.hour,
      endTime.minute,
    );

    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 1));
    }

    try {
      final creadorAuthId = widget.supabase.auth.currentUser?.id ?? '';
      final invitadosAnteriores = widget.editData == null
          ? <String>{}
          : List<String>.from(
              widget.editData!['invitados'] ?? const <String>[],
            ).toSet();
      final invitadosNuevos = invitados
          .map((authId) => authId.trim())
          .where(
            (authId) =>
                authId.isNotEmpty &&
                authId != creadorAuthId &&
                !invitadosAnteriores.contains(authId),
          )
          .toSet()
          .toList();

      late dynamic reunionId;
      late String roomIdFinal;

      if (widget.editData == null) {
        final roomId = 'safebrok-${DateTime.now().millisecondsSinceEpoch}';

        final reunionCreada = await widget.supabase
            .from('reuniones')
            .insert({
              'titulo': tituloCtrl.text.trim(),
              'descripcion': descripcionCtrl.text.trim(),
              'fecha_inicio': start.toIso8601String(),
              'fecha_fin': end.toIso8601String(),
              'room_id': roomId,
              'creador_auth_id': creadorAuthId,
              'invitados': invitados.toSet().toList(),
            })
            .select('id, room_id')
            .single();

        reunionId = reunionCreada['id'];
        roomIdFinal = reunionCreada['room_id']?.toString() ?? roomId;
      } else {
        await widget.supabase
            .from('reuniones')
            .update({
              'titulo': tituloCtrl.text.trim(),
              'descripcion': descripcionCtrl.text.trim(),
              'fecha_inicio': start.toIso8601String(),
              'fecha_fin': end.toIso8601String(),
              'invitados': invitados.toSet().toList(),
            })
            .eq('id', widget.editData!['id']);

        reunionId = widget.editData!['id'];
        roomIdFinal = widget.editData!['room_id']?.toString() ?? '';
      }

      // Se ejecuta después de guardar. Cualquier fallo del push se captura
      // internamente y nunca deshace la reunión.
      _notificarNuevosInvitados(
        authIdsInvitados: invitadosNuevos,
        creadorAuthId: creadorAuthId,
        reunionId: reunionId,
        roomId: roomIdFinal,
        titulo: tituloCtrl.text.trim(),
        descripcion: descripcionCtrl.text.trim(),
        inicio: start,
        fin: end,
      );

      widget.onSaved();

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  Future<void> _notificarNuevosInvitados({
    required List<String> authIdsInvitados,
    required String creadorAuthId,
    required dynamic reunionId,
    required String roomId,
    required String titulo,
    required String descripcion,
    required DateTime inicio,
    required DateTime fin,
  }) async {
    if (authIdsInvitados.isEmpty) return;

    try {
      final creador = usuarios.firstWhere(
        (usuario) => usuario['auth_id']?.toString().trim() == creadorAuthId,
        orElse: () => <String, dynamic>{},
      );

      final nombre = creador['nombre']?.toString().trim() ?? '';
      final apellidos = creador['apellidos']?.toString().trim() ?? '';
      final nombreCreador = '$nombre $apellidos'.trim();
      final organizador = nombreCreador.isEmpty
          ? 'Tu responsable'
          : nombreCreador;

      final fecha =
          '${inicio.day.toString().padLeft(2, '0')}/'
          '${inicio.month.toString().padLeft(2, '0')}/'
          '${inicio.year}';
      final hora =
          '${inicio.hour.toString().padLeft(2, '0')}:'
          '${inicio.minute.toString().padLeft(2, '0')}';

      final mensaje =
          '$organizador te ha invitado a "$titulo" '
          'el $fecha a las $hora. Consulta tu agenda para ver los detalles.';

      for (final authIdDestino in authIdsInvitados.toSet()) {
        try {
          final response = await widget.supabase.functions.invoke(
            'enviar-push',
            body: {
              'auth_id_destino': authIdDestino,
              'incluir_superiores': false,
              'titulo': 'Nueva invitación a un evento',
              'mensaje': mensaje,
              'data': {
                'tipo': 'invitacion_reunion',
                'reunion_id': reunionId,
                'room_id': roomId,
                'titulo_evento': titulo,
                'descripcion': descripcion,
                'fecha_inicio': inicio.toIso8601String(),
                'fecha_fin': fin.toIso8601String(),
                'creador_auth_id': creadorAuthId,
              },
            },
          );

          if (response.status < 200 || response.status >= 300) {
            debugPrint(
              'PUSH INVITACIÓN NO ENVIADO A $authIdDestino. '
              'HTTP ${response.status}: ${response.data}',
            );
          }
        } catch (errorPush) {
          debugPrint('ERROR PUSH INVITACIÓN A $authIdDestino: $errorPush');
        }
      }
    } catch (error) {
      // El evento ya está guardado y nunca debe revertirse por el push.
      debugPrint('ERROR GENERAL NOTIFICANDO INVITADOS: $error');
    }
  }

  String _dateText() {
    return '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.editData != null;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 720),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF).withOpacity(0.97),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(0.32),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withOpacity(0.13),
                  blurRadius: 36,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2563EB).withOpacity(0.13),
                          border: Border.all(
                            color: const Color(0xFF2563EB).withOpacity(0.38),
                          ),
                        ),
                        child: Icon(
                          editando
                              ? Icons.edit_calendar_rounded
                              : Icons.video_call_rounded,
                          color: const Color(0xFF2563EB),
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          editando ? 'Editar reunión' : 'Nueva reunión',
                          style: const TextStyle(
                            color: const Color(0xFF111827),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  _field(
                    controller: tituloCtrl,
                    label: 'Título',
                    icon: Icons.title_rounded,
                  ),

                  const SizedBox(height: 14),

                  _field(
                    controller: descripcionCtrl,
                    label: 'Descripción',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _selectorBox(
                          icon: Icons.calendar_month_rounded,
                          title: 'Fecha',
                          value: _dateText(),
                          color: const Color(0xFF2563EB),
                          onTap: () async {
                            final picked = await _pickDate();
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _selectorBox(
                          icon: Icons.access_time_rounded,
                          title: 'Inicio',
                          value: startTime.format(context),
                          color: const Color(0xFF2563EB),
                          onTap: () async {
                            final picked = await _pickTime(startTime);
                            if (picked != null) {
                              setState(() {
                                startTime = picked;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _selectorBox(
                          icon: Icons.timer_rounded,
                          title: 'Fin',
                          value: endTime.format(context),
                          color: const Color(0xFF2563EB),
                          onTap: () async {
                            final picked = await _pickTime(endTime);
                            if (picked != null) {
                              setState(() {
                                endTime = picked;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Invitados',
                          style: TextStyle(
                            color: const Color(0xFF111827),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF2563EB).withOpacity(0.30),
                          ),
                        ),
                        child: Text(
                          '${invitados.length}',
                          style: const TextStyle(
                            color: const Color(0xFF2563EB),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: usuarios.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(
                              child: Text(
                                'Cargando usuarios...',
                                style: TextStyle(
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: usuarios.length,
                            itemBuilder: (context, index) {
                              final u = usuarios[index];
                              final authId = u['auth_id']?.toString();
                              final nombre =
                                  '${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}'
                                      .trim();
                              final isSelected = invitados.contains(authId);

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: const Color(0xFF2563EB),
                                checkColor: const Color(0xFFFFFFFF),
                                title: Text(
                                  nombre.isEmpty
                                      ? 'Usuario sin nombre'
                                      : nombre,
                                  style: const TextStyle(
                                    color: const Color(0xFF111827),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  authId ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: const Color(0xFF78909C),
                                    fontSize: 11,
                                  ),
                                ),
                                onChanged: (v) {
                                  if (authId == null) return;

                                  setState(() {
                                    if (v == true) {
                                      invitados.add(authId);
                                    } else {
                                      invitados.remove(authId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.22),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : saveMeeting,
                          icon: saving
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                )
                              : Icon(
                                  editando
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                ),
                          label: Text(
                            editando ? 'Guardar' : 'Crear',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: const Color(0xFFFFFFFF),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: const Color(0xFF111827)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: const Color(0xFF64748B)),
        prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: const Color(0xFF2563EB).withOpacity(0.65),
          ),
        ),
      ),
    );
  }

  Widget _selectorBox({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.26)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaBackground extends StatelessWidget {
  const _AgendaBackground();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(child: ColoredBox(color: Color(0xFFF4F6FB)));
  }
}
