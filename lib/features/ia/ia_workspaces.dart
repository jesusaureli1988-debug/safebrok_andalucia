import 'package:flutter/material.dart';

class IaWorkspace {
  const IaWorkspace(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.prompts,
  );
  final String id, title, subtitle;
  final IconData icon;
  final List<(String, String)> prompts;
}

const iaWorkspaces = [
  IaWorkspace(
    'general',
    'Asistente general',
    'Conecta información y organiza tu trabajo con SafeBrok.',
    Icons.auto_awesome_outlined,
    [
      (
        'Mi día de trabajo',
        'Revisa mi agenda y mis gestiones pendientes y propón prioridades para hoy.',
      ),
      (
        'Analizar mi estructura',
        'Resume la producción de mi estructura por fecha de efecto del cargo actual.',
      ),
      (
        'Preparar una acción',
        'Explícame qué acciones puedes preparar y ayúdame a elegir la que necesito.',
      ),
      (
        'Explorar los módulos',
        'Consulta el catálogo y dime qué módulos puedes consultar con mis permisos.',
      ),
    ],
  ),
  IaWorkspace(
    'seguros',
    'Seguros y condicionados',
    'Compañías, coberturas y pólizas con fuentes verificables.',
    Icons.shield_outlined,
    [
      (
        'Comparar garantías',
        'Quiero comparar garantías de seguros. Pregúntame qué producto, compañías, país y modalidad me interesan. Busca documentación oficial y distingue lo verificado de lo que falta.',
      ),
      (
        'Analizar mi condicionado',
        'Quiero analizar un condicionado que voy a adjuntar. Revisa garantías, exclusiones, límites, franquicias y carencias citando sus cláusulas.',
      ),
      (
        'Buscar condicionados',
        'Ayúdame a localizar las condiciones generales oficiales de un producto. Pregúntame compañía, producto y versión si hace falta.',
      ),
      (
        'Preparar una comparativa',
        'Ayúdame a preparar un PDF comparativo de dos seguros con fuentes. Pregúntame cuáles.',
      ),
    ],
  ),
  IaWorkspace(
    'legal',
    'Consultas y documentos legales',
    'Normativa contrastada y borradores para revisar.',
    Icons.balance_outlined,
    [
      (
        'Consultar normativa',
        'Quiero consultar normativa de seguros con fuentes oficiales vigentes. Pregúntame el tema y la jurisdicción.',
      ),
      (
        'Redactar una reclamación',
        'Ayúdame a preparar un borrador de reclamación a una aseguradora. Pregúntame los hechos y documentos necesarios; no inventes datos ni lo envíes.',
      ),
      (
        'Revisar cláusulas',
        'Voy a adjuntar un contrato. Explícame las cláusulas relevantes y posibles dudas, diferenciando texto e interpretación.',
      ),
      (
        'Preparar un escrito',
        'Ayúdame a preparar un borrador jurídico. Pregúntame el propósito, destinatario y jurisdicción.',
      ),
    ],
  ),
  IaWorkspace(
    'creatividad',
    'Diseño y marca',
    'Logos, tarjetas e imágenes con tu estilo.',
    Icons.palette_outlined,
    [
      (
        'Crear un logo',
        'Quiero un logo original. Pregúntame la marca, el sector y el estilo; propón colores si no los tengo definidos.',
      ),
      (
        'Tarjeta de presentación',
        'Quiero una tarjeta de presentación profesional de dos caras. Pregúntame los datos de contacto y el estilo; no inventes información.',
      ),
      (
        'Proponer variantes',
        'Quiero tres variantes vectoriales de un logo. Pregúntame el nombre y el estilo.',
      ),
      (
        'Crear una imagen',
        'Ayúdame a crear una imagen. Pregúntame qué debe mostrar, el estilo y para qué la voy a usar.',
      ),
    ],
  ),
  IaWorkspace(
    'internet',
    'Buscar en internet',
    'Información actual con enlaces a las fuentes.',
    Icons.travel_explore_outlined,
    [
      (
        'Investigar un tema',
        'Quiero investigar un tema en internet con fuentes actuales. Pregúntame cuál.',
      ),
      (
        'Comprobar una afirmación',
        'Quiero verificar una afirmación con fuentes primarias. Pregúntame qué debo comprobar.',
      ),
      (
        'Preparar un resumen',
        'Quiero un resumen de una investigación en PDF con fuentes. Pregúntame el tema y el alcance.',
      ),
      (
        'Buscar documentación',
        'Ayúdame a localizar documentación oficial. Pregúntame de qué tema.',
      ),
    ],
  ),
  IaWorkspace(
    'bots',
    'Bots y automatizaciones',
    'Tu seguimiento diario, incluso cuando cierres la app.',
    Icons.smart_toy_outlined,
    [
      (
        'Actividad semanal por usuario',
        'Prepara un bot todos los lunes a las 9 que me entregue en PDF un resumen de toda la actividad registrada de cada usuario de mi ámbito durante los 7 días completos anteriores. Incluye todos los módulos disponibles, los usuarios sin registros, totales y limitaciones.',
      ),
      (
        'Seguir incorporaciones',
        'Prepara un bot semanal los lunes a las 10 para revisar las incorporaciones pendientes de mi ámbito.',
      ),
      (
        'Crear un recordatorio',
        'Ayúdame a preparar un recordatorio. Pregúntame qué debo recordar y cuándo.',
      ),
      (
        'Revisar mis bots',
        'Consulta mis bots y sus últimas ejecuciones y dime cuáles están activos o tienen errores.',
      ),
    ],
  ),
  IaWorkspace(
    'ventas',
    'Ventas y producción',
    'Pólizas, primas y evolución del cargo en un solo espacio.',
    Icons.insights_outlined,
    [
      (
        'Resumen del cargo',
        'Resume las pólizas de mi estructura cuya fecha de efecto corresponde al cargo actual.',
      ),
      (
        'Comparar compañías',
        'Compara la producción de mi ámbito por compañía en el cargo actual.',
      ),
      (
        'Ver pólizas anuladas',
        'Revisa las pólizas anuladas de mi ámbito y sus fechas de efecto.',
      ),
      (
        'Comparar productos',
        'Agrupa las pólizas del cargo actual de mi ámbito por producto.',
      ),
    ],
  ),
  IaWorkspace(
    'clientes',
    'Clientes y recibos',
    'Consulta fichas, pólizas relacionadas y cobros pendientes.',
    Icons.people_outline_rounded,
    [
      (
        'Buscar un cliente',
        'Ayúdame a localizar un cliente. Pregúntame el nombre, DNI o teléfono antes de buscar.',
      ),
      (
        'Recibos pendientes',
        'Revisa los recibos pendientes visibles para mí y resume las prioridades.',
      ),
      (
        'Preparar seguimiento',
        'Ayúdame a preparar una gestión de seguimiento de un cliente. Pregúntame cuál y qué necesito hacer.',
      ),
      (
        'Relacionar pólizas',
        'Ayúdame a revisar las pólizas de un cliente. Primero pregúntame qué cliente.',
      ),
    ],
  ),
  IaWorkspace(
    'incorporaciones',
    'Incorporaciones',
    'Candidatos, documentación, firmas y próximos pasos.',
    Icons.person_add_alt_rounded,
    [
      (
        'Qué está pendiente',
        'Resume las incorporaciones pendientes de mi ámbito por estado.',
      ),
      (
        'Firmas por confirmar',
        'Busca incorporaciones con contrato firmado pendientes de confirmación y explica cómo revisarlas.',
      ),
      (
        'Revisar un candidato',
        'Ayúdame a localizar un candidato y su incorporación. Pregúntame su nombre.',
      ),
      (
        'Preparar una gestión',
        'Ayúdame a preparar una gestión para dar seguimiento a una incorporación pendiente.',
      ),
    ],
  ),
  IaWorkspace(
    'agenda',
    'Agenda y gestiones',
    'Planifica citas, prepara tareas y organiza prioridades.',
    Icons.calendar_month_outlined,
    [
      (
        'Organizar el día',
        'Consulta mi agenda y las gestiones pendientes y ayúdame a organizar el día.',
      ),
      (
        'Preparar una cita',
        'Ayúdame a preparar una cita. Pregúntame título, fecha y horario.',
      ),
      (
        'Preparar una gestión',
        'Ayúdame a preparar una gestión. Pregúntame el objetivo, el destinatario y la fecha límite.',
      ),
      (
        'Revisar vencimientos',
        'Consulta las gestiones de mi ámbito y prioriza las que vencen antes.',
      ),
    ],
  ),
  IaWorkspace(
    'informes',
    'Informes y análisis',
    'Convierte los datos en conclusiones y documentos útiles.',
    Icons.description_outlined,
    [
      (
        'Informe de mi estructura',
        'Genera un informe PDF de la producción de mi estructura para el cargo actual.',
      ),
      (
        'Comparar periodos',
        'Ayúdame a comparar dos periodos de producción. Pregúntame cuáles antes de consultar.',
      ),
      (
        'Analizar resultados',
        'Analiza los resultados de mi ámbito y explica el periodo, el alcance y las limitaciones del dato.',
      ),
      (
        'Crear cualquier documento',
        'Ayúdame a crear un documento, tabla, presentación o imagen. Pregúntame el tema, el contenido y el formato que necesito.',
      ),
    ],
  ),
  IaWorkspace(
    'safecloud',
    'SafeCloud',
    'Encuentra carpetas y prepara la organización documental.',
    Icons.folder_outlined,
    [
      (
        'Ver mis carpetas',
        'Consulta mis carpetas y documentos visibles en SafeCloud y resume cómo están organizados.',
      ),
      (
        'Crear una carpeta',
        'Ayúdame a preparar una carpeta en SafeCloud. Pregúntame el nombre y dónde debe estar.',
      ),
      (
        'Encontrar un documento',
        'Ayúdame a localizar un documento en SafeCloud. Pregúntame su nombre.',
      ),
      (
        'Organizar un proyecto',
        'Propón una organización de carpetas para un proyecto. No prepares acciones hasta que elija la estructura.',
      ),
    ],
  ),
];
IaWorkspace iaWorkspace(String id) => iaWorkspaces.firstWhere(
  (w) => w.id == id,
  orElse: () => iaWorkspaces.first,
);
