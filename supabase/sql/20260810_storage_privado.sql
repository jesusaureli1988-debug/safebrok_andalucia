-- SafeBrok: buckets privados y acceso a objetos sujeto a identidad/RLS.
begin;

update storage.buckets
set public = false
where id in ('chat-archivos', 'cv_candidatos', 'gestiones-archivos');

drop policy if exists app_chat_archivos_select on storage.objects;
create policy app_chat_archivos_select on storage.objects for select to authenticated
using (
  bucket_id = 'chat-archivos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (storage.foldername(name))[2] = auth.uid()::text
  )
);

drop policy if exists app_chat_archivos_insert on storage.objects;
create policy app_chat_archivos_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-archivos'
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.app_can_access_auth_id((storage.foldername(name))[2])
);

drop policy if exists app_chat_archivos_update on storage.objects;
create policy app_chat_archivos_update on storage.objects for update to authenticated
using (bucket_id = 'chat-archivos' and owner_id = auth.uid()::text)
with check (bucket_id = 'chat-archivos' and owner_id = auth.uid()::text);
drop policy if exists app_chat_archivos_delete on storage.objects;
create policy app_chat_archivos_delete on storage.objects for delete to authenticated
using (bucket_id = 'chat-archivos' and owner_id = auth.uid()::text);

drop policy if exists app_gestiones_archivos_select on storage.objects;
create policy app_gestiones_archivos_select on storage.objects for select to authenticated
using (
  bucket_id = 'gestiones-archivos'
  and (
    public.app_can_access_auth_id((storage.foldername(name))[1])
    or (
      (storage.foldername(name))[1] = 'respuestas'
      and exists (
        select 1 from public.gestiones_asignadas g
        where g.id::text = (storage.foldername(name))[2]
      )
    )
  )
);

drop policy if exists app_gestiones_archivos_insert on storage.objects;
create policy app_gestiones_archivos_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'gestiones-archivos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'respuestas'
      and exists (
        select 1 from public.gestiones_asignadas g
        where g.id::text = (storage.foldername(name))[2]
      )
    )
  )
);

drop policy if exists app_gestiones_archivos_update on storage.objects;
create policy app_gestiones_archivos_update on storage.objects for update to authenticated
using (bucket_id = 'gestiones-archivos' and owner_id = auth.uid()::text)
with check (bucket_id = 'gestiones-archivos' and owner_id = auth.uid()::text);
drop policy if exists app_gestiones_archivos_delete on storage.objects;
create policy app_gestiones_archivos_delete on storage.objects for delete to authenticated
using (bucket_id = 'gestiones-archivos' and owner_id = auth.uid()::text);

drop policy if exists app_cv_candidatos_select on storage.objects;
create policy app_cv_candidatos_select on storage.objects for select to authenticated
using (
  bucket_id = 'cv_candidatos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
      select 1 from public.candidatos_captacion c
      where c.cv_url = 'storage://cv_candidatos/' || name
         or c.cv_url like '%/storage/v1/object/public/cv_candidatos/' || name
    )
  )
);

drop policy if exists app_cv_candidatos_insert on storage.objects;
create policy app_cv_candidatos_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'cv_candidatos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists app_cv_candidatos_update on storage.objects;
create policy app_cv_candidatos_update on storage.objects for update to authenticated
using (bucket_id = 'cv_candidatos' and owner_id = auth.uid()::text)
with check (bucket_id = 'cv_candidatos' and owner_id = auth.uid()::text);
drop policy if exists app_cv_candidatos_delete on storage.objects;
create policy app_cv_candidatos_delete on storage.objects for delete to authenticated
using (bucket_id = 'cv_candidatos' and owner_id = auth.uid()::text);

commit;
