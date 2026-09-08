begin;
create table if not exists public.previsiones_mensuales (
 id uuid primary key default gen_random_uuid(),
 usuario_auth_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 periodo date not null,
 ambito text not null check (ambito in ('propias','equipo')),
 primas_objetivo numeric(14,2) not null default 0 check (primas_objetivo>=0),
 decesos_vida_objetivo numeric(14,2) not null default 0 check (decesos_vida_objetivo>=0),
 incorporaciones_objetivo integer not null default 0 check (incorporaciones_objetivo>=0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(periodo=date_trunc('month',periodo)::date),
 check(decesos_vida_objetivo<=primas_objetivo),
 unique(usuario_auth_id,periodo,ambito)
);
create index if not exists previsiones_mensuales_usuario_periodo_idx on public.previsiones_mensuales(usuario_auth_id,periodo desc);
create or replace function public.previsiones_before_write() returns trigger language plpgsql security definer set search_path='' as $$
declare rol_actual text;
begin
 new.periodo:=date_trunc('month',new.periodo)::date; new.updated_at:=now();
 select lower(trim(replace(coalesce(rol_usuario,''),'-','_'))) into rol_actual from public.usuarios where auth_id=auth.uid() limit 1;
 if new.usuario_auth_id<>auth.uid() then raise exception 'Solo puedes guardar tus propias previsiones'; end if;
 if new.ambito='equipo' and rol_actual='agente' then raise exception 'Los agentes no pueden registrar previsiones de equipo'; end if;
 return new;
end $$;
drop trigger if exists previsiones_before_write_trg on public.previsiones_mensuales;
create trigger previsiones_before_write_trg before insert or update on public.previsiones_mensuales for each row execute function public.previsiones_before_write();
alter table public.previsiones_mensuales enable row level security;
drop policy if exists previsiones_select_propias on public.previsiones_mensuales;
create policy previsiones_select_propias on public.previsiones_mensuales for select to authenticated using(usuario_auth_id=auth.uid());
drop policy if exists previsiones_insert_propias on public.previsiones_mensuales;
create policy previsiones_insert_propias on public.previsiones_mensuales for insert to authenticated with check(usuario_auth_id=auth.uid());
drop policy if exists previsiones_update_propias on public.previsiones_mensuales;
create policy previsiones_update_propias on public.previsiones_mensuales for update to authenticated using(usuario_auth_id=auth.uid()) with check(usuario_auth_id=auth.uid());
grant select,insert,update on public.previsiones_mensuales to authenticated;
commit;