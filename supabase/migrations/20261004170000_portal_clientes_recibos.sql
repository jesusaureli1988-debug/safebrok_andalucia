drop policy if exists recibos_portal_cliente_select on public.recibos;

create policy recibos_portal_cliente_select
  on public.recibos
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.ventas v
      where upper(btrim(coalesce(v.numero_poliza, ''))) =
            upper(btrim(coalesce(recibos.poliza, '')))
        and public.portal_cliente_tiene_acceso(v.cliente_id)
    )
  );

comment on policy recibos_portal_cliente_select on public.recibos is
  'Permite al cliente autenticado consultar los recibos de sus propias polizas.';