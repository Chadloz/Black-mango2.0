import 'dart:io';
import 'package:flutter/foundation.dart';

/// Windows only: a troubleshooting switch between Flutter's newer drawing engine (Impeller, the
/// default since Flutter 3.47) and the older one.
///
/// The choice has to be made before the app's window exists, so it can't live in the normal
/// settings. It's a small marker file instead, which the Windows starter (windows/runner/main.cpp)
/// looks for: %APPDATA%\Black Mango\classic-renderer.txt. File there = older engine.
class RendererSwitch {
  static File? get _marker {
    if (!Platform.isWindows) return null;
    final base = Platform.environment['APPDATA'];
    if (base == null || base.isEmpty) return null;
    return File('$base\\Black Mango\\classic-renderer.txt');
  }

  /// Whether this computer has the switch at all (Windows).
  static bool get available => _marker != null;

  /// Whether the older engine is chosen (for the next time the app opens).
  static bool get classic {
    try {
      return _marker?.existsSync() ?? false;
    } catch (_) {
      return false;
    }
  }

  static void set(bool on) {
    final f = _marker;
    if (f == null) return;
    try {
      if (on) {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('Black Mango uses the older drawing engine while this file exists.\r\n'
            'Settings > Windows turns it off, or delete this file.\r\n');
      } else if (f.existsSync()) {
        f.deleteSync();
      }
      debugPrint('[startup] older drawing engine ${on ? 'on' : 'off'} from the next launch');
    } catch (e) {
      debugPrint('[startup] could not change the drawing engine switch: $e');
    }
  }
}
