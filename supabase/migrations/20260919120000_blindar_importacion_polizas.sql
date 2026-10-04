-- SafeBrok · integridad y visibilidad de pólizas.
begin;

create or replace function public.app_estado_usuario_activo(v text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(translate(btrim(coalesce(v, 'activo')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'))
    not in ('baja','inactivo','inactiva','bloqueado','bloqueada','desactivado','desactivada','suspendido','suspendida')
$$;

create or replace function public.app_puede_ver_auth_id(p_auth_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive actor as (
    select u.id
    from public.usuarios u
    where u.auth_id = auth.uid()
      and public.app_estado_usuario_activo(u.estado)
    limit 1
  ), visibles as (
    select a.id from actor a
    union
    select u.id
    from public.usuarios u
    join visibles v on u.parent_id = v.id
    where public.app_estado_usuario_activo(u.estado)
  )
  select exists (select 1 from actor) and (
    public.app_can_manage_global()
    or p_auth_id = auth.uid()
    or exists (
      select 1
      from visibles v
      join public.usuarios u on u.id = v.id
      where u.auth_id = p_auth_id
        and public.app_estado_usuario_activo(u.estado)
    )
  )
$$;

create or replace function public.app_validar_poliza()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  usuario_id uuid;
  cliente_auth_id uuid;
  estado_norm text;
begin
  new.numero_poliza := upper(btrim(coalesce(new.numero_poliza, '')));
  new.producto := nullif(btrim(coalesce(new.producto, '')), '');
  new.compania := nullif(btrim(coalesce(new.compania, '')), '');
  new.forma_pago := nullif(btrim(coalesce(new.forma_pago, '')), '');
  new.categoria_producto := coalesce(
    nullif(btrim(coalesce(new.categoria_producto, '')), ''),
    new.producto
  );

  if new.numero_poliza = '' then
    raise exception 'El número de póliza es obligatorio';
  end if;
  if new.producto is null then
    raise exception 'El producto o ramo es obligatorio';
  end if;
  if new.compania is null then
    raise exception 'La compañía aseguradora es obligatoria';
  end if;
  if new.fecha_efecto is null then
    raise exception 'La fecha de efecto es obligatoria';
  end if;
  if new.prima_anual_neta is null or new.prima_anual_neta < 0 then
    raise exception 'La prima anual neta debe ser un importe válido mayor o igual que cero';
  end if;
  if new.prima_anual is not null and new.prima_anual < 0 then
    raise exception 'La prima anual no puede ser negativa';
  end if;
  if new.prima_anual_bruta is not null and new.prima_anual_bruta < 0 then
    raise exception 'La prima anual bruta no puede ser negativa';
  end if;
  if new.comision is null or new.comision < 0 then
    raise exception 'La comisión debe ser un importe válido mayor o igual que cero';
  end if;
  if new.agente_auth_id is null then
    raise exception 'La póliza debe estar asignada a un usuario';
  end if;

  select u.id into usuario_id
  from public.usuarios u
  where u.auth_id = new.agente_auth_id
    and public.app_estado_usuario_activo(u.estado)
  limit 1;

  if usuario_id is null then
    raise exception 'La póliza no se puede asignar a un usuario inexistente o inactivo';
  end if;

  select c.auth_id into cliente_auth_id
  from public.clientes c
  where c.id = new.cliente_id;

  if cliente_auth_id is null or cliente_auth_id <> new.agente_auth_id then
    raise exception 'El cliente y la póliza deben pertenecer al mismo usuario';
  end if;

  if exists (
    select 1 from public.ventas v
    where v.id is distinct from new.id
      and upper(btrim(coalesce(v.numero_poliza, ''))) = new.numero_poliza
  ) then
    raise exception 'La póliza % ya existe', new.numero_poliza;
  end if;

  estado_norm := lower(translate(btrim(coalesce(new.estado_poliza, 'activa')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  new.estado_poliza := case
    when estado_norm in ('activa','activo','en vigor','vigor') then 'ACTIVA'
    when estado_norm in ('anulada','anulado','baja') then 'ANULADA'
    when estado_norm in ('pendiente','pendiente emision','pendiente de emision') then 'PENDIENTE'
    else upper(btrim(coalesce(new.estado_poliza, 'ACTIVA')))
  end;

  return new;
end;
$$;

drop trigger if exists ventas_validar_y_asignar on public.ventas;
create trigger ventas_validar_y_asignar
before insert or update of numero_poliza, producto, compania, forma_pago,
  categoria_producto, fecha_efecto, prima_anual_neta, comision,
  agente_auth_id, cliente_id, estado_poliza
on public.ventas
for each row execute function public.app_validar_poliza();

create index if not exists ventas_numero_poliza_normalizado_idx
  on public.ventas (upper(btrim(numero_poliza)));
create index if not exists ventas_agente_fecha_efecto_idx
  on public.ventas (agente_auth_id, fecha_efecto desc);
create index if not exists clientes_auth_dni_normalizado_idx
  on public.clientes (auth_id, upper(btrim(dni)));
create index if not exists clientes_auth_email_normalizado_idx
  on public.clientes (auth_id, lower(btrim(email)));

alter table public.ventas enable row level security;
alter table public.clientes enable row level security;

-- Se añade una política permisiva base para instalaciones antiguas sin política
-- y una política restrictiva que nunca permite saltarse la jerarquía.
drop policy if exists ventas_authenticated_base_select on public.ventas;
create policy ventas_authenticated_base_select on public.ventas
for select to authenticated using (true);
drop policy if exists ventas_visibilidad_estructura on public.ventas;
create policy ventas_visibilidad_estructura on public.ventas
as restrictive for select to authenticated
using (public.app_puede_ver_auth_id(agente_auth_id));

drop policy if exists ventas_authenticated_base_insert on public.ventas;
create policy ventas_authenticated_base_insert on public.ventas
for insert to authenticated with check (true);
drop policy if exists ventas_escritura_asignada on public.ventas;
create policy ventas_escritura_asignada on public.ventas
as restrictive for insert to authenticated
with check (public.app_can_manage_global() or agente_auth_id = auth.uid());

drop policy if exists ventas_authenticated_base_delete on public.ventas;
create policy ventas_authenticated_base_delete on public.ventas
for delete to authenticated using (true);
drop policy if exists ventas_borrado_estructura on public.ventas;
create policy ventas_borrado_estructura on public.ventas
as restrictive for delete to authenticated
using (public.app_puede_ver_auth_id(agente_auth_id));
drop policy if exists ventas_authenticated_base_update on public.ventas;
create policy ventas_authenticated_base_update on public.ventas
for update to authenticated using (true) with check (true);
drop policy if exists ventas_actualizacion_estructura on public.ventas;
create policy ventas_actualizacion_estructura on public.ventas
as restrictive for update to authenticated
using (public.app_puede_ver_auth_id(agente_auth_id))
with check (public.app_puede_ver_auth_id(agente_auth_id));

drop policy if exists clientes_authenticated_base_select on public.clientes;
create policy clientes_authenticated_base_select on public.clientes
for select to authenticated using (true);
drop policy if exists clientes_visibilidad_estructura on public.clientes;
create policy clientes_visibilidad_estructura on public.clientes
as restrictive for select to authenticated
using (public.app_puede_ver_auth_id(auth_id));

drop policy if exists clientes_authenticated_base_insert on public.clientes;
create policy clientes_authenticated_base_insert on public.clientes
for insert to authenticated with check (true);
drop policy if exists clientes_escritura_asignada on public.clientes;
create policy clientes_escritura_asignada on public.clientes
as restrictive for insert to authenticated
with check (public.app_can_manage_global() or auth_id = auth.uid());

drop policy if exists clientes_authenticated_base_delete on public.clientes;
create policy clientes_authenticated_base_delete on public.clientes
for delete to authenticated using (true);
drop policy if exists clientes_borrado_estructura on public.clientes;
create policy clientes_borrado_estructura on public.clientes
as restrictive for delete to authenticated
using (public.app_puede_ver_auth_id(auth_id));
drop policy if exists clientes_authenticated_base_update on public.clientes;
create policy clientes_authenticated_base_update on public.clientes
for update to authenticated using (true) with check (true);
drop policy if exists clientes_actualizacion_estructura on public.clientes;
create policy clientes_actualizacion_estructura on public.clientes
as restrictive for update to authenticated
using (public.app_puede_ver_auth_id(auth_id))
with check (public.app_puede_ver_auth_id(auth_id));

grant execute on function public.app_puede_ver_auth_id(uuid) to authenticated;
revoke all on function public.app_validar_poliza() from public, anon, authenticated;

comment on function public.app_validar_poliza() is
  'Normaliza y valida pólizas, impide duplicados y garantiza que cliente y agente coincidan.';
comment on function public.app_puede_ver_auth_id(uuid) is
  'Limita pólizas y clientes al usuario activo, su estructura descendente o gestión global.';

commit;