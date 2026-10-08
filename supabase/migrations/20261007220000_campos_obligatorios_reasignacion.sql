-- Valores ausentes en pendientes importadas antes de la correccion.
begin;
create or replace function public.app_asignar_polizas_pendientes(
  p_ids uuid[], p_agente_auth_id uuid
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  p public.polizas_pendientes_asignacion;
  c public.clientes;
  v public.ventas;
  cliente_id_actual uuid;
  total integer := 0;
begin
  if auth.uid() is null or not exists (
    select 1 from public.usuarios u where u.auth_id = auth.uid()
      and replace(replace(lower(btrim(u.rol_usuario)), '-', '_'), ' ', '_') = 'director_nacional'
      and public.app_estado_usuario_activo(u.estado)
  ) then raise exception 'Solo el director nacional puede reasignar estas pólizas'; end if;
  if not exists(select 1 from public.usuarios u where u.auth_id = p_agente_auth_id
    and public.app_estado_usuario_activo(u.estado)) then
    raise exception 'El mediador seleccionado no existe o está inactivo';
  end if;
  if coalesce(cardinality(p_ids), 0) = 0 or cardinality(p_ids) > 100 then
    raise exception 'Selecciona entre 1 y 100 pólizas por lote';
  end if;
  for p in select * from public.polizas_pendientes_asignacion
    where id = any(p_ids) order by id for update
  loop
    if exists(select 1 from public.ventas where upper(btrim(numero_poliza)) = p.numero_poliza) then
      raise exception 'La póliza % ya está registrada. No se ha modificado', p.numero_poliza;
    end if;
    c := jsonb_populate_record(null::public.clientes, p.cliente_datos);
    v := jsonb_populate_record(null::public.ventas, p.venta_datos);
    cliente_id_actual := null;
    if nullif(btrim(c.dni), '') is not null then
      select id into cliente_id_actual from public.clientes
      where auth_id = p_agente_auth_id and upper(btrim(dni)) = upper(btrim(c.dni)) limit 1;
    elsif nullif(btrim(c.email), '') is not null then
      select id into cliente_id_actual from public.clientes
      where auth_id = p_agente_auth_id and lower(btrim(email)) = lower(btrim(c.email)) limit 1;
    end if;
    if cliente_id_actual is null then
      insert into public.clientes(auth_id,nombre,apellidos,telefono,email,codigo_postal,
        provincia,poblacion,direccion,numero,dni)
      values(p_agente_auth_id,c.nombre,c.apellidos,coalesce(c.telefono,''),coalesce(c.email,''),c.codigo_postal,
        coalesce(nullif(btrim(c.provincia), ''), 'No informada'),c.poblacion,c.direccion,coalesce(nullif(btrim(c.numero), ''), 'No informado'),c.dni)
      returning id into cliente_id_actual;
    end if;
    insert into public.ventas(cliente_id,agente_auth_id,producto,compania,forma_pago,
      precio,numero_asegurados,fecha_efecto,prima_anual,prima_anual_bruta,
      prima_anual_neta,comision,categoria_producto,numero_poliza,estado_poliza)
    values(cliente_id_actual,p_agente_auth_id,v.producto,v.compania,coalesce(nullif(btrim(v.forma_pago), ''), 'No informada'),
      v.precio,v.numero_asegurados,v.fecha_efecto,v.prima_anual,v.prima_anual_bruta,
      v.prima_anual_neta,coalesce(v.comision,0),v.categoria_producto,p.numero_poliza,v.estado_poliza);
    delete from public.polizas_pendientes_asignacion where id = p.id;
    total := total + 1;
  end loop;
  return total;
end; $$;
commit;
