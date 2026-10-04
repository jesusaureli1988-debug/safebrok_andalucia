import { createClient } from 'npm:@supabase/supabase-js@2';

type Tarea = Record<string, unknown>;

const responseHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
};

const text = (value: unknown) => String(value ?? '').trim();

const normalized = (value: unknown) =>
  text(value)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');

const isActive = (status: unknown) =>
  ![
    'baja',
    'inactivo',
    'inactiva',
    'bloqueado',
    'bloqueada',
    'desactivado',
    'desactivada',
    'suspendido',
    'suspendida',
  ].includes(normalized(status));

const formatDate = (value: unknown) => {
  const raw = text(value);
  if (!raw) return '';

  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return '';

  return new Intl.DateTimeFormat('es-ES', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(date);
};

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response(
      JSON.stringify({ ok: false, error: 'Método no permitido' }),
      { status: 405, headers: responseHeaders },
    );
  }

  const expectedSecret = Deno.env.get('CRON_SECRET') ?? '';

  if (
    !expectedSecret ||
    request.headers.get('x-cron-secret') !== expectedSecret
  ) {
    return new Response(
      JSON.stringify({ ok: false, error: 'No autorizado' }),
      { status: 401, headers: responseHeaders },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: 'Falta configuración interna',
      }),
      { status: 500, headers: responseHeaders },
    );
  }

  try {
    const payload = await request.json() as {
      record?: Tarea;
      motivo?: string;
    };

    const task = payload.record;

    if (!task) {
      return new Response(
        JSON.stringify({ ok: true, procesados: 0 }),
        { headers: responseHeaders },
      );
    }

    const taskId = text(task.id);
    const recipientAuthId = text(task.asignado_a_auth_id);

    if (!taskId || !recipientAuthId) {
      return new Response(
        JSON.stringify({
          ok: true,
          procesados: 0,
          motivo: 'sin_tarea_o_destinatario',
        }),
        { headers: responseHeaders },
      );
    }

    const db = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const { data: recipient, error: recipientError } = await db
      .from('usuarios')
      .select('auth_id, estado')
      .eq('auth_id', recipientAuthId)
      .maybeSingle();

    if (recipientError) throw recipientError;

    if (!recipient || !isActive(recipient.estado)) {
      return new Response(
        JSON.stringify({
          ok: true,
          procesados: 0,
          motivo: 'destinatario_inactivo_o_inexistente',
        }),
        { headers: responseHeaders },
      );
    }

    const { data: existing, error: existingError } = await db
      .from('notificaciones')
      .select('id, enviada_push')
      .eq('tipo', 'tarea_nueva')
      .eq('entidad_id', taskId)
      .eq('usuario_auth_id', recipientAuthId)
      .maybeSingle();

    if (existingError) throw existingError;

    if (existing) {
      return new Response(
        JSON.stringify({
          ok: true,
          procesados: 1,
          duplicado: true,
        }),
        { headers: responseHeaders },
      );
    }

    const title = text(task.titulo) || 'Nueva tarea';
    const priority = text(task.prioridad);
    const dueDate = formatDate(task.fecha_limite);
    const detail = [
      priority ? `Prioridad ${priority}` : '',
      dueDate ? `fecha límite ${dueDate}` : '',
    ].filter(Boolean).join(' · ');

    const notificationTitle = payload.motivo === 'reasignacion'
      ? 'Tarea reasignada'
      : 'Nueva tarea asignada';

    const message =
      `Tienes una nueva tarea: «${title}»` +
      (detail ? ` · ${detail}` : '') +
      '. Revísala y ponte en marcha.';

    const notificationData = {
      tipo: 'tarea_nueva',
      tarea_id: taskId,
      titulo_tarea: title,
      prioridad: priority,
      fecha_limite: text(task.fecha_limite),
      pantalla_destino: 'mis_gestiones',
    };

    const { data: notification, error: insertError } = await db
      .from('notificaciones')
      .insert({
        usuario_auth_id: recipientAuthId,
        tipo: 'tarea_nueva',
        titulo: notificationTitle,
        mensaje: message,
        entidad_tipo: 'gestiones_asignadas',
        entidad_id: taskId,
        datos: notificationData,
        leida: false,
        enviada_push: false,
        pantalla_destino: 'mis_gestiones',
        creado_en: new Date().toISOString(),
      })
      .select('id')
      .single();

    if (insertError) throw insertError;

    let pushSent = false;
    let pushError = '';

    try {
      const pushResponse = await fetch(
        `${supabaseUrl}/functions/v1/enviar-push`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${serviceRoleKey}`,
            apikey: serviceRoleKey,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            auth_id_destino: recipientAuthId,
            incluir_superiores: false,
            titulo: notificationTitle,
            mensaje: message,
            data: notificationData,
          }),
        },
      );

      const pushBody = await pushResponse.json().catch(() => ({}));
      pushSent =
        pushResponse.ok &&
        typeof pushBody === 'object' &&
        pushBody !== null &&
        (pushBody as Record<string, unknown>).ok === true;

      if (!pushSent) pushError = JSON.stringify(pushBody);
    } catch (error) {
      pushError = error instanceof Error
        ? error.message
        : String(error);
    }

    await db
      .from('notificaciones')
      .update({
        enviada_push: pushSent,
        error_push: pushSent ? null : pushError.slice(0, 1000),
      })
      .eq('id', notification.id);

    return new Response(
      JSON.stringify({
        ok: true,
        procesados: 1,
        push: pushSent,
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    console.error('notificar-tarea-nueva', error);

    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error
          ? error.message
          : String(error),
      }),
      { status: 500, headers: responseHeaders },
    );
  }
});