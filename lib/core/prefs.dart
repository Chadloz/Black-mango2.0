import 'package:shared_preferences/shared_preferences.dart';

/// Small settings that survive restarts (filters, guide width...).
class Prefs {
  static late final SharedPreferencesWithCache _p;

  static Future<void> init() async {
    _p = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  }

  static Set<String> getSet(String k) => (_p.getStringList(k) ?? const <String>[]).toSet();
  static Future<void> setSet(String k, Set<String> v) => _p.setStringList(k, v.toList());
  static String? getStr(String k) => _p.getString(k);
  static Future<void> setStr(String k, String? v) => v == null ? _p.remove(k) : _p.setString(k, v);
  static bool getBool(String k) => _p.getBool(k) ?? false;
  static Future<void> setBool(String k, bool v) => _p.setBool(k, v);
  static int? getInt(String k) => _p.getInt(k);
  static Future<void> setInt(String k, int v) => _p.setInt(k, v);
  static double? getDouble(String k) => _p.getDouble(k);
  static Future<void> setDouble(String k, double v) => _p.setDouble(k, v);
}
