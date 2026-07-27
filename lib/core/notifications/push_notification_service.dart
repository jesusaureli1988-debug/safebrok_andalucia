import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance =
      PushNotificationService._();

  final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  final SupabaseClient _supabase =
      Supabase.instance.client;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  bool _initialized = false;
  bool _registrandoToken = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _initialized = true;

    try {
      await _requestPermission();

      if (Platform.isIOS) {
        await _messaging
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _listenAuthChanges();
      _listenTokenChanges();

      if (_supabase.auth.currentSession != null) {
        await registerCurrentToken();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR INICIALIZANDO PUSH NOTIFICATIONS: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );
    }
  }

  void _listenAuthChanges() {
    _authSubscription?.cancel();

    _authSubscription =
        _supabase.auth.onAuthStateChange.listen(
      (AuthState authState) async {
        debugPrint(
          'EVENTO AUTH PUSH: ${authState.event}',
        );

        final session = authState.session;

        switch (authState.event) {
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
          case AuthChangeEvent.userUpdated:
          case AuthChangeEvent.passwordRecovery:
            if (session != null) {
              await registerCurrentToken();
            }
            break;

          case AuthChangeEvent.signedOut:
            debugPrint(
              'USUARIO DESCONECTADO: el token se reasignará '
              'automáticamente en el próximo inicio de sesión.',
            );
            break;

          default:
            break;
        }
      },
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          'ERROR EN LISTENER AUTH PUSH: $error',
        );

        debugPrintStack(
          stackTrace: stackTrace,
        );
      },
    );
  }

  void _listenTokenChanges() {
    _tokenSubscription?.cancel();

    _tokenSubscription =
        _messaging.onTokenRefresh.listen(
      (String token) async {
        debugPrint(
          'FIREBASE HA RENOVADO EL TOKEN PUSH.',
        );

        await _saveToken(token);
      },
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          'ERROR EN RENOVACIÓN DEL TOKEN PUSH: $error',
        );

        debugPrintStack(
          stackTrace: stackTrace,
        );
      },
    );
  }

  Future<void> _requestPermission() async {
    final settings =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    debugPrint(
      'PERMISO NOTIFICACIONES: '
      '${settings.authorizationStatus}',
    );
  }

  Future<bool> _waitForApnsToken() async {
    if (!Platform.isIOS) return true;

    for (var intento = 1; intento <= 10; intento++) {
      final apnsToken = await _messaging.getAPNSToken();

      if (apnsToken != null &&
          apnsToken.trim().isNotEmpty) {
        debugPrint(
          'TOKEN APNS DISPONIBLE EN IOS.',
        );
        return true;
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 500),
      );
    }

    debugPrint(
      'TOKEN PUSH NO REGISTRADO: '
      'Apple todavía no ha proporcionado el token APNS.',
    );

    return false;
  }

  Future<void> registerCurrentToken() async {
    if (_registrandoToken) {
      debugPrint(
        'REGISTRO PUSH OMITIDO: '
        'ya hay otro registro en curso.',
      );
      return;
    }

    _registrandoToken = true;

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        debugPrint(
          'TOKEN PUSH NO REGISTRADO: '
          'no hay usuario autenticado.',
        );
        return;
      }

      final apnsDisponible =
          await _waitForApnsToken();

      if (!apnsDisponible) {
        return;
      }

      final token = await _messaging.getToken();

      if (token == null || token.trim().isEmpty) {
        debugPrint(
          'TOKEN PUSH NO REGISTRADO: '
          'Firebase no devolvió ningún token.',
        );
        return;
      }

      await _saveToken(token);
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR OBTENIENDO TOKEN PUSH: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );
    } finally {
      _registrandoToken = false;
    }
  }

  Future<void> _saveToken(
    String token,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      final session = _supabase.auth.currentSession;

      if (user == null || session == null) {
        debugPrint(
          'TOKEN PUSH NO GUARDADO: '
          'no existe una sesión autenticada.',
        );
        return;
      }

      final tokenLimpio = token.trim();

      if (tokenLimpio.isEmpty) {
        debugPrint(
          'TOKEN PUSH NO GUARDADO: '
          'el token está vacío.',
        );
        return;
      }

      final plataforma =
          Platform.isIOS ? 'ios' : 'android';

      await _supabase.rpc(
        'registrar_dispositivo_push',
        params: {
          'p_token': tokenLimpio,
          'p_plataforma': plataforma,
          'p_dispositivo':
              '${Platform.operatingSystem} '
              '${Platform.operatingSystemVersion}',
        },
      );

      debugPrint(
        'TOKEN PUSH REGISTRADO CORRECTAMENTE '
        'PARA EL USUARIO ${user.id} '
        'EN $plataforma.',
      );
    } on PostgrestException catch (
  error,
  stackTrace
) {
      debugPrint(
        'ERROR SUPABASE GUARDANDO TOKEN PUSH: '
        '${error.message}',
      );

      debugPrint(
        'CÓDIGO SUPABASE: ${error.code}',
      );

      debugPrint(
        'DETALLES SUPABASE: ${error.details}',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR GUARDANDO TOKEN PUSH: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );
    }
  }

  Future<String?> getCurrentToken() async {
    try {
      final apnsDisponible =
          await _waitForApnsToken();

      if (!apnsDisponible) {
        return null;
      }

      final token = await _messaging.getToken();

      if (token == null || token.trim().isEmpty) {
        return null;
      }

      return token.trim();
    } catch (error, stackTrace) {
      debugPrint(
        'ERROR LEYENDO TOKEN PUSH: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      return null;
    }
  }

  Future<void> forceRegisterCurrentToken() async {
    await registerCurrentToken();
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();

    _tokenSubscription = null;
    _authSubscription = null;

    _initialized = false;
    _registrandoToken = false;
  }
}