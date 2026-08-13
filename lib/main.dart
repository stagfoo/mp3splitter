import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'crash_log.dart';
import 'crash_log_file.dart';
import 'home_screen.dart';

Future<void> main() async {
  // Set once the app documents path resolves, inside the zone below. A
  // crash before that (vanishingly unlikely — it's the very first thing
  // that happens) just isn't logged; simpler than making the logger itself
  // handle a path that isn't ready yet.
  String? crashLogPath;

  void recordCrash(Object error, StackTrace stack) {
    final path = crashLogPath;
    if (path == null) return;
    _recordCrash(path, error, stack);
  }

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      crashLogPath = (await crashLogFile()).path;

      // Framework-level errors (build/layout/paint) — keep the usual
      // red-screen/console behaviour, and log them too.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        recordCrash(details.exception, details.stack ?? StackTrace.empty);
      };
      // Everything else the platform surfaces that isn't a Flutter
      // framework error.
      PlatformDispatcher.instance.onError = (error, stack) {
        recordCrash(error, stack);
        return true;
      };

      runApp(const Mp3SplitterApp());
    },
    // Uncaught errors in async code that escape the zone above — a `catch`
    // block that doesn't run, a Future nobody awaited.
    recordCrash,
  );
}

/// Appends one crash to the on-device log at [path], synchronously.
///
/// Deliberately sync, not async, unlike the rest of this app's file IO: this
/// can fire moments before the process dies, and an in-flight `await` risks
/// being abandoned mid-write if the isolate tears down first. A sync call
/// either finishes on the same call stack or doesn't happen at all — no
/// partial write to worry about. Wrapped in its own try/catch so the crash
/// handler itself can never throw. None of this can help against a true
/// native-level crash (e.g. inside a plugin's native code) — that ends the
/// process before any Dart handler, sync or async, gets a chance to run.
void _recordCrash(String path, Object error, StackTrace stack) {
  try {
    final file = File(path);
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final entry = formatCrashEntry(
      timestamp: DateTime.now(),
      error: error,
      stackTrace: stack,
    );
    file.writeAsStringSync(appendCrashEntry(existing, entry));
  } catch (_) {
    // The crash handler itself must never throw.
  }
}

class Mp3SplitterApp extends StatelessWidget {
  const Mp3SplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Splitter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEC4899)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEC4899),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
