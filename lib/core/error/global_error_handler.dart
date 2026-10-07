import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class GlobalErrorHandler {
  static const String _crashLogKey = 'crisis_link_crash_logs';
  
  static void recordError(Object error, StackTrace? stackTrace) async {
    try {
      AppLogger.error('Recorded Error: $error', error: error, stackTrace: stackTrace);
      
      final prefs = await SharedPreferences.getInstance();
      List<String> logs = prefs.getStringList(_crashLogKey) ?? [];
      
      final crashEntry = {
        'timestamp': DateTime.now().toIso8601String(),
        'error': error.toString(),
        'stack': stackTrace?.toString() ?? 'No stack trace',
      };
      
      logs.add(jsonEncode(crashEntry));
      if (logs.length > 20) {
        logs = logs.sublist(logs.length - 20); // Keep only the last 20
      }
      
      await prefs.setStringList(_crashLogKey, logs);
    } catch (e) {
      debugPrint('Failed to record crash log: $e');
    }
  }

  static void initialize() {
    // 1. Handle Flutter framework errors (e.g., layout, rendering)
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error('Flutter Error: ${details.exception}',
          error: details.exception, stackTrace: details.stack);
      recordError(details.exception, details.stack);
      
      if (!kReleaseMode) {
        FlutterError.presentError(details);
      }
    };

    // 2. Handle asynchronous errors outside of Flutter (e.g., Futures, streams)
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.error('Uncaught Async Error: $error',
          error: error, stackTrace: stack);
      recordError(error, stack);
      return true; // Return true prevents default unhandled exception crash
    };

    // 3. Setup a fallback UI for when a widget fails to build, 
    // avoiding the scary "Red Screen of Death"
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24.0),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 60),
              SizedBox(height: 16),
              Text(
                'Something went wrong.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Our team has been notified. Please restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    };
  }
}
