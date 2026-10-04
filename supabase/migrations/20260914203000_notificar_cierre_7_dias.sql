create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
do $$
declare existing_job bigint;
begin
 select jobid into existing_job from cron.job where jobname='notificar-cierre-produccion-7-dias';
 if existing_job is not null then perform cron.unschedule(existing_job); end if;
 perform cron.schedule('notificar-cierre-produccion-7-dias','0 * * * *',
 $cron$
  select net.http_post(
   url := 'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/notificar-cierre-7-dias',
   headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='cron_secret' limit 1)),
   body := '{}'::jsonb, timeout_milliseconds := 120000
  );
 $cron$);
end;
$$;