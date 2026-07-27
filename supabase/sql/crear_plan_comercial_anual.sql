create table if not exists public.objetivos_comerciales_anuales (
  id uuid primary key default gen_random_uuid(),
  anio integer not null check (anio between 2024 and 2100),
  usuario_auth_id uuid not null references auth.users(id) on delete cascade,
  usuario_nombre text not null,
  usuario_rol text not null check (
    usuario_rol in (
      'jefe_equipo',
      'jefe_ventas',
      'director_zona',
      'director_nacional'
    )
  ),
  incremento_prima_sin_vehiculos numeric(14,2) not null default 0,
  incremento_asegurados numeric(14,2) not null default 0,
  incremento_ventas_netas numeric(14,2) not null default 0,
  porcentaje_pendiente numeric(7,2) not null default 0,
  anulaciones_decesos numeric(14,2) not null default 0,
  anulaciones_resto numeric(14,2) not null default 0,
  ventas_netas numeric(14,2) not null default 0,
  facturacion numeric(14,2) not null default 0,
  captacion numeric(14,2) not null default 0,
  liquido_decesos numeric(14,2) not null default 0,
  observaciones text,
  creado_por uuid references auth.users(id) on delete set null,
  actualizado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint objetivos_comerciales_anuales_usuario_unique
    unique (anio, usuario_auth_id)
);

create or replace function public.actualizar_updated_at_objetivos_anuales()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_actualizar_objetivos_anuales
on public.objetivos_comerciales_anuales;

create trigger trg_actualizar_objetivos_anuales
before update on public.objetivos_comerciales_anuales
for each row execute function public.actualizar_updated_at_objetivos_anuales();

alter table public.objetivos_comerciales_anuales enable row level security;

drop policy if exists "objetivos_anuales_lectura_figuras"
on public.objetivos_comerciales_anuales;

create policy "objetivos_anuales_lectura_figuras"
on public.objetivos_comerciales_anuales
for select
to authenticated
using (
  exists (
    select 1
    from public.usuarios u
    where u.auth_id = auth.uid()
      and u.rol_usuario in (
        'jefe_equipo',
        'jefe_ventas',
        'director_zona',
        'director_nacional'
      )
  )
);

drop policy if exists "objetivos_anuales_gestion_director_nacional"
on public.objetivos_comerciales_anuales;

create policy "objetivos_anuales_gestion_director_nacional"
on public.objetivos_comerciales_anuales
for all
to authenticated
using (
  exists (
    select 1
    from public.usuarios u
    where u.auth_id = auth.uid()
      and u.rol_usuario = 'director_nacional'
  )
)
with check (
  exists (
    select 1
    from public.usuarios u
    where u.auth_id = auth.uid()
      and u.rol_usuario = 'director_nacional'
  )
);

create index if not exists idx_objetivos_anuales_usuario
on public.objetivos_comerciales_anuales (usuario_auth_id, anio);

comment on table public.objetivos_comerciales_anuales is
'Plan Comercial Anual de las figuras de liderazgo de SafeBrok.';
