import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (req) => {
  try {
    const {
      email,
      nombre,
      mes,
      anio,
      numero_factura,
      pdf_url,
    } = await req.json();

    const resendApiKey = Deno.env.get("RESEND_API_KEY");

    if (!resendApiKey) {
      throw new Error("Falta RESEND_API_KEY");
    }

    const pdfResponse = await fetch(pdf_url);
    const pdfBuffer = await pdfResponse.arrayBuffer();

    const pdfBase64 = btoa(
      String.fromCharCode(...new Uint8Array(pdfBuffer)),
    );

    const html = `
      <div style="font-family:Arial,sans-serif;color:#0f172a;line-height:1.5">
        <h2>Factura emitida</h2>

        <p>Estimado/a colaborador/a ${nombre ?? ''},</p>

        <p>
          Le informamos de que se ha procedido a emitir la factura correspondiente
          al mes de <strong>${mes} de ${anio}</strong>.
        </p>

        <p>
          Adjuntamos en este correo el documento en formato PDF para su consulta
          y archivo.
        </p>

        <p>
          Número de factura: <strong>${numero_factura}</strong>
        </p>

        <p>
          Para cualquier revisión o consulta sobre el detalle de pólizas incluidas,
          puede contactar con el departamento de administración.
        </p>

        <p style="margin-top:24px">
          Atentamente,<br/>
          <strong>Departamento de Administración</strong>
        </p>
      </div>
    `;

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Administración <facturas@tudominio.com>",
        to: [email],
        subject: `Factura emitida - ${mes} ${anio}`,
        html,
        attachments: [
          {
            filename: `${numero_factura}.pdf`,
            content: pdfBase64,
          },
        ],
      }),
    });

    const result = await response.json();

    if (!response.ok) {
      throw new Error(JSON.stringify(result));
    }

    return new Response(JSON.stringify({ ok: true, result }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});