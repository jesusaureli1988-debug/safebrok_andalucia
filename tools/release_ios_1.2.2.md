# SafeBrok iOS 1.2.2 - Codemagic

Seleccionar la rama `main` y el workflow `iOS Release SafeBrok` (`ios-release`).

- Se conserva la app existente: `com.safebrok`, Apple ID `6787038104`.
- Se conserva la integracion `Codemagic Safebrok` y los nombres de firma existentes.
- Flutter se fija en 3.41.9, el SDK usado para verificar esta version.
- Se ejecutan el analisis Dart y todos los tests antes de generar el IPA.
- La compilacion usa como minimo el numero 13 y consulta Apple para incrementar
  el ultimo numero disponible, evitando reutilizar una compilacion ya subida.
- El IPA se sube a App Store Connect. No se envia automaticamente a revision
  de App Store ni a revision beta externa: esos pasos siguen siendo manuales.

No iniciar dos compilaciones simultaneas de esta version: ambas podrian consultar
el mismo numero antes de que Apple procese una de ellas.

La firma, CocoaPods, compilacion nativa y subida a Apple se verifican realmente
en el Mac de Codemagic; no pueden garantizarse desde Windows. Los certificados,
perfiles e integracion deben seguir activos en la cuenta de Codemagic.

Esta preparacion no modifica ni migra la base de datos de Supabase. Los scripts
SQL incluidos en el repositorio no se ejecutan durante esta compilacion.
La paginacion visual de listas esta incluida; la descarga de todas las consultas
desde Supabase en lotes de 10 sigue siendo un trabajo independiente pendiente.

Referencia de numeracion automatica:
https://docs.codemagic.io/knowledge-codemagic/build-versioning/
