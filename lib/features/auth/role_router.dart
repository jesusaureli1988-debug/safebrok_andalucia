import 'package:flutter/material.dart';
import '../navigation/main_shell.dart';

class RoleRouter {
  static Widget getHomeByRole(String role) {
    return MainShell(role: role);
  }
}