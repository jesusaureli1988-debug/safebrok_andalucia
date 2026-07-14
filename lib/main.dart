import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';


import 'core/auth/login_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/Navigation/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ytmxjavihwylrswphczc.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0bXhqYXZpaHd5bHJzd3BoY3pjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4Njc3MzIsImV4cCI6MjA5NTQ0MzczMn0.4Jl8_law7AKDOF99sV3HlvTE1a0aSPohOXe1mK2hvcs',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
     
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
  return MaterialApp(
  debugShowCheckedModeBanner: false,
  home: const SplashScreen(),

  localizationsDelegates: [
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