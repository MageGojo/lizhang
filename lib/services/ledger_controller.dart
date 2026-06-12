import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/import_models.dart';
import '../models/ledger_entry.dart';
import 'bill_importer.dart';
import 'ledger_database.dart';
import 'money.dart';

class LedgerController extends ChangeNotifier {
  LedgerController(this.database) : importer = BillImporter(database);

  final LedgerDatabase database;
  final BillImporter importer;

  LedgerSnapshot? snapshot;
  ImportPreview? preview;
  String? notice;
  bool isBusy = false;

  Future<void> load() async {
    isBusy = true;
    notifyListeners();
    try {
      snapshot = await database.loadSnapshot();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> setBalanceAnchor(String amountText) async {
    final amount = parseMoneyToCents(amountText).abs();
    await database.updateBalanceAnchor(amount);
    notice = '当前金额已校准';
    await load();
  }

  Future<int> saveEntry({
    int? id,
    required EntryType type,
    required String amountText,
    required DateTime occurredAt,
    required String category,
    required String merchant,
    required String note,
  }) async {
    final amount = parseMoneyToCents(amountText).abs();
    final now = DateTime.now();
    final entry = LedgerEntry(
      id: id,
      type: type,
      amountCents: amount,
      occurredAt: occurredAt,
      category: category.trim().isEmpty ? type.label : category.trim(),
      merchant: merchant.trim().isEmpty ? '手动记账' : merchant.trim(),
      note: note.trim(),
      source: 'manual',
      externalId: id == null
          ? _manualExternalId(now, type, amount, merchant, note)
          : '',
      createdAt: now,
      updatedAt: now,
    );
    final savedId = await database.saveEntry(entry);
    notice = id == null ? '已记一笔' : '已更新账目';
    await load();
    return savedId;
  }

  Future<void> deleteEntry(int id) async {
    await database.deleteEntry(id);
    notice = '已删除，可撤销';
    await load();
  }

  Future<void> restoreEntry(int id) async {
    await database.restoreEntry(id);
    notice = '已撤销删除';
    await load();
  }

  Future<void> previewFile(String path, ImportMethod method) async {
    isBusy = true;
    notifyListeners();
    try {
      preview = await importer.previewFile(path, method);
      notice = '导入预览已生成';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> previewText(String text) async {
    isBusy = true;
    notifyListeners();
    try {
      preview = await importer.previewText(text);
      notice = '粘贴账单已解析';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<int> applyPreview() async {
    final current = preview;
    if (current == null) {
      return 0;
    }
    final inserted = await database.applyImportPreview(current);
    preview = null;
    notice = '已导入 $inserted 笔';
    await load();
    return inserted;
  }

  void clearPreview() {
    preview = null;
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
  }

  String _manualExternalId(
    DateTime now,
    EntryType type,
    int amount,
    String merchant,
    String note,
  ) {
    return sha1
        .convert(
          utf8.encode(
            [
              'manual',
              now.toIso8601String(),
              type.name,
              amount,
              merchant,
              note,
            ].join('|'),
          ),
        )
        .toString();
  }
}
