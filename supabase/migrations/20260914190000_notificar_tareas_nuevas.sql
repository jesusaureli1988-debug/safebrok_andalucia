create extension if not exists pg_net with schema extensions;

create or replace function public.app_notificar_tarea_nueva()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  notification_reason text;
begin
  select decrypted_secret
    into webhook_secret
  from vault.decrypted_secrets
  where name = 'cron_secret'
  limit 1;

  if nullif(webhook_secret, '') is null then
    raise warning 'No se envió el push de tareas: falta cron_secret en Vault.';
    return null;
  end if;

  notification_reason := case
    when tg_op = 'UPDATE' then 'reasignacion'
    else 'creacion'
  end;

  perform net.http_post(
    url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/notificar-tarea-nueva',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', webhook_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'motivo', notification_reason,
      'record', to_jsonb(new)
    ),
    timeout_milliseconds := 5000
  );

  return null;
end;
$$;

drop trigger if exists gestiones_notificar_nueva on public.gestiones_asignadas;
drop trigger if exists gestiones_notificar_reasignacion on public.gestiones_asignadas;

create trigger gestiones_notificar_nueva
after insert on public.gestiones_asignadas
for each row
execute function public.app_notificar_tarea_nueva();

create trigger gestiones_notificar_reasignacion
after update of asignado_a_auth_id on public.gestiones_asignadas
for each row
when (
  old.asignado_a_auth_id is distinct from new.asignado_a_auth_id
)
execute function public.app_notificar_tarea_nueva();

comment on function public.app_notificar_tarea_nueva() is
  'Encola el aviso push al crear o reasignar una tarea de SafeBrok.';