-- Conserva las validaciones de ventas/clientes. Las pendientes se guardan
-- separadamente hasta que administración les asigne un usuario registrado.
begin;
create table if not exists public.polizas_pendientes_asignacion (
  id uuid primary key default gen_random_uuid(),
  numero_poliza text not null unique,
  agente_nombre_importado text not null check (btrim(agente_nombre_importado) <> ''),
  cliente_datos jsonb not null check (jsonb_typeof(cliente_datos) = 'object'),
  venta_datos jsonb not null check (jsonb_typeof(venta_datos) = 'object'),
  importado_por uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (numero_poliza = upper(btrim(numero_poliza)) and numero_poliza <> '')
);
alter table public.polizas_pendientes_asignacion enable row level security;
create policy pendientes_select_admin on public.polizas_pendientes_asignacion
  for select to authenticated using (exists (
    select 1 from public.usuarios u where u.auth_id = auth.uid()
      and replace(replace(lower(btrim(u.rol_usuario)), '-', '_'), ' ', '_') = 'director_nacional'
      and public.app_estado_usuario_activo(u.estado)
  ));
grant select on public.polizas_pendientes_asignacion to authenticated;

-- El importador puede comprobar duplicados sin exponer datos de pendientes.
create or replace function public.app_polizas_ya_importadas(p_numeros text[])
returns table(numero_poliza text) language sql stable security definer set search_path = '' as $$
  select v.numero_poliza from public.ventas v
  where public.app_can_manage_global() and upper(btrim(v.numero_poliza)) = any(p_numeros)
  union
  select p.numero_poliza from public.polizas_pendientes_asignacion p
  where public.app_can_manage_global() and p.numero_poliza = any(p_numeros)
$$;
revoke all on function public.app_polizas_ya_importadas(text[]) from public, anon;
grant execute on function public.app_polizas_ya_importadas(text[]) to authenticated;

create or replace function public.app_importar_poliza_pendiente(
  p_numero_poliza text, p_agente_nombre text,
  p_cliente_datos jsonb, p_venta_datos jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_numero text := upper(btrim(p_numero_poliza));
begin
  if auth.uid() is null or not public.app_can_manage_global() then
    raise exception 'Solo gestión global puede importar pólizas pendientes';
  end if;
  if nullif(v_numero, '') is null or nullif(btrim(p_agente_nombre), '') is null then
    raise exception 'Se requiere número de póliza y nombre del agente del Excel';
  end if;
  if jsonb_typeof(p_cliente_datos) is distinct from 'object'
     or jsonb_typeof(p_venta_datos) is distinct from 'object'
     or nullif(btrim(p_cliente_datos->>'nombre'), '') is null
     or nullif(btrim(p_venta_datos->>'producto'), '') is null
     or nullif(btrim(p_venta_datos->>'compania'), '') is null
     or nullif(p_venta_datos->>'fecha_efecto', '') is null
     or nullif(p_venta_datos->>'prima_anual_neta', '') is null
     or nullif(p_venta_datos->>'prima_anual_bruta', '') is null then
    raise exception 'Faltan datos obligatorios de cliente o póliza';
  end if;
  perform (p_venta_datos->>'fecha_efecto')::date;
  if (p_venta_datos->>'prima_anual_neta')::numeric < 0
     or (p_venta_datos->>'prima_anual_bruta')::numeric < 0 then
    raise exception 'Las primas no pueden ser negativas';
  end if;
  if exists(select 1 from public.ventas where upper(btrim(numero_poliza)) = v_numero) then
    return null;
  end if;
  insert into public.polizas_pendientes_asignacion
    (numero_poliza, agente_nombre_importado, cliente_datos, venta_datos)
  values (v_numero, btrim(p_agente_nombre),
    p_cliente_datos - 'auth_id',
    (p_venta_datos - 'agente_auth_id' - 'cliente_id') || jsonb_build_object('numero_poliza', v_numero))
  on conflict (numero_poliza) do nothing returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.app_importar_poliza_pendiente(text,text,jsonb,jsonb) from public, anon;
grant execute on function public.app_importar_poliza_pendiente(text,text,jsonb,jsonb) to authenticated;

create or replace function public.app_asignar_polizas_pendientes(
  p_ids uuid[], p_agente_auth_id uuid
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  p public.polizas_pendientes_asignacion;
  c public.clientes;
  v public.ventas;
  cliente_id_actual uuid;
  total integer := 0;
begin
  if auth.uid() is null or not exists (
    select 1 from public.usuarios u where u.auth_id = auth.uid()
      and replace(replace(lower(btrim(u.rol_usuario)), '-', '_'), ' ', '_') = 'director_nacional'
      and public.app_estado_usuario_activo(u.estado)
  ) then raise exception 'Solo el director nacional puede reasignar estas pólizas'; end if;
  if not exists(select 1 from public.usuarios u where u.auth_id = p_agente_auth_id
    and public.app_estado_usuario_activo(u.estado)) then
    raise exception 'El mediador seleccionado no existe o está inactivo';
  end if;
  if coalesce(cardinality(p_ids), 0) = 0 or cardinality(p_ids) > 100 then
    raise exception 'Selecciona entre 1 y 100 pólizas por lote';
  end if;
  for p in select * from public.polizas_pendientes_asignacion
    where id = any(p_ids) order by id for update
  loop
    if exists(select 1 from public.ventas where upper(btrim(numero_poliza)) = p.numero_poliza) then
      raise exception 'La póliza % ya está registrada. No se ha modificado', p.numero_poliza;
    end if;
    c := jsonb_populate_record(null::public.clientes, p.cliente_datos);
    v := jsonb_populate_record(null::public.ventas, p.venta_datos);
    cliente_id_actual := null;
    if nullif(btrim(c.dni), '') is not null then
      select id into cliente_id_actual from public.clientes
      where auth_id = p_agente_auth_id and upper(btrim(dni)) = upper(btrim(c.dni)) limit 1;
    elsif nullif(btrim(c.email), '') is not null then
      select id into cliente_id_actual from public.clientes
      where auth_id = p_agente_auth_id and lower(btrim(email)) = lower(btrim(c.email)) limit 1;
    end if;
    if cliente_id_actual is null then
      insert into public.clientes(auth_id,nombre,apellidos,telefono,email,codigo_postal,
        provincia,poblacion,direccion,numero,dni)
      values(p_agente_auth_id,c.nombre,c.apellidos,c.telefono,c.email,c.codigo_postal,
        c.provincia,c.poblacion,c.direccion,c.numero,c.dni)
      returning id into cliente_id_actual;
    end if;
    insert into public.ventas(cliente_id,agente_auth_id,producto,compania,forma_pago,
      precio,numero_asegurados,fecha_efecto,prima_anual,prima_anual_bruta,
      prima_anual_neta,comision,categoria_producto,numero_poliza,estado_poliza)
    values(cliente_id_actual,p_agente_auth_id,v.producto,v.compania,v.forma_pago,
      v.precio,v.numero_asegurados,v.fecha_efecto,v.prima_anual,v.prima_anual_bruta,
      v.prima_anual_neta,coalesce(v.comision,0),v.categoria_producto,p.numero_poliza,v.estado_poliza);
    delete from public.polizas_pendientes_asignacion where id = p.id;
    total := total + 1;
  end loop;
  return total;
end; $$;
revoke all on function public.app_asignar_polizas_pendientes(uuid[],uuid) from public, anon;
grant execute on function public.app_asignar_polizas_pendientes(uuid[],uuid) to authenticated;
commit;
