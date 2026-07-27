import 'package:flutter/foundation.dart';

class PasswordRecoveryState {
  PasswordRecoveryState._();

  static final ValueNotifier<bool> active =
      ValueNotifier<bool>(false);

  static void start() {
    active.value = true;
  }

  static void finish() {
    active.value = false;
  }
}
