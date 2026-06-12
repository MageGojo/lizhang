import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/import_models.dart';
import '../models/ledger_entry.dart';
import 'money.dart';

class LedgerDatabase {
  LedgerDatabase({this.databasePath});

  sqflite.Database? _database;
  final String? databasePath;

  static void configureDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      sqflite.databaseFactory = databaseFactoryFfi;
    }
  }

  Future<sqflite.Database> get database async {
    final current = _database;
    if (current != null) {
      return current;
    }

    final path = databasePath ?? await _defaultDatabasePath();
    await Directory(p.dirname(path)).create(recursive: true);
    final db = await sqflite.openDatabase(
      path,
      version: 1,
      onCreate: _createSchema,
      onOpen: _ensureSchema,
    );
    _database = db;
    await _ensureAnchor(db);
    return db;
  }

  Future<String> _defaultDatabasePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'lizhang.sqlite');
  }

  Future<void> _createSchema(sqflite.Database db, int version) {
    return _ensureSchema(db);
  }

  Future<void> _ensureSchema(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS balance_anchor (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        amount_cents INTEGER NOT NULL,
        as_of_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        merchant TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'manual',
        external_id TEXT NOT NULL DEFAULT '',
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_active_day ON ledger_entries(deleted_at_ms, occurred_at_ms DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_external ON ledger_entries(source, external_id)',
    );
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    await current?.close();
  }

  Future<void> _ensureAnchor(sqflite.Database db) async {
    final rows = await db.query('balance_anchor', limit: 1);
    if (rows.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    await db.insert(
      'balance_anchor',
      BalanceAnchor(amountCents: 0, asOf: now, updatedAt: now).toMap(),
    );
  }

  Future<LedgerSnapshot> loadSnapshot() async {
    final db = await database;
    final anchorRows = await db.query('balance_anchor', limit: 1);
    final anchor = BalanceAnchor.fromMap(anchorRows.first);

    final rows = await db.query(
      'ledger_entries',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'occurred_at_ms DESC, id DESC',
    );
    final entries = rows.map(LedgerEntry.fromMap).toList(growable: false);

    var realtimeDelta = 0;
    var totalIncome = 0;
    var totalExpense = 0;
    for (final entry in entries) {
      if (entry.type == EntryType.income) {
        totalIncome += entry.amountCents;
      } else {
        totalExpense += entry.amountCents;
      }
      if (entry.occurredAt.isAfter(anchor.asOf)) {
        realtimeDelta += entry.signedAmountCents;
      }
    }

    return LedgerSnapshot(
      anchor: anchor,
      entries: entries,
      archives: _buildArchives(entries),
      realtimeBalanceCents: anchor.amountCents + realtimeDelta,
      totalIncomeCents: totalIncome,
      totalExpenseCents: totalExpense,
    );
  }

  List<DayArchive> _buildArchives(List<LedgerEntry> entries) {
    final grouped = <DateTime, List<LedgerEntry>>{};
    for (final entry in entries) {
      final day = DateTime(
        entry.occurredAt.year,
        entry.occurredAt.month,
        entry.occurredAt.day,
      );
      grouped.putIfAbsent(day, () => []).add(entry);
    }

    final archives = grouped.entries.map((group) {
      var income = 0;
      var expense = 0;
      for (final entry in group.value) {
        if (entry.type == EntryType.income) {
          income += entry.amountCents;
        } else {
          expense += entry.amountCents;
        }
      }
      return DayArchive(
        day: group.key,
        entries: group.value,
        incomeCents: income,
        expenseCents: expense,
        netCents: income - expense,
      );
    }).toList();

    archives.sort((a, b) => b.day.compareTo(a.day));
    return archives;
  }

  Future<void> updateBalanceAnchor(int amountCents) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert(
      'balance_anchor',
      BalanceAnchor(
        amountCents: amountCents,
        asOf: now,
        updatedAt: now,
      ).toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<int> saveEntry(LedgerEntry entry) async {
    final db = await database;
    final now = DateTime.now();
    if (entry.id == null) {
      final toInsert = entry.copyWith(createdAt: now, updatedAt: now);
      return db.insert('ledger_entries', toInsert.toMap()..remove('id'));
    }

    await db.update(
      'ledger_entries',
      entry.copyWith(updatedAt: now).toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    return entry.id!;
  }

  Future<void> deleteEntry(int id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'ledger_entries',
      {'deleted_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restoreEntry(int id) async {
    final db = await database;
    await db.update(
      'ledger_entries',
      {
        'deleted_at_ms': null,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> hasPotentialDuplicate(LedgerEntry entry) async {
    final db = await database;
    if (entry.externalId.isNotEmpty) {
      final externalRows = await db.query(
        'ledger_entries',
        columns: ['id'],
        where: 'deleted_at_ms IS NULL AND source = ? AND external_id = ?',
        whereArgs: [entry.source, entry.externalId],
        limit: 1,
      );
      if (externalRows.isNotEmpty) {
        return true;
      }
    }

    final sameRows = await db.query(
      'ledger_entries',
      columns: ['id'],
      where: '''
        deleted_at_ms IS NULL
        AND occurred_at_ms = ?
        AND amount_cents = ?
        AND type = ?
        AND merchant = ?
        AND note = ?
      ''',
      whereArgs: [
        entry.occurredAt.millisecondsSinceEpoch,
        entry.amountCents,
        entry.type.name,
        entry.merchant,
        entry.note,
      ],
      limit: 1,
    );
    return sameRows.isNotEmpty;
  }

  Future<int> applyImportPreview(ImportPreview preview) async {
    final db = await database;
    var inserted = 0;
    await db.transaction((txn) async {
      for (final candidate in preview.candidates) {
        if (!candidate.isValid) {
          continue;
        }
        final duplicate = await _hasPotentialDuplicateInTransaction(
          txn,
          candidate.entry,
        );
        if (duplicate) {
          continue;
        }
        await txn.insert(
          'ledger_entries',
          candidate.entry.toMap()..remove('id'),
        );
        inserted++;
      }
    });
    return inserted;
  }

  Future<bool> _hasPotentialDuplicateInTransaction(
    sqflite.Transaction txn,
    LedgerEntry entry,
  ) async {
    if (entry.externalId.isNotEmpty) {
      final rows = await txn.query(
        'ledger_entries',
        columns: ['id'],
        where: 'deleted_at_ms IS NULL AND source = ? AND external_id = ?',
        whereArgs: [entry.source, entry.externalId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return true;
      }
    }

    final rows = await txn.query(
      'ledger_entries',
      columns: ['id'],
      where:
          'deleted_at_ms IS NULL AND occurred_at_ms = ? AND amount_cents = ? AND type = ? AND merchant = ? AND note = ?',
      whereArgs: [
        entry.occurredAt.millisecondsSinceEpoch,
        entry.amountCents,
        entry.type.name,
        entry.merchant,
        entry.note,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
