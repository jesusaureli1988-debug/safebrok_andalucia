create table if not exists public.comisiones_aseguradoras (
  id uuid primary key default gen_random_uuid(),
  compania text not null,
  producto text not null,
  porcentaje_comision numeric(7,3) not null default 0
    check (porcentaje_comision >= 0 and porcentaje_comision <= 100),
  base_calculo text not null default 'prima_neta'
    check (base_calculo in ('prima_neta', 'prima_bruta')),
  activo boolean not null default true,
  observaciones text,
  creado_por uuid references auth.users(id) on delete set null,
  actualizado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comisiones_aseguradoras_compania_producto_unique
    unique (compania, producto)
);

create or replace function public.actualizar_updated_at_comisiones_aseguradoras()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_actualizar_comisiones_aseguradoras
on public.comisiones_aseguradoras;

create trigger trg_actualizar_comisiones_aseguradoras
before update on public.comisiones_aseguradoras
for each row execute function public.actualizar_updated_at_comisiones_aseguradoras();

alter table public.comisiones_aseguradoras enable row level security;

drop policy if exists "comisiones_aseguradoras_director_nacional"
on public.comisiones_aseguradoras;

create policy "comisiones_aseguradoras_director_nacional"
on public.comisiones_aseguradoras
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

create index if not exists idx_comisiones_aseguradoras_busqueda
on public.comisiones_aseguradoras (compania, producto)
where activo = true;

comment on table public.comisiones_aseguradoras is
'Porcentajes de ingreso que cada aseguradora paga a SafeBrok por producto.';
