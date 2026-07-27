create table if not exists public.programaciones_informes_comerciales (
  id uuid primary key default gen_random_uuid(),
  owner_auth_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  tipo_informe text not null check (
    tipo_informe in (
      'objetivo_individual',
      'objetivos_generales',
      'estructura',
      'ventas',
      'anulaciones',
      'recibos',
      'captacion'
    )
  ),
  parametro_objetivo text check (
    parametro_objetivo is null or parametro_objetivo in (
      'incremento_prima_sin_vehiculos',
      'incremento_asegurados',
      'incremento_ventas_netas',
      'porcentaje_pendiente',
      'anulaciones_decesos',
      'anulaciones_resto',
      'ventas_netas',
      'facturacion',
      'captacion',
      'liquido_decesos'
    )
  ),
  frecuencia text not null check (frecuencia in ('diaria', 'semanal', 'mensual')),
  dia_semana smallint check (dia_semana between 1 and 7),
  dia_mes smallint check (dia_mes between 1 and 28),
  email_destino text not null,
  incluir_detalle boolean not null default true,
  activa boolean not null default true,
  proxima_ejecucion timestamptz not null,
  ultima_ejecucion timestamptz,
  ultimo_estado text,
  ultimo_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint programacion_objetivo_unico check (
    (tipo_informe = 'objetivo_individual' and parametro_objetivo is not null)
    or
    (tipo_informe <> 'objetivo_individual' and parametro_objetivo is null)
  ),
  constraint programacion_frecuencia_dias check (
    (frecuencia = 'diaria' and dia_semana is null and dia_mes is null)
    or
    (frecuencia = 'semanal' and dia_semana is not null and dia_mes is null)
    or
    (frecuencia = 'mensual' and dia_semana is null and dia_mes is not null)
  )
);

create table if not exists public.informes_comerciales_generados (
  id uuid primary key default gen_random_uuid(),
  owner_auth_id uuid not null references auth.users(id) on delete cascade,
  programacion_id uuid references public.programaciones_informes_comerciales(id)
    on delete set null,
  tipo_informe text not null,
  parametro_objetivo text,
  frecuencia text not null,
  periodo_desde timestamptz not null,
  periodo_hasta timestamptz not null,
  nombre_archivo text not null,
  storage_path text,
  safecloud_item_id uuid,
  email_destino text,
  estado text not null default 'generando' check (
    estado in ('generando', 'generado', 'enviado', 'fallido')
  ),
  proveedor_email_id text,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists idx_programaciones_informes_pendientes
on public.programaciones_informes_comerciales (activa, proxima_ejecucion);

create index if not exists idx_programaciones_informes_owner
on public.programaciones_informes_comerciales (owner_auth_id, created_at desc);

create index if not exists idx_informes_generados_owner
on public.informes_comerciales_generados (owner_auth_id, created_at desc);

create or replace function public.actualizar_updated_at_informes_comerciales()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_programaciones_informes_updated_at
on public.programaciones_informes_comerciales;

create trigger trg_programaciones_informes_updated_at
before update on public.programaciones_informes_comerciales
for each row execute function public.actualizar_updated_at_informes_comerciales();

alter table public.programaciones_informes_comerciales enable row level security;
alter table public.informes_comerciales_generados enable row level security;

drop policy if exists "programaciones_propias_select"
on public.programaciones_informes_comerciales;
create policy "programaciones_propias_select"
on public.programaciones_informes_comerciales
for select to authenticated
using (owner_auth_id = auth.uid());

drop policy if exists "programaciones_propias_insert"
on public.programaciones_informes_comerciales;
create policy "programaciones_propias_insert"
on public.programaciones_informes_comerciales
for insert to authenticated
with check (
  owner_auth_id = auth.uid()
  and exists (
    select 1 from public.usuarios u
    where u.auth_id = auth.uid()
      and u.rol_usuario in (
        'jefe_equipo', 'jefe_ventas', 'director_zona', 'director_nacional'
      )
  )
);

drop policy if exists "programaciones_propias_update"
on public.programaciones_informes_comerciales;
create policy "programaciones_propias_update"
on public.programaciones_informes_comerciales
for update to authenticated
using (owner_auth_id = auth.uid())
with check (owner_auth_id = auth.uid());

drop policy if exists "programaciones_propias_delete"
on public.programaciones_informes_comerciales;
create policy "programaciones_propias_delete"
on public.programaciones_informes_comerciales
for delete to authenticated
using (owner_auth_id = auth.uid());

drop policy if exists "informes_generados_propios_select"
on public.informes_comerciales_generados;
create policy "informes_generados_propios_select"
on public.informes_comerciales_generados
for select to authenticated
using (owner_auth_id = auth.uid());

comment on table public.programaciones_informes_comerciales is
'Programaciones independientes de informes comerciales enviados a las 05:00 Europe/Madrid.';

comment on table public.informes_comerciales_generados is
'Historial de PDF comerciales generados, enviados y guardados en SafeCloud.';

-- El trabajo consulta cada cinco minutos, pero la función solo procesa
-- programaciones cuya proxima_ejecucion ya haya llegado. Así se respeta
-- siempre las 05:00 Europe/Madrid, incluido el cambio CET/CEST.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'informes-plan-comercial-pendientes';

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
end;
$$;

select cron.schedule(
  'informes-plan-comercial-pendientes',
  '*/5 * * * *',
  $cron$
  select net.http_post(
    url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/informes-plan-comercial',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'cron_secret'
        limit 1
      )
    ),
    body := '{"action":"process_due"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
