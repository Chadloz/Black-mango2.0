import '../net/fetch.dart';

class XtreamAuth {
  final bool ok;
  final String message;
  XtreamAuth(this.ok, this.message);
}

/// Talks to an Xtream Codes server through player_api.php.
class XtreamClient {
  final String server;
  final String username;
  final String password;
  XtreamClient(this.server, this.username, this.password);

  Uri _api([Map<String, String> extra = const {}]) => Uri.parse('$server/player_api.php')
      .replace(queryParameters: {'username': username, 'password': password, ...extra});

  Future<XtreamAuth> test() async {
    final j = await fetchJson(_api(), timeout: const Duration(seconds: 20));
    if (j is! Map) return XtreamAuth(false, 'Unexpected answer from the server.');
    final ui = j['user_info'];
    if (ui is! Map) return XtreamAuth(false, 'Server did not return account info.');
    if ('${ui['auth']}' != '1') return XtreamAuth(false, 'Login rejected. Check the username and password.');
    final status = '${ui['status'] ?? ''}';
    final exp = int.tryParse('${ui['exp_date'] ?? ''}');
    final expText = exp == null
        ? 'no expiration listed'
        : 'expires ${DateTime.fromMillisecondsSinceEpoch(exp * 1000).toLocal().toString().split(' ').first}';
    final conns = '${ui['max_connections'] ?? '?'}';
    final active = status.isEmpty || status.toLowerCase() == 'active';
    return XtreamAuth(active, 'Status ${status.isEmpty ? 'unknown' : status}, $expText, $conns connection(s).');
  }

  /// category_id -> category name
  Future<Map<String, String>> categories(String action) async {
    final j = await fetchJson(_api({'action': action}));
    final map = <String, String>{};
    if (j is List) {
      for (final c in j) {
        if (c is Map) map['${c['category_id']}'] = '${c['category_name'] ?? ''}';
      }
    }
    return map;
  }

  Future<List<Map>> list(String action) async {
    final j = await fetchJson(_api({'action': action}), timeout: const Duration(minutes: 3));
    return j is List ? j.whereType<Map>().toList() : <Map>[];
  }
}
