import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'core/services.dart';
import 'core/prefs.dart';
import 'core/session.dart';
import 'core/app_log.dart';
import 'core/playback/still_watching.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.start();
  MediaKit.ensureInitialized();
  await Prefs.init();
  Services.init();
  Session.start();
  StillWatching.start();
  runApp(const BlackMangoApp());
}
