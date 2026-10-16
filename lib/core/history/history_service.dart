import 'package:drift/drift.dart';
import '../storage/database.dart';

String historyKey(Item i) => '${i.accountId}|${i.kind}|${i.streamId.isNotEmpty ? i.streamId : i.url}';

class HistoryService {
  final AppDatabase db;
  HistoryService(this.db);

  Stream<List<WatchEntry>> watchAll() => db.select(db.history).watch();

  Future<void> record(Item item, {Duration position = Duration.zero, Duration duration = Duration.zero}) async {
    await db.into(db.history).insertOnConflictUpdate(HistoryCompanion.insert(
          entryKey: historyKey(item),
          accountId: item.accountId,
          kind: item.kind,
          name: item.name,
          logo: Value(item.logo),
          streamId: Value(item.streamId),
          ext: Value(item.ext),
          url: Value(item.url),
          positionMs: Value(position.inMilliseconds),
          durationMs: Value(duration.inMilliseconds),
          updatedAt: DateTime.now(),
        ));
  }

  /// Where to pick up, or null to start from the top.
  Future<Duration?> resumePosition(Item item) async {
    final e = await (db.select(db.history)..where((h) => h.entryKey.equals(historyKey(item)))).getSingleOrNull();
    if (e == null || e.positionMs < 30000) return null;
    if (e.durationMs > 0 && e.positionMs > e.durationMs * 0.95) return null;
    return Duration(milliseconds: e.positionMs);
  }

  /// Movies and episodes in progress, newest first.
  Future<List<WatchEntry>> continueWatching() async {
    final rows = await (db.select(db.history)
          ..where((h) => h.kind.isNotValue('live'))
          ..orderBy([(h) => OrderingTerm.desc(h.updatedAt)])
          ..limit(40))
        .get();
    return rows
        .where((e) => e.positionMs >= 30000 && (e.durationMs == 0 || e.positionMs < e.durationMs * 0.95))
        .take(20)
        .toList();
  }

  Future<List<WatchEntry>> recentChannels() => (db.select(db.history)
        ..where((h) => h.kind.equals('live'))
        ..orderBy([(h) => OrderingTerm.desc(h.updatedAt)])
        ..limit(20))
      .get();

  /// Rebuilds a playable item from a history entry.
  Item toItem(WatchEntry e) => Item(
        id: -(e.entryKey.hashCode.abs()),
        accountId: e.accountId,
        kind: e.kind,
        name: e.name,
        nameLower: e.name.toLowerCase(),
        category: '',
        logo: e.logo,
        streamId: e.streamId,
        ext: e.ext,
        url: e.url,
        position: 0,
        genre: '',
        country: '',
        language: '',
      );
}
