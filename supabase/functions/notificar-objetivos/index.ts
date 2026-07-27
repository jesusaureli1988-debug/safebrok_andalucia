import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface Solicitud {
  auth_id_prueba?: string;
  umbral_prueba?: 50 | 75 | 90 | 100;
}

interface Usuario {
  id: string;
  auth_id: string | null;
  parent_id: string | null;
  rol_usuario: string | null;
  estado?: string | null;
}

interface Venta {
  agente_auth_id?: string | null;
  prima_anual_neta?: number | string | null;
  prima_neta?: number | string | null;
  estado?: string | null;
  estado_poliza?: string | null;
  tipo?: string | null;
  tipo_movimiento?: string | null;
  situacion?: string | null;
}

const zonaHoraria = 'Europe/Madrid';
const umbrales = [50, 75, 90, 100] as const;

function json(
  contenido: Record<string, unknown>,
  estado = 200,
): Response {
  return new Response(JSON.stringify(contenido), {
    status: estado,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function numero(valor: unknown): number {
  if (typeof valor === 'number') return Number.isFinite(valor) ? valor : 0;
  if (valor === null || valor === undefined) return 0;

  const texto = String(valor).trim();
  if (!texto) return 0;

  const normalizado = texto.includes(',')
    ? texto.replaceAll('.', '').replace(',', '.')
    : texto;

  const resultado = Number(normalizado);
  return Number.isFinite(resultado) ? resultado : 0;
}

function euros(valor: number): string {
  return new Intl.NumberFormat('es-ES', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(valor);
}

function rolNormalizado(valor: unknown): string {
  return String(valor ?? '')
    .trim()
    .toLowerCase()
    .replaceAll('-', '_')
    .replaceAll(' ', '_');
}

function objetivoPorRol(rol: string): number | null {
  switch (rolNormalizado(rol)) {
    case 'agente':
      return 1250;
    case 'jefe_equipo':
      return 3125;
    case 'jefe_ventas':
      return 5208;
    case 'director_zona':
      return 10416;
    case 'director_nacional':
    case 'administracion':
      return 25000;
    default:
      return null;
  }
}

function ventaProductiva(venta: Venta): boolean {
  const texto = [
    venta.estado,
    venta.estado_poliza,
    venta.tipo,
    venta.tipo_movimiento,
    venta.situacion,
  ].map((valor) => String(valor ?? '').toLowerCase()).join(' ');

  return ![
    'baja',
    'extorno',
    'anulada',
    'anulado',
    'anulacion',
    'anulación',
    'cancelada',
    'cancelado',
  ].some((estado) => texto.includes(estado));
}

function partesFechaEnZona(fecha: Date): {
  year: number;
  month: number;
  day: number;
  weekday: string;
} {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: zonaHoraria,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  }).formatToParts(fecha);

  const valor = (tipo: string) =>
    partes.find((parte) => parte.type === tipo)?.value ?? '';

  return {
    year: Number(valor('year')),
    month: Number(valor('month')),
    day: Number(valor('day')),
    weekday: valor('weekday'),
  };
}

function fechaLocalAUtc(
  year: number,
  month: number,
  day: number,
): Date {
  const estimacion = Date.UTC(year, month - 1, day, 0, 0, 0);
  let resultado = estimacion;

  // Dos iteraciones resuelven correctamente el offset CET/CEST.
  for (let intento = 0; intento < 2; intento++) {
    const partes = new Intl.DateTimeFormat('en-CA', {
      timeZone: zonaHoraria,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(new Date(resultado));

    const valor = (tipo: string) =>
      Number(partes.find((parte) => parte.type === tipo)?.value ?? 0);

    const representacionUtc = Date.UTC(
      valor('year'),
      valor('month') - 1,
      valor('day'),
      valor('hour'),
      valor('minute'),
      valor('second'),
    );
    resultado += estimacion - representacionUtc;
  }

  return new Date(resultado);
}

function limitesSemana(): {
  inicio: Date;
  fin: Date;
  clave: string;
} {
  const ahora = new Date();
  const local = partesFechaEnZona(ahora);
  const indiceDia: Record<string, number> = {
    Mon: 0,
    Tue: 1,
    Wed: 2,
    Thu: 3,
    Fri: 4,
    Sat: 5,
    Sun: 6,
  };
  const retroceso = indiceDia[local.weekday] ?? 0;

  const fechaBase = new Date(Date.UTC(local.year, local.month - 1, local.day));
  fechaBase.setUTCDate(fechaBase.getUTCDate() - retroceso);

  const year = fechaBase.getUTCFullYear();
  const month = fechaBase.getUTCMonth() + 1;
  const day = fechaBase.getUTCDate();
  const inicio = fechaLocalAUtc(year, month, day);

  const siguiente = new Date(Date.UTC(year, month - 1, day + 7));
  const fin = fechaLocalAUtc(
    siguiente.getUTCFullYear(),
    siguiente.getUTCMonth() + 1,
    siguiente.getUTCDate(),
  );

  const clave = [
    year.toString().padStart(4, '0'),
    month.toString().padStart(2, '0'),
    day.toString().padStart(2, '0'),
  ].join('-');

  return { inicio, fin, clave };
}

function umbralActual(porcentaje: number): 50 | 75 | 90 | 100 | null {
  if (porcentaje >= 100) return 100;
  if (porcentaje >= 90) return 90;
  if (porcentaje >= 75) return 75;
  if (porcentaje >= 50) return 50;
  return null;
}

function contenido(
  umbral: 50 | 75 | 90 | 100,
  produccion: number,
  objetivo: number,
): { titulo: string; mensaje: string } {
  const restante = Math.max(0, objetivo - produccion);

  if (umbral === 100) {
    return {
      titulo: '¡Objetivo semanal conseguido!',
      mensaje:
        `Has alcanzado ${euros(produccion)} de producción. ` +
        `Gran trabajo: el objetivo de ${euros(objetivo)} ya está cumplido.`,
    };
  }

  if (umbral === 90) {
    return {
      titulo: 'Último impulso',
      mensaje:
        `Ya has alcanzado el 90 % de tu objetivo semanal. ` +
        `Solo faltan ${euros(restante)}. ¡Estás muy cerca!`,
    };
  }

  if (umbral === 75) {
    return {
      titulo: 'Objetivo a la vista',
      mensaje:
        `Has completado el 75 % de tu objetivo semanal. ` +
        `Mantén el ritmo: faltan ${euros(restante)}.`,
    };
  }

  return {
    titulo: 'Vas por buen camino',
    mensaje:
      `Ya has superado el 50 % de tu objetivo semanal. ` +
      `Llevas ${euros(produccion)} de ${euros(objetivo)}.`,
  };
}

async function enviarPush({
  supabaseUrl,
  serviceRoleKey,
  authId,
  titulo,
  mensaje,
  data,
}: {
  supabaseUrl: string;
  serviceRoleKey: string;
  authId: string;
  titulo: string;
  mensaje: string;
  data: Record<string, unknown>;
}): Promise<{ ok: boolean; status: number; respuesta: unknown }> {
  const respuesta = await fetch(
    `${supabaseUrl}/functions/v1/enviar-push`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        auth_id_destino: authId,
        incluir_superiores: false,
        titulo,
        mensaje,
        data,
      }),
    },
  );

  let cuerpo: unknown;
  try {
    cuerpo = await respuesta.json();
  } catch {
    cuerpo = await respuesta.text();
  }

  return {
    ok: respuesta.ok &&
      typeof cuerpo === 'object' &&
      cuerpo !== null &&
      (cuerpo as Record<string, unknown>).ok === true,
    status: respuesta.status,
    respuesta: cuerpo,
  };
}

async function cargarVentasSemana(
  supabase: ReturnType<typeof createClient>,
  inicio: Date,
  fin: Date,
): Promise<Venta[]> {
  const resultado: Venta[] = [];
  const tamanoPagina = 1000;

  for (let desde = 0; ; desde += tamanoPagina) {
    const { data, error } = await supabase
      .from('ventas')
      .select('*')
      .gte('created_at', inicio.toISOString())
      .lt('created_at', fin.toISOString())
      .order('created_at', { ascending: true })
      .range(desde, desde + tamanoPagina - 1);

    if (error) {
      throw new Error(`No se pudieron consultar las ventas: ${error.message}`);
    }

    const pagina = (data ?? []) as Venta[];
    resultado.push(...pagina);
    if (pagina.length < tamanoPagina) break;
  }

  return resultado;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ ok: false, error: 'Método no permitido.' }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('CRON_SECRET');
    const recibido = req.headers.get('x-cron-secret');

    if (!supabaseUrl || !serviceRoleKey || !cronSecret) {
      return json({
        ok: false,
        error: 'Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o CRON_SECRET.',
      }, 500);
    }

    if (!recibido || recibido !== cronSecret) {
      return json({ ok: false, error: 'No autorizado.' }, 401);
    }

    let solicitud: Solicitud = {};
    try {
      solicitud = await req.json();
    } catch {
      solicitud = {};
    }

    // Prueba aislada: envía el texto solicitado y no registra ningún hito.
    if (solicitud.auth_id_prueba && solicitud.umbral_prueba) {
      const objetivoPrueba = 1250;
      const produccionPrueba =
        objetivoPrueba * (solicitud.umbral_prueba / 100);
      const texto = contenido(
        solicitud.umbral_prueba,
        produccionPrueba,
        objetivoPrueba,
      );
      const push = await enviarPush({
        supabaseUrl,
        serviceRoleKey,
        authId: solicitud.auth_id_prueba,
        titulo: `[PRUEBA] ${texto.titulo}`,
        mensaje: texto.mensaje,
        data: {
          tipo: 'objetivo_semanal_prueba',
          umbral: solicitud.umbral_prueba,
        },
      });

      return json({
        ok: push.ok,
        prueba: true,
        auth_id_prueba: solicitud.auth_id_prueba,
        umbral_prueba: solicitud.umbral_prueba,
        push,
      }, push.ok ? 200 : push.status);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const { data: usuariosData, error: errorUsuarios } = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario, estado');

    if (errorUsuarios) {
      throw new Error(`No se pudieron consultar usuarios: ${errorUsuarios.message}`);
    }

    const usuarios = (usuariosData ?? []) as Usuario[];
    const usuariosValidos = usuarios.filter((usuario) => {
      if (!usuario.id || !usuario.auth_id) return false;
      if (objetivoPorRol(usuario.rol_usuario ?? '') === null) return false;
      const estado = String(usuario.estado ?? 'activo').trim().toLowerCase();
      return !['inactivo', 'baja', 'bloqueado', 'eliminado'].includes(estado);
    });

    const hijosPorParentId = new Map<string, Usuario[]>();
    for (const usuario of usuariosValidos) {
      if (!usuario.parent_id) continue;
      const lista = hijosPorParentId.get(String(usuario.parent_id)) ?? [];
      lista.push(usuario);
      hijosPorParentId.set(String(usuario.parent_id), lista);
    }

    const estructuraAuthIds = (usuarioInicial: Usuario): Set<string> => {
      const authIds = new Set<string>();
      const idsVisitados = new Set<string>();
      const pendientes: Usuario[] = [usuarioInicial];

      while (pendientes.length > 0) {
        const usuario = pendientes.pop()!;
        const id = String(usuario.id);
        if (idsVisitados.has(id)) continue;
        idsVisitados.add(id);

        if (usuario.auth_id) authIds.add(String(usuario.auth_id));
        pendientes.push(...(hijosPorParentId.get(id) ?? []));
      }

      return authIds;
    };

    const semana = limitesSemana();
    const ventas = (await cargarVentasSemana(
      supabase,
      semana.inicio,
      semana.fin,
    )).filter(ventaProductiva);

    const produccionPorAuthId = new Map<string, number>();
    for (const venta of ventas) {
      const authId = String(venta.agente_auth_id ?? '').trim();
      if (!authId) continue;
      const prima = numero(venta.prima_anual_neta ?? venta.prima_neta);
      produccionPorAuthId.set(
        authId,
        (produccionPorAuthId.get(authId) ?? 0) + prima,
      );
    }

    const { data: hitosData, error: errorHitos } = await supabase
      .from('notificaciones_objetivos_enviadas')
      .select('auth_id, umbral')
      .eq('semana_inicio', semana.clave);

    if (errorHitos) {
      throw new Error(
        `No se pudo consultar el control de objetivos: ${errorHitos.message}`,
      );
    }

    const hitosPorUsuario = new Map<string, Set<number>>();
    for (const fila of hitosData ?? []) {
      const authId = String(fila.auth_id ?? '');
      const lista = hitosPorUsuario.get(authId) ?? new Set<number>();
      lista.add(Number(fila.umbral));
      hitosPorUsuario.set(authId, lista);
    }

    let enviados = 0;
    let sinDispositivo = 0;
    let yaEnviados = 0;
    let sinHito = 0;
    let errores = 0;
    const detalles: Record<string, unknown>[] = [];

    for (const usuario of usuariosValidos) {
      const authId = String(usuario.auth_id);
      const objetivo = objetivoPorRol(usuario.rol_usuario ?? '');
      if (!objetivo) continue;

      const miembros = estructuraAuthIds(usuario);
      let produccion = 0;
      for (const miembroAuthId of miembros) {
        produccion += produccionPorAuthId.get(miembroAuthId) ?? 0;
      }

      const porcentaje = (produccion / objetivo) * 100;
      const umbral = umbralActual(porcentaje);

      if (umbral === null) {
        sinHito++;
        continue;
      }

      const hitosUsuario = hitosPorUsuario.get(authId) ?? new Set<number>();
      if (hitosUsuario.has(umbral)) {
        yaEnviados++;
        continue;
      }

      // Reserva atómica del hito para evitar dos envíos simultáneos.
      const { error: errorReserva } = await supabase
        .from('notificaciones_objetivos_enviadas')
        .insert({
          auth_id: authId,
          semana_inicio: semana.clave,
          umbral,
          estado: 'pendiente',
        });

      if (errorReserva) {
        if (errorReserva.code === '23505') {
          yaEnviados++;
          continue;
        }
        errores++;
        detalles.push({
          auth_id: authId,
          error: `No se pudo reservar el hito: ${errorReserva.message}`,
        });
        continue;
      }

      const texto = contenido(umbral, produccion, objetivo);
      const push = await enviarPush({
        supabaseUrl,
        serviceRoleKey,
        authId,
        titulo: texto.titulo,
        mensaje: texto.mensaje,
        data: {
          tipo: 'objetivo_semanal',
          umbral,
          porcentaje_real: porcentaje.toFixed(2),
          produccion,
          objetivo,
          restante: Math.max(0, objetivo - produccion),
          semana_inicio: semana.clave,
        },
      });

      if (!push.ok) {
        await supabase
          .from('notificaciones_objetivos_enviadas')
          .delete()
          .eq('auth_id', authId)
          .eq('semana_inicio', semana.clave)
          .eq('umbral', umbral);

        if (push.status === 404) {
          sinDispositivo++;
        } else {
          errores++;
        }
        detalles.push({
          auth_id: authId,
          umbral,
          push,
        });
        continue;
      }

      enviados++;

      await supabase
        .from('notificaciones_objetivos_enviadas')
        .update({
          estado: 'enviada',
          enviado_en: new Date().toISOString(),
        })
        .eq('auth_id', authId)
        .eq('semana_inicio', semana.clave)
        .eq('umbral', umbral);

      // Marca los hitos inferiores para que un salto grande produzca un solo push.
      const inferiores = umbrales.filter(
        (valor) => valor < umbral && !hitosUsuario.has(valor),
      );

      if (inferiores.length > 0) {
        await supabase
          .from('notificaciones_objetivos_enviadas')
          .upsert(
            inferiores.map((valor) => ({
              auth_id: authId,
              semana_inicio: semana.clave,
              umbral: valor,
              estado: 'superada',
              enviado_en: new Date().toISOString(),
            })),
            { onConflict: 'auth_id,semana_inicio,umbral' },
          );
      }
    }

    return json({
      ok: errores === 0,
      automatico: true,
      zona_horaria: zonaHoraria,
      semana_inicio: semana.clave,
      periodo_utc: {
        desde: semana.inicio.toISOString(),
        hasta_exclusivo: semana.fin.toISOString(),
      },
      usuarios_evaluados: usuariosValidos.length,
      ventas_productivas: ventas.length,
      enviados,
      sin_dispositivo: sinDispositivo,
      ya_enviados: yaEnviados,
      sin_hito: sinHito,
      errores,
      detalles: detalles.slice(0, 20),
    }, errores === 0 ? 200 : 207);
  } catch (error) {
    console.error('ERROR NOTIFICAR OBJETIVOS:', error);
    return json({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
