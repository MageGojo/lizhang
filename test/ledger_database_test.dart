import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lizhang/services/ledger_controller.dart';
import 'package:lizhang/services/ledger_database.dart';
import 'package:lizhang/services/money.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('saves a manual ledger entry and reloads snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('lizhang-db-test-');
    final database = LedgerDatabase(
      databasePath: p.join(dir.path, 'test.sqlite'),
    );
    final controller = LedgerController(database);

    try {
      await controller.load();
      await controller.setBalanceAnchor('100.00');
      final id = await controller.saveEntry(
        type: EntryType.expense,
        amountText: '12.34',
        occurredAt: DateTime.now().add(const Duration(seconds: 1)),
        category: '餐饮',
        merchant: '咖啡店',
        note: '拿铁',
      );

      expect(id, isPositive);
      expect(controller.snapshot?.entries, hasLength(1));
      expect(controller.snapshot?.entries.single.merchant, '咖啡店');
      expect(controller.snapshot?.realtimeBalanceCents, 8766);
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
