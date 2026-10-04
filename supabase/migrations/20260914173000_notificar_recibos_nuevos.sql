create extension if not exists pg_net with schema extensions;

create or replace function public.app_notificar_recibos_nuevos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  payload jsonb;
begin
  select decrypted_secret
    into webhook_secret
  from vault.decrypted_secrets
  where name = 'cron_secret'
  limit 1;

  if nullif(webhook_secret, '') is null then
    raise warning 'No se envió el push de recibos: falta cron_secret en Vault.';
    return null;
  end if;

  select jsonb_build_object(
    'type', 'INSERT',
    'table', 'recibos',
    'records', coalesce(jsonb_agg(to_jsonb(recibo)), '[]'::jsonb)
  )
    into payload
  from nuevos_recibos as recibo;

  perform net.http_post(
    url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/notificar-recibo-nuevo',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', webhook_secret
    ),
    body := payload,
    timeout_milliseconds := 5000
  );

  return null;
end;
$$;

drop trigger if exists recibos_notificar_nuevos on public.recibos;

create trigger recibos_notificar_nuevos
after insert on public.recibos
referencing new table as nuevos_recibos
for each statement
execute function public.app_notificar_recibos_nuevos();

comment on function public.app_notificar_recibos_nuevos() is
  'Encola un único aviso por lote para notificar a cada responsable cuando se insertan recibos.';