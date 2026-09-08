insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('password-pages', 'password-pages', true, 1048576, array['text/html'])
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
