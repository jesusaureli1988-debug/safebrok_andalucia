import { createClient } from 'npm:@supabase/supabase-js@2';

type Recibo = Record<string, unknown>;
type Usuario = { auth_id: string | null; nombre: string | null; apellidos: string | null; estado: string | null };
const headers = {'Content-Type': 'application/json; charset=utf-8'};
const text = (value: unknown) => String(value ?? '').trim();
const norm = (value: unknown) => text(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
const available = (value: unknown) => !['baja','inactivo','inactiva','bloqueado','bloqueada','desactivado','desactivada'].includes(norm(value));
const money = (value: unknown) => {
  const number = Number(value);
  return Number.isFinite(number) && number > 0
    ? new Intl.NumberFormat('es-ES', {style: 'currency', currency: 'EUR'}).format(number)
    : '';
};

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response(JSON.stringify({ok:false,error:'Método no permitido'}), {status:405,headers});
  const expected = Deno.env.get('CRON_SECRET') ?? '';
  if (!expected || request.headers.get('x-cron-secret') !== expected) {
    return new Response(JSON.stringify({ok:false,error:'No autorizado'}), {status:401,headers});
  }
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !service) return new Response(JSON.stringify({ok:false,error:'Falta configuración interna'}), {status:500,headers});

  try {
    const payload = await request.json() as {record?: Recibo; records?: Recibo[]};
    const receipts = Array.isArray(payload.records) ? payload.records : payload.record ? [payload.record] : [];
    if (!receipts.length) return new Response(JSON.stringify({ok:true,procesados:0}), {headers});
    const db = createClient(url, service, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data: rawUsers, error: usersError} = await db.from('usuarios').select('auth_id,nombre,apellidos,estado');
    if (usersError) throw usersError;
    const byAuth = new Map<string, Usuario>();
    const byName = new Map<string, Usuario>();
    for (const row of rawUsers ?? []) {
      const user = row as Usuario;
      const authId = text(user.auth_id);
      if (!authId || !available(user.estado)) continue;
      byAuth.set(authId, user);
      const name = norm(`${text(user.nombre)} ${text(user.apellidos)}`);
      if (name) byName.set(name, user);
    }

    const policies = [...new Set(receipts.map((r) => text(r.poliza)).filter(Boolean))];
    const ownerByPolicy = new Map<string,string>();
    for (let i=0; i<policies.length; i+=200) {
      const {data:sales,error} = await db.from('ventas').select('numero_poliza,agente_auth_id,created_at').in('numero_poliza',policies.slice(i,i+200)).order('created_at',{ascending:false});
      if (error) throw error;
      for (const sale of sales ?? []) {
        const policy=text(sale.numero_poliza), authId=text(sale.agente_auth_id);
        if (policy && byAuth.has(authId) && !ownerByPolicy.has(policy)) ownerByPolicy.set(policy,authId);
      }
    }

    const results: Record<string,unknown>[] = [];
    for (const receipt of receipts) {
      const receiptId=text(receipt.id), savedAgent=text(receipt.agente), policy=text(receipt.poliza);
      const authId = text(byAuth.get(savedAgent)?.auth_id ?? byAuth.get(ownerByPolicy.get(policy) ?? '')?.auth_id ?? byName.get(norm(savedAgent))?.auth_id);
      if (!receiptId || !authId) { results.push({recibo_id:receiptId,ok:false,motivo:'sin_destinatario_activo'}); continue; }
      const {data:existing} = await db.from('notificaciones').select('id').eq('tipo','recibo_nuevo').eq('entidad_id',receiptId).eq('usuario_auth_id',authId).maybeSingle();
      if (existing) { results.push({recibo_id:receiptId,ok:true,duplicado:true}); continue; }

      const customer=text(receipt.cliente)||'un cliente', amount=money(receipt.importe);
      const message=`Nuevo recibo de ${customer}${policy ? ` · Póliza ${policy}` : ''}${amount ? ` · ${amount}` : ''}. Ya está disponible para gestionarlo.`;
      const data={tipo:'recibo_nuevo',recibo_id:receiptId,numero_recibo:text(receipt.numero_recibo),poliza:policy,cliente:customer,compania:text(receipt.compania),estado:text(receipt.estado_recibo||receipt.estado||'Pendiente')};
      const {data:notification,error:insertError}=await db.from('notificaciones').insert({usuario_auth_id:authId,tipo:'recibo_nuevo',titulo:'Nuevo recibo pendiente',mensaje:message,entidad_tipo:'recibo',entidad_id:receiptId,datos:data,leida:false,enviada_push:false,creado_en:new Date().toISOString()}).select('id').single();
      if (insertError) throw insertError;

      let sent=false, pushError='';
      try {
        const response=await fetch(`${url}/functions/v1/enviar-push`,{method:'POST',headers:{Authorization:`Bearer ${service}`,apikey:service,'Content-Type':'application/json'},body:JSON.stringify({auth_id_destino:authId,incluir_superiores:false,titulo:'Nuevo recibo pendiente',mensaje:message,data})});
        const body=await response.json().catch(()=>({}));
        sent=response.ok && typeof body==='object' && body!==null && (body as Record<string,unknown>).ok===true;
        if(!sent) pushError=JSON.stringify(body);
      } catch(error) { pushError=error instanceof Error ? error.message : String(error); }
      await db.from('notificaciones').update({enviada_push:sent,error_push:sent?null:pushError.slice(0,1000)}).eq('id',notification.id);
      results.push({recibo_id:receiptId,ok:true,push:sent});
    }
    return new Response(JSON.stringify({ok:true,procesados:receipts.length,enviados:results.filter((r)=>r.push===true).length,resultados:results}),{headers});
  } catch(error) {
    console.error('notificar-recibo-nuevo',error);
    return new Response(JSON.stringify({ok:false,error:error instanceof Error?error.message:String(error)}),{status:500,headers});
  }
});