begin;
drop policy if exists previsiones_select_propias on public.previsiones_mensuales;
create policy previsiones_select_estructura
on public.previsiones_mensuales
for select to authenticated
using (
  usuario_auth_id = auth.uid()
  or public.app_can_manage_global()
  or exists (
    select 1
    from public.usuarios u
    where u.auth_id = previsiones_mensuales.usuario_auth_id
      and public.app_can_access_user_id(u.id)
  )
);
commit;