create table if not exists public.preferencias_negocio (
  usuario_auth_id uuid primary key references auth.users(id) on delete cascade,
  configuracion jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.preferencias_negocio enable row level security;

drop policy if exists "preferencias_negocio_select_own" on public.preferencias_negocio;
create policy "preferencias_negocio_select_own"
on public.preferencias_negocio for select
to authenticated
using (usuario_auth_id = auth.uid());

drop policy if exists "preferencias_negocio_insert_own" on public.preferencias_negocio;
create policy "preferencias_negocio_insert_own"
on public.preferencias_negocio for insert
to authenticated
with check (usuario_auth_id = auth.uid());

drop policy if exists "preferencias_negocio_update_own" on public.preferencias_negocio;
create policy "preferencias_negocio_update_own"
on public.preferencias_negocio for update
to authenticated
using (usuario_auth_id = auth.uid())
with check (usuario_auth_id = auth.uid());

create table if not exists public.preferencias_negocio_corporativas (
  id text primary key default 'default',
  configuracion jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint preferencias_negocio_corporativas_default check (id = 'default')
);

alter table public.preferencias_negocio_corporativas enable row level security;

drop policy if exists "preferencias_corporativas_read" on public.preferencias_negocio_corporativas;
create policy "preferencias_corporativas_read"
on public.preferencias_negocio_corporativas for select
to authenticated
using (true);

drop policy if exists "preferencias_corporativas_manage" on public.preferencias_negocio_corporativas;
create policy "preferencias_corporativas_manage"
on public.preferencias_negocio_corporativas for all
to authenticated
using (
  exists (
    select 1 from public.usuarios u
    where u.auth_id = auth.uid()
      and lower(replace(coalesce(u.rol_usuario, ''), ' ', '_')) in ('administracion', 'director_nacional')
  )
)
with check (
  exists (
    select 1 from public.usuarios u
    where u.auth_id = auth.uid()
      and lower(replace(coalesce(u.rol_usuario, ''), ' ', '_')) in ('administracion', 'director_nacional')
  )
);

insert into public.preferencias_negocio_corporativas (id, configuracion)
values ('default', '{}'::jsonb)
on conflict (id) do nothing;