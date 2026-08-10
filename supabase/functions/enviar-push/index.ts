import { createClient } from 'npm:@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'npm:jose@5';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface SolicitudPush {
  auth_id_destino?: string;
  incluir_superiores?: boolean;
  token?: string;
  titulo: string;
  mensaje: string;
  data?: Record<string, unknown>;
}

interface ResultadoEnvio {
  token: string;
  correcto: boolean;
  respuesta?: unknown;
  error?: unknown;
}

interface UsuarioJerarquia {
  id: string;
  auth_id: string | null;
  parent_id: string | null;
}

function respuestaJson(
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

function convertirDataAString(
  data?: Record<string, unknown>,
): Record<string, string> {
  const resultado: Record<string, string> = {};

  if (!data) {
    return resultado;
  }

  for (const [clave, valor] of Object.entries(data)) {
    if (valor === null || valor === undefined) {
      continue;
    }

    if (typeof valor === 'string') {
      resultado[clave] = valor;
    } else if (
      typeof valor === 'number' ||
      typeof valor === 'boolean'
    ) {
      resultado[clave] = String(valor);
    } else {
      resultado[clave] = JSON.stringify(valor);
    }
  }

  return resultado;
}

async function obtenerDestinatariosJerarquia(
  supabase: ReturnType<typeof createClient>,
  authIdInicial: string,
): Promise<string[]> {
  const destinatarios = new Set<string>([authIdInicial]);
  const usuariosVisitados = new Set<string>();

  const { data: usuarioInicial, error: errorUsuarioInicial } =
    await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id')
      .eq('auth_id', authIdInicial)
      .maybeSingle();

  if (errorUsuarioInicial) {
    throw new Error(
      `No se pudo consultar al agente: ${errorUsuarioInicial.message}`,
    );
  }

  if (!usuarioInicial) {
    // El agente sigue recibiendo la notificaci�n aunque su fila de
    // jerarqu�a todav�a no exista; simplemente no hay superiores que recorrer.
    return [...destinatarios];
  }

  const agente = usuarioInicial as UsuarioJerarquia;
  usuariosVisitados.add(String(agente.id));

  if (agente.auth_id) {
    destinatarios.add(String(agente.auth_id));
  }

  let parentId = agente.parent_id
    ? String(agente.parent_id)
    : null;

  // L�mite defensivo adicional ante una jerarqu�a corrupta.
  const maximoNiveles = 100;
  let nivel = 0;

  while (parentId && nivel < maximoNiveles) {
    if (usuariosVisitados.has(parentId)) {
      console.warn(
        'Ciclo detectado en usuarios.parent_id. Usuario:',
        parentId,
      );
      break;
    }

    usuariosVisitados.add(parentId);

    const { data: superior, error: errorSuperior } = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id')
      .eq('id', parentId)
      .maybeSingle();

    if (errorSuperior) {
      throw new Error(
        `No se pudo consultar al superior ${parentId}: ` +
          errorSuperior.message,
      );
    }

    if (!superior) {
      console.warn(
        'Superior no encontrado en usuarios. ID:',
        parentId,
      );
      break;
    }

    const filaSuperior = superior as UsuarioJerarquia;

    if (filaSuperior.auth_id) {
      destinatarios.add(String(filaSuperior.auth_id));
    }

    parentId = filaSuperior.parent_id
      ? String(filaSuperior.parent_id)
      : null;
    nivel += 1;
  }

  if (nivel >= maximoNiveles) {
    console.warn(
      `Recorrido de superiores detenido al alcanzar ${maximoNiveles} niveles.`,
    );
  }

  return [...destinatarios];
}

function normalizarClavePrivada(valor: string): string {
  let clave = valor.trim();

  /*
   * Elimina comillas exteriores que puedan haberse guardado
   * accidentalmente dentro del secreto.
   */
  if (
    (clave.startsWith('"') && clave.endsWith('"')) ||
    (clave.startsWith("'") && clave.endsWith("'"))
  ) {
    clave = clave.substring(1, clave.length - 1);
  }

  /*
   * Convierte:
   *
   * \\n  -> salto de l�nea
   * \n   -> salto de l�nea
   *
   * Esto permite aceptar claves guardadas con uno o dos
   * niveles de escape.
   */
  clave = clave
    .replace(/\\\\n/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\r/g, '')
    .trim();

  /*
   * Si por error se guard� el valor completo de JSON:
   *
   * "private_key":"-----BEGIN..."
   *
   * intentamos extraer �nicamente la clave.
   */
  const inicio = clave.indexOf('-----BEGIN PRIVATE KEY-----');
  const final = clave.indexOf('-----END PRIVATE KEY-----');

  if (inicio >= 0 && final >= 0) {
    clave = clave.substring(
      inicio,
      final + '-----END PRIVATE KEY-----'.length,
    );
  }

  /*
   * Normalizamos el cuerpo Base64 de la clave.
   */
  const cuerpo = clave
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  if (!cuerpo) {
    throw new Error(
      'FIREBASE_PRIVATE_KEY est� vac�a o no contiene una clave v�lida.',
    );
  }

  /*
   * Una clave Base64 solo puede incluir estos caracteres.
   * No mostramos nunca el contenido real de la clave.
   */
  if (!/^[A-Za-z0-9+/=]+$/.test(cuerpo)) {
    throw new Error(
      'FIREBASE_PRIVATE_KEY contiene caracteres inv�lidos. Revisa el formato del secreto.',
    );
  }

  /*
   * Reconstruimos siempre un PEM limpio y v�lido.
   */
  const lineas = cuerpo.match(/.{1,64}/g);

  if (!lineas || lineas.length === 0) {
    throw new Error(
      'No se pudo reconstruir la clave privada de Firebase.',
    );
  }

  return [
    '-----BEGIN PRIVATE KEY-----',
    ...lineas,
    '-----END PRIVATE KEY-----',
  ].join('\n');
}

async function obtenerAccessToken(): Promise<string> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
  const privateKeyOriginal = Deno.env.get('FIREBASE_PRIVATE_KEY');

  if (!projectId || !clientEmail || !privateKeyOriginal) {
    throw new Error(
      'Faltan FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL o FIREBASE_PRIVATE_KEY.',
    );
  }

  const privateKey = normalizarClavePrivada(
    privateKeyOriginal,
  );

  console.log('FIREBASE_PROJECT_ID configurado:', Boolean(projectId));
  console.log(
    'FIREBASE_CLIENT_EMAIL configurado:',
    Boolean(clientEmail),
  );
  console.log(
    'FIREBASE_PRIVATE_KEY encontrada:',
    Boolean(privateKeyOriginal),
  );
  console.log(
    'FIREBASE_PRIVATE_KEY comienza correctamente:',
    privateKey.startsWith('-----BEGIN PRIVATE KEY-----'),
  );
  console.log(
    'FIREBASE_PRIVATE_KEY termina correctamente:',
    privateKey.endsWith('-----END PRIVATE KEY-----'),
  );

  let clave: CryptoKey;

  try {
    clave = await importPKCS8(privateKey, 'RS256');
  } catch (error) {
    console.error(
      'ERROR IMPORTANDO FIREBASE_PRIVATE_KEY:',
      error instanceof Error ? error.message : String(error),
    );

    throw new Error(
      'No se pudo importar FIREBASE_PRIVATE_KEY. La clave privada no tiene un formato PKCS8 v�lido.',
    );
  }

  const ahora = Math.floor(Date.now() / 1000);

  const jwt = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({
      alg: 'RS256',
      typ: 'JWT',
    })
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

  let contenido: Record<string, unknown>;

  try {
    contenido = await respuesta.json();
  } catch {
    throw new Error(
      `Google OAuth respondi� con un contenido inv�lido. HTTP ${respuesta.status}.`,
    );
  }

  if (!respuesta.ok || !contenido.access_token) {
    console.error('ERROR OAUTH FIREBASE:', contenido);

    const descripcion =
      typeof contenido.error_description === 'string'
        ? contenido.error_description
        : null;

    const errorOAuth =
      typeof contenido.error === 'string'
        ? contenido.error
        : null;

    throw new Error(
      descripcion ??
        errorOAuth ??
        'No se pudo obtener el access token de Firebase.',
    );
  }

  return contenido.access_token as string;
}

async function enviarAToken({
  token,
  titulo,
  mensaje,
  data,
  accessToken,
  projectId,
}: {
  token: string;
  titulo: string;
  mensaje: string;
  data: Record<string, string>;
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
            data,
            android: {
  priority: 'high',
  notification: {
    sound: 'default',
    channel_id: 'safebrok_general',
  },
},
apns: {
  headers: {
    'apns-priority': '10',
    'apns-push-type': 'alert',
  },
  payload: {
    aps: {
      sound: 'default',
      badge: 1,
      'content-available': 1,
    },
  },
},
          },
        }),
      },
    );

    let contenido: unknown;

    try {
      contenido = await respuesta.json();
    } catch {
      contenido = {
        error: 'Firebase devolvi� una respuesta no JSON.',
        status: respuesta.status,
      };
    }

    if (!respuesta.ok) {
      console.error('ERROR FCM:', contenido);

      return {
        token,
        correcto: false,
        error: contenido,
      };
    }

    return {
      token,
      correcto: true,
      respuesta: contenido,
    };
  } catch (error) {
    console.error('EXCEPCI�N ENVIANDO PUSH:', error);

    return {
      token,
      correcto: false,
      error: error instanceof Error
        ? error.message
        : String(error),
    };
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders,
    });
  }

  if (req.method !== 'POST') {
    return respuestaJson(
      {
        ok: false,
        error: 'M�todo no permitido. Utiliza POST.',
      },
      405,
    );
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get(
      'SUPABASE_SERVICE_ROLE_KEY',
    );
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID');

    if (!supabaseUrl || !serviceRoleKey) {
      return respuestaJson(
        {
          ok: false,
          error:
            'Faltan las credenciales internas de Supabase.',
        },
        500,
      );
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {global: {headers: {Authorization: authHeader}}},
    );
    const {data: {user}, error: authError} = await userClient.auth.getUser();
    if (authError || !user) {
      return respuestaJson({ok: false, error: 'No autorizado.'}, 401);
    }

    if (!projectId) {
      return respuestaJson(
        {
          ok: false,
          error: 'Falta el secreto FIREBASE_PROJECT_ID.',
        },
        500,
      );
    }

    let solicitud: SolicitudPush;

    try {
      solicitud = await req.json();
    } catch {
      return respuestaJson(
        {
          ok: false,
          error:
            'El cuerpo de la petici�n no contiene un JSON v�lido.',
        },
        400,
      );
    }

    const authIdDestino =
      solicitud.auth_id_destino?.trim();

    if (!authIdDestino) {
      return respuestaJson({ok: false, error: 'Falta el destinatario.'}, 400);
    }
    const {data: canAccess, error: accessError} = await userClient.rpc(
      'app_can_access_auth_id',
      {target_auth_id: authIdDestino},
    );
    if (accessError || canAccess !== true) {
      return respuestaJson({ok: false, error: 'Sin permisos para el destinatario.'}, 403);
    }

    const incluirSuperiores =
      solicitud.incluir_superiores === true;

    const tokenDirecto =
      solicitud.token?.trim();

    const titulo =
      solicitud.titulo?.trim();

    const mensaje =
      solicitud.mensaje?.trim();

    if (!titulo) {
      return respuestaJson(
        {
          ok: false,
          error: 'El campo titulo es obligatorio.',
        },
        400,
      );
    }

    if (!mensaje) {
      return respuestaJson(
        {
          ok: false,
          error: 'El campo mensaje es obligatorio.',
        },
        400,
      );
    }

    if (!authIdDestino && !tokenDirecto) {
      return respuestaJson(
        {
          ok: false,
          error:
            'Debes enviar auth_id_destino o un token de dispositivo.',
        },
        400,
      );
    }

    const supabase = createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    let tokens: string[] = [];
    let authIdsDestinatarios: string[] = [];

    if (tokenDirecto) {
      tokens = [tokenDirecto];
    } else {
      authIdsDestinatarios = incluirSuperiores
        ? await obtenerDestinatariosJerarquia(
            supabase,
            authIdDestino!,
          )
        : [authIdDestino!];

      const {
        data: dispositivos,
        error: errorDispositivos,
      } = await supabase
        .from('dispositivos_push')
        .select('token')
        .in('usuario_auth_id', authIdsDestinatarios)
        .eq('activo', true);

      if (errorDispositivos) {
        console.error(
          'ERROR CONSULTANDO DISPOSITIVOS PUSH:',
          errorDispositivos,
        );

        return respuestaJson(
          {
            ok: false,
            error:
              'No se pudieron consultar los dispositivos.',
            detalle: errorDispositivos.message,
          },
          500,
        );
      }

      tokens = [
        ...new Set(
          (dispositivos ?? [])
            .map((fila) =>
              String(fila.token ?? '').trim()
            )
            .filter((token) => token.length > 0),
        ),
      ];
    }

    if (tokens.length === 0) {
      return respuestaJson(
        {
          ok: false,
          error:
            'Los destinatarios no tienen dispositivos push activos.',
          auth_id_destino: authIdDestino,
          destinatarios: authIdsDestinatarios.length,
        },
        404,
      );
    }

    const accessToken = await obtenerAccessToken();

    const dataString = convertirDataAString(
      solicitud.data,
    );

    const resultados = await Promise.all(
      tokens.map((token) =>
        enviarAToken({
          token,
          titulo,
          mensaje,
          data: dataString,
          accessToken,
          projectId,
        })
      ),
    );

    const enviados = resultados.filter(
      (resultado) => resultado.correcto,
    ).length;

    const fallidos = resultados.length - enviados;

    return respuestaJson(
      {
        ok: enviados > 0,
        total_destinatarios: tokenDirecto
          ? 1
          : authIdsDestinatarios.length,
        total_dispositivos: resultados.length,
        enviados,
        fallidos,
        resultados,
      },
      enviados > 0 ? 200 : 502,
    );
  } catch (error) {
    console.error(
      'ERROR GENERAL ENVIAR PUSH:',
      error,
    );

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
