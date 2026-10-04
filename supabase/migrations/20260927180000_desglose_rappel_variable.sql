alter table if exists public.nominas_facturas
  add column if not exists rappel_base numeric not null default 0,
  add column if not exists diferencial_variable numeric not null default 0;

alter table if exists public.nominas_mensuales
  add column if not exists rappel_base numeric not null default 0,
  add column if not exists diferencial_variable numeric not null default 0;

comment on column public.nominas_facturas.rappel is
  'Total compatible: rappel base más diferencial variable.';
comment on column public.nominas_facturas.rappel_base is
  'Importe fijo de rappel alcanzado según figura, producción y mix.';
comment on column public.nominas_facturas.diferencial_variable is
  'Variable calculada sobre las primas que exceden el umbral de la figura.';
