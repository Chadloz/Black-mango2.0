import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small settings that survive restarts (filters, guide width...).
class Prefs {
  static late final SharedPreferencesWithCache _p;

  /// Bumps on every change, so screens can refresh when a setting flips.
  static final changes = ValueNotifier<int>(0);

  static Future<void> init() async {
    _p = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  }

  static Future<void> _done(Future<void> f) {
    changes.value++;
    return f;
  }

  /// Every stored key and its raw value (for backups).
  static Set<String> keys() => _p.keys;
  static Object? raw(String k) => _p.get(k);

  static Set<String> getSet(String k) => (_p.getStringList(k) ?? const <String>[]).toSet();
  static Future<void> setSet(String k, Set<String> v) => _done(_p.setStringList(k, v.toList()));
  static String? getStr(String k) => _p.getString(k);
  static Future<void> setStr(String k, String? v) => _done(v == null ? _p.remove(k) : _p.setString(k, v));
  static bool getBool(String k) => _p.getBool(k) ?? false;
  static Future<void> setBool(String k, bool v) => _done(_p.setBool(k, v));
  static int? getInt(String k) => _p.getInt(k);
  static Future<void> setInt(String k, int v) => _done(_p.setInt(k, v));
  static double? getDouble(String k) => _p.getDouble(k);
  static Future<void> setDouble(String k, double v) => _done(_p.setDouble(k, v));
}
