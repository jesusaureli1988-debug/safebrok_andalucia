# SafeBrok 1.2.2 (13)

## Cambios incluidos

- Producción y cálculos económicos de pólizas por fecha de efecto.
- Periodos de cargo según los cierres de producción configurados.
- Consultas de ventas completas, sin truncar la carga a 1.000 registros.
- Importación de pólizas: normalización de columnas, valores ausentes y control de duplicados.
- Ventas sin agente y reasignación en el panel autorizado.
- Presentación progresiva de listados en bloques de diez.

## Alcance y comprobaciones antes de publicar

- La paginación visual no convierte las consultas completas de Supabase en descarga bajo demanda de diez registros. Esa optimización sigue pendiente.
- No se han recalculado ni modificado facturas o nóminas históricas de Supabase.
- Las migraciones de base de datos no se ejecutan al instalar la APK. Confirmar que están aplicadas las migraciones de pólizas pendientes y reasignación de 2026-10-07 antes de usar esas funciones.
- Android conserva el identificador y la firma de distribución anteriores; no cambiar la clave durante esta actualización.
- Probar la instalación sobre una APK ya instalada, acceso, ventas, recibos e importación antes de activar la fila de Android en app_versions.
- No se ha publicado ni subido automáticamente ningún archivo ni cambiado app_versions.

Versión de Android para app_versions, tras subir y probar el archivo: `1.2.2+13`.

## Resultado de la revisión y compilación

- `flutter test --no-pub`: 33 pruebas superadas.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: finalizó con código 0, sin errores; quedan advertencias y recomendaciones.
- `flutter build apk --release --no-pub`: compilación correcta.
- Versión leída del APK: `1.2.2`, código `13`.
- APK para subir: `D:\safebrok_andalucia\releases\SafeBrok_1.2.2_13.apk`.
- Tamaño: 83.451.167 bytes.
- SHA-256 del archivo: `A32C6F61C334D96FFF722DBF46D34FE726D6064015ED14C8FC9793A4C7A817BE`.
- Firma Android verificada y certificado coincidente con la APK anterior local; se conserva la clave de depuración usada por la distribución anterior.
- APK anterior conservada en `releases\archive\SafeBrok_1.2.0_11.apk`.
- Pendiente de prueba de instalación y uso en un dispositivo Android real antes de publicar.
