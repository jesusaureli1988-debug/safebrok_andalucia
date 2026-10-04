create extension if not exists pg_net with schema extensions;
create or replace function public.app_notificar_venta_nueva()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare webhook_secret text;
begin
 select decrypted_secret into webhook_secret from vault.decrypted_secrets where name='cron_secret' limit 1;
 if nullif(webhook_secret,'') is null then raise warning 'No se notificó la venta: falta cron_secret en Vault.'; return null; end if;
 perform net.http_post(
  url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/notificar-venta-nueva',
  headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',webhook_secret),
  body := jsonb_build_object('type','INSERT','table','ventas','record',to_jsonb(new)),
  timeout_milliseconds := 30000
 );
 return null;
end;
$$;
drop trigger if exists ventas_notificar_superiores on public.ventas;
create trigger ventas_notificar_superiores after insert on public.ventas
for each row execute function public.app_notificar_venta_nueva();
comment on function public.app_notificar_venta_nueva() is 'Notifica en campanita y por push a todos los superiores activos cuando se registra una venta.';
