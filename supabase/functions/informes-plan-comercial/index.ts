import { createClient } from 'npm:@supabase/supabase-js@2';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, apikey, content-type, x-client-info, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const clean = (v: unknown) => String(v ?? '').trim();
const num = (v: unknown) => Number(String(v ?? 0).replace(',', '.')) || 0;
const json = (v: unknown, status = 200) => new Response(JSON.stringify(v), {
  status,
  headers: {...cors, 'Content-Type': 'application/json; charset=utf-8'},
});
const name = (u: Record<string, unknown>) =>
  `${clean(u.nombre)} ${clean(u.apellidos)}`.trim() || 'Usuario';
const errorMessage = (error: unknown) => {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
};
const bytesToBase64 = (bytes: Uint8Array) => {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(
      ...bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length)),
    );
  }
  return btoa(binary);
};

function period(frequency: string) {
  const end = new Date();
  end.setUTCHours(0, 0, 0, 0);
  const start = new Date(end);
  if (frequency === 'mensual') {
    start.setUTCMonth(start.getUTCMonth() - 1, 1);
    end.setUTCDate(1);
  } else {
    start.setUTCDate(start.getUTCDate() - (frequency === 'semanal' ? 7 : 1));
  }
  return {start, end};
}

function madridDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Madrid',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  }).formatToParts(date);
  const get = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? '';
  return {
    year: Number(get('year')),
    month: Number(get('month')),
    day: Number(get('day')),
    weekday: get('weekday'),
  };
}

function madridLocalToUtc(year: number, month: number, day: number, hour: number) {
  const wanted = Date.UTC(year, month - 1, day, hour);
  let result = wanted;
  for (let i = 0; i < 3; i++) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Europe/Madrid',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(new Date(result));
    const get = (type: string) =>
      Number(parts.find((part) => part.type === type)?.value ?? 0);
    const represented = Date.UTC(
      get('year'),
      get('month') - 1,
      get('day'),
      get('hour'),
      get('minute'),
    );
    result += wanted - represented;
  }
  return new Date(result);
}

function nextRun(row: Record<string, unknown>) {
  const local = madridDateParts();
  let base = new Date(Date.UTC(local.year, local.month - 1, local.day));
  const frequency = clean(row.frecuencia);
  if (frequency === 'diaria') {
    base.setUTCDate(base.getUTCDate() + 1);
  } else if (frequency === 'semanal') {
    const weekDays: Record<string, number> = {
      Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7,
    };
    const current = weekDays[local.weekday] ?? 1;
    let difference = num(row.dia_semana) - current;
    if (difference <= 0) difference += 7;
    base.setUTCDate(base.getUTCDate() + difference);
  } else {
    const day = Math.max(1, Math.min(28, num(row.dia_mes)));
    base = new Date(Date.UTC(local.year, local.month - 1, day));
    if (base <= new Date(Date.UTC(local.year, local.month - 1, local.day))) {
      base = new Date(Date.UTC(local.year, local.month, day));
    }
  }
  return madridLocalToUtc(
    base.getUTCFullYear(),
    base.getUTCMonth() + 1,
    base.getUTCDate(),
    5,
  ).toISOString();
}

function descendants(root: Record<string, unknown>, users: Record<string, unknown>[]) {
  const result = [root];
  const seen = new Set([clean(root.id)]);
  for (let i = 0; i < result.length; i++) {
    for (const user of users) {
      const id = clean(user.id);
      if (clean(user.parent_id) === clean(result[i].id) && !seen.has(id)) {
        seen.add(id);
        result.push(user);
      }
    }
  }
  return result;
}

async function makePdf(
  title: string,
  owner: Record<string, unknown>,
  members: Record<string, unknown>[],
  sales: Record<string, unknown>[],
  cancellations: Record<string, unknown>[],
  receipts: Record<string, unknown>[],
  candidates: Record<string, unknown>[],
  from: Date,
  to: Date,
) {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const navy = rgb(.025, .10, .18);
  const blue = rgb(.08, .42, .82);
  const light = rgb(.95, .97, .985);
  const border = rgb(.83, .87, .91);
  const muted = rgb(.39, .46, .56);
  const ink = rgb(.06, .12, .20);
  const white = rgb(1, 1, 1);
  const safe = (value: unknown) =>
    clean(value).replace(/[^\x20-\xFF]/g, '').slice(0, 120);
  const euros = (value: number) =>
    `${new Intl.NumberFormat('es-ES', {maximumFractionDigits: 2}).format(value)} EUR`;
  const formatDate = (value: Date) =>
    new Intl.DateTimeFormat('es-ES', {
      timeZone: 'Europe/Madrid',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    }).format(value);
  const role = (value: unknown) => ({
    director_nacional: 'Director nacional',
    director_zona: 'Director de zona',
    jefe_ventas: 'Jefe de ventas',
    jefe_equipo: 'Jefe de equipo',
    agente: 'Agente comercial',
  }[clean(value)] ?? clean(value));
  const truncate = (
    value: unknown,
    maxWidth: number,
    size: number,
    font = regular,
  ) => {
    let output = safe(value);
    while (output.length > 2 && font.widthOfTextAtSize(output, size) > maxWidth) {
      output = `${output.slice(0, -2)}...`;
    }
    return output;
  };
  const addHeaderFooter = (page: ReturnType<typeof pdf.addPage>, index: number) => {
    if (index > 0) {
      page.drawRectangle({x: 0, y: 788, width: 595, height: 54, color: navy});
      page.drawText('SAFEBROK  |  INFORME COMERCIAL', {
        x: 46, y: 810, size: 10, font: bold, color: white,
      });
    }
    page.drawText('Documento confidencial - Generado automaticamente por SafeBrok', {
      x: 46, y: 25, size: 7.5, font: regular, color: muted,
    });
    page.drawText(`Pagina ${index + 1}`, {
      x: 500, y: 25, size: 7.5, font: regular, color: muted,
    });
  };
  const sectionTitle = (
    page: ReturnType<typeof pdf.addPage>,
    value: string,
    y: number,
  ) => {
    page.drawText(safe(value), {x: 52, y, size: 16, font: bold, color: ink});
    page.drawLine({
      start: {x: 52, y: y - 8},
      end: {x: 543, y: y - 8},
      thickness: 1,
      color: border,
    });
    return y - 30;
  };
  const drawTable = (
    page: ReturnType<typeof pdf.addPage>,
    headers: string[],
    rows: string[][],
    widths: number[],
    startY: number,
    rowHeight = 25,
  ) => {
    const x = 52;
    let y = startY;
    let currentX = x;
    for (let i = 0; i < headers.length; i++) {
      page.drawRectangle({
        x: currentX, y: y - rowHeight, width: widths[i], height: rowHeight,
        color: navy, borderColor: navy, borderWidth: .5,
      });
      page.drawText(truncate(headers[i], widths[i] - 10, 7.5, bold), {
        x: currentX + 5, y: y - 16, size: 7.5, font: bold, color: white,
      });
      currentX += widths[i];
    }
    y -= rowHeight;
    for (let r = 0; r < rows.length; r++) {
      currentX = x;
      for (let c = 0; c < headers.length; c++) {
        page.drawRectangle({
          x: currentX, y: y - rowHeight, width: widths[c], height: rowHeight,
          color: r % 2 ? light : white, borderColor: border, borderWidth: .4,
        });
        page.drawText(truncate(rows[r][c] ?? '', widths[c] - 10, 7.3), {
          x: currentX + 5, y: y - 16, size: 7.3, font: regular, color: ink,
        });
        currentX += widths[c];
      }
      y -= rowHeight;
    }
    return y;
  };

  const premium = sales.reduce((s, r) => s + num(r.prima_anual_neta), 0);
  const insured = sales.reduce((s, r) => s + num(r.numero_asegurados), 0);
  const pending = receipts.filter((r) =>
    `${clean(r.estado)} ${clean(r.estado_recibo)}`.toLowerCase()
      .includes('pendiente')
  ).length;
  const pendingPercentage = receipts.length ? pending / receipts.length * 100 : 0;

  // Portada
  const cover = pdf.addPage([595, 842]);
  cover.drawRectangle({x: 42, y: 345, width: 511, height: 390, color: navy});
  cover.drawText('SAFEBROK', {
    x: 90, y: 690, size: 13, font: bold, color: rgb(.55, .76, 1),
  });
  cover.drawText('Informe comercial', {
    x: 90, y: 610, size: 30, font: bold, color: white,
  });
  cover.drawText('de estructura', {
    x: 90, y: 570, size: 30, font: bold, color: white,
  });
  cover.drawText(
    truncate(title, 410, 14),
    {x: 90, y: 505, size: 14, font: regular, color: rgb(.82, .90, .98)},
  );
  const meta = [
    ['RESPONSABLE', name(owner)],
    ['PERIODO', `${formatDate(from)} - ${formatDate(new Date(to.getTime() - 1))}`],
    ['ALCANCE', `${members.length} personas incluidas`],
    ['GENERACION', 'Automatica - 05:00 Europe/Madrid'],
  ];
  let metaY = 300;
  for (const [label, value] of meta) {
    cover.drawRectangle({
      x: 52, y: metaY - 34, width: 491, height: 34,
      color: white, borderColor: border, borderWidth: .5,
    });
    cover.drawRectangle({
      x: 52, y: metaY - 34, width: 120, height: 34,
      color: light, borderColor: border, borderWidth: .5,
    });
    cover.drawText(label, {x: 62, y: metaY - 21, size: 8, font: bold, color: muted});
    cover.drawText(truncate(value, 350, 9), {
      x: 183, y: metaY - 21, size: 9, font: regular, color: ink,
    });
    metaY -= 34;
  }

  // Resumen ejecutivo
  const summary = pdf.addPage([595, 842]);
  let y = sectionTitle(summary, 'Resumen ejecutivo', 760);
  const kpis = [
    ['VENTAS', String(sales.length)],
    ['PRIMA NETA', euros(premium)],
    ['ASEGURADOS', String(insured)],
    ['ANULACIONES', String(cancellations.length)],
  ];
  for (let i = 0; i < kpis.length; i++) {
    const x = 52 + i * 123;
    summary.drawRectangle({
      x, y: y - 76, width: 118, height: 76,
      color: light, borderColor: border, borderWidth: .6,
    });
    summary.drawText(truncate(kpis[i][1], 104, 16, bold), {
      x: x + 8, y: y - 33, size: 16, font: bold, color: ink,
    });
    summary.drawText(kpis[i][0], {
      x: x + 8, y: y - 58, size: 7.5, font: regular, color: muted,
    });
  }
  y -= 108;
  summary.drawText('Lectura de direccion', {
    x: 52, y, size: 13, font: bold, color: blue,
  });
  y -= 24;
  const reading = sales.length === 0
    ? 'No se registraron ventas en el periodo. Se recomienda revisar la actividad comercial, las oportunidades abiertas y la planificacion de la estructura.'
    : `La estructura registro ${sales.length} ventas y ${euros(premium)} de prima anual neta. El pendiente de recibos se situa en ${pendingPercentage.toFixed(1)}%. Conviene revisar las desviaciones individuales, las anulaciones y la calidad de cartera antes de definir las proximas acciones.`;
  const words = reading.split(' ');
  let line = '';
  for (const word of words) {
    const candidate = `${line}${line ? ' ' : ''}${word}`;
    if (regular.widthOfTextAtSize(candidate, 9.5) > 485) {
      summary.drawText(line, {x: 52, y, size: 9.5, font: regular, color: ink});
      y -= 15;
      line = word;
    } else {
      line = candidate;
    }
  }
  if (line) summary.drawText(line, {x: 52, y, size: 9.5, font: regular, color: ink});
  y -= 42;
  y = sectionTitle(summary, 'Rendimiento de la estructura', y);
  const teamRows = members.slice(0, 15).map((member) => {
    const own = sales.filter((s) => clean(s.agente_auth_id) === clean(member.auth_id));
    const ownPremium = own.reduce((s, r) => s + num(r.prima_anual_neta), 0);
    return [name(member), role(member.rol_usuario), String(own.length), euros(ownPremium)];
  });
  drawTable(summary, ['Figura', 'Cargo', 'Ventas', 'Prima neta'], teamRows, [190, 120, 65, 116], y);

  // Detalle operativo
  let detail = pdf.addPage([595, 842]);
  y = sectionTitle(detail, 'Detalle de ventas del periodo', 760);
  const names = new Map(members.map((u) => [clean(u.auth_id), name(u)]));
  const saleRows = sales.slice(0, 20).map((sale) => [
    clean(sale.fecha_efecto).slice(0, 10),
    names.get(clean(sale.agente_auth_id)) ?? 'Sin asignar',
    clean(sale.producto),
    clean(sale.compania),
    clean(sale.numero_poliza),
    euros(num(sale.prima_anual_neta)),
  ]);
  y = drawTable(
    detail,
    ['Fecha', 'Comercial', 'Producto', 'Compania', 'Poliza', 'Prima neta'],
    saleRows,
    [58, 112, 72, 74, 96, 79],
    y,
    23,
  );
  if (y < 230) {
    detail = pdf.addPage([595, 842]);
    y = 760;
  }
  y = sectionTitle(detail, 'Control de cartera', y - 18);
  const controlRows = [
    ['Anulaciones', String(cancellations.length), 'Revisar causa y responsable'],
    ['Recibos pendientes', String(pending), `${pendingPercentage.toFixed(1)}% del total`],
    ['Captaciones', String(candidates.length), 'Seguimiento del proceso'],
  ];
  y = drawTable(detail, ['Indicador', 'Resultado', 'Lectura'], controlRows, [170, 90, 231], y, 25);
  y -= 24;
  detail.drawText('Acciones recomendadas', {x: 52, y, size: 13, font: bold, color: blue});
  const actions = [
    '1. Revisar las anulaciones con los responsables de cada operacion.',
    '2. Priorizar los equipos con menor produccion y reforzar su seguimiento.',
    '3. Mantener control diario del pendiente de recibos y la calidad de cartera.',
    '4. Replicar las practicas de las figuras con mejor conversion.',
  ];
  y -= 24;
  for (const action of actions) {
    detail.drawText(action, {x: 52, y, size: 9, font: regular, color: ink});
    y -= 17;
  }

  pdf.getPages().forEach((page, index) => addHeaderFooter(page, index));
  return pdf.save();
}

async function generate(db: ReturnType<typeof createClient>, schedule: Record<string, unknown>) {
  const ownerId = clean(schedule.owner_auth_id);
  const {data: users, error: usersError} = await db.from('usuarios')
    .select('id,auth_id,parent_id,nombre,apellidos,rol_usuario,email');
  if (usersError) throw usersError;
  const owner = (users ?? []).find((u) => clean(u.auth_id) === ownerId);
  if (!owner) throw new Error('Perfil no encontrado.');
  const members = descendants(owner, users ?? []);
  const ids = members.map((u) => clean(u.auth_id)).filter(Boolean);
  const p = period(clean(schedule.frecuencia) || 'diaria');
  const [salesResult, cancelResult, receiptsResult, candidatesResult] = await Promise.all([
    db.from('ventas').select(
      'id,agente_auth_id,numero_poliza,producto,compania,fecha_efecto,prima_anual_neta,numero_asegurados,estado_poliza',
    ).in('agente_auth_id', ids)
      .gte('fecha_efecto', p.start.toISOString()).lt('fecha_efecto', p.end.toISOString()),
    db.from('anulaciones_polizas').select(
      'id,venta_id,fecha_anulacion,prima_extornada,estado',
    ).gte('fecha_anulacion', p.start.toISOString()).lt('fecha_anulacion', p.end.toISOString()),
    db.from('recibos').select(
      'id,agente,poliza,numero_recibo,cliente,importe,estado,estado_recibo,fecha',
    ).in('agente', ids).gte('fecha', p.start.toISOString()).lt('fecha', p.end.toISOString()),
    db.from('candidatos_captacion').select(
      'id,asignado_auth_id,fecha_asignacion',
    ).in('asignado_auth_id', ids)
      .gte('fecha_asignacion', p.start.toISOString()).lt('fecha_asignacion', p.end.toISOString()),
  ]);
  if (salesResult.error) throw salesResult.error;
  if (cancelResult.error) throw cancelResult.error;
  if (receiptsResult.error) throw receiptsResult.error;
  if (candidatesResult.error) throw candidatesResult.error;
  const sales = salesResult.data ?? [];
  const saleIds = new Set(sales.map((s) => clean(s.id)));
  const cancellations = (cancelResult.data ?? []).filter((r) => saleIds.has(clean(r.venta_id)));
  const title = clean(schedule.nombre) || 'Informe comercial';
  const pdf = await makePdf(
    title, owner, members, sales, cancellations,
    receiptsResult.data ?? [], candidatesResult.data ?? [], p.start, p.end,
  );
  const filename = `${title}_${new Date().toISOString().slice(0,10)}.pdf`
    .replace(/[\\/:*?"<>| ]+/g, '_');
  const path = `${ownerId}/informes_comerciales/${Date.now()}_${filename}`;
  const {error: uploadError} = await db.storage.from('safecloud')
    .upload(path, pdf, {contentType: 'application/pdf'});
  if (uploadError) throw uploadError;
  const {data: item, error: itemError} = await db.from('safecloud_items').insert({
    owner_auth_id: ownerId, parent_id: null, nombre: filename, tipo: 'archivo',
    storage_path: path, mime_type: 'pdf', size_bytes: pdf.length,
  }).select('id').single();
  if (itemError) throw itemError;
  const {data: signed} = await db.storage.from('safecloud').createSignedUrl(path, 604800);
  let emailId = '';
  const key = Deno.env.get('RESEND_API_KEY');
  if (key && clean(schedule.email_destino)) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {Authorization: `Bearer ${key}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({
        from:
          Deno.env.get('RESEND_FROM_EMAIL') ||
          'SafeBrok <onboarding@resend.dev>',
        to: [clean(schedule.email_destino)],
        subject: `SafeBrok | ${title}`,
        html: `<h2>${title}</h2><p>Adjuntamos el informe comercial solicitado.</p>`,
        attachments: [{filename, content: bytesToBase64(pdf)}],
      }),
    });
    const responseBody = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(JSON.stringify(responseBody));
    emailId = clean(responseBody.id);
  }
  await db.from('informes_comerciales_generados').insert({
    owner_auth_id: ownerId, programacion_id: schedule.id || null,
    tipo_informe: schedule.tipo_informe, parametro_objetivo: schedule.parametro_objetivo || null,
    frecuencia: schedule.frecuencia, periodo_desde: p.start.toISOString(),
    periodo_hasta: p.end.toISOString(), nombre_archivo: filename,
    storage_path: path, safecloud_item_id: item.id, email_destino: schedule.email_destino,
    estado: emailId ? 'enviado' : 'generado', proveedor_email_id: emailId || null,
  });
  return {filename, signed_url: signed?.signedUrl ?? null, enviado: Boolean(emailId)};
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers: cors});
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json({ok:false,error:'Faltan secretos.'}, 500);
  const db = createClient(url, key, {auth:{persistSession:false}});
  try {
    const body = await req.json();
    if (body.action === 'process_due') {
      if (req.headers.get('x-cron-secret') !== Deno.env.get('CRON_SECRET')) {
        return json({ok:false,error:'No autorizado.'}, 401);
      }
      const {data: rows, error} = await db.from('programaciones_informes_comerciales')
        .select().eq('activa', true).lte('proxima_ejecucion', new Date().toISOString());
      if (error) throw error;
      const results = [];
      for (const row of rows ?? []) {
        try {
          results.push({id: row.id, ok: true, data: await generate(db, row)});
          await db.from('programaciones_informes_comerciales').update({
            ultima_ejecucion: new Date().toISOString(), proxima_ejecucion: nextRun(row),
            ultimo_estado: 'enviado', ultimo_error: null,
          }).eq('id', row.id);
        } catch (e) {
          const message = errorMessage(e);
          await db.from('programaciones_informes_comerciales').update({
            ultima_ejecucion: new Date().toISOString(), proxima_ejecucion: nextRun(row),
            ultimo_estado: 'fallido', ultimo_error: message,
          }).eq('id', row.id);
          results.push({id: row.id, ok: false, error: message});
        }
      }
      return json({ok:true,procesadas:results.length,resultados:results});
    }
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    const {data: auth} = await db.auth.getUser(token);
    if (!auth.user) return json({ok:false,error:'Sesión no válida.'}, 401);
    const schedule = {...body.programacion, owner_auth_id: auth.user.id};
    return json({ok:true,...await generate(db, schedule)});
  } catch (e) {
    return json({ok:false,error:errorMessage(e)}, 500);
  }
});
