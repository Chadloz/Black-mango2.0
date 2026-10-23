import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'core/services.dart';
import 'core/prefs.dart';
import 'core/session.dart';
import 'core/app_log.dart';
import 'core/hotkeys.dart';
import 'core/playback/ts_relay.dart';
import 'core/log_quiet.dart';
import 'core/widgets/mini_player.dart';
import 'package:window_manager/window_manager.dart';
import 'core/playback/still_watching.dart';
import 'core/updates.dart';
import 'app/skins.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.start();
  MediaKit.ensureInitialized();
  await Prefs.init();
  Skins.load(); // the skin you picked last time (Settings > Appearance)
  await windowManager.ensureInitialized();
  Services.init();
  Session.start();
  StillWatching.start();
  Hotkeys.start();
  await TsRelay.start();
  LogQuiet.start();
  PopOut.startAutoFloat();
  runApp(const BlackMangoApp());
  Updates.start(); // release builds: a quiet check now and once a day
}
