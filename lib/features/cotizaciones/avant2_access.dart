import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final avant2Portal = Uri.parse('https://dapeal.avant2.es/login');

Future<void> openAvant2(BuildContext context) async {
  try {
    if (!await launchUrl(avant2Portal, mode: LaunchMode.externalApplication)) {
      throw StateError('No se pudo abrir el navegador');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir Avant2. Inténtalo de nuevo desde tu navegador: https://dapeal.avant2.es/login',
          ),
        ),
      );
    }
  }
}
