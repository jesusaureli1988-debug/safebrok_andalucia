import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const normalizeEmail = (value: unknown) => String(value ?? "").trim().toLowerCase();
const normalizeDni = (value: unknown) => String(value ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
const redirectTo = "https://safebrok-acceso-47f45.web.app/crear-password.html";

async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 20; page += 1) {
    const result = await admin.auth.admin.listUsers({ page, perPage: 100 });
    if (result.error) throw result.error;
    const user = result.data.users.find((item) => normalizeEmail(item.email) === email);
    if (user) return user;
    if (result.data.users.length < 100) break;
  }
  return null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const body = await request.json();
    const email = normalizeEmail(body.email);
    const dniLast4 = normalizeDni(body.dni_last4);

    if (!email.includes("@") || dniLast4.length !== 4) {
      throw new Error("Introduce el email y los cuatro últimos caracteres de tu DNI o NIE.");
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const clients = await admin
      .from("clientes")
      .select("id,email,dni,nombre,apellidos")
      .ilike("email", email)
      .limit(10);

    if (clients.error) throw clients.error;

    const client = (clients.data ?? []).find((item) => normalizeDni(item.dni).endsWith(dniLast4));

    if (!client) {
      return Response.json(
        {
          ok: true,
          detected: false,
          status: "not_found",
          message: "No hemos encontrado ningún cliente que coincida con ese email y los últimos cuatro caracteres del DNI o NIE.",
        },
        { headers: cors },
      );
    }

    let authUser = await findUserByEmail(admin, email);
    const hadAuthUser = authUser !== null;

    if (authUser) {
      // La misma cuenta puede pertenecer a un profesional y, al mismo tiempo,
      // estar vinculada a su ficha como cliente. No se crea un segundo usuario:
      // se reutiliza el auth_id y se habilita también el acceso al portal.
      const linked = await admin
        .from("clientes_portal_accesos")
        .upsert(
          { auth_id: authUser.id, cliente_id: client.id, estado: "activo" },
          { onConflict: "auth_id" },
        );

      if (linked.error) throw linked.error;

      const reset = await admin.auth.resetPasswordForEmail(email, { redirectTo });
      if (reset.error) throw reset.error;
    } else {
      const invitation = await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo,
        data: {
          portal: "safebrok_clientes",
          requires_password_setup: true,
          cliente_id: client.id,
        },
      });
      if (invitation.error || !invitation.data.user) {
        throw invitation.error ?? new Error("No se pudo preparar el acceso.");
      }

      authUser = invitation.data.user;
      const linked = await admin.from("clientes_portal_accesos").insert({
        auth_id: authUser.id,
        cliente_id: client.id,
        estado: "activo",
      });

      if (linked.error) {
        await admin.auth.admin.deleteUser(authUser.id);
        throw linked.error;
      }
    }

    return Response.json(
      {
        ok: true,
        detected: true,
        status: hadAuthUser ? "password_email_sent" : "activation_email_sent",
        message: hadAuthUser
          ? "Cliente detectado. Te hemos enviado un correo para crear o restablecer tu contraseña."
          : "Cliente detectado. Te hemos enviado un correo para crear tu contraseña y activar tu espacio privado.",
      },
      { headers: cors },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se ha podido preparar el acceso.";
    console.error("registrar-cliente", message);
    return Response.json({ error: message }, { status: 400, headers: cors });
  }
});
