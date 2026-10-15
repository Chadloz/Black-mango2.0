import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Many providers block unknown apps, so identify like a common player.
const bmUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

/// A readable error message for the UI.
class BMError implements Exception {
  final String message;
  BMError(this.message);
  @override
  String toString() => message;
}

Future<String> fetchText(Uri uri, {Duration timeout = const Duration(seconds: 60)}) async {
  final client = HttpClient()
    ..userAgent = bmUserAgent
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(timeout);
    if (res.statusCode >= 400) throw BMError('Server answered ${res.statusCode}');
    return await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
  } on SocketException catch (e) {
    throw BMError('Could not reach the server (${e.osError?.message ?? e.message})');
  } on HandshakeException {
    throw BMError('Secure connection failed (SSL)');
  } finally {
    client.close(force: true);
  }
}

/// Downloads JSON and decodes it on a background worker so the UI never freezes.
Future<dynamic> fetchJson(Uri uri, {Duration timeout = const Duration(seconds: 90)}) async {
  final body = await fetchText(uri, timeout: timeout);
  return Isolate.run(() => jsonDecode(body));
}
