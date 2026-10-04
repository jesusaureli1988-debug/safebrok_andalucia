-- Campaña comercial "Trae a un amigo".
-- Se mantiene separada de nóminas/facturas: por ahora solo registra
-- la recomendación y deja trazada la recompensa pactada del 2 %.

create table if not exists public.referidos_campana_amigo (
  id uuid primary key default gen_random_uuid(),
  referente_auth_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null check (char_length(trim(nombre)) >= 2),
  apellidos text not null check (char_length(trim(apellidos)) >= 2),
  email text not null,
  telefono text,
  ciudad text,
  observaciones text,
  cv_url text,
  estado text not null default 'PENDIENTE_REVISION'
    check (estado in (
      'PENDIENTE_REVISION',
      'CONTACTADO',
      'EN_PROCESO',
      'INCORPORADO',
      'DESCARTADO'
    )),
  porcentaje_recompensa numeric(5,2) not null default 2.00
    check (porcentaje_recompensa = 2.00),
  candidato_auth_id uuid references auth.users(id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (referente_auth_id, email)
);

create index if not exists referidos_campana_amigo_referente_idx
  on public.referidos_campana_amigo (referente_auth_id, creado_en desc);

alter table public.referidos_campana_amigo enable row level security;

drop policy if exists "Los agentes consultan sus referidos" on public.referidos_campana_amigo;
create policy "Los agentes consultan sus referidos"
  on public.referidos_campana_amigo for select to authenticated
  using (referente_auth_id = auth.uid());

drop policy if exists "Los agentes registran sus referidos" on public.referidos_campana_amigo;
create policy "Los agentes registran sus referidos"
  on public.referidos_campana_amigo for insert to authenticated
  with check (referente_auth_id = auth.uid());

drop policy if exists "Los agentes actualizan sus referidos" on public.referidos_campana_amigo;
create policy "Los agentes actualizan sus referidos"
  on public.referidos_campana_amigo for update to authenticated
  using (referente_auth_id = auth.uid())
  with check (referente_auth_id = auth.uid());

create or replace function public.actualizar_referido_campana_amigo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado_en = now();
  return new;
end;
$$;

drop trigger if exists trg_actualizar_referido_campana_amigo
  on public.referidos_campana_amigo;
create trigger trg_actualizar_referido_campana_amigo
before update on public.referidos_campana_amigo
for each row execute function public.actualizar_referido_campana_amigo();

comment on table public.referidos_campana_amigo is
  'Recomendaciones de la campaña Trae a un amigo. La recompensa del 2% se define aquí, pero no se liquida todavía.';
