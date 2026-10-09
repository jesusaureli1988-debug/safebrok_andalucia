# Correccion iOS ITMS-91061

- Mantener version App Store 1.2.2 y usar build minimo 14.
- Actualizar package_info_plus de 4.2.0 a 8.3.1 con manifiesto de privacidad.
- Codemagic verifica el manifiesto del SDK en el IPA final antes de publicar.
- El numero de build se incrementa tambien consultando App Store Connect.
- No incluir los cambios pendientes de home_screen, production_period_service,
  home_ranking_service ni sus dos nuevos tests: quedan para otra actualizacion.
- No modificar las versiones de la tabla de actualizaciones Android/Windows:
  sus APK e instaladores existentes no se han regenerado.

La compilacion y comprobacion del IPA real requieren el Mac de Codemagic.
Esta correccion aborda el SDK especifico que menciona Apple, no garantiza
ausencia de otros avisos ni aprobacion de la revision.
