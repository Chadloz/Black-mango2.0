import 'dart:async';
import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Automatic updates through Sparkle on the Mac and WinSparkle on Windows (the same idea, the
/// same feed: each item says which system it's for). Release builds check quietly at launch and
/// once a day; Settings has a Check now button. When there's a new version, you see what's new
/// and choose: install and relaunch, or later. Development builds only check when you press it.
class Updates {
  /// The update feed, kept on the repo's "updates" branch by the release workflow.
  static const feed = 'https://raw.githubusercontent.com/Chadloz/Black-mango2.0/updates/appcast.xml';

  /// This build's version, set by the release workflow (empty for development builds).
  static const version = String.fromEnvironment('BM_VERSION');

  static bool _ready = false;

  static Future<void> _setUp() async {
    if (_ready) return;
    // Windows: the installer can't replace a running app, so close when the update is ready to go
    // in (the installer reopens Black Mango afterwards). The Mac updater handles this itself.
    if (Platform.isWindows) autoUpdater.addListener(_CloseForUpdate());
    await autoUpdater.setFeedURL(feed);
    _ready = true;
  }

  static Future<void> start() async {
    if (!(Platform.isMacOS || Platform.isWindows) || !kReleaseMode) return;
    try {
      await _setUp();
      await autoUpdater.checkForUpdates(inBackground: true);
      Timer.periodic(const Duration(hours: 24), (_) {
        autoUpdater.checkForUpdates(inBackground: true).catchError((Object e) => debugPrint('[updates] $e'));
      });
    } catch (e) {
      debugPrint('[updates] could not check: $e');
    }
  }

  /// Settings > Check for updates: shows Sparkle's window either way ("You're up to date" or what's new).
  static Future<void> checkNow() async {
    try {
      await _setUp();
      await autoUpdater.checkForUpdates();
    } catch (e) {
      debugPrint('[updates] could not check: $e');
    }
  }
}

class _CloseForUpdate with UpdaterListener {
  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    debugPrint('[updates] closing so the update can install');
    Future.delayed(const Duration(milliseconds: 300), () => exit(0));
  }

  @override
  void onUpdaterError(UpdaterError? error) => debugPrint('[updates] ${error?.message}');

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {}

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {}

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {}

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {}
}
