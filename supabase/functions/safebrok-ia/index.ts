import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders() });
    }

    const { pregunta } = await req.json();

    if (!pregunta) {
      return json({ error: "Falta la pregunta" }, 400);
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!openaiKey || !supabaseUrl || !supabaseAnonKey) {
      return json({ error: "Faltan variables de entorno" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return json({ error: "Usuario no autenticado" }, 401);
    }

    const { data: usuarioApp, error: usuarioError } = await supabase
      .from("usuarios")
      .select("id, auth_id, nombre, apellidos, rol_usuario")
      .eq("auth_id", user.id)
      .maybeSingle();

    if (usuarioError) {
      return json({ error: "Error leyendo usuario", detalle: usuarioError }, 500);
    }

    if (!usuarioApp) {
      return json({ error: "Usuario no encontrado en tabla usuarios" }, 404);
    }

    const nombreCompleto =
      `${usuarioApp.nombre ?? ""} ${usuarioApp.apellidos ?? ""}`.trim();

      // ==========================
// MEMORIA DE LA IA
// ==========================

const { data: memorias } = await supabase
  .from("ia_memoria")
  .select("titulo, contenido, tipo, created_at")
  .eq("auth_id", user.id)
  .order("created_at", { ascending: false })
  .limit(15);

const memoriaTexto = (memorias ?? [])
  .map((m: any) => `• ${m.titulo ?? "Memoria"}: ${m.contenido}`)
  .join("\n");

// Si el usuario quiere guardar algo en memoria
const preguntaLowerMemoria = pregunta.toLowerCase();

if (
  preguntaLowerMemoria.includes("recuerda que") ||
  preguntaLowerMemoria.includes("acuérdate de") ||
  preguntaLowerMemoria.includes("acuerdate de") ||
  preguntaLowerMemoria.includes("guarda en memoria")
) {
  await supabase.from("ia_memoria").insert({
    auth_id: user.id,
    titulo: "Preferencia del usuario",
    contenido: pregunta,
    tipo: "preferencia",
  });
}

    const preguntaLower = pregunta.toLowerCase();

    let contextoDatos = "";

    if (
      preguntaLower.includes("venta") ||
      preguntaLower.includes("ventas") ||
      preguntaLower.includes("producción") ||
      preguntaLower.includes("produccion") ||
      preguntaLower.includes("póliza") ||
      preguntaLower.includes("poliza")
    ) {
      const resumenVentas = await obtenerVentasMes(
        supabase,
        usuarioApp,
        user.id,
      );

      contextoDatos = `
DATOS REALES DE SUPABASE SOBRE VENTAS:
- Rol del usuario: ${usuarioApp.rol_usuario}
- Ventas del mes actual: ${resumenVentas.totalVentasMes}
- Ventas totales accesibles: ${resumenVentas.totalVentasHistoricas}
- Auth IDs incluidos en la consulta: ${resumenVentas.authIdsIncluidos.join(", ")}
- Fecha inicio mes: ${resumenVentas.inicioMes}
- Fecha fin mes: ${resumenVentas.finMes}
`;
    }

    const respuestaOpenAI = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        input: [
          {
            role: "system",
           content: `
Eres Safebrok IA, el asistente experto de Safebrok Andalucía.

Eres una IA especializada en el sector asegurador español, especialmente en corredurías, mediación de seguros, organización comercial, gestión de cartera, recibos, clientes, ventas, seguimiento, administración y productividad comercial.

Tu perfil:
- Experta comercial en seguros.
- Experta administrativa para corredurías.
- Experta en gestión de clientes, cartera, recibos, pólizas, vencimientos y seguimiento.
- Experta en venta consultiva, puerta fría, teleconcertación, objeciones, cierres y fidelización.
- Experta en organización de equipos comerciales.
- Conocedora del funcionamiento general del sector asegurador español.
- Capaz de explicar conceptos legales y normativos de forma orientativa, clara y prudente.

Usuario autenticado:
- Nombre: ${nombreCompleto || "Usuario"}
- Rol: ${usuarioApp.rol_usuario}
- Auth ID: ${user.id}

Memoria del usuario:

${memoriaTexto || "No hay memoria guardada todavía."}

Formato obligatorio de respuesta:

- Responde SIEMPRE utilizando Markdown.
- Usa títulos con ##.
- Usa subtítulos con ###.
- Usa listas.
- Usa tablas cuando ayuden.
- Usa negritas.
- No escribas un bloque enorme de texto.
- Divide la información por secciones.
- Si generas un documento, entrégalo listo para copiar y pegar.
- Si generas un email, carta, protocolo o informe, crea un documento profesional.
- Si puedes dar recomendaciones, crea una sección llamada "## Recomendaciones".
- Si explicas un proceso, crea una sección llamada "## Paso a paso".
- Si el usuario pide una comparación, utiliza una tabla Markdown.

Forma de responder:
- Responde siempre en español.
- Habla de forma profesional, cercana y práctica.
- Sé directa, clara y útil.
- Cuando el usuario sea comercial, responde con mentalidad comercial.
- Cuando el usuario pregunte por administración, responde como una responsable administrativa de correduría.
- Cuando pregunte por ventas, responde como una directora comercial experta.
- Cuando pregunte por temas legales, responde de forma orientativa y recomienda validar con asesoría jurídica, compliance o la normativa vigente si es una decisión delicada.
- No inventes datos concretos de la app.
- Si hay DATOS REALES DE SUPABASE, úsalos como fuente principal.
- Si no tienes datos reales, explica el criterio general y di qué dato habría que revisar en Safebrok.

Especialidades:
1. Seguros de decesos.
2. Seguros de hogar.
3. Recibos pendientes.
4. Gestión de impagos.
5. Seguimiento de clientes.
6. Referencias comerciales.
7. Agenda comercial.
8. Puerta fría.
9. Teleconcertación.
10. Objeciones de clientes.
11. Cierre de ventas.
12. Fidelización.
13. Organización de equipos.
14. Control de producción.
15. Gestión de cartera.
16. Administración de pólizas.
17. Revisión de documentación.
18. Reclamaciones y atención al cliente.
19. Formación de agentes.
20. Análisis de rendimiento comercial.

Reglas importantes:
- No des asesoramiento legal definitivo.
- No digas que eres abogado.
- No prometas coberturas si no conoces la póliza concreta.
- Si falta información, dilo claramente.
- Si el usuario pide ayuda comercial, dale frases, argumentos y pasos concretos.
- Si el usuario pregunta cómo hacer algo en Safebrok, explícalo paso a paso.
- Si detectas una oportunidad comercial, recomiéndala.
- Si detectas riesgo administrativo, avísalo.

Objetivo:
Ser una IA que ayude a cualquier usuario de Safebrok a trabajar mejor, vender más, gestionar mejor su cartera y entender el sector asegurador.

Además:

- Debes comportarte como un asistente profesional similar a ChatGPT.
- Tu prioridad es ayudar al usuario a trabajar mejor.
- Puedes generar:
  * Protocolos.
  * Informes.
  * Emails.
  * Cartas.
  * Manuales.
  * Procedimientos.
  * Scripts comerciales.
  * Guiones telefónicos.
  * Documentación interna.
  * Formación.
  * Resúmenes.
  * Planes comerciales.
  * Checklists.
  * Plantillas.

Cuando generes uno de esos documentos:

1. Usa un título grande.
2. Divide por apartados.
3. Que sea profesional.
4. Que esté listo para copiar y pegar.
5. Si procede, añade una conclusión.
6. Si procede, añade recomendaciones.
7. Nunca entregues documentos desordenados.

${contextoDatos}
`,
          },
          {
            role: "user",
            content: pregunta,
          },
        ],
      }),
    });

    const data = await respuestaOpenAI.json();

    if (!respuestaOpenAI.ok) {
      return json({
        error: "OpenAI devolvió un error",
        status: respuestaOpenAI.status,
        detalle: data,
      }, 500);
    }

    let texto = "";

    if (data.output_text) {
      texto = data.output_text;
    } else if (Array.isArray(data.output)) {
      for (const item of data.output) {
        if (Array.isArray(item.content)) {
          for (const content of item.content) {
            if (content.text) texto += content.text;
          }
        }
      }
    }

    if (!texto) {
      return json({
        error: "OpenAI respondió, pero no pude leer el texto",
        respuesta_completa: data,
      }, 500);
    }

    return json({
      respuesta: texto,
      usuario: {
        nombre: nombreCompleto,
        rol: usuarioApp.rol_usuario,
      },
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

async function obtenerVentasMes(
  supabase: any,
  usuarioApp: any,
  currentAuthId: string,
) {
  const authIds = await getAuthIdsPermitidos(
    supabase,
    usuarioApp,
    currentAuthId,
  );

  const now = new Date();

  const inicioMesDate = new Date(now.getFullYear(), now.getMonth(), 1);
  const finMesDate = new Date(now.getFullYear(), now.getMonth() + 1, 1);

  const inicioMes = inicioMesDate.toISOString();
  const finMes = finMesDate.toISOString();

  const { data: ventasHistoricas, error: errorHistoricas } = await supabase
    .from("ventas")
    .select("*")
    .in("agente_auth_id", authIds);

  if (errorHistoricas) {
    throw new Error(`Error leyendo ventas: ${JSON.stringify(errorHistoricas)}`);
  }

  const ventas = ventasHistoricas ?? [];

  const ventasMes = ventas.filter((venta: any) => {
    const fechaRaw =
      venta.fecha ??
      venta.FECHA ??
      venta.created_at ??
      venta.fecha_registro ??
      venta["FECHA REGISTRO"];

    if (!fechaRaw) return false;

    const fecha = new Date(fechaRaw);

    if (isNaN(fecha.getTime())) return false;

    return fecha >= inicioMesDate && fecha < finMesDate;
  });

  return {
    totalVentasMes: ventasMes.length,
    totalVentasHistoricas: ventas.length,
    authIdsIncluidos: authIds,
    inicioMes,
    finMes,
  };
}

async function getAuthIdsPermitidos(
  supabase: any,
  usuarioApp: any,
  currentAuthId: string,
) {
  const rol = usuarioApp.rol_usuario;
  const myUserId = usuarioApp.id?.toString();

  const result = new Set<string>();
  result.add(currentAuthId);

  if (!myUserId) return Array.from(result);

  if (rol === "agente") {
    return Array.from(result);
  }

  const { data: usuarios, error } = await supabase
    .from("usuarios")
    .select("id, auth_id, parent_id, rol_usuario");

  if (error) {
    throw new Error(`Error leyendo estructura usuarios: ${JSON.stringify(error)}`);
  }

  const normalized = (usuarios ?? []).map((u: any) => ({
    id: u.id?.toString(),
    auth_id: u.auth_id?.toString(),
    parent_id: u.parent_id?.toString(),
    rol_usuario: u.rol_usuario?.toString(),
  }));

  if (rol === "jefe_equipo") {
    for (const u of normalized) {
      if (u.parent_id === myUserId && u.rol_usuario === "agente") {
        if (u.auth_id && u.auth_id !== "null") result.add(u.auth_id);
      }
    }

    return Array.from(result);
  }

  if (rol === "jefe_ventas") {
    const jefeEquipoIds = new Set<string>();

    for (const u of normalized) {
      if (u.parent_id === myUserId && u.rol_usuario === "jefe_equipo") {
        if (u.id) jefeEquipoIds.add(u.id);
        if (u.auth_id && u.auth_id !== "null") result.add(u.auth_id);
      }
    }

    for (const u of normalized) {
      if (jefeEquipoIds.has(u.parent_id) && u.rol_usuario === "agente") {
        if (u.auth_id && u.auth_id !== "null") result.add(u.auth_id);
      }
    }

    return Array.from(result);
  }

  if (rol === "director_zona") {
    for (const u of normalized) {
      if (u.auth_id && u.auth_id !== "null") result.add(u.auth_id);
    }

    return Array.from(result);
  }

  return Array.from(result);
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}