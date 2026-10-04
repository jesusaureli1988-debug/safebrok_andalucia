-- Garantiza que cada recibo se normalice y llegue al usuario correcto.
-- Una póliza puede tener múltiples recibos; el número de recibo es la clave única.
alter table public.recibos drop constraint if exists unique_poliza;
drop index if exists public.unique_poliza;

create index if not exists recibos_poliza_normalizada_idx
  on public.recibos (upper(btrim(poliza)));
create index if not exists recibos_agente_idx on public.recibos (agente);
create index if not exists recibos_fecha_idx on public.recibos (fecha desc);
create index if not exists recibos_estado_idx on public.recibos (upper(btrim(estado)));

create or replace function public.app_normalizar_recibo_importado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  agente_entrada text;
  agente_resuelto uuid;
  coincidencias integer := 0;
  estado_normalizado text;
begin
  new.numero_recibo := upper(btrim(coalesce(new.numero_recibo, '')));
  new.poliza := upper(btrim(coalesce(new.poliza, '')));
  new.cliente := nullif(btrim(coalesce(new.cliente, '')), '');
  new.compania := nullif(btrim(coalesce(new.compania, '')), '');

  if new.numero_recibo = '' then
    raise exception 'El número de recibo es obligatorio';
  end if;
  if new.poliza = '' then
    raise exception 'La póliza es obligatoria para distribuir el recibo';
  end if;
  if new.importe is null then
    raise exception 'El importe del recibo es obligatorio';
  end if;
  if new.fecha is null then
    raise exception 'La fecha del recibo es obligatoria';
  end if;

  estado_normalizado := lower(translate(btrim(coalesce(new.estado, new.estado_recibo, '')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  new.estado := case
    when estado_normalizado in ('cobrado','pagado','abonado') then 'COBRADO'
    when estado_normalizado in ('devuelto','impagado','impago') then 'DEVUELTO'
    when estado_normalizado in ('pendiente','pendiente de cobro') then 'PENDIENTE'
    when estado_normalizado in ('en gestion','gestion') then 'En gestión'
    when estado_normalizado in ('para baja','para_baja','baja') then 'PARA BAJA'
    else nullif(btrim(coalesce(new.estado, '')), '')
  end;
  if new.estado is null then
    raise exception 'El estado del recibo es obligatorio o no es reconocible';
  end if;

  agente_entrada := btrim(coalesce(new.agente, ''));

  select count(*), (array_agg(u.auth_id order by u.id))[1]
    into coincidencias, agente_resuelto
  from public.usuarios u
  where u.auth_id is not null
    and lower(coalesce(u.estado, 'activo')) not in
      ('baja','inactivo','inactiva','bloqueado','bloqueada','desactivado','desactivada','suspendido','suspendida')
    and (
      u.auth_id::text = agente_entrada
      or u.id::text = agente_entrada
      or lower(btrim(coalesce(u.email, ''))) = lower(agente_entrada)
      or regexp_replace(
           lower(translate(btrim(coalesce(u.nombre, '') || ' ' || coalesce(u.apellidos, '')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')),
           '[^a-z0-9]', '', 'g'
         ) = regexp_replace(
           lower(translate(agente_entrada, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')),
           '[^a-z0-9]', '', 'g'
         )
    );

  if coincidencias <> 1 then
    agente_resuelto := null;
  end if;

  if agente_resuelto is null then
    select v.agente_auth_id
      into agente_resuelto
    from public.ventas v
    join public.usuarios u on u.auth_id = v.agente_auth_id
    where upper(btrim(coalesce(v.numero_poliza, ''))) = new.poliza
      and lower(coalesce(u.estado, 'activo')) not in
        ('baja','inactivo','inactiva','bloqueado','bloqueada','desactivado','desactivada','suspendido','suspendida')
    order by v.created_at desc nulls last, v.id desc
    limit 1;
  end if;

  if agente_resuelto is null then
    raise exception 'No se pudo asignar el recibo % a un usuario activo. Revisa agente o póliza %',
      new.numero_recibo, new.poliza;
  end if;

  new.agente := agente_resuelto::text;
  new.estado_recibo := coalesce(nullif(btrim(new.estado_recibo), ''), 'ACTIVO');
  return new;
end;
$$;

drop trigger if exists recibos_normalizar_y_asignar on public.recibos;
create trigger recibos_normalizar_y_asignar
before insert
on public.recibos
for each row execute function public.app_normalizar_recibo_importado();

comment on function public.app_normalizar_recibo_importado() is
  'Valida, normaliza y asigna cada recibo a un usuario activo antes de guardarlo.';