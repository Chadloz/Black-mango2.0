import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'core/services.dart';
import 'core/prefs.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Prefs.init();
  Services.init();
  Session.start();
  runApp(const BlackMangoApp());
}
