import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/import_models.dart';
import '../models/ledger_entry.dart';
import 'ledger_database.dart';
import 'money.dart';

class BillImporter {
  BillImporter(this.database);

  final LedgerDatabase database;

  Future<ImportPreview> previewFile(String path, ImportMethod method) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final lowerPath = path.toLowerCase();
    final rows = lowerPath.endsWith('.xlsx')
        ? _rowsFromXlsx(bytes)
        : _rowsFromText(_decodeText(bytes));
    final source = _detectSource(path, rows);
    return _previewRows(
      rows,
      source: source,
      method: method,
      label: file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last,
    );
  }

  Future<ImportPreview> previewText(String text) {
    final rows = _rowsFromText(text);
    return _previewRows(
      rows,
      source: _detectSource(text, rows),
      method: ImportMethod.paste,
      label: '粘贴账单',
    );
  }

  String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  List<List<String>> _rowsFromText(String text) {
    final cleaned = text.replaceFirst('\uFEFF', '').trim();
    if (cleaned.isEmpty) {
      return const [];
    }

    if (cleaned.contains('\t') && !cleaned.contains(',')) {
      return cleaned
          .split(RegExp(r'\r?\n'))
          .map((line) => line.split('\t').map((cell) => cell.trim()).toList())
          .toList();
    }

    final rows = Csv(dynamicTyping: false).decode(cleaned);
    return rows
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .toList();
  }

  List<List<String>> _rowsFromXlsx(List<int> bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final rows = <List<String>>[];
    for (final tableName in workbook.tables.keys) {
      final sheet = workbook.tables[tableName];
      if (sheet == null) {
        continue;
      }
      rows.addAll(
        sheet.rows.map(
          (row) =>
              row.map((cell) => cell?.value.toString().trim() ?? '').toList(),
        ),
      );
    }
    return rows;
  }

  Future<ImportPreview> _previewRows(
    List<List<String>> rows, {
    required String source,
    required ImportMethod method,
    required String label,
  }) async {
    final now = DateTime.now();
    final headerIndex = _findHeaderIndex(rows);
    if (headerIndex == -1) {
      return ImportPreview(
        source: source,
        method: method,
        label: label,
        createdAt: now,
        candidates: [
          ImportCandidate(
            entry: _fallbackEntry(now, source),
            rowNumber: 0,
            rawSummary: '未找到交易时间/金额等表头',
            isDuplicate: false,
            error: '无法识别账单表头',
          ),
        ],
      );
    }

    final headers = rows[headerIndex].map(_normalizeHeader).toList();
    final candidates = <ImportCandidate>[];
    for (var index = headerIndex + 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.every((cell) => cell.trim().isEmpty)) {
        continue;
      }
      try {
        final entry = _entryFromRow(row, headers, source);
        final duplicate = await database.hasPotentialDuplicate(entry);
        candidates.add(
          ImportCandidate(
            entry: entry,
            rowNumber: index + 1,
            rawSummary: row
                .where((cell) => cell.isNotEmpty)
                .take(4)
                .join(' / '),
            isDuplicate: duplicate,
          ),
        );
      } on FormatException catch (error) {
        candidates.add(
          ImportCandidate(
            entry: _fallbackEntry(now, source),
            rowNumber: index + 1,
            rawSummary: row
                .where((cell) => cell.isNotEmpty)
                .take(4)
                .join(' / '),
            isDuplicate: false,
            error: error.message,
          ),
        );
      }
    }

    return ImportPreview(
      source: source,
      method: method,
      label: label,
      createdAt: now,
      candidates: candidates,
    );
  }

  LedgerEntry _entryFromRow(
    List<String> row,
    List<String> headers,
    String source,
  ) {
    final timeIndex = _findColumn(headers, const [
      '交易时间',
      '付款时间',
      '创建时间',
      '时间',
    ]);
    final amountIndex = _findColumn(headers, const ['金额', '金额元', '交易金额']);
    if (timeIndex == -1 || amountIndex == -1) {
      throw const FormatException('缺少时间或金额列');
    }

    final statusIndex = _findColumn(headers, const ['状态', '交易状态', '当前状态']);
    final status = _cell(row, statusIndex);
    if (status.contains('关闭') || status.contains('失败')) {
      throw FormatException('忽略非成功交易：$status');
    }

    final amount = parseMoneyToCents(_cell(row, amountIndex));
    if (amount == 0) {
      throw const FormatException('金额为 0');
    }

    final typeIndex = _findColumn(headers, const ['收支', '收支类型', '收支方向', '类型']);
    final typeText = _cell(row, typeIndex);
    if (typeText.contains('不计')) {
      throw const FormatException('不计收支');
    }
    final type =
        amount < 0 || typeText.contains('支出') || typeText.contains('付款')
        ? EntryType.expense
        : EntryType.income;

    final occurredAt = _parseDateTime(_cell(row, timeIndex));
    final merchantIndex = _findColumn(headers, const [
      '交易对方',
      '对方',
      '商户',
      '商家',
      '商品',
      '商品名称',
      '商品说明',
    ]);
    final noteIndex = _findColumn(headers, const ['备注', '说明', '商品说明', '交易说明']);
    final categoryIndex = _findColumn(headers, const ['分类', '交易分类', '交易类型']);
    final externalIndex = _findColumn(headers, const [
      '交易单号',
      '交易号',
      '商户单号',
      '商家订单号',
      '订单号',
    ]);

    final merchant = _cell(row, merchantIndex);
    final note = _cell(row, noteIndex);
    final category = _cell(row, categoryIndex).isEmpty
        ? (type == EntryType.expense ? '日常支出' : '收入')
        : _cell(row, categoryIndex);
    final externalId = _cell(row, externalIndex).isEmpty
        ? _hashParts([
            source,
            occurredAt.toIso8601String(),
            '$amount',
            merchant,
            note,
          ])
        : _cell(row, externalIndex);
    final now = DateTime.now();

    return LedgerEntry(
      id: null,
      type: type,
      amountCents: amount.abs(),
      occurredAt: occurredAt,
      category: category,
      merchant: merchant.isEmpty ? source : merchant,
      note: note,
      source: source,
      externalId: externalId,
      createdAt: now,
      updatedAt: now,
    );
  }

  int _findHeaderIndex(List<List<String>> rows) {
    for (var index = 0; index < rows.length; index++) {
      final normalized = rows[index].map(_normalizeHeader).toList();
      final hasTime =
          _findColumn(normalized, const ['交易时间', '付款时间', '创建时间', '时间']) != -1;
      final hasAmount =
          _findColumn(normalized, const ['金额', '金额元', '交易金额']) != -1;
      if (hasTime && hasAmount) {
        return index;
      }
    }
    return -1;
  }

  int _findColumn(List<String> headers, List<String> keywords) {
    for (final keyword in keywords) {
      for (var i = 0; i < headers.length; i++) {
        if (headers[i] == keyword) {
          return i;
        }
      }
    }

    for (final keyword in keywords) {
      for (var i = 0; i < headers.length; i++) {
        if (headers[i].contains(keyword)) {
          return i;
        }
      }
    }
    return -1;
  }

  String _cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  String _normalizeHeader(String value) {
    return value
        .replaceAll(RegExp(r'[\s　()（）/\\:_-]'), '')
        .replaceAll('人民币', '')
        .replaceAll('元', '')
        .trim();
  }

  DateTime _parseDateTime(String value) {
    final normalized = value
        .replaceAll('/', '-')
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', ' ')
        .trim();
    final direct = DateTime.tryParse(normalized);
    if (direct != null) {
      return direct;
    }

    for (final pattern in const [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-M-d HH:mm:ss',
      'yyyy-M-d HH:mm',
      'yyyy-MM-dd',
      'yyyy-M-d',
    ]) {
      try {
        return DateFormat(pattern).parseLoose(normalized);
      } on FormatException {
        continue;
      }
    }
    throw FormatException('无法识别时间：$value');
  }

  String _detectSource(String hint, List<List<String>> rows) {
    final sample = '$hint ${rows.take(8).map((row) => row.join(' ')).join(' ')}'
        .toLowerCase();
    if (sample.contains('支付宝') || sample.contains('alipay')) {
      return 'alipay';
    }
    if (sample.contains('微信') || sample.contains('wechat')) {
      return 'wechat';
    }
    return '账单';
  }

  String _hashParts(List<String> parts) {
    return sha1.convert(utf8.encode(parts.join('|'))).toString();
  }

  LedgerEntry _fallbackEntry(DateTime now, String source) {
    return LedgerEntry(
      id: null,
      type: EntryType.expense,
      amountCents: 0,
      occurredAt: now,
      category: '',
      merchant: source,
      note: '',
      source: source,
      externalId: '',
      createdAt: now,
      updatedAt: now,
    );
  }
}
