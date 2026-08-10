-- Solicitudes de eliminación iniciadas dentro de la app.
begin;

create table if not exists public.solicitudes_eliminacion_cuenta (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid not null,
  email text,
  motivo text,
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'en_proceso', 'completada', 'cancelada')),
  solicitado_at timestamptz not null default now(),
  fecha_limite timestamptz not null default (now() + interval '30 days'),
  procesado_at timestamptz,
  procesado_por uuid,
  notas_administracion text
);

create unique index if not exists solicitudes_eliminacion_pendiente_uidx
  on public.solicitudes_eliminacion_cuenta (auth_id)
  where estado in ('pendiente', 'en_proceso');

alter table public.solicitudes_eliminacion_cuenta enable row level security;
revoke all on table public.solicitudes_eliminacion_cuenta from anon;
grant select, insert, update on table public.solicitudes_eliminacion_cuenta to authenticated;

drop policy if exists app_solicitud_eliminacion_select on public.solicitudes_eliminacion_cuenta;
create policy app_solicitud_eliminacion_select
on public.solicitudes_eliminacion_cuenta for select to authenticated
using (auth_id = auth.uid() or public.app_can_manage_global());

drop policy if exists app_solicitud_eliminacion_insert on public.solicitudes_eliminacion_cuenta;
create policy app_solicitud_eliminacion_insert
on public.solicitudes_eliminacion_cuenta for insert to authenticated
with check (auth_id = auth.uid() and estado = 'pendiente');

drop policy if exists app_solicitud_eliminacion_cancel on public.solicitudes_eliminacion_cuenta;
create policy app_solicitud_eliminacion_cancel
on public.solicitudes_eliminacion_cuenta for update to authenticated
using (auth_id = auth.uid() and estado = 'pendiente')
with check (auth_id = auth.uid() and estado = 'cancelada');

drop policy if exists app_solicitud_eliminacion_manage on public.solicitudes_eliminacion_cuenta;
create policy app_solicitud_eliminacion_manage
on public.solicitudes_eliminacion_cuenta for update to authenticated
using (public.app_can_manage_global())
with check (public.app_can_manage_global());

commit;
