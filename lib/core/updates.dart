import 'dart:async';
import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Automatic updates through Sparkle (the updater most Mac apps outside the App Store use).
/// Release builds check quietly at launch and once a day; Settings has a Check now button.
/// When there's a new version, Sparkle shows what's new and asks: install and relaunch, or later.
/// Development builds (flutter run) only check when you press the button.
class Updates {
  /// The update feed, kept on the repo's "updates" branch by the release workflow.
  static const feed = 'https://raw.githubusercontent.com/Chadloz/Black-mango2.0/updates/appcast.xml';

  /// This build's version, set by the release workflow (empty for development builds).
  static const version = String.fromEnvironment('BM_VERSION');

  static bool _ready = false;

  static Future<void> _setUp() async {
    if (_ready) return;
    await autoUpdater.setFeedURL(feed);
    _ready = true;
  }

  static Future<void> start() async {
    if (!Platform.isMacOS || !kReleaseMode) return; // Windows comes later
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
