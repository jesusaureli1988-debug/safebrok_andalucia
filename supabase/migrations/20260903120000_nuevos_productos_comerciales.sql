-- Amplía el catálogo oficial utilizado por ventas, comisiones, impuestos y nóminas.
with nuevos(producto, posicion) as (
  values
    ('Transportes construcción', 1),
    ('Caución', 2),
    ('Camión', 3),
    ('Decenal', 4),
    ('Pymes', 5),
    ('Accidentes colectivos', 6),
    ('Salud colectivo', 7),
    ('Transportes', 8)
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