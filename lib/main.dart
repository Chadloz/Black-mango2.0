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
import 'app/skin_textures.dart';
import 'app/skin_drops.dart';
import 'core/startup_log.dart';
import 'core/renderer_switch.dart';
import 'core/catalog/pack_refresh.dart';

Future<void> main() async {
  StartupLog.begin(); // every step below is timed in the log ("[startup] ...")
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.start();
  StartupLog.mark('app started');
  if (RendererSwitch.available) {
    debugPrint('[startup] drawing engine: ${RendererSwitch.classic ? 'older (chosen in Settings > Windows)' : 'newer (the default)'}');
  }
  MediaKit.ensureInitialized();
  StartupLog.mark('video engine loaded');
  await Prefs.init();
  StartupLog.mark('settings read');
  await Skins.loadBundledPacks(); // holiday pack files in assets/packs
  Skins.load(); // the skin you picked last time (Settings > Skins)
  await SkinTextures.init(); // where your own skin pictures live
  StartupLog.mark('skins ready');
  await windowManager.ensureInitialized();
  StartupLog.mark('window ready');
  Services.init();
  StartupLog.mark('player and services created');
  Session.start();
  StillWatching.start();
  Hotkeys.start();
  await TsRelay.start();
  LogQuiet.start();
  PopOut.startAutoFloat();
  StartupLog.mark('relay started');
  StartupLog.watch(); // from here on, any freeze is logged ("[freeze] ...")
  runApp(const BlackMangoApp());
  StartupLog.firstFrame();
  StartupLog.time('update check', Updates.start); // release builds: a quiet check now and once a day
  SkinDrops.start(); // holiday skin drops: a check shortly after opening, then every 6 hours
  PackRefresh.start(); // free channel packs: reload any that are more than a day old
}
