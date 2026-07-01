const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ error: "Método no permitido" }),
        {
          status: 405,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    const { email, cliente, poliza, importe, url } = await req.json();

    if (!email || !email.includes("@")) {
      return new Response(
        JSON.stringify({ error: "Email inválido" }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    const resendApiKey = Deno.env.get("RESEND_API_KEY");

    if (!resendApiKey) {
      return new Response(
        JSON.stringify({ error: "Falta RESEND_API_KEY" }),
        {
          status: 500,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    const importeFormateado = Number(importe || 0).toFixed(2);

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "SafeBrok Andalucía <onboarding@resend.dev>",
        to: [email],
        subject: "Pago de recibo pendiente",
        html: `
          <div style="margin:0;padding:0;background:#f4f7fb;font-family:Arial,sans-serif;">
            <div style="max-width:620px;margin:0 auto;padding:28px;">
              <div style="background:#061018;border-radius:20px;padding:26px;color:white;">
                <h1 style="margin:0;font-size:24px;">SafeBrok Andalucía</h1>
                <p style="margin:8px 0 0;color:#9fb3c8;">Gestión de recibos</p>
              </div>

              <div style="background:white;border-radius:20px;padding:26px;margin-top:18px;color:#111827;">
                <h2 style="margin:0 0 14px;font-size:22px;">Pago de recibo pendiente</h2>

                <p style="font-size:15px;line-height:1.6;">Hola ${cliente || "cliente"},</p>

                <p style="font-size:15px;line-height:1.6;">
                  Te enviamos el enlace para realizar el pago del recibo pendiente.
                </p>

                <div style="background:#f1f5f9;border-radius:14px;padding:16px;margin:20px 0;">
                  <p style="margin:0 0 8px;"><strong>Cliente:</strong> ${cliente || "-"}</p>
                  <p style="margin:0 0 8px;"><strong>Póliza:</strong> ${poliza || "-"}</p>
                  <p style="margin:0;"><strong>Importe:</strong> ${importeFormateado} €</p>
                </div>

                <a href="${url}"
                   style="display:inline-block;background:#06b6d4;color:white;
                   padding:14px 22px;border-radius:12px;text-decoration:none;
                   font-weight:bold;">
                  Pagar recibo
                </a>

                <p style="font-size:13px;color:#64748b;margin-top:22px;">
                  Si el botón no funciona, copia y pega este enlace en tu navegador:
                </p>

                <p style="font-size:13px;color:#0f766e;word-break:break-all;">${url}</p>
              </div>

              <p style="text-align:center;color:#64748b;font-size:12px;margin-top:18px;">
                Este email ha sido generado desde SafeBrok Andalucía.
              </p>
            </div>
          </div>
        `,
      }),
    });

    const result = await resendResponse.json();

    if (!resendResponse.ok) {
      return new Response(
        JSON.stringify({
          error: "Error enviando email",
          details: result,
        }),
        {
          status: resendResponse.status,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        message: "Email enviado correctamente",
        result,
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({
        error: "Error interno",
        details: String(e),
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  }
});
