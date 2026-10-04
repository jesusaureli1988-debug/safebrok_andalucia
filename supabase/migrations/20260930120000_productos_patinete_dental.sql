-- Añade Patinete y Dental al catálogo utilizado por ventas y comisiones.
with nuevos(producto, posicion) as (
  values
    ('Patinete', 1),
    ('Dental', 2)
), base as (
  select coalesce(max(orden), 0) as ultimo_orden
  from public.comisiones_productos
)
insert into public.comisiones_productos (
  producto,
  porcentaje_comision,
  porcentaje_impuestos,
  orden
)
select
  n.producto,
  0,
  0,
  b.ultimo_orden + n.posicion
from nuevos n
cross join base b
where not exists (
  select 1
  from public.comisiones_productos existente
  where lower(trim(existente.producto)) = lower(trim(n.producto))
);