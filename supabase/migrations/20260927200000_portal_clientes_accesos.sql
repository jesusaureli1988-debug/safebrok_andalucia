-- Accesos del portal SafeBrok Clientes.
-- Cada cuenta de cliente se vincula a una única ficha de clientes y solo puede
-- consultar sus propios datos, pólizas y recibos.

create table if not exists public.clientes_portal_accesos (
  auth_id uuid primary key references auth.users(id) on delete cascade,
  cliente_id uuid not null unique references public.clientes(id) on delete cascade,
  estado text not null default 'activo'
    check (estado in ('activo', 'bloqueado')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index if not exists clientes_portal_accesos_cliente_idx
  on public.clientes_portal_accesos(cliente_id);

alter table public.clientes_portal_accesos enable row level security;

drop policy if exists clientes_portal_accesos_mi_acceso on public.clientes_portal_accesos;
create policy clientes_portal_accesos_mi_acceso
  on public.clientes_portal_accesos for select to authenticated
  using (auth_id = auth.uid() and estado = 'activo');

create or replace function public.portal_cliente_tiene_acceso(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.clientes_portal_accesos a
    where a.auth_id = auth.uid()
      and a.cliente_id = p_cliente_id
      and a.estado = 'activo'
  )
$$;

drop policy if exists clientes_visibilidad_estructura on public.clientes;
create policy clientes_visibilidad_estructura on public.clientes
as restrictive for select to authenticated
using (
  public.app_puede_ver_auth_id(auth_id)
  or public.portal_cliente_tiene_acceso(id)
);

drop policy if exists ventas_visibilidad_estructura on public.ventas;
create policy ventas_visibilidad_estructura on public.ventas
as restrictive for select to authenticated
using (
  public.app_puede_ver_auth_id(agente_auth_id)
  or public.portal_cliente_tiene_acceso(cliente_id)
);

grant execute on function public.portal_cliente_tiene_acceso(uuid) to authenticated;

comment on table public.clientes_portal_accesos is
  'Vincula una cuenta auth del portal SafeBrok Clientes con una ficha de cliente.';
