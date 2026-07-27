import { createClient } from 'npm:@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'npm:jose@5';

interface ResultadoEnvio {
  correcto: boolean;
  error?: unknown;
}

interface MensajeCierre {
  titulo: string;
  mensaje: string;
}

const DIAS_DE_AVISO = new Set([10, 5, 3, 2, 1]);
const ZONA_HORARIA = 'Europe/Madrid';
const HORA_ENVIO = 9;

function respuestaJson(
  contenido: Record<string, unknown>,
  estado = 200,
): Response {
  return new Response(JSON.stringify(contenido), {
    status: estado,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function comparacionSegura(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const bytesA = encoder.encode(a);
  const bytesB = encoder.encode(b);

  if (bytesA.length !== bytesB.length) return false;

  let diferencia = 0;

  for (let i = 0; i < bytesA.length; i += 1) {
    diferencia |= bytesA[i] ^ bytesB[i];
  }

  return diferencia === 0;
}

function fechaEnMadrid(): {
  year: number;
  month: number;
  day: number;
  hour: number;
} {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: ZONA_HORARIA,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date());

  const valor = (tipo: Intl.DateTimeFormatPartTypes): number => {
    const parte = partes.find((elemento) => elemento.type === tipo);
    return Number(parte?.value ?? 0);
  };

  return {
    year: valor('year'),
    month: valor('month'),
    day: valor('day'),
    hour: valor('hour'),
  };
}

function calcularCierre(
  year: number,
  month: number,
  day: number,
): {
  cierreYear: number;
  cierreMonth: number;
  diasRestantes: number;
  fechaCierre: string;
} {
  let cierreYear = year;
  let cierreMonth = month;

  // Replica la regla del Home: desde el día 24 se muestra el cierre
  // del mes siguiente.
  if (day >= 24) {
    cierreMonth += 1;

    if (cierreMonth === 13) {
      cierreMonth = 1;
      cierreYear += 1;
    }
  }

  const hoyUtc = Date.UTC(year, month - 1, day);
  const cierreUtc = Date.UTC(cierreYear, cierreMonth - 1, 24);
  const diasRestantes = Math.round(
    (cierreUtc - hoyUtc) / 86_400_000,
  );

  const fechaCierre =
    `${cierreYear.toString().padStart(4, '0')}-` +
    `${cierreMonth.toString().padStart(2, '0')}-24`;

  return {
    cierreYear,
    cierreMonth,
    diasRestantes,
    fechaCierre,
  };
}

function obtenerMensaje(dias: number): MensajeCierre {
  switch (dias) {
    case 10:
      return {
        titulo: '¡Comienza la recta final!',
        mensaje:
          'Quedan 10 días para el cierre de producción. ' +
          'Es el momento de acelerar.',
      };
    case 5:
      return {
        titulo: '¡Semana decisiva!',
        mensaje:
          'Quedan 5 días para cerrar producción. ' +
          'Vamos a por el objetivo.',
      };
    case 3:
      return {
        titulo: '¡Último impulso!',
        mensaje:
          'Solo quedan 3 días para el cierre de producción. ' +
          'Cada venta cuenta.',
      };
    case 2:
      return {
        titulo: '¡Estamos muy cerca!',
        mensaje:
          'Quedan 2 días para el cierre. ' +
          'Es el momento de darlo todo.',
      };
    case 1:
      return {
        titulo: '¡Mañana cerramos producción!',
        mensaje:
          'Última oportunidad para superar tus objetivos. ' +
          '¡A por todas!',
      };
    default:
      throw new Error(`No existe mensaje para ${dias} días.`);
  }
}

function normalizarClavePrivada(valor: string): string {
  let clave = valor.trim();

  if (
    (clave.startsWith('"') && clave.endsWith('"')) ||
    (clave.startsWith("'") && clave.endsWith("'"))
  ) {
    clave = clave.substring(1, clave.length - 1);
  }

  clave = clave
    .replace(/\\\\n/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\r/g, '')
    .trim();

  const inicio = clave.indexOf('-----BEGIN PRIVATE KEY-----');
  const final = clave.indexOf('-----END PRIVATE KEY-----');

  if (inicio >= 0 && final >= 0) {
    clave = clave.substring(
      inicio,
      final + '-----END PRIVATE KEY-----'.length,
    );
  }

  const cuerpo = clave
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  if (!cuerpo || !/^[A-Za-z0-9+/=]+$/.test(cuerpo)) {
    throw new Error('FIREBASE_PRIVATE_KEY no tiene un formato válido.');
  }

  const lineas = cuerpo.match(/.{1,64}/g);

  if (!lineas) {
    throw new Error('No se pudo reconstruir FIREBASE_PRIVATE_KEY.');
  }

  return [
    '-----BEGIN PRIVATE KEY-----',
    ...lineas,
    '-----END PRIVATE KEY-----',
  ].join('\n');
}

async function obtenerAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
  const privateKeyOriginal = Deno.env.get('FIREBASE_PRIVATE_KEY');

  if (!clientEmail || !privateKeyOriginal) {
    throw new Error(
      'Faltan FIREBASE_CLIENT_EMAIL o FIREBASE_PRIVATE_KEY.',
    );
  }

  const clave = await importPKCS8(
    normalizarClavePrivada(privateKeyOriginal),
    'RS256',
  );

  const ahora = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(ahora)
    .setExpirationTime(ahora + 3600)
    .sign(clave);

  const respuesta = await fetch(
    'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type:
          'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    },
  );

  const contenido = await respuesta.json();

  if (!respuesta.ok || !contenido.access_token) {
    throw new Error(
      contenido.error_description ??
        contenido.error ??
        'No se pudo obtener el access token de Firebase.',
    );
  }

  return contenido.access_token;
}

async function enviarAToken({
  token,
  titulo,
  mensaje,
  dias,
  fechaCierre,
  accessToken,
  projectId,
}: {
  token: string;
  titulo: string;
  mensaje: string;
  dias: number;
  fechaCierre: string;
  accessToken: string;
  projectId: string;
}): Promise<ResultadoEnvio> {
  try {
    const respuesta = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: titulo,
              body: mensaje,
            },
            data: {
              tipo: 'cierre_produccion',
              dias_restantes: String(dias),
              fecha_cierre: fechaCierre,
            },
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channel_id: 'safebrok_general',
              },
            },
          },
        }),
      },
    );

    if (respuesta.ok) {
      return { correcto: true };
    }

    return {
      correcto: false,
      error: await respuesta.text(),
    };
  } catch (error) {
    return {
      correcto: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return respuestaJson(
      { ok: false, error: 'Método no permitido.' },
      405,
    );
  }

  try {
    const cronSecret = Deno.env.get('CRON_SECRET');
    const secretoRecibido = req.headers.get('x-cron-secret') ?? '';

    if (
      !cronSecret ||
      !comparacionSegura(cronSecret, secretoRecibido)
    ) {
      return respuestaJson(
        { ok: false, error: 'No autorizado.' },
        401,
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');

    if (!supabaseUrl || !serviceRoleKey || !projectId) {
      throw new Error(
        'Faltan credenciales internas de Supabase o Firebase.',
      );
    }

    let diasPrueba: number | null = null;
    let authIdPrueba: string | null = null;

    try {
      const body = await req.json();
      const candidato = Number(body?.dias_prueba);

      if (DIAS_DE_AVISO.has(candidato)) {
        diasPrueba = candidato;
      }

      if (
        diasPrueba !== null &&
        typeof body?.auth_id_prueba === 'string' &&
        body.auth_id_prueba.trim()
      ) {
        authIdPrueba = body.auth_id_prueba.trim();
      }
    } catch {
      // El cron puede invocar la función con un objeto vacío.
    }

    const hoy = fechaEnMadrid();

    if (diasPrueba === null && hoy.hour !== HORA_ENVIO) {
      return respuestaJson({
        ok: true,
        enviado: false,
        motivo: `Fuera de la hora de envío (${HORA_ENVIO}:00).`,
        hora_madrid: hoy.hour,
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const fechaHoy =
      `${hoy.year.toString().padStart(4, '0')}-` +
      `${hoy.month.toString().padStart(2, '0')}-` +
      `${hoy.day.toString().padStart(2, '0')}`;

    const { data: cierreConfigurado, error: errorCierre } = await supabase
      .from('cierres_produccion')
      .select('id, anio, mes, fecha_desde, fecha_hasta, estado')
      .lte('fecha_desde', fechaHoy)
      .gte('fecha_hasta', fechaHoy)
      .limit(1)
      .maybeSingle();

    if (errorCierre) {
      throw new Error(
        `No se pudo consultar el cierre de producción: ${errorCierre.message}`,
      );
    }

    if (!cierreConfigurado) {
      return respuestaJson({
        ok: true,
        enviado: false,
        motivo: 'No existe un cierre de producción configurado para hoy.',
        fecha_actual: fechaHoy,
      });
    }

    const fechaCierre = String(cierreConfigurado.fecha_hasta);
    const [cierreYear, cierreMonth, cierreDay] = fechaCierre
      .split('-')
      .map(Number);
    const hoyUtc = Date.UTC(hoy.year, hoy.month - 1, hoy.day);
    const cierreUtc = Date.UTC(cierreYear, cierreMonth - 1, cierreDay);
    const cierre = {
      fechaCierre,
      diasRestantes: Math.round((cierreUtc - hoyUtc) / 86_400_000),
    };
    const dias = diasPrueba ?? cierre.diasRestantes;

    if (!DIAS_DE_AVISO.has(dias)) {
      return respuestaJson({
        ok: true,
        enviado: false,
        motivo: 'Hoy no corresponde enviar un aviso.',
        dias_restantes: dias,
        fecha_cierre: cierre.fechaCierre,
      });
    }

    const esPrueba = diasPrueba !== null;
    const claveAviso =
      `cierre-produccion:${cierre.fechaCierre}:${dias}`;



    if (!esPrueba) {
      const { error: errorReserva } = await supabase
        .from('avisos_push_programados')
        .insert({
          clave: claveAviso,
          tipo: 'cierre_produccion',
          fecha_objetivo: cierre.fechaCierre,
          dias_restantes: dias,
          estado: 'procesando',
        });

      if (errorReserva?.code === '23505') {
        return respuestaJson({
          ok: true,
          enviado: false,
          motivo: 'Este aviso ya fue procesado.',
          clave: claveAviso,
        });
      }

      if (errorReserva) {
        throw new Error(
          `No se pudo reservar el aviso: ${errorReserva.message}`,
        );
      }
    }

    let consultaDispositivos = supabase
      .from('dispositivos_push')
      .select('token')
      .eq('activo', true);

    if (esPrueba && authIdPrueba) {
      consultaDispositivos = consultaDispositivos.eq(
        'usuario_auth_id',
        authIdPrueba,
      );
    }

    const { data: dispositivos, error: errorDispositivos } =
      await consultaDispositivos;

    if (errorDispositivos) {
      throw new Error(
        `No se pudieron consultar los dispositivos: ` +
          errorDispositivos.message,
      );
    }

    const tokens = [
      ...new Set(
        (dispositivos ?? [])
          .map((fila) => String(fila.token ?? '').trim())
          .filter((token) => token.length > 0),
      ),
    ];

    if (tokens.length === 0) {
      throw new Error('No hay dispositivos push activos.');
    }

    const accessToken = await obtenerAccessToken();
    const contenido = obtenerMensaje(dias);
    const resultados: ResultadoEnvio[] = [];
    const tamanoLote = 100;

    for (let inicio = 0; inicio < tokens.length; inicio += tamanoLote) {
      const lote = tokens.slice(inicio, inicio + tamanoLote);

      resultados.push(
        ...(await Promise.all(
          lote.map((token) =>
            enviarAToken({
              token,
              titulo: esPrueba
                ? `[PRUEBA] ${contenido.titulo}`
                : contenido.titulo,
              mensaje: contenido.mensaje,
              dias,
              fechaCierre: cierre.fechaCierre,
              accessToken,
              projectId,
            })
          ),
        )),
      );
    }

    const enviados = resultados.filter(
      (resultado) => resultado.correcto,
    ).length;
    const fallidos = resultados.length - enviados;

    if (!esPrueba) {
      await supabase
        .from('avisos_push_programados')
        .update({
          estado: enviados > 0 ? 'completado' : 'fallido',
          total_dispositivos: resultados.length,
          enviados,
          fallidos,
          procesado_at: new Date().toISOString(),
        })
        .eq('clave', claveAviso);
    }

    return respuestaJson(
      {
        ok: enviados > 0,
        prueba: esPrueba,
        auth_id_prueba: authIdPrueba,
        dias_restantes: dias,
        fecha_cierre: cierre.fechaCierre,
        total_dispositivos: resultados.length,
        enviados,
        fallidos,
      },
      enviados > 0 ? 200 : 502,
    );
  } catch (error) {
    console.error('ERROR AVISO CIERRE PRODUCCIÓN:', error);

    return respuestaJson(
      {
        ok: false,
        error: error instanceof Error
          ? error.message
          : String(error),
      },
      500,
    );
  }
});

