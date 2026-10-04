create or replace function public.app_notificar_venta_nueva()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  public_anon_key constant text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0bXhqYXZpaHd5bHJzd3BoY3pjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4Njc3MzIsImV4cCI6MjA5NTQ0MzczMn0.4Jl8_law7AKDOF99sV3HlvTE1a0aSPohOXe1mK2hvcs';
begin
  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets
  where name = 'cron_secret'
  limit 1;

  if nullif(webhook_secret, '') is null then
    raise warning 'No se notificó la venta: falta cron_secret en Vault.';
    return null;
  end if;

  perform net.http_post(
    url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/notificar-venta-nueva',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || public_anon_key,
      'apikey', public_anon_key,
      'x-cron-secret', webhook_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'ventas',
      'record', to_jsonb(new)
    ),
    timeout_milliseconds := 30000
  );
  return null;
end;
$$;
