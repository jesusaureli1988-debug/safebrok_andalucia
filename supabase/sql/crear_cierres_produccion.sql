create table if not exists public.cierres_produccion (
  id uuid primary key default gen_random_uuid(),
  anio integer not null check (anio between 2024 and 2100),
  mes integer not null check (mes between 1 and 12),
  fecha_desde date not null,
  fecha_hasta date not null,
  estado text not null default 'abierto'
    check (estado in ('abierto', 'cerrado')),
  observaciones text,
  creado_por uuid references auth.users(id) on delete set null,
  cerrado_por uuid references auth.users(id) on delete set null,
  cerrado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cierres_produccion_fechas_validas
    check (fecha_hasta >= fecha_desde),
  constraint cierres_produccion_periodo_unico
    unique (anio, mes),
  constraint cierres_produccion_sin_solapamientos
    exclude using gist (
      daterange(fecha_desde, fecha_hasta + 1, '[)') with &&
    )
);

create or replace function public.actualizar_updated_at_cierre_produccion()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_actualizar_cierre_produccion
on public.cierres_produccion;

create trigger trg_actualizar_cierre_produccion
before update on public.cierres_produccion
for each row
execute function public.actualizar_updated_at_cierre_produccion();

alter table public.cierres_produccion enable row level security;

drop policy if exists "cierres_produccion_lectura_autenticados"
on public.cierres_produccion;

create policy "cierres_produccion_lectura_autenticados"
on public.cierres_produccion
for select
to authenticated
using (true);

drop policy if exists "cierres_produccion_gestion_director_nacional"
on public.cierres_produccion;

create policy "cierres_produccion_gestion_director_nacional"
on public.cierres_produccion
for all
to authenticated
using (
  exists (
    select 1
    from public.usuarios u
    where u.auth_id = auth.uid()
      and lower(trim(replace(u.rol_usuario, '-', '_'))) = 'director_nacional'
  )
)
with check (
  exists (
    select 1
    from public.usuarios u
    where u.auth_id = auth.uid()
      and lower(trim(replace(u.rol_usuario, '-', '_'))) = 'director_nacional'
  )
);

create index if not exists idx_cierres_produccion_fechas
on public.cierres_produccion (fecha_desde, fecha_hasta);

comment on table public.cierres_produccion is
'Calendario oficial de periodos de producción utilizado por toda la aplicación.';
