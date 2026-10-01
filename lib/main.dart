import 'package:flutter/material.dart';
import 'core/theme/design_system.dart';
import 'presentation/screens/main_navigation.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'core/error/global_error_handler.dart';
import 'core/auth/auth_manager.dart';

import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    )
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  GlobalErrorHandler.initialize();
  await AuthManager.initialize();
  runApp(const CrsisLinkApp());
}

class CrsisLinkApp extends StatelessWidget {
  const CrsisLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crsis Link',
      theme: AppTheme.lightTheme,
      home: const MainNavigation(),
      routes: {
        '/main': (context) => const MainNavigation(),
      },
      builder: (context, widget) {
        return widget ?? const SizedBox();
      },
    );
  }
}

