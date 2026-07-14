import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/features/navigation/main_shell.dart';

class RoleRouter {
  static Widget getHomeByRole(String role) {
    return MainShell(role: role);
  }
}