import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/features/navigation/main_shell.dart';
import 'app_role.dart';

class RoleRouter {
  static Widget getHomeByRole(String role) {
    final appRole = AppRole.from(role);
    if (appRole == null) {
      throw ArgumentError.value(role, 'role', 'Rol de SafeBrok no reconocido');
    }
    return MainShell(role: appRole.value);
  }
}
