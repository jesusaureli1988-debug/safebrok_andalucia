-- Solo los usuarios con figura de agente pueden participar en la campaña.
-- La restricción se aplica en base de datos, no únicamente en la interfaz.

drop policy if exists "Los agentes consultan sus referidos" on public.referidos_campana_amigo;
create policy "Los agentes consultan sus referidos"
  on public.referidos_campana_amigo for select to authenticated
  using (
    referente_auth_id = auth.uid()
    and exists (
      select 1
      from public.usuarios u
      where u.auth_id = auth.uid()
        and lower(replace(coalesce(u.rol_usuario, ''), ' ', '_')) = 'agente'
    )
  );

drop policy if exists "Los agentes registran sus referidos" on public.referidos_campana_amigo;
create policy "Los agentes registran sus referidos"
  on public.referidos_campana_amigo for insert to authenticated
  with check (
    referente_auth_id = auth.uid()
    and exists (
      select 1
      from public.usuarios u
      where u.auth_id = auth.uid()
        and lower(replace(coalesce(u.rol_usuario, ''), ' ', '_')) = 'agente'
    )
  );

drop policy if exists "Los agentes actualizan sus referidos" on public.referidos_campana_amigo;
