import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';

import 'core/auth/password_recovery_state.dart';
import 'core/auth/reset_password_screen.dart';
import 'core/notifications/push_notification_service.dart';
import 'features/splash/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  if (isMobile) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  await Supabase.initialize(
    url: 'https://ytmxjavihwylrswphczc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0bXhqYXZpaHd5bHJzd3BoY3pjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4Njc3MzIsImV4cCI6MjA5NTQ0MzczMn0.4Jl8_law7AKDOF99sV3HlvTE1a0aSPohOXe1mK2hvcs',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );

  if (isMobile) {
    await PushNotificationService.instance.initialize();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<AuthState>? _authSubscription;

  bool _navigatorReady = false;
  bool _recoveryPending = false;
  bool _resetScreenOpened = false;

  @override
  void initState() {
    super.initState();

    _listenForPasswordRecovery();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorReady = true;

      if (_recoveryPending) {
        _openResetPasswordScreen();
      }
    });
  }

  void _listenForPasswordRecovery() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(
      (AuthState authState) {
        debugPrint(
          'SUPABASE AUTH EVENT: ${authState.event} | '
          'SESSION: ${authState.session != null}',
        );

        if (authState.event == AuthChangeEvent.passwordRecovery) {
          PasswordRecoveryState.start();
          _recoveryPending = true;

          if (_navigatorReady) {
            _openResetPasswordScreen();
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'ERROR EN SUPABASE AUTH LISTENER: $error',
        );
      },
    );
  }

  void _openResetPasswordScreen() {
    if (_resetScreenOpened) return;

    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      Future.delayed(
        const Duration(milliseconds: 150),
        _openResetPasswordScreen,
      );
      return;
    }

    _resetScreenOpened = true;
    _recoveryPending = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentNavigator = navigatorKey.currentState;

      if (currentNavigator == null) {
        _resetScreenOpened = false;
        _recoveryPending = true;
        return;
      }

      currentNavigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ResetPasswordScreen(),
        ),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
    );
  }
}
